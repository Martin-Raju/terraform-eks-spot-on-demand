terraform {
  required_version = ">= 1.6.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.15.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.04"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3.7"
    }
    helm = {
      source = "hashicorp/helm"
      #version = "~> 3.0.2"
      version = ">= 2.5.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.16.0"
    }
  }
}
