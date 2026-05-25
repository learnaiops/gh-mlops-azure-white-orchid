"""
simulate_drift.py — Inject shifted feature distributions into the white-orchid prod endpoint.

Two modes:
  simulate  POST drift records to a live scoring endpoint (triggers Azure ML monitor). Default.
  augment   Write a pseudo-labeled CSV for challenger retraining (no endpoint required).

Drift simulates realistic health-insurance population shifts:
  - Aging policyholder cohort        (age +4 to +13 years depending on intensity)
  - Obesity trend                    (BMI +2 to +6)
  - Regional claims surge            (num_claims 0.5x to 2.3x increase)
  - Smoking prevalence rise          (25% → 32–45%)
  - Reduced exercise frequency       (2.5 → 1.0 sessions/week at severe)
  - Higher chronic-conditions burden (mean 0.9 → 1.8 at severe)

Drift thresholds that fire Azure ML monitor (Wasserstein > 0.1):
  - mild:     ~3 features drift slightly, monitor unlikely to fire
  - moderate: ~5 features drift, monitor fires within 2 daily runs
  - severe:   all features drift, monitor fires on next run

Usage:
  # Simulate — send 500 records to prod endpoint
  python simulate_drift.py --endpoint-url $URL --endpoint-key $KEY

  # Augment — write shifted + pseudo-labeled CSV for retraining
  python simulate_drift.py --mode augment --output /tmp/augmented.csv

  # Specific intensity
  python simulate_drift.py --endpoint-url $URL --endpoint-key $KEY --intensity moderate
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error

import numpy as np
import pandas as pd

FEATURE_COLS = [
    "age", "bmi", "smoker", "chronic_conditions", "annual_income",
    "exercise_freq_per_week", "alcohol_units_per_week",
    "num_claims_last_year", "family_history", "region",
]

REGIONS = ["North", "South", "East", "West", "Central"]

# Training-set baseline statistics (derived from health_insurance_risk_dataset.csv)
BASELINE = {
    "age_mean": 45.0,        "age_std": 13.0,
    "bmi_mean": 27.0,        "bmi_std": 5.0,
    "smoker_rate": 0.25,
    "chronic_mean": 0.90,    "chronic_std": 0.80,
    "income_mean": 75000.0,  "income_std": 28000.0,
    "exercise_mean": 2.50,   "exercise_std": 1.50,
    "alcohol_mean": 5.0,     "alcohol_std": 4.0,
    "claims_mean": 1.20,     "claims_std": 1.20,
    "family_history_rate": 0.40,
    "region_weights": [0.20, 0.20, 0.20, 0.20, 0.20],
}

# Per-intensity shift parameters applied on top of BASELINE
DRIFT = {
    "mild": {
        "age_shift": 4,     "bmi_shift": 2,   "smoker_rate": 0.32,
        "chronic_shift": 0.30, "claims_mult": 1.5, "exercise_shift": -0.5,
        "income_shift": -5000, "alcohol_shift": 1,
        "region_weights": [0.30, 0.25, 0.20, 0.15, 0.10],
    },
    "moderate": {
        "age_shift": 8,     "bmi_shift": 4,   "smoker_rate": 0.38,
        "chronic_shift": 0.60, "claims_mult": 2.0, "exercise_shift": -1.0,
        "income_shift": -12000, "alcohol_shift": 2,
        "region_weights": [0.40, 0.25, 0.20, 0.10, 0.05],
    },
    "severe": {
        "age_shift": 13,    "bmi_shift": 6,   "smoker_rate": 0.45,
        "chronic_shift": 0.90, "claims_mult": 2.9, "exercise_shift": -1.5,
        "income_shift": -20000, "alcohol_shift": 3,
        "region_weights": [0.50, 0.25, 0.15, 0.07, 0.03],
    },
}


def generate_records(n: int, intensity: str, rng: np.random.Generator) -> pd.DataFrame:
    d = DRIFT[intensity]
    b = BASELINE

    age = rng.normal(b["age_mean"] + d["age_shift"], b["age_std"], n).clip(22, 85).astype(int)
    bmi = rng.normal(b["bmi_mean"] + d["bmi_shift"], b["bmi_std"], n).clip(16, 50).round(1)
    smoker = rng.binomial(1, d["smoker_rate"], n)
    chronic = rng.normal(b["chronic_mean"] + d["chronic_shift"], b["chronic_std"], n).clip(0, 3).round().astype(int)
    income = rng.normal(b["income_mean"] + d["income_shift"], b["income_std"], n).clip(20000, 200000).round(-2).astype(int)
    exercise = rng.normal(b["exercise_mean"] + d["exercise_shift"], b["exercise_std"], n).clip(0, 7).round(1)
    alcohol = rng.normal(b["alcohol_mean"] + d["alcohol_shift"], b["alcohol_std"], n).clip(0, 20).round(1)
    claims_mean = b["claims_mean"] * d["claims_mult"]
    claims = rng.normal(claims_mean, b["claims_std"], n).clip(0, 10).round().astype(int)
    family = rng.binomial(1, b["family_history_rate"] + 0.10, n)
    region = rng.choice(REGIONS, size=n, p=d["region_weights"])

    return pd.DataFrame({
        "age": age, "bmi": bmi, "smoker": smoker,
        "chronic_conditions": chronic, "annual_income": income,
        "exercise_freq_per_week": exercise, "alcohol_units_per_week": alcohol,
        "num_claims_last_year": claims, "family_history": family, "region": region,
    })


def _heuristic_labels(df: pd.DataFrame) -> np.ndarray:
    """Assign pseudo-labels based on domain rules (used in augment mode)."""
    high_risk = (
        (df["smoker"] == 1) |
        (df["chronic_conditions"] >= 2) |
        ((df["age"] > 55) & (df["num_claims_last_year"] >= 3)) |
        ((df["bmi"] > 33) & (df["chronic_conditions"] >= 1)) |
        (df["num_claims_last_year"] >= 5)
    )
    return high_risk.astype(int).values


def mode_augment(args):
    """Generate a pseudo-labeled training CSV for retraining the challenger."""
    rng = np.random.default_rng(seed=42)
    print(f"Generating {args.count} augmented records (intensity={args.intensity})...")

    df_shifted = generate_records(args.count, args.intensity, rng)
    df_shifted["high_risk_customer"] = _heuristic_labels(df_shifted)

    # Mix with a small portion of baseline records to prevent catastrophic forgetting
    n_baseline = int(args.count * 0.3)
    df_base = generate_records(n_baseline, "mild", rng)
    df_base["high_risk_customer"] = _heuristic_labels(df_base)

    df_out = pd.concat([df_shifted, df_base], ignore_index=True)
    df_out = df_out.sample(frac=1, random_state=42).reset_index(drop=True)
    df_out.insert(0, "customer_id", [f"drift-aug-{i:06d}" for i in range(len(df_out))])

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    df_out.to_csv(args.output, index=False)

    pos_rate = df_out["high_risk_customer"].mean()
    print(f"Augmented dataset: {len(df_out)} rows, {pos_rate:.1%} high-risk rate")
    print(f"Age mean:    {df_out['age'].mean():.1f}  (baseline {BASELINE['age_mean']})")
    print(f"BMI mean:    {df_out['bmi'].mean():.1f}  (baseline {BASELINE['bmi_mean']})")
    print(f"Smoker rate: {df_out['smoker'].mean():.1%}  (baseline {BASELINE['smoker_rate']:.1%})")
    print(f"Claims mean: {df_out['num_claims_last_year'].mean():.2f}  (baseline {BASELINE['claims_mean']})")
    print(f"Saved to: {args.output}")


def mode_simulate(args):
    """POST drift records to a live scoring endpoint in batches."""
    endpoint_url = args.endpoint_url or os.getenv("ML_ENDPOINT_URL", "")
    endpoint_key = args.endpoint_key or os.getenv("ML_ENDPOINT_KEY", "")

    if not endpoint_url or not endpoint_key:
        print("Error: --endpoint-url / --endpoint-key (or ML_ENDPOINT_URL / ML_ENDPOINT_KEY) required for simulate mode", file=sys.stderr)
        sys.exit(1)

    rng = np.random.default_rng(seed=99)
    df = generate_records(args.count, args.intensity, rng)

    records = df[FEATURE_COLS].to_dict(orient="records")
    n_sent = 0
    n_errors = 0
    risk_probs = []

    print(f"Sending {len(records)} drift records to endpoint (batch_size={args.batch_size}, intensity={args.intensity})")
    print(f"Endpoint: {endpoint_url[:60]}...")
    print()

    for start in range(0, len(records), args.batch_size):
        batch = records[start:start + args.batch_size]
        payload = json.dumps(batch).encode()
        req = urllib.request.Request(
            endpoint_url,
            data=payload,
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {endpoint_key}"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = json.loads(resp.read())
                if isinstance(body, list):
                    for r in body:
                        risk_probs.append(r.get("risk_probability", 0))
                n_sent += len(batch)
        except urllib.error.HTTPError as exc:
            n_errors += len(batch)
            print(f"  Batch {start}–{start+len(batch)}: HTTP {exc.code} — {exc.read().decode()[:120]}")
        except Exception as exc:
            n_errors += len(batch)
            print(f"  Batch {start}–{start+len(batch)}: {exc}")

        if (start // args.batch_size) % 5 == 0:
            print(f"  Progress: {n_sent}/{len(records)} sent, {n_errors} errors")
        time.sleep(0.1)

    print()
    print("=" * 60)
    print("DRIFT SIMULATION SUMMARY")
    print("=" * 60)
    print(f"Records sent:        {n_sent}")
    print(f"Errors:              {n_errors}")
    if risk_probs:
        arr = np.array(risk_probs)
        print(f"Risk prob (mean):    {arr.mean():.3f}  (baseline ~0.45)")
        print(f"Risk prob (p75):     {np.percentile(arr, 75):.3f}")
        print(f"Risk prob (p95):     {np.percentile(arr, 95):.3f}")
        print(f"High-risk rate:      {(arr >= 0.5).mean():.1%}  (baseline ~35%)")
        drift_signal = arr.mean() > 0.60
        print(f"Drift signal:        {'DETECTED — avg risk_prob > 0.60' if drift_signal else 'NOT YET — avg < 0.60 threshold'}")
    print()
    print("Feature distribution sent:")
    print(f"  age mean:    {df['age'].mean():.1f}  (baseline {BASELINE['age_mean']})")
    print(f"  BMI mean:    {df['bmi'].mean():.1f}  (baseline {BASELINE['bmi_mean']})")
    print(f"  smoker rate: {df['smoker'].mean():.1%}  (baseline {BASELINE['smoker_rate']:.1%})")
    print(f"  claims mean: {df['num_claims_last_year'].mean():.2f}  (baseline {BASELINE['claims_mean']})")
    print()
    print("Azure ML Monitor checks once daily.")
    print("App Insights alert evaluates every 30 min (fires when avg_risk_prob > 0.60 with 20+ records).")

    if n_errors > 0:
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mode", choices=["simulate", "augment"], default="simulate")
    parser.add_argument("--intensity", choices=["mild", "moderate", "severe"], default="severe",
                        help="Drift intensity (default: severe)")
    parser.add_argument("--count", type=int, default=500, help="Number of records to generate (default: 500)")
    parser.add_argument("--endpoint-url", default="", help="Scoring endpoint URL (or ML_ENDPOINT_URL env var)")
    parser.add_argument("--endpoint-key", default="", help="Endpoint primary key (or ML_ENDPOINT_KEY env var)")
    parser.add_argument("--batch-size", type=int, default=10, help="Records per HTTP request (default: 10)")
    parser.add_argument("--output", default="/tmp/augmented_training.csv", help="Output CSV path for augment mode")
    args = parser.parse_args()

    if args.mode == "simulate":
        mode_simulate(args)
    else:
        mode_augment(args)


if __name__ == "__main__":
    main()
