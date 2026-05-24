# Azure ML region advice — white-orchid

Evaluated 9 region(s). 2 viable, 7 blocked.

## Recommendation

- **Pre-prod region:** `swedencentral` (Sweden Central) — SKU `Standard_E4ds_v4` @ $0.061/hr (lowpri)
- **Prod region:** `swedencentral` (Sweden Central) — AKS SKU `Standard_D2s_v3` @ $0.102/hr  *(same region as pre-prod — simplest, no cross-region egress)*
- Model-drift monitoring: available wherever Azure ML + Application Insights are (all viable regions above).

## Ranked viable regions

| Rank | Region | Score | Pre-prod SKU | Pre-prod $/hr | Prod SKU | Prod $/hr | Regional vCPU | Dist (km) |
|------|--------|-------|--------------|---------------|----------|-----------|---------------|-----------|
| 1 | `swedencentral` | 88.9 | Standard_E4ds_v4 | $0.061/hr (lowpri) | Standard_D2s_v3 | $0.102/hr | 0/4 | 1470 |
| 2 | `westeurope` | 33.3 | Standard_E4ds_v4 | $0.069/hr (lowpri) | Standard_D2s_v3 | $0.120/hr | 0/4 | 357 |

## Blocked regions

| Region | Blockers |
|--------|----------|
| `uksouth` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |
| `ukwest` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |
| `northeurope` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |
| `francecentral` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |
| `germanywestcentral` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |
| `switzerlandnorth` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |
| `norwayeast` | no usable pre-prod SKU (restricted / no quota); no usable prod SKU (restricted / no quota) |

---
*Read-only analysis. Prices are USD retail (no free-credit discount applied). Pre-prod price uses low-priority/spot when available — fine for training compute clusters, not for managed online endpoints (those bill on-demand).*
