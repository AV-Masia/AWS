terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = var.project
      managed_by = "terraform"
    }
  }
}

# Аутентификация к Keycloak — bootstrap-admin из aws_secretsmanager_secret.keycloak_admin
# (см. secrets.tf). URL берём из уже поднятого ALB (ecs.tf) — тестовый стенд, без
# своего домена/сертификата, поэтому Keycloak слушает по HTTP.
provider "keycloak" {
  client_id = "admin-cli"
  username  = var.keycloak_admin_username
  password  = var.keycloak_admin_password
  url       = "http://${aws_lb.keycloak.dns_name}"
}
