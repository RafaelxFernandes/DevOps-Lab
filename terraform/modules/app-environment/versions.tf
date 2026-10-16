# A module declares WHICH providers it needs, but never configures them:
# the root configuration that calls the module passes its provider configuration in.
terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
  }
}
