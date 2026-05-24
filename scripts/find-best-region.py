#!/usr/bin/env python3
"""
find-best-region.py — Azure ML region advisor for the white-orchid MLOps project.

Read-only planning tool. It does NOT create or change any Azure resources.
Given the project's two workloads it scores candidate regions and tells you
where to provision so you don't hit a wall mid-`terraform apply`.

Workloads (see CLAUDE.md):
  * Pre-prod  — Azure ML workspace, train + deploy to a managed online endpoint /
                compute cluster on a cheap CPU SKU. Low-priority nodes welcome.
  * Prod      — Azure ML workspace with an AKS-backed Kubernetes online endpoint,
                plus model-drift monitoring (Azure ML model monitoring + App Insights).

For each candidate region the script checks the things that actually block a
free / pay-as-you-go subscription:
  1. Azure ML (Microsoft.MachineLearningServices) is offered in the region.
  2. AKS (Microsoft.ContainerService) is offered in the region (prod only).
  3. The candidate VM SKUs are NOT "NotAvailableForSubscription" there
     (the #1 silent blocker on free subscriptions).
  4. There is regional vCPU + per-family quota headroom for the SKU.
  5. Retail price of the SKUs (on-demand + low-priority/spot) in that region.
  6. Proximity to the UK (great-circle distance from London) as a tie-breaker.

Requires: az CLI (logged in) and python3 (stdlib only). No pip installs.

Usage:
  python3 scripts/find-best-region.py                # default EU/UK-focused list
  python3 scripts/find-best-region.py --regions uksouth,ukwest,northeurope,westeurope
  python3 scripts/find-best-region.py --all-eu        # all European regions
  python3 scripts/find-best-region.py --report infra/region-report.md
"""

import argparse
import json
import math
import subprocess
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# --------------------------------------------------------------------------- #
# Requirements / tunables — edit these to match your workload.
# --------------------------------------------------------------------------- #

# Cheap CPU SKUs acceptable for pre-prod training / managed endpoint.
# Order = preference (first usable one is treated as the chosen SKU).
PREPROD_SKUS = [
    "Standard_DS2_v2",
    "Standard_DS3_v2",
    "Standard_F2s_v2",
    "Standard_F4s_v2",
    "Standard_E4ds_v4",
]

# SKUs acceptable for the prod AKS node pool / inference.
PROD_SKUS = [
    "Standard_DS2_v2",
    "Standard_D2s_v3",
    "Standard_DS3_v2",
    "Standard_D4s_v3",
]

# Default candidate regions: UK + Europe (data residency friendly, low latency).
DEFAULT_REGIONS = [
    "uksouth", "ukwest", "northeurope", "westeurope", "francecentral",
    "germanywestcentral", "swedencentral", "switzerlandnorth", "norwayeast",
]

LONDON = (51.5074, -0.1278)  # for proximity scoring

# Scoring weights (higher weight = matters more). Lower raw cost/distance is better.
W_PREPROD_COST = 3.0   # weight on pre-prod hourly price (low-priority if available)
W_PROD_COST = 3.0      # weight on prod on-demand hourly price
W_QUOTA = 1.5          # weight on regional vCPU headroom
W_PROXIMITY = 1.0      # weight on closeness to the UK
W_FLEXIBILITY = 0.5    # weight on how many candidate SKUs are usable


# --------------------------------------------------------------------------- #
# Azure helpers
# --------------------------------------------------------------------------- #

def az(args):
    """Run an `az ... -o json` command and return parsed JSON (or None on error)."""
    try:
        out = subprocess.run(
            ["az", *args, "-o", "json"],
            capture_output=True, text=True, check=True,
        )
        return json.loads(out.stdout) if out.stdout.strip() else None
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"  ! az {' '.join(args)} failed: {e.stderr.strip()[:200]}\n")
        return None


def get_locations():
    """Map arm region name -> {displayName, lat, lon, geographyGroup}."""
    locs = az(["account", "list-locations"]) or []
    out = {}
    for l in locs:
        md = l.get("metadata") or {}
        out[l["name"]] = {
            "display": l.get("displayName", l["name"]),
            "lat": float(md["latitude"]) if md.get("latitude") else None,
            "lon": float(md["longitude"]) if md.get("longitude") else None,
            "geo": md.get("geographyGroup", ""),
        }
    return out


