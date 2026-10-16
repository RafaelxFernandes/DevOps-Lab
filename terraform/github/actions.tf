resource "github_workflow_repository_permissions" "devops_lab" {
  repository                       = github_repository.devops_lab.name
  default_workflow_permissions     = "read" # GITHUB_TOKEN is read-only unless a job asks for more
  can_approve_pull_request_reviews = true   # "Allow GitHub Actions to create and approve PRs"
}