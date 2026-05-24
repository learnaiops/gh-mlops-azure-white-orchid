variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "swedencentral"
}

variable "service_connection_client_id" {
  description = "Client (application) ID of the Azure DevOps service connection app registration"
  type        = string
  default     = "1f79af3a-acab-4259-8a61-2fc265567c2f"
}

variable "ml_endpoint_key" {
  description = "Primary key for the ML online scoring endpoint (set after first deploy)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "prod_ml_endpoint_url" {
  description = "Scoring URI of the prod AKS endpoint (set after infra-prod apply + model-promote pipeline)"
  type        = string
  default     = ""
}

variable "app_service_sku" {
  description = "SKU for the App Service Plan"
  type        = string
  default     = "B1"
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics"
  type        = number
  default     = 30
}
