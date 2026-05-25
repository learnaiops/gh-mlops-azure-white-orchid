#!/usr/bin/env bash
# manage-infra.sh — stop/start/status white-orchid Azure resources to save cost
#
# Usage:
#   ./manage-infra.sh stop    — scale everything down (cheapest idle state)
#   ./manage-infra.sh start   — bring everything back up
#   ./manage-infra.sh status  — show current state without making changes
#
# Pre-prod resources  (rg-white-orchid-8bx7s6, swedencentral)
#   • App Service web app        app-white-orchid-8bx7s6
#   • ML managed endpoint        ep-white-orchid-8bx7s6 / dp-white-orchid-8bx7s6
#   • ML compute cluster         cpu-cluster  (already min=0; shown in status only)
#
# Prod resources  (rg-white-orchid-prod-<suffix>, westeurope)
#   • AKS cluster                aks-white-orchid-prod-<suffix>   ← biggest cost driver
#   • ML Kubernetes endpoint     ep-prod-white-orchid / dp-prod-blue
#
# NOTE: The App Service Plan (asp-*) is a reserved slot billed whether or not
#       the web app is running. Stopping the web app saves nothing on the plan cost.
#       Only AKS stop/start and ML endpoint scaling actually reduce compute spend.
#
# Requirements: az CLI logged in with sufficient RBAC (Contributor on both RGs)

set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── static pre-prod names ─────────────────────────────────────────────────────
PREPROD_RG="rg-white-orchid-8bx7s6"
PREPROD_MLW="mlw-white-orchid-8bx7s6"
PREPROD_ENDPOINT="ep-white-orchid-8bx7s6"
PREPROD_DEPLOYMENT="dp-white-orchid-8bx7s6"
PREPROD_WEBAPP="app-white-orchid-8bx7s6"
PREPROD_COMPUTE="cpu-cluster"

# ── dynamic prod names (suffix from random_string) ────────────────────────────
discover_prod() {
  PROD_RG=$(az group list \
    --query "[?starts_with(name,'rg-white-orchid-prod-')].name | [0]" \
    -o tsv 2>/dev/null || true)

  if [[ -z "$PROD_RG" || "$PROD_RG" == "None" ]]; then
    PROD_DEPLOYED=false
    return
  fi

  PROD_DEPLOYED=true
  SUFFIX="${PROD_RG##rg-white-orchid-prod-}"
  PROD_MLW="mlw-white-orchid-prod-${SUFFIX}"
  PROD_AKS="aks-white-orchid-prod-${SUFFIX}"
  PROD_ENDPOINT="ep-prod-white-orchid"
  PROD_DEPLOYMENT="dp-prod-blue"
}

# ── helpers ───────────────────────────────────────────────────────────────────
webapp_state() {
  az webapp show --resource-group "$PREPROD_RG" --name "$PREPROD_WEBAPP" \
    --query state -o tsv 2>/dev/null || echo "Unknown"
}

endpoint_instances() {
  local rg=$1 mlw=$2 ep=$3 dp=$4
  az ml online-deployment show \
    --resource-group "$rg" --workspace-name "$mlw" \
    --endpoint-name "$ep" --name "$dp" \
    --query instance_count -o tsv 2>/dev/null || echo "Unknown"
}

aks_state() {
  az aks show --resource-group "$PROD_RG" --name "$PROD_AKS" \
    --query "powerState.code" -o tsv 2>/dev/null || echo "Unknown"
}

compute_state() {
  az ml compute show \
    --resource-group "$PREPROD_RG" --workspace-name "$PREPROD_MLW" \
    --name "$PREPROD_COMPUTE" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown"
}

# ── STOP ──────────────────────────────────────────────────────────────────────
do_stop() {
  echo ""
  echo "━━━  STOPPING white-orchid resources  ━━━"

  # 1. Scale pre-prod ML endpoint to 0
  info "Scaling pre-prod endpoint deployment to 0 instances..."
  if az ml online-deployment update \
      --resource-group "$PREPROD_RG" \
      --workspace-name "$PREPROD_MLW" \
      --endpoint-name "$PREPROD_ENDPOINT" \
      --name "$PREPROD_DEPLOYMENT" \
      --instance-count 0 \
      --no-wait 2>/dev/null; then
    success "Pre-prod endpoint scaling to 0 (async — takes ~2 min)"
  else
    warn "Pre-prod endpoint not found or already scaled down — skipping"
  fi

  # 2. Stop the App Service web app
  info "Stopping App Service web app: $PREPROD_WEBAPP..."
  if az webapp stop --resource-group "$PREPROD_RG" --name "$PREPROD_WEBAPP" 2>/dev/null; then
    success "Web app stopped"
    warn "App Service Plan (asp-white-orchid-8bx7s6) is still billed — delete the plan to fully save costs"
  else
    warn "Web app not found or already stopped — skipping"
  fi

  # 3. Prod: scale endpoint to 0, then stop AKS
  if [[ "$PROD_DEPLOYED" == true ]]; then
    info "Scaling prod endpoint deployment to 0 instances..."
    if az ml online-deployment update \
        --resource-group "$PROD_RG" \
        --workspace-name "$PROD_MLW" \
        --endpoint-name "$PROD_ENDPOINT" \
        --name "$PROD_DEPLOYMENT" \
        --instance-count 0 \
        --no-wait 2>/dev/null; then
      success "Prod endpoint scaling to 0 (async)"
    else
      warn "Prod endpoint not found or already scaled down — skipping"
    fi

    info "Stopping AKS cluster: $PROD_AKS (this saves the most cost, takes ~3 min)..."
    if az aks stop --resource-group "$PROD_RG" --name "$PROD_AKS" --no-wait 2>/dev/null; then
      success "AKS stop issued (async — watch: az aks show -g $PROD_RG -n $PROD_AKS --query powerState.code -o tsv)"
    else
      warn "AKS not found or already stopped — skipping"
    fi
  else
    warn "No prod resource group found — skipping prod resources"
  fi

  echo ""
  echo "━━━  Stop commands issued.  Run './manage-infra.sh status' in ~5 min to verify.  ━━━"
}

