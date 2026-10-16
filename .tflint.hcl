# TFLint: a linter for Terraform (like flake8/eslint for HCL)
plugin "terraform" {
  enabled = true
  preset  = "recommended"   # built-in rules: unused declarations, version pins, deprecated syntax…
}