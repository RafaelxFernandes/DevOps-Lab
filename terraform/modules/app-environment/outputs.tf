# The module's OUTPUTS: values the caller can use (module.<name>.<output>).

output "namespace" {
  description = "Namespace of this environment"
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "application_name" {
  description = "Name of the Argo CD Application"
  value       = kubernetes_manifest.application.manifest.metadata.name
}
