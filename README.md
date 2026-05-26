# White Orchid — Health Insurance Risk MLOps on Azure

An end-to-end **MLOps** project that trains, registers, deploys, and monitors a health
insurance **risk prediction** model on Azure — using Azure ML, AKS, and Azure DevOps.

Given a customer's health, lifestyle, and claims profile, the model predicts whether
they are a **high-risk** insurance customer (binary decision + probability).

## High-level overview

| Area | What it does |
|---|---|
| **Model** | Gradient Boosting classifier (sklearn) on a synthetic insurance dataset; quality gate of **AUC ≥ 0.80** blocks bad models from deploying. |
| **Pre-prod** | Azure ML workspace + **managed online endpoint** (Standard_DS2_v2). |
| **Prod** | Azure ML workspace + **AKS online endpoint** (Standard_D4s_v3, autoscaled). |
| **Pipelines** | Azure DevOps: train→deploy to pre-prod, promote to prod, deploy UI. |
| **Monitoring** | App Insights telemetry per prediction, Azure ML drift monitors, metric alerts, Azure dashboard. |
| **UI** | React + Express app that calls **both** endpoints and compares results side-by-side. |

## Architecture & flow

```mermaid
flowchart TD
    subgraph Dev["Source & CI/CD"]
        Repo["Git repo<br/>(model code · Terraform · pipelines · UI)"]
        ADO["Azure DevOps Pipelines"]
        Repo --> ADO
    end

    subgraph Train["Training"]
        Data["Synthetic insurance<br/>risk dataset (CSV)"]
        TrainJob["train.py<br/>Gradient Boosting"]
        Gate{"AUC ≥ 0.80?"}
        Registry["Model registry<br/>white-orchid-risk-model"]
        Data --> TrainJob --> Gate
        Gate -- "no" --> Fail["Block deploy"]
        Gate -- "yes" --> Registry
    end

    subgraph PreProd["Pre-Prod (Azure ML)"]
        EpPre["Managed online endpoint<br/>Standard_DS2_v2"]
    end

    subgraph Prod["Prod (AKS)"]
        EpProd["AKS online endpoint<br/>Standard_D4s_v3"]
    end

    subgraph App["User-facing"]
        UI["React + Express UI"]
        User["Underwriter / user"]
    end

    subgraph Obs["Monitoring & Drift"]
        AI["App Insights<br/>(per-prediction telemetry)"]
        Drift["Azure ML drift monitor<br/>+ metric alerts"]
        Dash["Azure dashboard"]
    end

    ADO --> TrainJob
    Registry -->|"ci-pipeline"| EpPre
    Registry -->|"model-promote-prod"| EpProd
    User --> UI
    UI -->|"/api/predict"| EpPre
    UI -->|"/api/predict-prod"| EpProd
    EpPre --> AI
    EpProd --> AI
    AI --> Drift --> Dash
```

## Prediction flow (UI)

On form submit, the UI calls both endpoints in parallel (`Promise.allSettled`):

- **Both respond** → side-by-side `ModelComparison` (highlights disagreement = drift signal).
- **Only pre-prod responds** → single `RiskResult` (prod not yet deployed).

![White Orchid UI — customer details form and side-by-side pre-prod vs prod model comparison](docs/images/ui-screenshot.png)

## Repo layout

```
infra/              Pre-prod Azure ML workspace + managed endpoint + App Service (UI)
infra-prod/         Prod AKS + Azure ML workspace + drift monitoring + dashboard
machinelearning/    Model code (train.py, score.py), conda envs, training job, sample data
pipelines/          Azure DevOps pipeline YAMLs
src/                Node.js/React UI (calls pre-prod + prod endpoints)
```

## Environments

| | Pre-prod | Prod |
|---|---|---|
| Endpoint | `ep-white-orchid-8bx7s6` (managed) | `ep-prod-white-orchid` (AKS) |
| Compute | Standard_DS2_v2 | AKS Standard_D4s_v3 |
| Pipeline | `ci-pipeline.yml` | `model-promote-prod-pipeline.yml` |

Azure region: `swedencentral`. See [`CLAUDE.md`](CLAUDE.md) for full details, and
[`GenAI.md`](GenAI.md) for GenAI/LLM extension ideas.
