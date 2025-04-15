terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use the latest version compatible with your setup
    }
  }
}

# Default AWS provider (Backend - `eu-north-1`)
provider "aws" {
  region  = var.primary_region
  profile = "SandboxTsedey"
}

# Secondary AWS provider (ACM & CloudFront - `us-east-1`)
provider "aws" {
  alias   = "us_east_1"
  region  = var.secondary_region
  profile = "SandboxTsedey"
}
