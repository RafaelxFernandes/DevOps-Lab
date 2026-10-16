# Every environment in ONE map. Adding "staging" = adding 3 lines here.
locals {
  environments = {
    dev = {
      kustomize_path = "kustomize/overlays/dev"
    }
    prod = {
      kustomize_path = "kustomize/overlays/prod"
    }
  }
}

# One module call, instantiated once per map entry (for_each)
module "env" {
  source   = "../modules/app-environment" # a local folder (could also be a git URL or registry module)
  for_each = local.environments

  name           = each.key # "dev" / "prod"
  kustomize_path = each.value.kustomize_path
  repo_url       = var.repo_url

  github_user     = var.github_user
  cr_pat          = var.cr_pat
  cr_pat_revision = var.cr_pat_revision
}
