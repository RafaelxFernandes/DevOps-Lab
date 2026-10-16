# ---------------------------------------------------------------------------
# T1: Terraform basics with a harmless local file.
# ---------------------------------------------------------------------------

# Which Terraform version and which providers (plugins) this code needs
terraform {
  required_version = ">= 1.16"

  required_providers {
    local = {
      source  = "hashicorp/local" # registry.terraform.io/hashicorp/local
      version = "~> 2.9"          # any 2.x from 2.9 up (not 3.0)
    }
  }
}

# A variable: an input with a default you can override
variable "greeting" {
  description = "Text written into the file"
  type        = string
  default     = "Hello from Terraform!"
}

# A RESOURCE: something Terraform creates and manages.
# Syntax: resource "<TYPE>" "<LOCAL NAME>" { ... }
resource "local_file" "hello" {
  filename = "${path.module}/hello.txt" # path.module = this folder
  content  = "${var.greeting}\n"        # var.x = read a variable
}

# An OUTPUT: a value printed after apply (and readable by other tools)
output "file_path" {
  value = local_file.hello.filename # <TYPE>.<NAME>.<ATTRIBUTE>
}