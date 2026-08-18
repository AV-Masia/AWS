terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.5.0 — в этой версии появился aws_cognito_log_delivery_configuration
      version = "~> 6.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  # Чтобы потом одним фильтром найти и снести всё, что относится к этому демо
  default_tags {
    tags = {
      project    = var.project
      managed_by = "terraform"
    }
  }
}
