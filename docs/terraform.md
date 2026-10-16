# Part 4: Terraform (infrastructure as code)

[← Back to README](../README.md)

Terraform describes infrastructure in files and makes reality match them: it creates, changes and deletes things through **providers** (AWS, Azure, GitHub, Kubernetes, Helm…).

**Contents**

- [Where Terraform fits](#where-terraform-fits)
- [Roadmap](#roadmap)
- [Setup](#setup)
- [Step T1 – Basics with a local file](#step-t1--basics-with-a-local-file)
- [Step T2 – The GitHub repo as code](#step-t2--the-github-repo-as-code)
- [Concepts reference](#concepts-reference)
- [Terraform vs OpenTofu](#terraform-vs-opentofu)

---

## Where Terraform fits

```
Terraform   →  creates the INFRASTRUCTURE      cloud cluster, networks, DNS, databases,
                                               IAM, GitHub repo settings…
CI          →  builds and tests the APP        GitHub Actions
Argo CD     →  manages what runs INSIDE        apps, Argo CD itself
               the Kubernetes cluster
```

Same idea as Argo CD (desired state in git → reality), one layer lower. One difference: Argo CD watches **continuously**; Terraform only checks when you run `plan`/`apply`.

## Roadmap

| Step | Topic | Status |
|---|---|---|
| T1 | install, `init → plan → apply → destroy`, state, drift | ✅ |
| T2 | GitHub provider: repo settings as code, `import`, safety nets, `count` | ✅ |
| T3 | Helm + Kubernetes providers: cluster bootstrap with Terraform, secrets in state | next |
| T4 | Terraform in CI: `fmt` / `validate` / `plan` on PRs, remote state | |
| T5 | modules + per-environment variables | |

---

## Setup

```bash
winget install Hashicorp.Terraform     # reopen Git Bash afterwards
terraform version                      # v1.16.x
```

VS Code extension: **HashiCorp Terraform** (highlighting, autocomplete, format on save).

### `.gitignore` additions

```
# Terraform
.terraform/            # downloaded providers (like node_modules)
*.tfstate              # state: may contain secrets, never commit
*.tfstate.*            # state backups
*.tfvars               # variable values: may contain tokens
crash.log
terraform/t1-basics/hello.txt
```

**Do commit** `.terraform.lock.hcl`: it pins exact provider versions (like `package-lock.json`), so everyone and CI use the same ones.

---

## Step T1 – Basics with a local file

A harmless resource (a text file on my PC) to learn the workflow with zero risk.

### `terraform/t1-basics/main.tf`

```hcl
# Which Terraform version and which providers (plugins) this code needs
terraform {
  required_version = ">= 1.16"

  required_providers {
    local = {
      source  = "hashicorp/local"   # registry.terraform.io/hashicorp/local
      version = "~> 2.9"            # any 2.x from 2.9 up (not 3.0)
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
  filename = "${path.module}/hello.txt"   # path.module = this folder
  content  = "${var.greeting}\n"          # var.x = read a variable
}

# An OUTPUT: a value printed after apply
output "file_path" {
  value = local_file.hello.filename       # <TYPE>.<NAME>.<ATTRIBUTE>
}
```

| Syntax | Meaning |
|---|---|
| `resource "local_file" "hello"` | type `local_file` (from the `local` provider), named `hello` in my code |
| `local_file.hello.filename` | **reference** to another resource's attribute; Terraform uses references to work out the order |
| `var.greeting` | a variable's value |
| `"${...}"` | expression inside a string |
| `~> 2.9` | ≥ 2.9 and < 3.0: bug fixes yes, breaking changes no |

### The workflow

```bash
cd terraform/t1-basics
terraform init        # download providers into .terraform/, create .terraform.lock.hcl
terraform fmt         # format .tf files
terraform validate    # syntax + type check, changes nothing
terraform plan        # what WOULD happen (changes nothing)
terraform apply       # shows the plan again, asks "yes"
terraform destroy     # delete everything this folder created
```

Plan symbols: `+` create · `~` update in place · `-` destroy · `-/+` destroy and recreate (**replace**).
**Reading plans is the most important Terraform skill.**

### State

```bash
terraform state list  # what Terraform manages
terraform show        # everything it knows about it
```

`terraform.tfstate` (JSON) is Terraform's **memory**. Every plan compares three things:

```
.tf code   ←→   state (what I created last time)   ←→   reality (what exists now)
```

Never commit state: for real resources it holds IDs, IPs and often **secrets in plain text**.

### What I practised

| Exercise | What it showed |
|---|---|
| `apply -var 'greeting=...'` | changing `content` forces **`-/+` replacement**: some changes can't be done in place, and the plan says so |
| `rm hello.txt` → `plan` | **drift**: reality ≠ state → Terraform wants to recreate it |
| `destroy` | removes everything it created; state becomes empty |

---

## Step T2 – The GitHub repo as code

Terraform manages the real repository's settings. New concepts: **import**, **safety nets**, **`count`**.

### What's managed

| Setting | Before | After |
|---|---|---|
| Description, visibility, features | clicked | in code |
| "Allow GitHub Actions to create and approve pull requests" | clicked in step 7 | in code |
| Auto-delete branches after merge | off | **on** (cleans up `release/deploy-*` branches) |
| Protection of `main` (no deletion, no force-push) | none | **ruleset** |
| Visibility | private | **public** (rulesets on private repos need a paid plan) |

### Token

A **fine-grained PAT**: only `DevOps-Lab`, **Administration: Read and write**, **Contents: Read-only**, short expiration. The provider reads it from `GITHUB_TOKEN`:

```bash
read -s GITHUB_TOKEN && export GITHUB_TOKEN    # once per terminal
```

`export` makes the variable visible to programs started from the shell (Terraform), not just the shell itself.

### Files in `terraform/github/`

Terraform reads **every `.tf` file in the folder** as one configuration; splitting is only for readability.

**`versions.tf`**
```hcl
terraform {
  required_version = ">= 1.16"
  required_providers {
    github = {
      source  = "integrations/github"   # maintained by GitHub
      version = "~> 6.13"
    }
  }
}

provider "github" {
  owner = var.github_owner   # token from the GITHUB_TOKEN env var
}
```

**`variables.tf`**
```hcl
variable "github_owner" {
  type    = string
  default = "rafaelxfernandes"
}

variable "repository_name" {
  type    = string
  default = "DevOps-Lab"
}

variable "enable_main_protection" {
  description = "Create the ruleset protecting main (private repos need GitHub Pro/Team)"
  type        = bool
  default     = true
}
```

**`repository.tf`**
```hcl
resource "github_repository" "devops_lab" {
  name        = var.repository_name
  description = "Personal lab: GitHub Actions, Docker, Kubernetes, Helm, Argo CD, Terraform"
  visibility  = "public"

  has_issues   = true
  has_projects = true
  has_wiki     = true

  allow_merge_commit     = true
  allow_squash_merge     = true
  allow_rebase_merge     = true
  delete_branch_on_merge = true

  archive_on_destroy = true          # safety net 1: archive instead of delete

  lifecycle {
    prevent_destroy = true           # safety net 2: refuse any plan that destroys it
  }
}
```

**`actions.tf`**
```hcl
resource "github_workflow_repository_permissions" "devops_lab" {
  repository                       = github_repository.devops_lab.name
  default_workflow_permissions     = "read"   # GITHUB_TOKEN read-only unless a job asks for more
  can_approve_pull_request_reviews = true     # "Allow GitHub Actions to create and approve PRs"
}
```

**`rulesets.tf`**
```hcl
resource "github_repository_ruleset" "protect_main" {
  count = var.enable_main_protection ? 1 : 0   # 1 = create, 0 = don't

  name        = "protect-main"
  repository  = github_repository.devops_lab.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]   # whatever the default branch is
      exclude = []
    }
  }

  rules {
    deletion         = true   # main cannot be deleted
    non_fast_forward = true   # no force-push to main
  }
}
```

**`imports.tf`**
```hcl
# These already existed: adopt them instead of creating them.
import {
  to = github_repository.devops_lab
  id = "DevOps-Lab"
}

import {
  to = github_workflow_repository_permissions.devops_lab
  id = "DevOps-Lab"
}
```

**`outputs.tf`**
```hcl
output "repository_url" {
  value = github_repository.devops_lab.html_url
}
```

### Import: adopting what already exists

`import { to = ..., id = ... }` (config-driven import) tells the next plan to **read the existing object into state** instead of creating it. The `id` format depends on the resource type (here: the repo name).

**The import rule: after import, the plan must show only the changes you want.** Every other `~` line means the code doesn't match reality: either accept it or change the code to the current value, then plan again.

What happened in my first plan:

```
~ delete_branch_on_merge = false -> true          ← intended
+ description            = "Personal lab: ..."   ← intended
~ has_wiki               = false -> true          ← NOT intended: my code said true, repo had it off
Plan: 2 to import, 1 to add, 1 to change, 0 to destroy.
```

I applied it anyway, so the wiki got turned on. Harmless, but exactly the mistake the rule is about.

### Safety nets for things that must never disappear

| Mechanism | Effect |
|---|---|
| `lifecycle { prevent_destroy = true }` | any plan that would destroy the resource **fails**. `terraform plan -destroy` → "Instance cannot be destroyed" |
| `archive_on_destroy = true` | provider-specific: archive the repo instead of deleting it |

### `count`: conditional resources

| Syntax | Meaning |
|---|---|
| `count = 1` / `0` | create one copy or none |
| `condition ? a : b` | if/else in one expression |
| `resource.name[0]` | with `count`, the resource becomes a list: references need an index |

Used here as a **feature switch**: the ruleset exists only when `enable_main_protection` is true. Switching from the command line: `terraform apply -var 'enable_main_protection=false'`.

### What happened when the ruleset failed

The first apply failed on the ruleset with **`403 Upgrade to GitHub Pro or make this repository public`**: the account is on **GitHub Free** (billing page: "GitHub Free", "Copilot Free"), and rulesets on private repos need a paid plan.

**Terraform is not all-or-nothing:** the two imports and the repo changes had already succeeded and were saved in state; only the ruleset was missing. The next plan showed just the ruleset left to create.

Fix: `visibility = "public"` **in code** (plan → apply), not by clicking. Because the ruleset references the repo, Terraform made the repo public **first**, then created the ruleset.

Before going public I checked that the history had no secrets:
```bash
git log -p --all | grep -n -E 'ghp_|github_pat_|gho_' || echo "no GitHub tokens found in history"
git log --format='%ae' | sort -u      # emails visible in commits
```

Side effects of going public: Actions minutes are free for public repos (standard runners); container images on ghcr.io keep their **own** (private) visibility.

### What I verified

| Test | Result |
|---|---|
| Settings → General | description set, "Automatically delete head branches" ticked, repo public |
| Settings → Rules → Rulesets | `protect-main` active |
| Settings → Actions → General | PR permission still ticked |
| Untick "delete head branches" by hand → `plan` | drift detected: `~ delete_branch_on_merge = false -> true` → `apply` fixed it |
| `terraform plan -destroy` | fails on purpose (`prevent_destroy`) |

### Why the ruleset doesn't require PRs or status checks

That's the usual company setup, but here it would collide with the existing flow: the **bump PR has no CI checks** (the `GITHUB_TOKEN` rule, see [setup-and-tokens.md](setup-and-tokens.md#github_token-automatic-used-by-ci)), so "require status checks" would block merging it, and "require a PR" would block direct pushes to `main`. Revisited in T4.

---

## Concepts reference

| Concept | Meaning |
|---|---|
| **Provider** | plugin that talks to one platform (`hashicorp/local`, `integrations/github`, …) |
| **Resource** | one managed object: `resource "<type>" "<name>" { ... }` |
| **Variable / output** | inputs (`var.x`) / values printed after apply |
| **Reference** | `type.name.attribute`: also defines the order of operations |
| **State** | Terraform's memory of what it manages; never in git; may contain secrets |
| **Plan** | the diff between code, state and reality: read it every time |
| **Drift** | reality changed outside Terraform; shown by the next plan |
| **Import** | adopt an existing object into state instead of creating it |
| **Lock file** | `.terraform.lock.hcl`: exact provider versions; committed |

## Terraform vs OpenTofu

In 2023 HashiCorp moved Terraform from an open-source license to a more restrictive one. The community fork **OpenTofu** (Linux Foundation) is almost a drop-in replacement: same HCL language, `tofu` instead of `terraform`. Everything learned here applies to both.