def get_provider_regions(namespace, resource_type):
    """Return a set of arm region names where a provider resource type is offered."""
    data = az(["provider", "show", "--namespace", namespace,
               "--query", f"resourceTypes[?resourceType=='{resource_type}'].locations | [0]"])
    # provider locations come back as display names ("UK South"); normalise later.
    return set(data or [])


def list_vm_skus(region):
    """All virtualMachines SKUs in a region with restrictions + capabilities."""
    return az(["vm", "list-skus", "--location", region,
               "--resource-type", "virtualMachines", "--all"]) or []


def list_usage(region):
    """Regional vCPU usage/limits keyed by family name.value."""
    items = az(["vm", "list-usage", "--location", region]) or []
    by_name = {}
    for it in items:
        name = (it.get("name") or {}).get("value", "")
        by_name[name] = {
            "local": (it.get("name") or {}).get("localizedValue", name),
            "current": int(it.get("currentValue", 0)),
            "limit": int(it.get("limit", 0)),
        }
    return by_name


def get_prices(region, skus):
    """Cheapest Linux on-demand / low-priority / spot hourly price per SKU in region."""
    sku_filter = " or ".join(f"armSkuName eq '{s}'" for s in skus)
    flt = (f"serviceName eq 'Virtual Machines' and priceType eq 'Consumption' "
           f"and armRegionName eq '{region}' and ({sku_filter})")
    url = "https://prices.azure.com/api/retail/prices?" + urllib.parse.urlencode(
        {"$filter": flt, "currencyCode": "USD"})
    prices = {}  # sku -> {ondemand, lowpri, spot}
    try:
        while url:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = json.loads(resp.read())
            for it in data.get("Items", []):
                sku = it["armSkuName"]
                if "Windows" in it.get("productName", ""):
                    continue
                if it.get("unitOfMeasure") != "1 Hour":
                    continue
                meter = it.get("meterName", "")
                price = float(it["retailPrice"])
                if price <= 0:
                    continue
                bucket = prices.setdefault(sku, {})
                if "Spot" in meter:
                    key = "spot"
                elif "Low Priority" in meter:
                    key = "lowpri"
                else:
                    key = "ondemand"
                if key not in bucket or price < bucket[key]:
                    bucket[key] = price
            url = data.get("NextPageLink")
    except Exception as e:  # network / API hiccup — degrade gracefully
        sys.stderr.write(f"  ! pricing lookup failed for {region}: {e}\n")
    return prices


# --------------------------------------------------------------------------- #
# Analysis
# --------------------------------------------------------------------------- #

def haversine(a, b):
    if not a or not b or a[0] is None or b[0] is None:
        return None
    r = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dphi = math.radians(b[0] - a[0])
    dlmb = math.radians(b[1] - a[1])
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def sku_usable(sku_obj, usage):
    """Return (usable, reason). Checks subscription restriction + quota headroom."""
    # 1) restriction: NotAvailableForSubscription at the Location scope is a hard no.
    for r in sku_obj.get("restrictions", []):
        if r.get("reasonCode") == "NotAvailableForSubscription" and r.get("type") == "Location":
            return False, "NotAvailableForSubscription"

    # 2) quota: family must have headroom for this SKU's vCPU count.
    vcpus = 0
    for cap in sku_obj.get("capabilities", []):
        if cap.get("name") == "vCPUs":
            vcpus = int(cap.get("value", 0))
    family = sku_obj.get("family", "")
    fam = usage.get(family)
    if fam is not None:
        headroom = fam["limit"] - fam["current"]
        if fam["limit"] == 0:
            return False, f"family quota 0 ({family})"
        if vcpus and headroom < vcpus:
            return False, f"family quota full ({fam['current']}/{fam['limit']})"
    return True, f"{vcpus} vCPU"


