terraform {
  required_version = ">= 1.16"

  required_providers {
    github = {
      source  = "integrations/github" # maintained by GitHub, not HashiCorp
      version = "~> 6.13"
    }
  }
}

provider "github" {
  owner = var.github_owner # the token comes from the GITHUB_TOKEN env var
}