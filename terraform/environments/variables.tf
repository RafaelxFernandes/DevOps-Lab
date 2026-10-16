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

variable "cr_pat" {
  description = "Classic PAT with read:packages (same token as terraform/cluster)"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "cr_pat_revision" {
  description = "Bump when the token is rotated"
  type        = number
  default     = 1
}
