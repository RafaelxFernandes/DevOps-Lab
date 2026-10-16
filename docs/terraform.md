# Part 4: Terraform (infrastructure as code)

[← Back to README](../README.md)

Terraform describes infrastructure in files and makes reality match them: it creates, changes and deletes things through **providers** (AWS, Azure, GitHub, Kubernetes, Helm…).

**Contents**

- [What Terraform is and why companies use it](#what-terraform-is-and-why-companies-use-it)
- [How Terraform works](#how-terraform-works)
- [Where Terraform fits](#where-terraform-fits)
- [Roadmap](#roadmap)
- [Setup](#setup)
- [Step T1 – Basics with a local file](#step-t1--basics-with-a-local-file)
- [Step T2 – The GitHub repo as code](#step-t2--the-github-repo-as-code)
- [Step T3 – Cluster bootstrap with Terraform](#step-t3--cluster-bootstrap-with-terraform)
- [Step T4 – Terraform in CI](#step-t4--terraform-in-ci)
- [Step T5 – Modules and environments](#step-t5--modules-and-environments)
- [Concepts reference](#concepts-reference)
- [Terraform vs OpenTofu](#terraform-vs-opentofu)

---

## What Terraform is and why companies use it

**Infrastructure as Code (IaC)** means describing infrastructure (servers, Kubernetes clusters, networks, DNS records, databases, permissions, repository settings…) in **text files kept in git**, instead of creating it by clicking in web consoles.

Terraform (by HashiCorp) is the most widely used IaC tool. You write **what you want**; Terraform works out **how** to get there.

### Clicking vs code

| Clicking in a web console | Terraform |
|---|---|
| nobody remembers exactly what was clicked, or why | every setting is in a file, with git history (who, when, why) |
| rebuilding an environment = hours of clicking, easy to forget a step | `terraform apply` rebuilds it identically |
| dev and prod slowly drift apart | the same code (with different variables) creates both |
| a change goes live the moment you click | a change is a **PR**: reviewed, with a `plan` showing its exact effect |
| deleting a test environment: hope you find everything | `terraform destroy` removes everything it created |
| one console per platform | one language for AWS, Azure, Google, GitHub, Kubernetes, DNS… |

### Declarative, not step-by-step

A script says **how**: "create a repo, then enable this, then add that". Run it twice and it fails ("already exists").

Terraform is **declarative**: it says **what the end result is**. Terraform compares it with reality and does only what's missing. Running it twice is safe: the second time there's nothing to do. Kubernetes YAML and Argo CD work the same way, which is why this felt familiar.

### What companies typically manage with it

- the **cloud account**: networks, firewalls, permissions (IAM)
- the **Kubernetes cluster itself** (EKS, AKS, GKE) and its node pools
- **managed services** next to the cluster: databases, storage buckets, queues, DNS, certificates
- **SaaS settings**: GitHub repos and teams, monitoring dashboards and alerts, and more
- sometimes the **cluster bootstrap** (Argo CD install, base secrets), which is step T3 here

It's one of the most requested skills in DevOps / platform engineering job ads.

---

## How Terraform works

### The pieces

```
your .tf files (HCL)         →  what you want
        │
        ▼
Terraform core               →  compares and plans
        │       ▲
        │       └── state file  (what Terraform created last time, with IDs)
        ▼
providers (plugins)          →  translate into API calls
        │
        ▼
real platforms               →  GitHub API, AWS API, Kubernetes API, your disk…
```

| Piece | What it is |
|---|---|
| **HCL** | HashiCorp Configuration Language: the `.tf` files. Declarative, readable, with variables, references and expressions |
| **Terraform core** | the `terraform` program: reads the code, builds a dependency graph, plans, applies |
| **Providers** | plugins downloaded by `terraform init`, one per platform (`integrations/github`, `hashicorp/aws`, …). Terraform itself knows nothing about GitHub; the provider does |
| **Resources** | the objects you declare (`resource "github_repository" "devops_lab"`) |
| **State** | a JSON file mapping each resource in the code to the real object it created (IDs, attributes) |

### What happens on `plan` and `apply`

1. **Read the code** and build a **dependency graph** from the references. For example, the ruleset uses `github_repository.devops_lab.name`, so the repo comes first. Independent resources run in parallel.
2. **Refresh**: ask each provider what the real objects look like *now*.
3. **Diff** three things:
   ```
   code (desired)   ←→   state (what I manage)   ←→   reality (what exists)
   ```
4. **Plan**: list the actions needed (`+` create, `~` update, `-` destroy, `-/+` replace).
5. **Apply**: call the platform APIs through the providers, in graph order, and save the result into **state**.

### Why state exists

Reality alone isn't enough. Without state, Terraform couldn't tell:
- which real objects **it** manages (versus things created by hand or by other tools), and
- that a resource **deleted from the code** should be destroyed in reality.

That's why state is precious and sensitive:
- **lose it** → Terraform forgets what it manages (the next plan wants to create everything again)
- **commit it** → anyone with repo access can read whatever it contains, including secrets, in plain text
- **two people applying at once** → corrupted state. Teams keep it in a **remote backend** (S3, Azure Storage, Terraform Cloud…) with **locking**. That's step T4.

### Terraform vs Argo CD vs Ansible

| | Terraform | Argo CD | Ansible |
|---|---|---|---|
| Manages | infrastructure (cloud, SaaS settings) | apps inside Kubernetes | configuration inside servers (packages, files) |
| When it acts | only when you run `plan`/`apply` (or CI does) | continuously | when you run a playbook |
| Style | declarative + state | declarative, git = state | mostly step-by-step tasks |

Ansible isn't used in this lab; it's in the table because job ads often list it next to Terraform.

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
| T3 | Helm + Kubernetes providers: cluster bootstrap with Terraform, secrets in state | ✅ |
| T4 | Terraform in CI: `fmt` / `validate` / TFLint on PRs (part A); remote state + `plan` in CI (part B) | ✅ part A · 📘 part B documented |
| T5 | modules + environments (dev / prod) | ✅ |

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

## Step T3 – Cluster bootstrap with Terraform

Terraform takes over what `scripts/bootstrap.sh` does: namespaces, the two Secrets, Argo CD, and the root app. After that, Argo CD deploys everything else from git, exactly as before.

### Why, when `bootstrap.sh` already works

| `bootstrap.sh` | Terraform |
|---|---|
| runs commands in order and hopes | **plan first**: you see exactly what will be created |
| create-or-update written by hand (`--dry-run=client -o yaml \| kubectl apply -f -`) | create-or-update is built in |
| the order is the order of the lines | the order comes from **references** (dependency graph) |
| doesn't know what it created | **state**: knows what it manages, detects drift, can `destroy` |
| context check written by hand | the provider is **pinned** to the `docker-desktop` context in code |

Both stay in the repo: the script as the simple option, Terraform as the real-world one. Use **one or the other** on a given cluster, not both.

### Two providers

| Provider | Replaces | Used for |
|---|---|---|
| `hashicorp/kubernetes` | `kubectl create …` | namespaces, Secrets |
| `hashicorp/helm` | `helm upgrade --install …` | Argo CD, the root app |

### Starting point: an empty cluster

Terraform can't create things that already exist (see import in T2), so the cluster was reset first: Docker Desktop → **Settings → Kubernetes → Reset Kubernetes cluster**. That also made it a real test: `terraform apply` rebuilt everything from nothing.

### Tokens

The same two tokens as `bootstrap.sh` (see [setup-and-tokens.md](setup-and-tokens.md)), passed as environment variables. Terraform automatically reads `TF_VAR_<variable name>`:

```bash
read -s TF_VAR_cr_pat && export TF_VAR_cr_pat              # classic PAT, read:packages
read -s TF_VAR_gh_repo_pat && export TF_VAR_gh_repo_pat    # fine-grained, Contents read-only
```

### Files in `terraform/cluster/` (final version)

**`versions.tf`**
```hcl
terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

# Both providers use the kubeconfig, PINNED to one context:
# even if kubectl points elsewhere, Terraform only ever touches docker-desktop.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {                       # Helm provider v3 syntax: an attribute ("="), not a block
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}
```

**`variables.tf`**
```hcl
variable "kube_context" {
  description = "kubeconfig context Terraform is allowed to touch"
  type        = string
  default     = "docker-desktop"
}

variable "github_user" {
  type    = string
  default = "rafaelxfernandes"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/rafaelxfernandes/DevOps-Lab.git"
}

variable "argocd_chart_version" {
  description = "Keep equal to argocd/apps/argocd.yaml and scripts/bootstrap.sh"
  type        = string
  default     = "10.7.1"
}

# --- Secrets: no default, so they MUST come from outside (TF_VAR_ env vars) ---
variable "cr_pat" {
  description = "Classic PAT with read:packages (image pulls)"
  type        = string
  sensitive   = true          # hidden in plan/apply OUTPUT
  ephemeral   = true          # never stored in plan or state
}

variable "gh_repo_pat" {
  description = "Fine-grained PAT, Contents read-only (Argo CD reads the repo)"
  type        = string
  sensitive   = true
  ephemeral   = true
}
```

**`namespaces.tf`**
```hcl
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
```

The `_v1` suffix is the current naming: since provider v3, names without it (`kubernetes_namespace`) are deprecated.

**`secrets.tf`**
```hcl
# Image pull secret: what "kubectl create secret docker-registry" generated, written by hand
resource "kubernetes_secret_v1" "ghcr" {
  metadata {
    name      = "ghcr-secret"
    namespace = kubernetes_namespace_v1.devops_lab.metadata[0].name   # reference = ordering
  }

  type = "kubernetes.io/dockerconfigjson"

  data_wo_revision = 2        # write-only values are invisible to Terraform: bump to push a new value
                              # (1 at creation, 2 after the first token rotation)
  data_wo = {                 # write-only: sent to Kubernetes, NEVER stored in state
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

  data_wo_revision = 2
  data_wo = {
    type     = "git"
    url      = var.repo_url
    username = var.github_user
    password = var.gh_repo_pat
  }
}
```

**`argocd.tf`**
```hcl
# 1. Argo CD itself: same chart, version, release name and values as bootstrap.sh
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  values     = [file("${path.module}/../../platform/argocd/values.yaml")]
  timeout    = 600                         # seconds; first install pulls several images

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

  # No attribute references these, so the order is declared explicitly:
  # Argo CD must run, and its credentials must exist, before the root app starts syncing.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo,
    kubernetes_secret_v1.ghcr,
  ]
}
```

**`outputs.tf`**
```hcl
output "next_steps" {
  value = <<-EOT
    Argo CD UI:  kubectl port-forward svc/argocd-server -n argocd 8443:443  →  https://localhost:8443
    Password:    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
  EOT
}
```

The Argo CD password is deliberately **not** a Terraform output: reading it through Terraform (a data source) would store it in state.

### New concepts in T3

| Concept | Meaning |
|---|---|
| `TF_VAR_<name>` | environment variable that sets a Terraform variable |
| variable without `default` | must be provided from outside |
| `sensitive = true` | hides the value in plan/apply **output only**, not in state |
| `ephemeral = true` (variables) | the value is **never written** to plan or state; it can only be used where nothing is stored (e.g. write-only arguments) |
| `*_wo` (write-only arguments) | sent to the API, never stored in state (e.g. `data_wo` on `kubernetes_secret_v1`) |
| `*_wo_revision` | Terraform can't see write-only values, so it can't detect changes: bump this number to resend them |
| `.metadata[0].name` | blocks are lists in the provider's schema; `[0]` picks the single one |
| `jsonencode()` `yamlencode()` `yamldecode()` `file()` `base64encode()` `merge()` | built-in **functions** |
| `locals { }` | named intermediate values, used as `local.x` |
| `(expression) = value` | parentheses make a map **key** an expression |
| `depends_on` | explicit ordering when no reference exists |
| `lifecycle { ignore_changes = all }` | after creation, never update: **hand ownership to another tool** |
| `-replace=<address>` | force delete-and-recreate of one resource |
| `<<-EOT … EOT` | multi-line string (heredoc) |

### Two design decisions worth remembering

**1. The handover (`ignore_changes = all` on Argo CD).** Terraform installs Argo CD; from then on the `argocd` Application (step 9) manages it from git. If Terraform also kept managing the release, two tools would fight over the same resources. Common real-world pattern: *Terraform bootstraps, GitOps owns.* Consequence: Argo CD upgrades go through `argocd/apps/argocd.yaml`, never through `terraform apply`.

**2. The root app through the `argocd-apps` chart.** The natural choice (`kubernetes_manifest` with an `Application`) fails on an empty cluster: Terraform validates it during `plan`, when Argo CD's CRDs don't exist yet. Helm doesn't validate at plan time, so the small official `argocd-apps` chart creates the Application instead. Its values are built from `argocd/root-app.yaml` with `yamldecode`, so there's still **one** definition of the root app.

### The security lesson: secrets in state

**1. Naive version first.** The first version used `data = { … }` and variables with `sensitive = true` only. After `apply`:

```bash
grep -c "$TF_VAR_cr_pat" terraform.tfstate        # 2 → the token is in the file, in plain text
grep -c "$TF_VAR_gh_repo_pat" terraform.tfstate   # 2
```

`sensitive = true` only hides values **on screen**. To compare and update resources, Terraform stores their attributes in state. **Whoever can read the state can read every secret that went through Terraform.**

**2. The fix: ephemeral variables + write-only arguments.** Added `ephemeral = true` to both variables, and changed `data` to `data_wo` with `data_wo_revision = 1` (Terraform ≥ 1.11, and a provider that supports `*_wo` arguments).

**3. Surprise: the tokens were still in state.** After switching, `grep` still counted 2. Reading the provider's source code explained it: `data` is an *Optional + Computed* attribute; when `data_wo` is used, the provider **stops reading** `data`, but **never clears** the value already stored. The plan even showed it, as `# (6 unchanged attributes hidden)`.

| Secret… | State contains the token? |
|---|---|
| created with `data_wo` from the start | never |
| created with `data`, then switched to `data_wo` | yes, kept forever under `data` |

**Lesson: state remembers.** Changing how Terraform manages something doesn't scrub what it already stored.

**4. Fix: recreate the secrets** so they go through the "created with `data_wo`" path:

```bash
terraform apply \
  -replace=kubernetes_secret_v1.ghcr \
  -replace=kubernetes_secret_v1.argocd_repo
# plan: 2 to add, 0 to change, 2 to destroy (-/+ on the two secrets only)

grep -c "$TF_VAR_cr_pat" terraform.tfstate          # 0
grep -c "$TF_VAR_gh_repo_pat" terraform.tfstate     # 0
rm terraform.tfstate.backup                         # the PREVIOUS state, still had the tokens
```

**5. Rotation.** A secret that ever reached state counts as **exposed**, so both tokens were rotated:
1. Create new tokens on GitHub, delete the old ones.
2. Export the new values (`read -s TF_VAR_… && export TF_VAR_…`).
3. `data_wo_revision = 1` → `2` in both secrets.
4. `terraform plan` → `~ data_wo_revision = 1 -> 2` on both → `apply`.
5. `grep` checks again (0); Argo CD → Settings → Repositories → *Successful*; app Healthy.

`terraform.tfstate.backup` is covered by `*.tfstate.*` in `.gitignore`, so it was never at risk of being committed. Real teams also keep state in an **encrypted remote backend with access control** (T4), and often keep secrets out of Terraform entirely (External Secrets, Sealed Secrets).

### Commands used

```bash
cd terraform/cluster
terraform init && terraform fmt && terraform validate
terraform plan                 # first run: 6 to add (2 namespaces, 2 secrets, 2 Helm releases)
terraform apply                # a few minutes: installs Argo CD
kubectl get applications -n argocd     # root, argocd, devops-lab
curl http://localhost:8080/
```

### Drift and idempotency

```bash
terraform plan                                    # No changes.
kubectl delete secret ghcr-secret -n devops-lab   # drift
terraform plan                                    # ghcr will be created
terraform apply                                   # fixed (TF_VAR_ variables must be exported)
```

### Rebuilding the cluster with Terraform

The state describes **this** cluster. After a cluster reset, the old state describes things that no longer exist, so:

```bash
# Docker Desktop → Reset Kubernetes cluster, then:
cd terraform/cluster
rm -f terraform.tfstate terraform.tfstate.backup
read -s TF_VAR_cr_pat && export TF_VAR_cr_pat
read -s TF_VAR_gh_repo_pat && export TF_VAR_gh_repo_pat
terraform apply
```

Deleting state is right **here** only because the cluster itself isn't Terraform-managed. In a company, Terraform would also create the cluster, so code, state and cluster would never get out of step like this.

### Version pinning: now in three places

The Argo CD chart version (`10.7.1`) appears in:
1. `argocd/apps/argocd.yaml` (`targetRevision`): what Argo CD keeps running
2. `scripts/bootstrap.sh` (`ARGOCD_CHART_VERSION`): install via script
3. `terraform/cluster/variables.tf` (`argocd_chart_version`): install via Terraform

Keep them equal. If they differ, a fresh install deploys one version and Argo CD immediately upgrades or downgrades itself to the one in git.

---

## Step T4 – Terraform in CI

Two parts:

| Part | What | Status |
|---|---|---|
| **A** | `fmt` / `validate` / TFLint on every PR: no credentials, no state | ✅ implemented |
| **B** | remote state + `terraform plan` on PRs (+ optional apply on merge) | 📘 documented for the future; needs an extra account (decided not to create one for now) |

### Part A – Checks on every Terraform PR

| Check | Catches | Needs credentials or state? |
|---|---|---|
| `terraform fmt -check` | badly formatted files | no |
| `terraform validate` | syntax errors, wrong types, unknown references | no |
| **TFLint** | unused variables, missing version pins, deprecated syntax | no |

#### `.tflint.hcl` (repo root)

```hcl
# TFLint: a linter for Terraform (like flake8/eslint for HCL)
plugin "terraform" {
  enabled = true
  preset  = "recommended"   # built-in rules: unused declarations, version pins, deprecated syntax…
}
```

#### `.github/workflows/terraform.yml`

```yaml
name: Terraform

on:
  pull_request:
    paths:                                  # only run when Terraform code changes
      - "terraform/**"
      - ".tflint.hcl"
      - ".github/workflows/terraform.yml"
  push:
    branches: [main]
    paths:
      - "terraform/**"
      - ".tflint.hcl"
      - ".github/workflows/terraform.yml"
  workflow_dispatch:

permissions:
  contents: read                            # workflow-level default: read-only for every job

env:
  TF_VERSION: "1.16.6"                      # same Terraform version everywhere

jobs:
  # ── 1. Formatting: one job for the whole terraform/ folder ──────────
  fmt:
    name: terraform fmt
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: ${{ env.TF_VERSION }}
      - name: Check formatting
        run: terraform fmt -check -recursive -diff terraform/
        # -check: don't change files, just fail if they need formatting
        # -diff: show exactly what is wrong in the log

  # ── 2. Validate each configuration separately ───────────────────────
  validate:
    name: validate (${{ matrix.dir }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false                      # one broken folder doesn't cancel the others
      matrix:
        dir:
          - terraform/t1-basics
          - terraform/github
          - terraform/cluster
    defaults:
      run:
        working-directory: ${{ matrix.dir }}   # every "run:" step starts in that folder
    steps:
      - uses: actions/checkout@v7
      - uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: ${{ env.TF_VERSION }}
      - name: Init (providers only, no state)
        run: terraform init -backend=false -input=false
      - name: Validate
        run: terraform validate

  # ── 3. Lint everything with TFLint ──────────────────────────────────
  tflint:
    name: tflint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: terraform-linters/setup-tflint@v6
      - name: Install TFLint plugins
        run: tflint --init --config "$GITHUB_WORKSPACE/.tflint.hcl"
      - name: Lint all Terraform folders
        run: tflint --recursive --config "$GITHUB_WORKSPACE/.tflint.hcl" --format compact
```

#### New concepts in part A

| Concept | Meaning |
|---|---|
| **separate workflow file** | Terraform checks are independent from the app pipeline (`ci.yml`), with their own triggers |
| `paths:` filter | the workflow runs only when matching files change |
| `permissions:` at **workflow** level | default for all jobs; read-only is enough |
| `env:` at workflow level | one `TF_VERSION` for every job |
| `defaults.run.working-directory` | all `run:` steps of the job start in that folder |
| matrix over **folders** | same job once per Terraform configuration, in parallel |
| `fail-fast: false` | one failing matrix job doesn't cancel the others |
| `terraform init -backend=false` | downloads providers without touching state: validation needs no state and no credentials |
| `$GITHUB_WORKSPACE` | absolute path of the checked-out repo |

#### How to use it

```bash
terraform fmt -recursive terraform/     # before committing: fix formatting locally
```

Exercises on a PR branch:
- **Formatting:** extra spaces in a `.tf` file → `terraform fmt` job fails, the log shows the `-diff` → fix with `terraform fmt -recursive terraform/`.
- **Validation:** typo in a variable reference (e.g. `var.argocd_chart_versio`) → only `validate (terraform/cluster)` fails with `Reference to undeclared input variable`; the other two still pass (`fail-fast: false`).
- **TFLint:** if it flags something, read the rule name in the message; the rule docs explain the fix.

#### Why these checks aren't *required* on `main`

A ruleset can require status checks before merging. Two reasons not to here:
1. **`paths` filter pitfall:** a required check that **never runs** (the PR didn't touch `terraform/`) blocks that PR forever. Teams solve it with an always-running "gate" job that succeeds when nothing relevant changed and otherwise depends on the real checks.
2. **The bump PR has no checks at all** (the `GITHUB_TOKEN` rule, see [setup-and-tokens.md](setup-and-tokens.md#github_token-automatic-used-by-ci)). Real fix: a GitHub App token for the bump job.

### Part B – Remote state and `plan` in CI (for the future)

**Not implemented.** This section is a ready-to-follow guide for when it's wanted.

#### The problem with local state

`terraform.tfstate` currently lives on the laptop, so:
- CI **can't run `terraform plan`**: it doesn't have the state
- laptop lost → state lost → Terraform forgets what it manages
- no **locking**: two people (or a person + CI) applying at once can corrupt it
- the state's secrets are only as safe as the laptop

#### Remote backends

A **backend** is where Terraform keeps state. Remote backends add sharing, encryption, **locking** and history.

| Backend | Typical user | Cost / requirement |
|---|---|---|
| **HCP Terraform** (`cloud` block) | teams wanting a managed service with run history UI | HashiCorp account; a free tier exists (described by third parties as 500 managed resources since March 2026: check current terms) |
| **AWS S3** (`backend "s3"`) | AWS companies (most common overall) | AWS account; tiny storage cost |
| **Azure Storage** (`backend "azurerm"`) | Azure companies | Azure account |
| **Google Cloud Storage** (`backend "gcs"`) | Google Cloud companies | GCP account |
| **Kubernetes** (`backend "kubernetes"`) | state in a Secret inside a cluster | not reachable from GitHub runners for a local cluster |

**Scope for this repo:** only `terraform/github` would move. `terraform/cluster` stays local: GitHub's runners can't reach the Kubernetes cluster on the PC, so CI could never plan it anyway.

#### Option 1: HCP Terraform

1. Sign up at app.terraform.io, create an **organization** and a workspace (e.g. `devops-lab-github`, "CLI-driven workflow").
2. In the workspace settings, set **Execution mode: Local**, so HCP Terraform only stores state and runs happen on my PC / in GitHub Actions (with the default *Remote* mode, runs execute on HashiCorp's servers and the GitHub token would have to be stored there as a workspace variable).
3. Add to `terraform/github/versions.tf`, inside the `terraform { }` block:
   ```hcl
   cloud {
     organization = "<my-org>"
     workspaces {
       name = "devops-lab-github"
     }
   }
   ```
4. Log in and migrate the existing state:
   ```bash
   terraform login                  # opens the browser, stores an API token locally
   cd terraform/github
   terraform init -migrate-state    # copies local state to HCP Terraform (asks for confirmation)
   terraform plan                   # must say "No changes": same state, new location
   ```
5. Delete the local `terraform.tfstate*` files once the plan is clean.

#### Option 2: AWS S3 (the most common in companies)

```hcl
terraform {
  backend "s3" {
    bucket       = "<my-state-bucket>"          # created once, by hand or by a separate Terraform config
    key          = "devops-lab/github.tfstate"  # path of this configuration's state inside the bucket
    region       = "eu-south-1"
    encrypt      = true                         # encryption at rest
    use_lockfile = true                         # S3-native locking (Terraform ≥ 1.11): no DynamoDB table needed
  }
}
```

Then the same migration: `terraform init -migrate-state` → `terraform plan` shows "No changes". The bucket should have **versioning** enabled (old states recoverable) and **public access blocked**.

#### `plan` on every PR, posted as a comment

Sketch of a job to add to `terraform.yml` once state is remote (HCP Terraform version):

```yaml
  plan-github:
    name: plan (terraform/github)
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository
    #   ↑ only PRs from this repo: fork PRs don't get secrets, and must never be given them
    permissions:
      contents: read
      pull-requests: write                 # to post the plan as a comment
    defaults:
      run:
        working-directory: terraform/github
    env:
      GITHUB_TOKEN: ${{ secrets.TF_GITHUB_TOKEN }}   # fine-grained PAT for the GitHub provider (repo secret)
    steps:
      - uses: actions/checkout@v7
      - uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: ${{ env.TF_VERSION }}
          cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}   # HCP Terraform API token
          terraform_wrapper: false
      - run: terraform init -input=false
      - name: Plan
        run: terraform plan -no-color -input=false -lock-timeout=60s | tee plan.txt
      - name: Comment the plan on the PR
        env:
          GH_TOKEN: ${{ github.token }}      # the automatic token (only needs pull-requests: write)
        run: |
          { echo '### Terraform plan: `terraform/github`'; echo '```'; tail -c 60000 plan.txt; echo '```'; } > comment.md
          gh pr comment ${{ github.event.pull_request.number }} --body-file comment.md
```

Notes:
- **Two different tokens:** `TF_GITHUB_TOKEN` (repo secret, admin rights, used by the provider) vs `github.token` (automatic, used only to comment).
- `-lock-timeout=60s`: wait for the state lock instead of failing if someone else is running Terraform.
- **Public repo security:** never use the `pull_request_target` trigger to run Terraform on PR code: it runs with secrets on code written by strangers. The `if:` above skips fork PRs.

#### Optional: apply on merge

```yaml
  apply-github:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    environment: terraform-github     # Settings → Environments: add "Required reviewers" = manual approval
    # … same setup as plan-github, then:
    #   terraform apply -auto-approve -input=false
```

A GitHub **environment** with required reviewers pauses the job until someone approves it: "plan on PR, approve, apply on merge" is the classic company flow.

#### Going further (company practices)

- **OIDC instead of long-lived tokens:** GitHub Actions can get short-lived cloud credentials (AWS/Azure/GCP) without storing any secret.
- **Policy as code:** tools like OPA/Conftest, or HCP Terraform policies, block plans that break rules (e.g. "no public buckets").
- **Drift detection:** a scheduled workflow runs `terraform plan` nightly and alerts if reality changed.

---

## Step T5 – Modules and environments

A Terraform **module** that defines "one environment of the app", called once per environment. Result: two extra, real environments next to the main app.

| Environment | URL | Deployed from | Replicas | Version (at creation) |
|---|---|---|---|---|
| main app (unchanged) | `localhost:8080` | Helm chart `charts/devops-lab` | 2 | follows releases (bump PR) |
| **dev** | `localhost:8081` | Kustomize overlay `kustomize/overlays/dev` | 1 | 1.5.0 |
| **prod** | `localhost:8082` | Kustomize overlay `kustomize/overlays/prod` | 3 | 1.4.0 |

### The structure

```
terraform/environments/              ← ROOT: the list of environments (own state)
        │  calls once per environment (for_each)
        ▼
terraform/modules/app-environment/   ← MODULE: what ONE environment is
        ├─ namespace       devops-lab-<env>
        ├─ pull secret     ghcr-secret  (write-only, as in T3)
        └─ Argo CD Application → deploys kustomize/overlays/<env>
```

**Layered roots:** `terraform/environments` needs Argo CD to exist (its `Application` CRD), so it's applied **after** `terraform/cluster` (or `bootstrap.sh`). Separate folders = separate states = separate blast radius.

### What a module is

| Programming | Terraform |
|---|---|
| function definition | a module folder (`modules/app-environment/`) |
| parameters | its `variable` blocks |
| return values | its `output` blocks |
| function call | `module "env" { source = "..." ... }` |
| calling it in a loop | `for_each` on the module |

Every folder written before was already a module: the **root module**. Companies write "a standard environment / database / repo" **once**, with their conventions built in, and reuse it everywhere.

### Module: `terraform/modules/app-environment/`

**`versions.tf`**
```hcl
# A module declares WHICH providers it needs, but never configures them:
# the root configuration that calls the module passes its provider configuration in.
terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
  }
}
```

**`variables.tf`** (the module's inputs)
```hcl
variable "name" {
  description = "Environment name, e.g. dev or prod"
  type        = string

  validation {                                   # reject bad input at plan time
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name must be lowercase letters, digits or dashes (it becomes part of Kubernetes names)."
  }
}

variable "kustomize_path" {
  description = "Path in the repo of the Kustomize overlay to deploy"
  type        = string
}

variable "repo_url" {
  description = "Git repository Argo CD reads"
  type        = string
}

variable "target_revision" {
  description = "Git branch/tag Argo CD follows"
  type        = string
  default     = "main"
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD runs (Applications live there)"
  type        = string
  default     = "argocd"
}

variable "github_user" {
  description = "Username for the ghcr.io pull secret"
  type        = string
}

variable "cr_pat" {
  description = "Classic PAT with read:packages, for the ghcr.io pull secret"
  type        = string
  sensitive   = true
  ephemeral   = true            # never stored in state (see T3)
}

variable "cr_pat_revision" {
  description = "Bump to push a new token value into the pull secret"
  type        = number
  default     = 1
}
```

**`main.tf`**
```hcl
locals {
  namespace = "devops-lab-${var.name}"   # e.g. devops-lab-dev
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
#    at plan time: fine here, because Argo CD is already installed.
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
```

**`outputs.tf`** (the module's return values)
```hcl
output "namespace" {
  description = "Namespace of this environment"
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "application_name" {
  description = "Name of the Argo CD Application"
  value       = kubernetes_manifest.application.manifest.metadata.name
}
```

### Root: `terraform/environments/`

**`versions.tf`**
```hcl
terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
  }
}

# The ROOT configures the provider; the module inherits it automatically.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}
```

**`variables.tf`**
```hcl
variable "kube_context" {
  type    = string
  default = "docker-desktop"
}

variable "github_user" {
  type    = string
  default = "rafaelxfernandes"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/rafaelxfernandes/DevOps-Lab.git"
}

variable "cr_pat" {
  description = "Classic PAT with read:packages (same token as terraform/cluster)"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "cr_pat_revision" {
  description = "Bump when the token is rotated"
  type        = number
  default     = 1
}
```

**`main.tf`**
```hcl
# Every environment in ONE map. Adding "staging" = adding 3 lines here.
locals {
  environments = {
    dev = {
      kustomize_path = "kustomize/overlays/dev"
    }
    prod = {
      kustomize_path = "kustomize/overlays/prod"
    }
  }
}

# One module call, instantiated once per map entry (for_each)
module "env" {
  source   = "../modules/app-environment"   # a local folder (could also be a git URL or registry module)
  for_each = local.environments

  name           = each.key                 # "dev" / "prod"
  kustomize_path = each.value.kustomize_path
  repo_url       = var.repo_url

  github_user     = var.github_user
  cr_pat          = var.cr_pat
  cr_pat_revision = var.cr_pat_revision
}
```

**`outputs.tf`**
```hcl
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
```

### New concepts in T5

| Concept | Meaning |
|---|---|
| `module "x" { source = "../modules/…" }` | call a module. `source` can be a local folder, a git URL, or the public Terraform Registry |
| module **inputs** / **outputs** | its variables / its outputs, read by the caller as `module.env["dev"].namespace` |
| providers in modules | a module only **declares** providers (`required_providers`); the root **configures** them and the module inherits them |
| `for_each` with a map | one instance per key: `module.env["dev"]`, `module.env["prod"]` |
| `each.key` / `each.value` | current map key / value |
| `validation { }` | custom check on a variable, with your own error message, at plan time |
| `can(expr)` | true if `expr` works, false if it errors |
| `{ for k, v in … : k => … }` | **for expression**: build a map or list from another collection |
| `kubernetes_manifest` | any Kubernetes object in HCL (incl. custom resources like `Application`); needs API access and the CRD at **plan** time |
| **layered roots** | separate root folders with separate states, applied in order (cluster → environments) |

**`for_each` vs `count`:** `count` (T2) is for on/off switches. For collections use `for_each`: instances are named by **key**. With `count`, removing an item from the middle of a list shifts the indexes and Terraform destroys/recreates the wrong things.

### One owner per object: the overlays lost their `namespace.yaml`

Terraform now creates each namespace (the pull secret must exist **before** Argo CD deploys into it). If the Kustomize overlays also created the namespace, two tools would own the same object, the same conflict as the Argo CD handover in T3. So `kustomize/overlays/{dev,prod}/namespace.yaml` were deleted and removed from each `kustomization.yaml`.

### Commands used

```bash
cd terraform/environments
read -s TF_VAR_cr_pat && export TF_VAR_cr_pat
terraform init                 # "Initializing modules..." → the local module is registered
terraform fmt -recursive ../
terraform validate
terraform plan                 # Plan: 6 to add (3 resources × 2 environments)
terraform apply
terraform output environments
kubectl get applications -n argocd     # devops-lab-dev, devops-lab-prod
curl http://localhost:8081/            # dev
curl http://localhost:8082/            # prod
```

Resource addresses in plans and state now include the module instance:

```
module.env["dev"].kubernetes_namespace_v1.this
module.env["dev"].kubernetes_secret_v1.ghcr
module.env["prod"].kubernetes_manifest.application
```

### Exercises

| Exercise | Result |
|---|---|
| Add `staging = { kustomize_path = "kustomize/overlays/dev" }` to the map | plan: **3 to add**, all under `module.env["staging"]`; remove it again → **3 to destroy**. A new environment = 3 lines. (staging reuses dev's overlay, so both want port 8081: one Service gets it, the other stays `<pending>`) |
| Rename the key `dev` → `Dev_1` | plan stops with the module's own `validation` error message |
| Change `newTag` in the prod overlay and merge | prod updates through Argo CD; **Terraform isn't involved** (see the release guide below) |

### Who decides what

| Question | Decided by | Changes how often |
|---|---|---|
| *Which environments exist* (namespace, secret, Application) | Terraform (`terraform/environments`) | rarely |
| *Which version runs in each environment* | git (overlays / Helm values) + Argo CD | every release |

Infrastructure and versions are deliberately separated: a release never needs `terraform apply`.

### Other ways companies organize environments

| Pattern | How | When |
|---|---|---|
| **one root + `for_each`** (this lab) | all environments in one state | small setups; simple, but one `apply` touches every environment |
| **one root folder per environment** | `envs/dev/main.tf`, `envs/prod/main.tf`, each calling the same module | the most common: separate state, a mistake in dev can't touch prod |
| **same code + `.tfvars` files** | `terraform apply -var-file=prod.tfvars`, separate state per environment | common with remote backends. Note: this repo's `.gitignore` ignores `*.tfvars` (they can hold secrets); teams using this commit non-secret tfvars and ignore only secret ones |
| **workspaces** | `terraform workspace new prod`: same code, one state per workspace | simple, but easy to apply to the wrong workspace |

### Releases with three deployment targets

The complete step-by-step release guide (main app, dev, prod) is in the [README](../README.md#how-to-release--roll-back--change-the-platform-day-to-day). Summary:

```
git tag v1.6.0 ──► CI ──► "Deploy 1.6.0" PR (Helm values + dev overlay) ──► merge
                                                   │
                         Argo CD: main app + dev → 1.6.0
                                                   │
                         test in dev ──► one-line PR on the prod overlay ──► merge
                                                   │
                         Argo CD: prod → 1.6.0
```

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
| **Sensitive / ephemeral / write-only** | hidden on screen / never stored in plan or state / sent to the API but never stored |
| **Handover** | `lifecycle { ignore_changes = all }`: Terraform creates, another tool owns |
| **Backend** | where state is stored: local file (default) or remote (HCP Terraform, S3…) with locking |
| **Locking** | prevents two runs from changing the same state at once |
| **Module** | a reusable folder of `.tf` files with inputs (variables) and outputs |
| **`for_each`** | one instance per key of a map/set, addressed as `resource["key"]` |

## Terraform vs OpenTofu

In 2023 HashiCorp moved Terraform from an open-source license to a more restrictive one. The community fork **OpenTofu** (Linux Foundation) is almost a drop-in replacement: same HCL language, `tofu` instead of `terraform`. Everything learned here applies to both.
