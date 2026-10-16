variable "kube_context" {
  description = "kubeconfig context Terraform is allowed to touch"
  type        = string
  default     = "docker-desktop"
}

variable "github_user" {
  type    = string
  default = "rafaelxfernandes"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/rafaelxfernandes/DevOps-Lab.git"
}

variable "argocd_chart_version" {
  description = "Keep equal to argocd/apps/argocd.yaml and scripts/bootstrap.sh"
  type        = string
  default     = "10.7.1"
}

# --- Secrets: no default, so they MUST come from outside (env vars) ---
variable "cr_pat" {
  description = "Classic PAT with read:packages (image pulls)"
  type        = string
  sensitive   = true
  ephemeral   = true # never stored in plan or state
}

variable "gh_repo_pat" {
  description = "Fine-grained PAT, Contents read-only (Argo CD reads the repo)"
  type        = string
  sensitive   = true
  ephemeral   = true
}