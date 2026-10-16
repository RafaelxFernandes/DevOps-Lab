output "next_steps" {
  value = <<-EOT
    Argo CD UI:  kubectl port-forward svc/argocd-server -n argocd 8443:443  →  https://localhost:8443
    Password:    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
  EOT
}