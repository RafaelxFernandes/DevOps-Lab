terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

# Both providers talk to the cluster through the kubeconfig, PINNED to one context:
# even if kubectl currently points elsewhere, Terraform only ever touches docker-desktop.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = { # Helm provider v3 syntax: an attribute (with "="), not a block
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}