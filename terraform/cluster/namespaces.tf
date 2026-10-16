resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace_v1" "devops_lab" {
  metadata {
    name = "devops-lab"
  }
}