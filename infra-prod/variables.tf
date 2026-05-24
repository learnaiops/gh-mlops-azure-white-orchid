variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "swedencentral"
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
  description = "VM size for the AKS inference node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_min_node_count" {
  description = "Minimum number of AKS nodes (autoscaler lower bound)"
  type        = number
  default     = 1
}

variable "aks_max_node_count" {
  description = "Maximum number of AKS nodes (autoscaler upper bound)"
  type        = number
  default     = 3
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
