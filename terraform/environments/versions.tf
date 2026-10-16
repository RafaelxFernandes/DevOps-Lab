terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
  }
}

# The ROOT configures the provider; the module inherits it automatically.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}
