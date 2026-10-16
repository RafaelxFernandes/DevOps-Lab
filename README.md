# DevOps Lab

A personal project to learn, hands-on, how a real CI/CD + GitOps pipeline is built:
**GitHub Actions** → **Docker** → **Kubernetes** → **Helm** → **Argo CD**.

The app is deliberately tiny (a Flask app with two endpoints) so the focus stays on everything around it.

- **Part 1 (steps 1–5 + bonus):** everything done **by hand** to understand each piece.
- **Part 2 (steps 6–8):** replacing the manual parts with the tools companies use in real life.
- **Part 3 (step 9):** the "platform team" view: the whole platform rebuilt from git with **one command**, and Argo CD managing itself.

```
developer ─► PR ─► CI tests ─► merge ─► git tag v1.x.0
                                            │
      CI: test (×2) → docker → k8s-test (kind + Helm) → publish to ghcr.io → open "Deploy 1.x.0" PR
                                                                                 │
                                                          human reviews + merges the PR
                                                                                 │
                        Argo CD (inside the cluster) pulls git ─► syncs ─► self-heals drift
```

**Deploying = merging a PR. Rolling back = reverting a PR.** Nobody runs `kubectl`/`helm` against the cluster.

---

## Documentation

| Doc | What's inside |
|---|---|
| [Setup and tokens](docs/setup-and-tokens.md) | tools on the PC, every token/secret, rotation when they expire |
| [Part 1: by hand](docs/part1-by-hand.md) | steps 1–5 + bonus: app, Docker, GitHub Actions, ghcr.io, Kubernetes, kind in CI |
| [Part 2: real-world tools](docs/part2-real-world-tools.md) | steps 6–8: Helm, automated version-bump PR, Argo CD |
| [Part 3: platform as code](docs/part3-platform-as-code.md) | step 9: bootstrap script, app of apps, Argo CD managing itself |
| [CI/CD pipeline](docs/ci-pipeline.md) | the complete `ci.yml`, annotated |
| [Cheat sheet](docs/cheat-sheet.md) | the commands I use most |
| [Troubleshooting](docs/troubleshooting.md) | problems I hit, causes and fixes |

---

## Start from scratch (rebuild everything)

