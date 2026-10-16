# Image pull secret: what "kubectl create secret docker-registry" generated, written by hand
resource "kubernetes_secret_v1" "ghcr" {
  metadata {
    name      = "ghcr-secret"
    namespace = kubernetes_namespace_v1.devops_lab.metadata[0].name # reference = ordering
  }

  type = "kubernetes.io/dockerconfigjson"

  data_wo_revision = 1
  data_wo = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_user
          password = var.cr_pat
          auth     = base64encode("${var.github_user}:${var.cr_pat}")
        }
      }
    })
  }
}

# Argo CD repo credentials (the label tells Argo CD what this Secret is)
resource "kubernetes_secret_v1" "argocd_repo" {
  metadata {
    name      = "repo-devops-lab"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data_wo_revision = 1
  data_wo = {
    type     = "git"
    url      = var.repo_url
    username = var.github_user
    password = var.gh_repo_pat
  }
}