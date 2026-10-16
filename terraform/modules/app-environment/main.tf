# One environment of the app = namespace + image pull secret + Argo CD Application.

locals {
  namespace = "devops-lab-${var.name}" # e.g. devops-lab-dev
}

# 1. The namespace (Terraform owns it, so the Kustomize overlays don't create it)
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.namespace
    labels = {
      environment = var.name
    }
  }
}

# 2. The image pull secret: created with write-only data, never stored in state
resource "kubernetes_secret_v1" "ghcr" {
  metadata {
    name      = "ghcr-secret"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data_wo_revision = var.cr_pat_revision
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

# 3. The Argo CD Application that deploys the Kustomize overlay into the namespace.
#    kubernetes_manifest = any Kubernetes object written in HCL. It needs the CRD to exist
#    at plan time: fine here, because Argo CD is already installed (terraform/cluster).
resource "kubernetes_manifest" "application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "devops-lab-${var.name}"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        targetRevision = var.target_revision
        path           = var.kustomize_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace_v1.this.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  # The pull secret must exist before Argo CD starts creating Pods
  depends_on = [kubernetes_secret_v1.ghcr]
}
