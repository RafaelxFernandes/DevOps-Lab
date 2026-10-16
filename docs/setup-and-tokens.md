# Setup and tokens

[← Back to README](../README.md)

Tools on my PC, and every credential the project uses: what it can do, where it lives, how to rotate it.

**Contents**

- [Environment and tools](#environment-and-tools)
- [Tokens, secrets and permissions](#tokens-secrets-and-permissions)

## Environment and tools

| Tool | Notes |
|---|---|
| Windows 11 | |
| Git Bash | Main terminal. Same shell (bash) as the GitHub Actions Linux runners, so commands transfer 1:1. |
| Docker Desktop | Docker **and** a single-node Kubernetes cluster (`docker-desktop` context). |
| kubectl | Comes with Docker Desktop. |
| Helm 4 | `winget install Helm.Helm` (reopen the terminal afterwards). |
| VS Code | With the **GitHub Actions** extension (workflow autocomplete/validation). |
| GitHub Pro | Private repo; Actions minutes and private ghcr.io packages included. |

Ports used locally:

| Port | What |
|---|---|
| `localhost:8080` | the app (Service type LoadBalancer) |
| `localhost:8443` | Argo CD UI (via `kubectl port-forward`) |

---

## Tokens, secrets and permissions

Every credential in this project, what it can do, where it lives, and what to do when it expires.

### `GITHUB_TOKEN` (automatic, used by CI)

- Created **automatically by GitHub for every workflow run**, expires when the job ends. Nothing to create or store.
- Referenced as `${{ secrets.GITHUB_TOKEN }}`.
- What it may do is controlled by `permissions:` per job (**least privilege**: grant only what the job needs):

| Job | Permissions | Why |
|---|---|---|
| `test`, `docker`, `k8s-test` | defaults (read) | only read code |
| `publish` | `contents: read`, `packages: write` | push image to ghcr.io |
| `bump-version` | `contents: write`, `pull-requests: write` | push a branch + open a PR |

- **Repo setting required for `bump-version`:** Settings → Actions → General → Workflow permissions → **"Allow GitHub Actions to create and approve pull requests"**. Without it: permission error at `gh pr create`.

#### Two consequences of using `GITHUB_TOKEN` for the bump PR

**The bump PR shows no CI checks.** That's a deliberate GitHub rule: events created with the built-in `GITHUB_TOKEN` don't trigger new workflow runs, to prevent infinite loops of workflows triggering workflows. It's fine here, because the image was already fully tested before it was published. Companies that want checks on bot PRs use a **GitHub App token** or a **PAT** instead of `GITHUB_TOKEN`.

- *GitHub App token (preferred in companies):* you create a GitHub App owned by the org, install it on the repo, store its App ID + private key as repo secrets, and the workflow exchanges them for a short-lived token (e.g. with `actions/create-github-app-token`). Not tied to a person, fine-grained, auto-expiring.
- *PAT:* simpler, but tied to a human account (if that person leaves, it breaks) and long-lived.

**Merging the PR triggers CI on `main` again**, since it's a normal push. It rebuilds and pushes `latest` plus a new `sha-` tag, but no new version tag, so `bump-version` stays skipped and there's no loop.

### `CR_PAT`: classic PAT with `read:packages`

- **Why classic:** container registry access (ghcr.io) works with classic tokens and the `read:packages` scope.
- **Create:** GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → scope **`read:packages` only** → set an expiration.
- **Used in two places:**
  1. `docker login ghcr.io` on my PC (stored by Docker Desktop afterwards).
  2. The Kubernetes Secret **`ghcr-secret`** in namespace `devops-lab` (lets the cluster pull the private image; referenced by `imagePullSecrets` in the chart).
- **Never committed to git.** Created with `kubectl create secret` only.

### `GH_REPO_PAT`: fine-grained PAT, Contents read-only

- **Why fine-grained:** can be restricted to **one repository** and **read-only**. If leaked, it can only read this repo.
- **Create:** Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Repository access: *Only select repositories* → `DevOps-Lab` → Repository permissions → **Contents: Read-only** → expiration.
- **Used by:** Argo CD, stored in Secret **`repo-devops-lab`** in namespace `argocd`, recognised thanks to the label `argocd.argoproj.io/secret-type=repository`.
- Check in Argo CD UI → **Settings → Repositories** → status *Successful*.

### Argo CD admin password

- Auto-generated at install, stored in Secret `argocd-initial-admin-secret` (namespace `argocd`).
- Read it: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo`
- Kubernetes stores Secret values **base64-encoded** (encoding, *not* encryption), hence `base64 -d`.
- Real setups: change it and delete that secret, or use SSO (GitHub/Google/Okta login).

### `GITHUB_TOKEN` env var for Terraform (fine-grained PAT, Administration read/write)

- **Not** the automatic CI token: same variable name, different token. The GitHub Terraform provider reads `GITHUB_TOKEN` from the environment.
- **Create:** Fine-grained tokens → only `DevOps-Lab` → **Administration: Read and write**, **Contents: Read-only** → short expiration.
- **Can change the repo's settings**, so it's the most powerful token here. Only in the terminal, never in a file:
  ```bash
  read -s GITHUB_TOKEN && export GITHUB_TOKEN    # once per terminal
  ```
- Expired → Terraform fails with `401 Bad credentials`: create a new one and export it again.

### Tokens in Terraform (`terraform/cluster/`)

The same `CR_PAT` and `GH_REPO_PAT`, passed as `TF_VAR_cr_pat` / `TF_VAR_gh_repo_pat` (Terraform reads `TF_VAR_<name>` automatically). The variables are `ephemeral` and the Secrets use write-only `data_wo`, so the tokens are **never stored in Terraform state**. To rotate: export the new values, bump `data_wo_revision` in `terraform/cluster/secrets.tf`, `terraform apply`. Details: [docs/terraform.md](terraform.md#step-t3--cluster-bootstrap-with-terraform).

### When a token expires: rotation

Symptoms: Pods in `ImagePullBackOff` (CR_PAT expired) or Argo CD repo status *Failed* / app *Unknown* (GH_REPO_PAT expired).

```bash
# Replace the image pull secret
read -s CR_PAT
kubectl delete secret ghcr-secret -n devops-lab
kubectl create secret docker-registry ghcr-secret -n devops-lab \
  --docker-server=ghcr.io --docker-username=rafaelxfernandes --docker-password="$CR_PAT"
kubectl rollout restart deployment/devops-lab -n devops-lab   # retry pulls now

# Replace Argo CD's repo credentials
read -s GH_REPO_PAT
kubectl delete secret repo-devops-lab -n argocd
kubectl create secret generic repo-devops-lab -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/rafaelxfernandes/DevOps-Lab.git \
  --from-literal=username=rafaelxfernandes \
  --from-literal=password="$GH_REPO_PAT"
kubectl label secret repo-devops-lab -n argocd argocd.argoproj.io/secret-type=repository
```

### Safety rules I follow

- `read -s VAR` to paste tokens: hidden, and not saved in shell history.
- Secrets are **never** in git. (Companies use Sealed Secrets, External Secrets + a vault, or SOPS to manage them declaratively.)
- Smallest scope + an expiration on every token.
