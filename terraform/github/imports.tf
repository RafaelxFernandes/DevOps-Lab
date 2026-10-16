# "These resources already exist: adopt them, don't create them."
import {
  to = github_repository.devops_lab
  id = "DevOps-Lab"
}

import {
  to = github_workflow_repository_permissions.devops_lab
  id = "DevOps-Lab"
}

# No import for the ruleset: it doesn't exist yet, so Terraform creates it.