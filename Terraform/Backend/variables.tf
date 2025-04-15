variable "primary_region" {
  description = "The primary AWS region for deployment"
  type        = string
  default     = "eu-north-1"
}

variable "secondary_region" {
  description = "The secondary AWS region for deployment"
  type        = string
  default     = "us-east-1"
}