# ── START ─────────────────────────────────────────────────────────────────────
do_start() {
  echo ""
  echo "━━━  STARTING white-orchid resources  ━━━"

  # 1. Start AKS first (longest lead time ~5 min) so endpoint can come up after
  if [[ "$PROD_DEPLOYED" == true ]]; then
    info "Starting AKS cluster: $PROD_AKS..."
    if az aks start --resource-group "$PROD_RG" --name "$PROD_AKS" --no-wait 2>/dev/null; then
      success "AKS start issued (async — takes ~5 min before endpoint can scale up)"
    else
      warn "AKS not found or already running — skipping"
    fi
  else
    warn "No prod resource group found — skipping prod resources"
  fi

  # 2. Start the App Service web app
  info "Starting App Service web app: $PREPROD_WEBAPP..."
  if az webapp start --resource-group "$PREPROD_RG" --name "$PREPROD_WEBAPP" 2>/dev/null; then
    success "Web app started"
  else
    warn "Web app not found or already running — skipping"
  fi

  # 3. Scale pre-prod endpoint back up
  info "Scaling pre-prod endpoint deployment to 1 instance..."
  if az ml online-deployment update \
      --resource-group "$PREPROD_RG" \
      --workspace-name "$PREPROD_MLW" \
      --endpoint-name "$PREPROD_ENDPOINT" \
      --name "$PREPROD_DEPLOYMENT" \
      --instance-count 1 \
      --no-wait 2>/dev/null; then
    success "Pre-prod endpoint scaling to 1 (async — takes ~2 min)"
  else
    warn "Pre-prod endpoint not found — skipping"
  fi

  # 4. Scale prod endpoint back up (only after AKS is Running)
  if [[ "$PROD_DEPLOYED" == true ]]; then
    info "Scaling prod endpoint deployment to 1 instance..."
    info "  (This will fail if AKS hasn't finished starting yet — re-run start if needed)"
    if az ml online-deployment update \
        --resource-group "$PROD_RG" \
        --workspace-name "$PROD_MLW" \
        --endpoint-name "$PROD_ENDPOINT" \
        --name "$PROD_DEPLOYMENT" \
        --instance-count 1 \
        --no-wait 2>/dev/null; then
      success "Prod endpoint scaling to 1 (async)"
    else
      warn "Prod endpoint not found or AKS not ready — re-run './manage-infra.sh start' once AKS is Running"
    fi
  fi

  echo ""
  echo "━━━  Start commands issued.  Run './manage-infra.sh status' in ~5 min to verify.  ━━━"
}

# ── STATUS ────────────────────────────────────────────────────────────────────
do_status() {
  echo ""
  echo "━━━  white-orchid resource status  ━━━"
  echo ""
  echo "PRE-PROD  ($PREPROD_RG)"

  WS=$(webapp_state)
  echo "  Web app ($PREPROD_WEBAPP):          $WS"

  EP=$(endpoint_instances "$PREPROD_RG" "$PREPROD_MLW" "$PREPROD_ENDPOINT" "$PREPROD_DEPLOYMENT")
  echo "  ML endpoint instances:             $EP"

  CS=$(compute_state)
  echo "  Compute cluster ($PREPROD_COMPUTE): $CS (auto-scales; min=0)"

  echo ""
  if [[ "$PROD_DEPLOYED" == true ]]; then
    echo "PROD  ($PROD_RG)"
    AKS=$(aks_state)
    echo "  AKS ($PROD_AKS):    $AKS"

    EP2=$(endpoint_instances "$PROD_RG" "$PROD_MLW" "$PROD_ENDPOINT" "$PROD_DEPLOYMENT")
    echo "  ML endpoint instances ($PROD_ENDPOINT/$PROD_DEPLOYMENT): $EP2"
  else
    echo "PROD  — not yet deployed"
  fi
  echo ""
}

# ── entrypoint ────────────────────────────────────────────────────────────────
ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 {stop|start|status}"
  exit 1
fi

case "$ACTION" in
  stop|start|status) ;;
  *)
    err "Unknown action: $ACTION"
    echo "Usage: $0 {stop|start|status}"
    exit 1
    ;;
esac

info "Checking Azure login..."
if ! az account show -o none 2>/dev/null; then
  err "Not logged in. Run: az login"
  exit 1
fi
success "Logged in as: $(az account show --query user.name -o tsv)"

info "Discovering prod resource group..."
discover_prod
if [[ "$PROD_DEPLOYED" == true ]]; then
  success "Prod resources found: $PROD_RG (suffix: $SUFFIX)"
else
  warn "No prod resources found — prod steps will be skipped"
fi

case "$ACTION" in
  stop)   do_stop   ;;
  start)  do_start  ;;
  status) do_status ;;
esac
