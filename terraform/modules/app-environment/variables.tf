# The module's INPUTS: everything that differs between environments.

variable "name" {
  description = "Environment name, e.g. dev or prod"
  type        = string

  validation { # reject bad input at plan time
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name must be lowercase letters, digits or dashes (it becomes part of Kubernetes names)."
  }
}

variable "kustomize_path" {
  description = "Path in the repo of the Kustomize overlay to deploy"
  type        = string
}

variable "repo_url" {
  description = "Git repository Argo CD reads"
  type        = string
}

variable "target_revision" {
  description = "Git branch/tag Argo CD follows"
  type        = string
  default     = "main"
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD runs (Applications live there)"
  type        = string
  default     = "argocd"
}

variable "github_user" {
  description = "Username for the ghcr.io pull secret"
  type        = string
}

variable "cr_pat" {
  description = "Classic PAT with read:packages, for the ghcr.io pull secret"
  type        = string
  sensitive   = true
  ephemeral   = true # never stored in state (see T3)
}

variable "cr_pat_revision" {
  description = "Bump to push a new token value into the pull secret (write-only values are invisible to Terraform)"
  type        = number
  default     = 1
}
