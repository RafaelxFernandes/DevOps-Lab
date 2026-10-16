# 1. Argo CD itself: same chart, version, release name and values as bootstrap.sh
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  values     = [file("${path.module}/../../platform/argocd/values.yaml")]
  timeout    = 600 # seconds; first install pulls several images

  # HANDOVER: Terraform installs Argo CD ONCE. After that, the "argocd" Application
  # (argocd/apps/argocd.yaml) owns it from git. Without this, Terraform and Argo CD
  # would both try to manage the same release.
  lifecycle {
    ignore_changes = all
  }
}

# 2. The root app, read from the SAME file Argo CD uses (one source of truth)
locals {
  root_app = yamldecode(file("${path.module}/../../argocd/root-app.yaml"))
}

# Created through the small official "argocd-apps" chart, because Terraform can't
# validate an "Application" before Argo CD's CRDs exist (they don't, on an empty cluster).
resource "helm_release" "root_app" {
  name       = "root-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.6"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode({
    applications = {
      (local.root_app.metadata.name) = merge(local.root_app.spec, {
        namespace = local.root_app.metadata.namespace
      })
    }
  })]

  # No attribute references these, so tell Terraform the order explicitly:
  # Argo CD must run, and its credentials must exist, before the root app starts syncing.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo,
    kubernetes_secret_v1.ghcr,
  ]
}