def analyse_region(region, locmap, aml_regions, aks_regions):
    info = locmap.get(region, {"display": region, "lat": None, "lon": None, "geo": ""})
    result = {
        "region": region, "display": info["display"], "geo": info["geo"],
        "aml": False, "aks": False, "blockers": [],
        "preprod_sku": None, "preprod_price": None, "preprod_basis": None,
        "prod_sku": None, "prod_price": None,
        "preprod_usable": [], "prod_usable": [],
        "regional_quota": None, "distance_km": haversine(
            (info["lat"], info["lon"]), LONDON),
    }

    disp = info["display"]
    result["aml"] = disp in aml_regions
    result["aks"] = disp in aks_regions
    if not result["aml"]:
        result["blockers"].append("Azure ML not offered in region")
    if not result["aks"]:
        result["blockers"].append("AKS not offered in region")

    skus = {s["name"]: s for s in list_vm_skus(region)}
    usage = list_usage(region)
    tot = usage.get("cores") or usage.get("Total Regional vCPUs")
    if tot:
        result["regional_quota"] = f"{tot['current']}/{tot['limit']}"

    prices = get_prices(region, list(set(PREPROD_SKUS + PROD_SKUS)))

    def cheapest(sku, prefer_lowpri):
        p = prices.get(sku, {})
        if prefer_lowpri:
            for k in ("lowpri", "spot", "ondemand"):
                if k in p:
                    return p[k], k
        return (p.get("ondemand"), "ondemand") if "ondemand" in p else (None, None)

    for sku in PREPROD_SKUS:
        obj = skus.get(sku)
        if not obj:
            continue
        ok, reason = sku_usable(obj, region, usage)
        if ok:
            result["preprod_usable"].append(sku)
            if result["preprod_sku"] is None:
                price, basis = cheapest(sku, prefer_lowpri=True)
                result["preprod_sku"] = sku
                result["preprod_price"] = price
                result["preprod_basis"] = basis

    for sku in PROD_SKUS:
        obj = skus.get(sku)
        if not obj:
            continue
        ok, reason = sku_usable(obj, region, usage)
        if ok:
            result["prod_usable"].append(sku)
            if result["prod_sku"] is None:
                price, _ = cheapest(sku, prefer_lowpri=False)
                result["prod_sku"] = sku
                result["prod_price"] = price

    if not result["preprod_usable"]:
        result["blockers"].append("no usable pre-prod SKU (restricted / no quota)")
    if not result["prod_usable"]:
        result["blockers"].append("no usable prod SKU (restricted / no quota)")

    return result


def score(results):
    """Attach a 0-100 score to each viable region (lower cost/distance is better)."""
    viable = [r for r in results if not r["blockers"]]
    if not viable:
        return

    def col(key):
        return [r[key] for r in viable if r.get(key) is not None]

    def norm(val, lo, hi, invert):
        if val is None or hi == lo:
            return 0.5
        x = (val - lo) / (hi - lo)
        return 1 - x if invert else x

    pp = col("preprod_price"); pr = col("prod_price"); ds = col("distance_km")
    pp_lo, pp_hi = (min(pp), max(pp)) if pp else (0, 1)
    pr_lo, pr_hi = (min(pr), max(pr)) if pr else (0, 1)
    ds_lo, ds_hi = (min(ds), max(ds)) if ds else (0, 1)
    max_flex = max(len(r["preprod_usable"]) + len(r["prod_usable"]) for r in viable)

    for r in viable:
        s = 0.0
        s += W_PREPROD_COST * norm(r["preprod_price"], pp_lo, pp_hi, invert=True)
        s += W_PROD_COST * norm(r["prod_price"], pr_lo, pr_hi, invert=True)
        s += W_PROXIMITY * norm(r["distance_km"], ds_lo, ds_hi, invert=True)
        flex = len(r["preprod_usable"]) + len(r["prod_usable"])
        s += W_FLEXIBILITY * (flex / max_flex if max_flex else 0)
        # quota headroom bonus
        q = 0.5
        if r["regional_quota"]:
            cur, lim = (int(x) for x in r["regional_quota"].split("/"))
            q = (lim - cur) / lim if lim else 0
        s += W_QUOTA * q
        total_w = (W_PREPROD_COST + W_PROD_COST + W_PROXIMITY +
                   W_FLEXIBILITY + W_QUOTA)
        r["score"] = round(100 * s / total_w, 1)


# --------------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------------- #

def fmt_price(p):
    return f"${p:.3f}/hr" if p is not None else "n/a"


