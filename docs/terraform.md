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
| T4 | Terraform in CI: `fmt` / `validate` / `plan` on PRs, remote state | next |
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

## Terraform vs OpenTofu

In 2023 HashiCorp moved Terraform from an open-source license to a more restrictive one. The community fork **OpenTofu** (Linux Foundation) is almost a drop-in replacement: same HCL language, `tofu` instead of `terraform`. Everything learned here applies to both.