Use this when the cluster was reset (Docker Desktop → Reset Kubernetes), on a new PC, or to rebuild the whole environment from this repo. Every command is explained in the [docs](#documentation).

### Prerequisites

1. Install **Git**, **Docker Desktop**, **Helm** (`winget install Helm.Helm`), VS Code.
2. Docker Desktop → **Settings → Kubernetes → Enable Kubernetes** → Apply & restart. Check:
   ```bash
   kubectl config current-context   # docker-desktop
   kubectl get nodes                # Ready
   ```
3. Clone the repo:
   ```bash
   git clone https://github.com/rafaelxfernandes/DevOps-Lab.git
   cd DevOps-Lab
   ```

### GitHub one-time settings (already done for this repo; needed for a new repo)

- **Settings → Actions → General → Workflow permissions** → tick **"Allow GitHub Actions to create and approve pull requests"** (needed by the `bump-version` job).

### Tokens you need (see [Tokens, secrets and permissions](docs/setup-and-tokens.md#tokens-secrets-and-permissions) for details)

| Token | Type | Permission | Used for |
|---|---|---|---|
| `CR_PAT` | Classic PAT | `read:packages` | pulling the private image (Docker + Kubernetes) |
| `GH_REPO_PAT` | Fine-grained PAT | this repo only, **Contents: Read-only** | Argo CD reading the private repo |

### Rebuild the cluster: one command

```bash
bash scripts/bootstrap.sh
```

It asks for the two tokens (hidden input), then does everything and prints the Argo CD login at the end. It takes a few minutes, and it's safe to run again. Details: [step 9](docs/part3-platform-as-code.md#step-9--platform-as-code-bootstrap--argo-cd-manages-itself).

Afterwards:

```bash
# Argo CD UI (separate Git Bash window, keep open)
kubectl port-forward svc/argocd-server -n argocd 8443:443
# → https://localhost:8443  (accept self-signed cert), user: admin
# Password: printed at the end of the script, or read it any time with:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# The app
curl http://localhost:8080/health

# Optional, only to `docker pull` the private image on the PC:
read -s CR_PAT
echo "$CR_PAT" | docker login ghcr.io -u rafaelxfernandes --password-stdin
```

> **Order matters**, and the script handles it: `ghcr-secret` must exist before Argo CD syncs the app, otherwise the Pods end in `ImagePullBackOff`.

### Starting a brand-new project with this setup (checklist)

1. App + tests → run locally ([step 1](docs/part1-by-hand.md#step-1--the-app))
2. `Dockerfile` + `.dockerignore`, use a production server (gunicorn), non-root user ([step 2](docs/part1-by-hand.md#step-2--docker))
3. `.github/workflows/ci.yml`: test → docker ([step 3](docs/part1-by-hand.md#step-3--github-actions-ci))
4. `publish` job to ghcr.io with `permissions: packages: write` ([step 4](docs/part1-by-hand.md#step-4--publishing-the-image-to-ghcrio))
5. Helm chart in `charts/<app>/` ([step 6](docs/part2-real-world-tools.md#step-6--helm))
6. `k8s-test` job (kind + `helm upgrade --install --wait`) ([bonus](docs/part1-by-hand.md#bonus--testing-kubernetes-in-ci-with-kind))
7. Repo setting "Allow GitHub Actions to create PRs" + `bump-version` job ([step 7](docs/part2-real-world-tools.md#step-7--automated-version-bump-pr))
8. Argo CD `Application` manifest ([step 8](docs/part2-real-world-tools.md#step-8--gitops-with-argo-cd))
9. `argocd/root-app.yaml` + `argocd/apps/` + `scripts/bootstrap.sh` ([step 9](docs/part3-platform-as-code.md#step-9--platform-as-code-bootstrap--argo-cd-manages-itself))

### Tear everything down

Easiest and cleanest: Docker Desktop → **Settings → Kubernetes → Reset Kubernetes cluster**. Everything in the cluster is deleted; nothing in git is affected. Then `bash scripts/bootstrap.sh` rebuilds it.

---

## How to release / roll back / change the platform (day-to-day)

### Release

```bash
# 1. Code change + tests → commit → push (or PR → merge)
git add . && git commit -m "Describe the change" && git push

# 2. Tag the release
git tag v1.6.0 && git push origin v1.6.0
```

3. Wait for the green pipeline → open the **"Deploy 1.6.0"** PR → check *Files changed* (2 lines) → **Merge**.
4. Argo CD deploys it (or click **Refresh** in the UI). Verify: `curl http://localhost:8080/`.
5. `git pull` locally to stay up to date.

### Roll back

1. On GitHub, open the merged **"Deploy x.y.z"** PR → **Revert** → merge the revert PR.
2. Argo CD syncs back to the previous version.

> Don't use `kubectl rollout undo` or `helm rollback` anymore: Argo CD's selfHeal undoes them because git still says the newer version. Git is the only lever.

### Change the platform

| I want to… | Do this (in a PR, then merge) |
|---|---|
| change an Argo CD setting | edit `platform/argocd/values.yaml` |
| upgrade Argo CD | bump `targetRevision` in `argocd/apps/argocd.yaml` **and** `ARGOCD_CHART_VERSION` in `scripts/bootstrap.sh` (check the chart's release notes first) |
| add another app | add an Application file to `argocd/apps/` |
| remove an app | delete its file from `argocd/apps/` |
| rebuild everything | Reset Kubernetes cluster in Docker Desktop → `bash scripts/bootstrap.sh` |
| fix a broken/half-installed setup | `bash scripts/bootstrap.sh` again (idempotent) |

---

## Project structure

```
DevOps-Lab/
├── app.py                          # The Flask web app
├── test_app.py                     # Unit tests (pytest)
├── requirements.txt                # Python dependencies
├── Dockerfile                      # How to build the container image
├── .dockerignore                   # Files Docker must NOT copy into the image
├── .gitignore                      # Files git must NOT track
├── .gitattributes                  # Forces LF line endings for *.sh (Windows safety)
├── .github/
│   └── workflows/
│       └── ci.yml                  # The whole CI/CD pipeline
├── charts/
│   └── devops-lab/                 # Helm chart (replaced the old k8s/ folder in step 6)
│       ├── Chart.yaml              # chart metadata + appVersion
│       ├── values.yaml             # all settings; image.tag = what gets deployed
│       └── templates/
│           ├── deployment.yaml
│           └── service.yaml
├── argocd/
│   ├── root-app.yaml               # "app of apps": deploys everything in argocd/apps/
│   └── apps/
│       ├── devops-lab.yaml         # the app (Helm chart above)
│       └── argocd.yaml             # Argo CD managing ITSELF
├── platform/
│   └── argocd/
│       └── values.yaml             # Argo CD's own configuration
└── scripts/
    └── bootstrap.sh                # rebuilds the whole platform with one command
```

> The annotated file copies in [`docs/`](docs/) explain each line. The real files in the repo are always the source of truth (e.g. the greeting text and the current version change over time).

---

## Next things to learn

- **Argo Rollouts**: canary releases (send 10% of traffic to the new version, auto-rollback on errors).
- **Sealed Secrets / External Secrets**: put secrets in git safely (encrypted) or pull them from a vault.
- **Multiple environments**: `values-dev.yaml` / `values-prod.yaml`, promotion between environments.
- **GitHub App token** for the bump job so bot PRs get CI checks.
- **Dependabot**: automatic PRs keeping `actions/*@vX`, base images and pip packages up to date.
- **Kustomize**: the other common way to vary manifests per environment.
