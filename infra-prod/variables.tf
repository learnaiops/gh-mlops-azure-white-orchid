variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "white-orchid"
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics"
  type        = number
  default     = 90
}

variable "service_connection_client_id" {
  description = "Client (application) ID of the Azure DevOps service connection app registration"
  type        = string
  default     = "1f79af3a-acab-4259-8a61-2fc265567c2f"
}

variable "aks_node_vm_size" {
  description = "VM size for the AKS inference node pool. Standard_D2s_v3 (2 vCPU) keeps 2 nodes within the 4-vCPU DSv3-family quota."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_min_node_count" {
  description = "Minimum number of AKS nodes (autoscaler lower bound). Kept at 2 so the AML extension's ~12-15 pods can schedule immediately on install, avoiding the ARM agent-response timeout that occurs while a single node autoscales."
  type        = number
  default     = 2
}

variable "aks_max_node_count" {
  description = "Maximum number of AKS nodes (autoscaler upper bound). Capped at 2 so 2x Standard_D2s_v3 (4 vCPU) stays within the 4-vCPU DSv3-family quota."
  type        = number
  default     = 2
}

variable "aks_compute_name" {
  description = "Name for the Kubernetes compute target registered in the Azure ML workspace"
  type        = string
  default     = "aks-inf-prod"
}

variable "prod_endpoint_name" {
  description = "Name for the production AKS Kubernetes online endpoint"
  type        = string
  default     = "ep-prod-white-orchid"
}

variable "prod_deployment_name" {
  description = "Name for the production AKS online deployment"
  type        = string
  default     = "dp-prod-blue"
}
