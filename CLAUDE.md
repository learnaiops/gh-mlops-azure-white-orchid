# white-orchid

MLOps project on Azure: train, register, deploy, and monitor a health insurance risk prediction model using Azure ML, AKS, and Azure DevOps.
The domain is Insurance
## What this project does
Predict whether a customer is a “high risk” insurance customer.
Predicts the 

## Data set 
I created a synthetic health insurance risk dataset for you that is perfect for learning:

    Feature engineering
    Model training
    AUC calculation
    MLflow logging
    Azure ML deployment
    Endpoint monitoring
The dataset includes features like:

    age
    BMI
    smoker status
    chronic conditions
    annual income
    exercise frequency
    alcohol usage
    previous insurance claims
    family medical history
    region
## Repo layout

```
infra/              Pre-prod Azure ML workspace (managed online endpoint on Standard_DS2_v2)
infra-pord/         Prod AKS cluster + Azure ML workspace (Kubernetes online endpoint)
machinelearning/    Model code (train.py, score.py), conda envs, training job YAML, sample data
pipelines/          Azure DevOps pipeline YAMLs
src/                Node.js/React UI
```

## Environments

| | Pre-prod | Prod |
|---|---|---|
| Resource group | `rg-white-orchid-8bx7s6` | `rg-white-orchid-prod-31okr7` |
| ML workspace | `mlw-white-orchid-8bx7s6` | `mlw-white-orchid-prod-31okr7` |
| Endpoint | `ep-white-orchid-8bx7s6` | `ep-prod-white-orchid` |
| Deployment | `dp-white-orchid-8bx7s6` | `dp-prod-blue` |
| Compute | Managed (Standard_DS2_v2) | AKS (`aks-inf-prod`) |

## Pipelines

- `ci-pipeline.yml` — trains and deploys to **pre-prod** managed endpoint
- `model-promote-prod-pipeline.yml` — promotes validated model to **prod** AKS endpoint (trigger: push to `main`)
- `model-deploy-pipeline.yml` — manual train + deploy to pre-prod
- `ui-deploy-pipeline.yml` — deploys the Node.js UI

Azure DevOps service connection: `sp-blue-moon`  
Agent pool: `blue-moon-hub-linux`

## Infra (Terraform)

- `infra/` — pre-prod workspace, App Insights, Log Analytics, Web App for the UI
- `infra-pord/` — prod AKS cluster, ML workspace, monitoring schedule

Key resources in `infra-pord/`:
- `aks.tf` — AKS cluster + `null_resource` to install AML k8s extension and attach it as a compute target
- `monitoring.tf` — enables data collection on the prod deployment and creates the `white-orchid-risk-prod-monitor` daily schedule
- `log-analytics.tf` — Log Analytics workspace, Application Insights, AKS diagnostic settings, ML workspace diagnostic settings

## Model

- Algorithm: linear regression (sklearn) on BigMac index CSV data
- Input features: country, year
- Model registered as `white-orchid-risk-model` in both workspaces
- Training data: `machinelearning/data/health_insurance_risk_dataset.csv` (also in AML datastore `health_insurance_risk_dataset_data`)

## Monitoring (prod)

After `terraform apply` on `infra-pord/`:

Note: both `null_resource` steps skip gracefully if the endpoint is not yet deployed — re-run `terraform apply` after the first pipeline run to activate monitoring.

## Location

Azure region: `swedencentral`

## User

Naushad is a DevOps engineer learning MLOps on Azure.