def render(results, regions):
    lines = []
    viable = sorted([r for r in results if not r["blockers"]],
                    key=lambda r: r.get("score", 0), reverse=True)
    blocked = [r for r in results if r["blockers"]]

    lines.append("# Azure ML region advice — white-orchid\n")
    lines.append(f"Evaluated {len(regions)} region(s). "
                 f"{len(viable)} viable, {len(blocked)} blocked.\n")

    if viable:
        best = viable[0]
        lines.append("## Recommendation\n")
        lines.append(f"- **Pre-prod region:** `{best['region']}` ({best['display']}) "
                     f"— SKU `{best['preprod_sku']}` "
                     f"@ {fmt_price(best['preprod_price'])} ({best['preprod_basis']})")
        # prod: prefer same region if it also serves prod well, else top prod region.
        prod_ranked = sorted(viable, key=lambda r: (
            r["prod_price"] if r["prod_price"] is not None else 9e9))
        prod_best = best if best["prod_sku"] else prod_ranked[0]
        same = prod_best["region"] == best["region"]
        lines.append(f"- **Prod region:** `{prod_best['region']}` "
                     f"({prod_best['display']}) — AKS SKU `{prod_best['prod_sku']}` "
                     f"@ {fmt_price(prod_best['prod_price'])}"
                     f"{'  *(same region as pre-prod — simplest, no cross-region egress)*' if same else ''}")
        lines.append(f"- Model-drift monitoring: available wherever Azure ML + "
                     f"Application Insights are (all viable regions above).\n")

    lines.append("## Ranked viable regions\n")
    lines.append("| Rank | Region | Score | Pre-prod SKU | Pre-prod $/hr | Prod SKU | Prod $/hr | Regional vCPU | Dist (km) |")
    lines.append("|------|--------|-------|--------------|---------------|----------|-----------|---------------|-----------|")
    for i, r in enumerate(viable, 1):
        lines.append(
            f"| {i} | `{r['region']}` | {r.get('score','')} | {r['preprod_sku']} | "
            f"{fmt_price(r['preprod_price'])} ({r['preprod_basis']}) | {r['prod_sku']} | "
            f"{fmt_price(r['prod_price'])} | {r['regional_quota'] or 'n/a'} | "
            f"{int(r['distance_km']) if r['distance_km'] else 'n/a'} |")

    if blocked:
        lines.append("\n## Blocked regions\n")
        lines.append("| Region | Blockers |")
        lines.append("|--------|----------|")
        for r in blocked:
            lines.append(f"| `{r['region']}` | {'; '.join(r['blockers'])} |")

    lines.append("\n---\n*Read-only analysis. Prices are USD retail (no free-credit "
                 "discount applied). Pre-prod price uses low-priority/spot when "
                 "available — fine for training compute clusters, not for managed "
                 "online endpoints (those bill on-demand).*")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Find the best Azure region for the ML workloads.")
    ap.add_argument("--regions", help="comma-separated arm region names")
    ap.add_argument("--all-eu", action="store_true", help="evaluate all European regions")
    ap.add_argument("--report", help="write the markdown report to this path")
    args = ap.parse_args()

    print("Loading Azure metadata (locations, AML/AKS availability)...", file=sys.stderr)
    locmap = get_locations()
    aml_regions = get_provider_regions("Microsoft.MachineLearningServices", "workspaces")
    aks_regions = get_provider_regions("Microsoft.ContainerService", "managedClusters")

    if args.regions:
        regions = [r.strip() for r in args.regions.split(",") if r.strip()]
    elif args.all_eu:
        regions = sorted(name for name, i in locmap.items()
                         if i["geo"] == "Europe" and "stage" not in name
                         and "euap" not in name)
    else:
        regions = DEFAULT_REGIONS

    print(f"Evaluating {len(regions)} region(s): {', '.join(regions)}\n", file=sys.stderr)

    results = []
    with ThreadPoolExecutor(max_workers=5) as ex:
        futs = {ex.submit(analyse_region, r, locmap, aml_regions, aks_regions): r
                for r in regions}
        for f in futs:
            r = futs[f]
            print(f"  analysed {r}", file=sys.stderr)
            results.append(f.result())

    score(results)
    report = render(results, regions)
    print("\n" + report)

    if args.report:
        with open(args.report, "w") as fh:
            fh.write(report + "\n")
        print(f"\nReport written to {args.report}", file=sys.stderr)


if __name__ == "__main__":
    main()
