resource "github_repository" "devops_lab" {
  name        = var.repository_name
  description = "Personal lab: GitHub Actions, Docker, Kubernetes, Helm, Argo CD, Terraform"
  visibility  = "public"

  has_issues   = true
  has_projects = true
  has_wiki     = true

  allow_merge_commit     = true
  allow_squash_merge     = true
  allow_rebase_merge     = true
  delete_branch_on_merge = true # NEW: delete release/deploy-* branches after merge

  # Safety net 1: if this resource is ever destroyed, ARCHIVE the repo instead of deleting it
  archive_on_destroy = true

  lifecycle {
    # Safety net 2: Terraform refuses ANY plan that would destroy this resource
    prevent_destroy = true
  }
}