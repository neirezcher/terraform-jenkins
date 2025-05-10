# Configure variables that will be populated from terraform.tfvars
variable "accessToken" {
  description = "Azure AD access token"
  type        = string
  sensitive   = true
}

variable "subscription" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant" {
  description = "Azure AD tenant ID"
  type        = string
  sensitive   = true
}
