resource "github_repository_ruleset" "protect_main" {
  name        = "protect-main"
  repository  = github_repository.devops_lab.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"] # special value: whatever the default branch is
      exclude = []
    }
  }

  rules {
    deletion         = true # main cannot be deleted
    non_fast_forward = true # no force-push to main (history can't be rewritten)
  }
}