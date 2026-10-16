# A "for expression": build a map from all module instances
output "environments" {
  description = "Namespace and Argo CD Application of each environment"
  value = {
    for name, env in module.env : name => {
      namespace   = env.namespace
      application = env.application_name
    }
  }
}
