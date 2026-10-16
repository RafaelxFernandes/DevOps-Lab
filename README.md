# DevOps Lab

A personal project to learn, hands-on, how a real CI/CD + GitOps pipeline is built:
**GitHub Actions** → **Docker** → **Kubernetes** → **Helm** → **Argo CD**.

The app is deliberately tiny (a Flask app with two endpoints) so the focus stays on everything around it.

- **Part 1 (steps 1–5 + bonus):** everything done **by hand** to understand each piece.
- **Part 2 (steps 6–8):** replacing the manual parts with the tools companies use in real life.

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

## Table of contents

1. [Project structure](#1-project-structure)
2. [Environment and tools](#2-environment-and-tools)
3. [Start from scratch (rebuild everything)](#3-start-from-scratch-rebuild-everything)
4. [Tokens, secrets and permissions](#4-tokens-secrets-and-permissions)
5. [Step 1 – The app](#5-step-1--the-app)
6. [Step 2 – Docker](#6-step-2--docker)
7. [Step 3 – GitHub Actions: CI](#7-step-3--github-actions-ci)
8. [Step 4 – Publishing the image to ghcr.io](#8-step-4--publishing-the-image-to-ghcrio)
9. [Step 5 – Kubernetes by hand](#9-step-5--kubernetes-by-hand)
10. [Bonus – Testing Kubernetes in CI with kind](#10-bonus--testing-kubernetes-in-ci-with-kind)
11. [Step 6 – Helm](#11-step-6--helm)
12. [Step 7 – Automated version-bump PR](#12-step-7--automated-version-bump-pr)
13. [Step 8 – GitOps with Argo CD](#13-step-8--gitops-with-argo-cd)
14. [The complete `ci.yml`, annotated](#14-the-complete-ciyml-annotated)
15. [How to release / roll back (day-to-day)](#15-how-to-release--roll-back-day-to-day)
16. [Command cheat sheet](#16-command-cheat-sheet)
17. [Problems I hit and what they taught me](#17-problems-i-hit-and-what-they-taught-me)
18. [Next things to learn](#18-next-things-to-learn)

---

## 1. Project structure

```
DevOps-Lab/
├── app.py                          # The Flask web app
├── test_app.py                     # Unit tests (pytest)
├── requirements.txt                # Python dependencies
├── Dockerfile                      # How to build the container image
├── .dockerignore                   # Files Docker must NOT copy into the image
├── .gitignore                      # Files git must NOT track
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
└── argocd/
    └── devops-lab-app.yaml         # tells Argo CD what to deploy and where
```

> The annotated file copies in this README explain each line. The real files in the repo are always the source of truth (e.g. the greeting text and the current version change over time).

---

## 2. Environment and tools

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

## 3. Start from scratch (rebuild everything)

Use this when the cluster was reset (Docker Desktop → Reset Kubernetes), on a new PC, or to rebuild the whole environment from this repo. Every command below is explained in the step sections further down.

### 3.1 Prerequisites

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

### 3.2 GitHub one-time settings (already done for this repo; needed for a new repo)

- **Settings → Actions → General → Workflow permissions** → tick **"Allow GitHub Actions to create and approve pull requests"** (needed by the `bump-version` job).

### 3.3 Tokens you need (see [section 4](#4-tokens-secrets-and-permissions) for details)

| Token | Type | Permission | Used for |
|---|---|---|---|
| `CR_PAT` | Classic PAT | `read:packages` | pulling the private image (Docker + Kubernetes) |
| `GH_REPO_PAT` | Fine-grained PAT | this repo only, **Contents: Read-only** | Argo CD reading the private repo |

### 3.4 Rebuild the cluster (copy-paste in order)

```bash
# --- 1. Docker can pull the private image (optional, only for local docker pull) ---
read -s CR_PAT                                   # paste classic token, Enter
echo "$CR_PAT" | docker login ghcr.io -u rafaelxfernandes --password-stdin

# --- 2. Namespace + pull secret for the app ---
kubectl create namespace devops-lab
kubectl create secret docker-registry ghcr-secret \
  --namespace devops-lab \
  --docker-server=ghcr.io \
  --docker-username=rafaelxfernandes \
  --docker-password="$CR_PAT"

# --- 3. Install Argo CD ---
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd -w                    # wait until all Running, then Ctrl+C

# --- 4. Argo CD can read the private repo ---
read -s GH_REPO_PAT                              # paste fine-grained token, Enter
kubectl create secret generic repo-devops-lab -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/rafaelxfernandes/DevOps-Lab.git \
  --from-literal=username=rafaelxfernandes \
  --from-literal=password="$GH_REPO_PAT"
kubectl label secret repo-devops-lab -n argocd argocd.argoproj.io/secret-type=repository

# --- 5. Hand the app to Argo CD (the ONLY manual apply) ---
kubectl apply -f argocd/devops-lab-app.yaml
```

Then:

```bash
# Argo CD UI (separate Git Bash window, keep open)
kubectl port-forward svc/argocd-server -n argocd 8443:443
# → https://localhost:8443  (accept self-signed cert), user: admin, password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# The app
curl http://localhost:8080/health
```

> **Order matters:** `ghcr-secret` must exist before Argo CD syncs, otherwise the Pods end in `ImagePullBackOff` (fix: create the secret; Argo CD/Kubernetes retry automatically).

### 3.5 Starting a brand-new project with this setup (checklist)

1. App + tests → run locally ([step 1](#5-step-1--the-app))
2. `Dockerfile` + `.dockerignore`, use a production server (gunicorn), non-root user ([step 2](#6-step-2--docker))
3. `.github/workflows/ci.yml`: test → docker ([step 3](#7-step-3--github-actions-ci))
4. `publish` job to ghcr.io with `permissions: packages: write` ([step 4](#8-step-4--publishing-the-image-to-ghcrio))
5. Helm chart in `charts/<app>/` ([step 6](#11-step-6--helm))
6. `k8s-test` job (kind + `helm upgrade --install --wait`) ([bonus](#10-bonus--testing-kubernetes-in-ci-with-kind))
7. Repo setting "Allow GitHub Actions to create PRs" + `bump-version` job ([step 7](#12-step-7--automated-version-bump-pr))
8. Argo CD `Application` manifest + bootstrap ([step 8](#13-step-8--gitops-with-argo-cd))

### 3.6 Tear everything down

```bash
kubectl delete -f argocd/devops-lab-app.yaml   # with prune, Argo CD removes the app's resources
kubectl delete namespace devops-lab
kubectl delete namespace argocd
```

---

## 4. Tokens, secrets and permissions

Every credential in this project, what it can do, where it lives, and what to do when it expires.

### 4.1 `GITHUB_TOKEN` (automatic, used by CI)

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

### 4.2 `CR_PAT`: classic PAT with `read:packages`

- **Why classic:** container registry access (ghcr.io) works with classic tokens and the `read:packages` scope.
- **Create:** GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → scope **`read:packages` only** → set an expiration.
- **Used in two places:**
  1. `docker login ghcr.io` on my PC (stored by Docker Desktop afterwards).
  2. The Kubernetes Secret **`ghcr-secret`** in namespace `devops-lab` (lets the cluster pull the private image; referenced by `imagePullSecrets` in the chart).
- **Never committed to git.** Created with `kubectl create secret` only.

### 4.3 `GH_REPO_PAT`: fine-grained PAT, Contents read-only

- **Why fine-grained:** can be restricted to **one repository** and **read-only**. If leaked, it can only read this repo.
- **Create:** Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Repository access: *Only select repositories* → `DevOps-Lab` → Repository permissions → **Contents: Read-only** → expiration.
- **Used by:** Argo CD, stored in Secret **`repo-devops-lab`** in namespace `argocd`, recognised thanks to the label `argocd.argoproj.io/secret-type=repository`.
- Check in Argo CD UI → **Settings → Repositories** → status *Successful*.

### 4.4 Argo CD admin password

- Auto-generated at install, stored in Secret `argocd-initial-admin-secret` (namespace `argocd`).
- Read it: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo`
- Kubernetes stores Secret values **base64-encoded** (encoding, *not* encryption), hence `base64 -d`.
- Real setups: change it and delete that secret, or use SSO (GitHub/Google/Okta login).

### 4.5 When a token expires: rotation

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

### 4.6 Safety rules I follow

- `read -s VAR` to paste tokens: hidden, and not saved in shell history.
- Secrets are **never** in git. (Companies use Sealed Secrets, External Secrets + a vault, or SOPS to manage them declaratively.)
- Smallest scope + an expiration on every token.

---

## 5. Step 1 – The app

### `app.py`

```python
from flask import Flask

app = Flask(__name__)            # create the web application object

@app.route("/")                  # when someone visits "/", run hello()
def hello():
    return "Hello from my DevOps lab!"   # (greeting text changes between versions)

@app.route("/health")            # health endpoint: used by Kubernetes probes
def health():
    return {"status": "ok"}      # Flask turns a dict into a JSON response

if __name__ == "__main__":       # only when run directly with `python app.py`
    app.run(host="0.0.0.0", port=5000)   # 0.0.0.0 = listen on all interfaces (needed in containers)
```

### `test_app.py`

```python
from app import app

def test_hello():
    client = app.test_client()              # fake browser, no real server needed
    response = client.get("/")
    assert response.status_code == 200
    assert b"Hello" in response.data        # b"..." = bytes, because response.data is bytes

def test_health():
    client = app.test_client()
    assert client.get("/health").json == {"status": "ok"}
```

### `requirements.txt`

```
flask        # web framework
pytest       # test runner
gunicorn     # production web server (see problem "PID 1")
```

### `.gitignore`

```
.venv/
__pycache__/
.pytest_cache/
```

### Run it locally (without Docker)

```bash
python -m venv .venv
source .venv/Scripts/activate      # Git Bash on Windows
pip install -r requirements.txt
pytest                             # expect: 2 passed
python app.py                      # http://localhost:5000 and /health
```

---

## 6. Step 2 – Docker

### `Dockerfile`

```dockerfile
FROM python:3.12-slim
# Base image: official, small Python image.

WORKDIR /app
# All following commands run inside /app in the container.

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Copy ONLY requirements first, then install → this slow layer is CACHED
# and reused when only the app code changes.

COPY . .
# Copy the rest of the code (respecting .dockerignore).

RUN useradd --create-home appuser
USER appuser
# Don't run as root inside the container.

EXPOSE 5000
# Documentation only: the app listens on 5000. Does NOT publish the port.

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
# gunicorn = production server; handles SIGTERM properly (graceful shutdown).
# "app:app" = in file app.py, the object named app.
# (Originally CMD ["python", "app.py"]: see problem "PID 1".)
```

### `.dockerignore`

```
.venv/
__pycache__/
.pytest_cache/
.git/
```

### Commands

```bash
docker build -t devops-lab:1.0 .        # -t name:tag, "." = build context
docker run -d -p 8080:5000 --name devops-lab devops-lab:1.0
#   -d background · -p host:container · --name friendly name
curl http://localhost:8080/health
docker ps / docker logs devops-lab / docker exec devops-lab whoami
docker run --rm devops-lab:1.0 pytest   # run tests INSIDE the image
docker stop devops-lab && docker rm devops-lab
```

---

## 7. Step 3 – GitHub Actions: CI

| Term | Meaning |
|---|---|
| **Workflow** | A YAML file in `.github/workflows/`. |
| **`on`** | Events that trigger it (push, pull_request, tag, manual button…). |
| **Job** | Group of steps on a **fresh VM** (runner). Jobs run **in parallel** unless chained with `needs`. |
| **Step** | `uses:` (ready-made action) or `run:` (shell commands). |
| **`${{ ... }}`** | Expression, replaced by GitHub before the step runs. |
| **Matrix** | One job definition → several parallel jobs (e.g. per Python version). |
| **`needs`** | Run only if those jobs succeeded; otherwise this job is **skipped**. |
| **`if:`** | Condition on a job/step. |

YAML: **indentation is everything**, spaces only.

Practised: watching runs in the **Actions** tab, breaking a test on purpose (red ❌, dependent jobs skipped), CI checks on pull requests.

Full annotated workflow: [section 14](#14-the-complete-ciyml-annotated).

---

## 8. Step 4 – Publishing the image to ghcr.io

| Term | Meaning |
|---|---|
| **ghcr.io** | GitHub Container Registry. Private repo → private package (Profile → Packages). |
| **`permissions`** | What `GITHUB_TOKEN` may do in that job (see [section 4.1](#41-github_token-automatic-used-by-ci)). |
| **Image tags** | `sha-abc1234` (exact commit), `latest` (main), `1.2.0` + `1.2` (from git tag `v1.2.0`). |
| **Buildx + `type=gha` cache** | Docker layer cache shared between CI runs. |

Pull locally (Git Bash can't prompt for the password → pipe it):

```bash
read -s CR_PAT
echo "$CR_PAT" | docker login ghcr.io -u rafaelxfernandes --password-stdin
docker pull ghcr.io/rafaelxfernandes/devops-lab:latest
```

Image names on ghcr.io must be **lowercase**.

---

## 9. Step 5 – Kubernetes by hand

> Historical: these raw manifests lived in `k8s/` and were **replaced by the Helm chart in step 6**. Kept here because they explain what the chart templates produce.

### Core objects

| Object | What it is |
|---|---|
| **Namespace** | A folder in the cluster grouping this project's resources. |
| **Deployment** | "Keep N copies of this container running." |
| **ReplicaSet** | Created by the Deployment for each version. |
| **Pod** | One running instance. Disposable, replaced automatically. |
| **Service** | Stable address in front of the Pods. |
| **Secret** | Sensitive data (e.g. registry credentials). |

**Labels connect everything:** the Deployment stamps a label on Pods, the Service selects Pods by that label.

### The Deployment, annotated (what the chart renders)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-lab
  namespace: devops-lab
spec:
  replicas: 2                       # desired number of Pods
  selector:
    matchLabels:
      app: devops-lab               # "my Pods are the ones with this label"
  template:                         # blueprint for every Pod
    metadata:
      labels:
        app: devops-lab
    spec:
      imagePullSecrets:
        - name: ghcr-secret         # credentials to pull the private image
      containers:
        - name: web
          image: ghcr.io/rafaelxfernandes/devops-lab:1.2.0   # pinned, never "latest"
          ports:
            - containerPort: 5000
          readinessProbe:           # READY for traffic? No → removed from Service (not restarted)
            httpGet: { path: /health, port: 5000 }
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:            # still ALIVE? Fails repeatedly → container restarted
            httpGet: { path: /health, port: 5000 }
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests: { cpu: 50m, memory: 64Mi }    # reserved by the scheduler
            limits:   { cpu: 250m, memory: 128Mi }  # hard ceiling
```

### The Service, annotated

```yaml
apiVersion: v1
kind: Service
metadata:
  name: devops-lab
  namespace: devops-lab
spec:
  type: LoadBalancer      # Docker Desktop exposes it on localhost
  selector:
    app: devops-lab       # send traffic to Pods with this label
  ports:
    - port: 8080          # localhost port
      targetPort: 5000    # container port
```

### Exercises done (watch with `kubectl get pods -n devops-lab -w`)

| Exercise | How | Result |
|---|---|---|
| Self-healing | `kubectl delete pod ...` | Replacement Pod in seconds |
| Scaling | change `replicas`, apply | Pods added/removed |
| Rolling update | change image tag, apply | Pods replaced one at a time: zero downtime |
| Rollback | `kubectl rollout undo deployment/devops-lab -n devops-lab` | Previous version back |
| Drift | after undo, git still said the new version | Learned: git must match the cluster |

---

## 10. Bonus – Testing Kubernetes in CI with kind

**kind** = "Kubernetes IN Docker": a full cluster inside a container, ~30s to start on a runner, thrown away afterwards.

- Image built in the job and loaded with `kind load docker-image` → no registry/secret needed.
- Since step 6 it deploys the **Helm chart** with CI-specific values (`--set image.tag=ci --set service.type=ClusterIP`).
- `publish` needs `k8s-test` → an image is only published if it **actually deploys and answers HTTP**.
- `if: failure()` debug step dumps `kubectl get all / describe / logs` when something breaks.

Break-it exercise: readiness probe path `/healthz` → Pods never Ready → job failed with `Readiness probe failed: ... statuscode: 404` → `publish` skipped.

---

## 11. Step 6 – Helm

**Helm = template engine + release manager.** Templates (`{{ .Values.x }}`) + `values.yaml` → plain Kubernetes YAML. The version becomes **one line** (`image.tag`).

### `charts/devops-lab/Chart.yaml`

```yaml
apiVersion: v2
name: devops-lab
description: My DevOps lab Flask app
type: application
version: 0.1.0          # version of the CHART (packaging). Bump when templates change.
appVersion: "1.2.0"     # version of the APP. Informational label; updated by the bump PR.
```

### `charts/devops-lab/values.yaml`

```yaml
replicaCount: 2

image:
  repository: ghcr.io/rafaelxfernandes/devops-lab
  tag: "1.2.0"                 # ← THE line that changes on every release (via bump PR)
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: ghcr-secret

containerPort: 5000

service:
  type: LoadBalancer
  port: 8080

resources:
  requests: { cpu: 50m, memory: 64Mi }
  limits:   { cpu: 250m, memory: 128Mi }
```

### `charts/devops-lab/templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/version: {{ .Values.image.tag | quote }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .Chart.Name }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ .Chart.Name }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: web
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.containerPort }}
          readinessProbe:
            httpGet:
              path: /health
              port: {{ .Values.containerPort }}
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: {{ .Values.containerPort }}
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

### `charts/devops-lab/templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.containerPort }}
```

### Template syntax

| Syntax | Meaning |
|---|---|
| `{{ .Values.x }}` | read `x` from `values.yaml` (or `--set x=...`) |
| `{{ .Release.Name }}` | release name chosen at install (`devops-lab`) |
| `{{ .Chart.Name }}` | `name` from `Chart.yaml` |
| `\| quote` | wrap in quotes (keeps `1.2.0` a string) |
| `{{- ... }}` | trim whitespace/newline on that side |
| `{{- with X }} … {{- end }}` | render only if X is set; inside, `.` = X |
| `toYaml . \| nindent 8` | value → YAML, indented 8 spaces on a new line |
| `app.kubernetes.io/*` | standard Kubernetes label names |

No namespace in templates: chosen at install time (`-n`) → same chart, any namespace.
**Same chart, different values per environment** (laptop: LoadBalancer; CI: ClusterIP + local image).

### Helm commands I practised

```bash
helm lint charts/devops-lab                       # check the chart
helm template devops-lab charts/devops-lab        # print rendered YAML (installs nothing)
helm install devops-lab charts/devops-lab -n devops-lab
helm upgrade devops-lab charts/devops-lab -n devops-lab --wait
helm upgrade --install ...                        # install-or-upgrade (pipeline idiom)
helm history devops-lab -n devops-lab
helm rollback devops-lab 1 -n devops-lab --wait   # creates a NEW revision copying rev 1
helm list -n devops-lab
helm uninstall devops-lab -n devops-lab
```

> `--set` on the command line creates drift (cluster ≠ git), just like `kubectl rollout undo`. Only used for experiments; real version changes go through `values.yaml` in a PR.

---

## 12. Step 7 – Automated version-bump PR

After a release image is published, CI opens a PR changing `image.tag` and `appVersion`. A human reviews and merges it.

```
git tag v1.4.0 ─► test ─► docker ─► k8s-test ─► publish 1.4.0 ─► bump-version
                                                                    │
                                     PR "Deploy 1.4.0" ◄────────────┘
                                     (values.yaml: tag 1.3.0 → 1.4.0, Chart.yaml: appVersion)
```

Key pieces (full job in [section 14](#14-the-complete-ciyml-annotated)):

| Piece | Meaning |
|---|---|
| `if: startsWith(github.ref, 'refs/tags/v')` | only for release tags |
| `ref: main` on checkout | edit the current `main`, not the tagged commit |
| `${GITHUB_REF_NAME#v}` | `v1.4.0` → `1.4.0` (bash: strip leading `v`) |
| `echo "VERSION=..." >> "$GITHUB_ENV"` | make a variable available to **later steps** |
| `yq -i '.image.tag = strenv(VERSION)'` | YAML-aware edit (preinstalled on runners) |
| `gh pr create` | GitHub CLI (preinstalled), authenticated with `GH_TOKEN` |
| bot identity | `github-actions[bot]` as commit author |

Required repo setting + token behaviour: [section 4.1](#41-github_token-automatic-used-by-ci).

---

## 13. Step 8 – GitOps with Argo CD

### What it does

Argo CD runs **inside the cluster** and loops forever:
1. reads **desired state** from git (`charts/devops-lab` on `main`)
2. reads **live state** from the cluster
3. different → **OutOfSync** → syncs the cluster to match git

**Pull model:** the cluster pulls from git; CI never needs cluster credentials (security win).
Argo CD uses Helm only as a **template engine** → `helm list` is empty; history lives in git + the Argo CD UI.

### Install + access

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# --server-side: some Argo CD CRDs are too big for client-side apply

kubectl port-forward svc/argocd-server -n argocd 8443:443      # separate window
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
# https://localhost:8443 → admin / <password>
```

Repo credentials: [section 4.3](#43-gh_repo_pat-fine-grained-pat-contents-read-only).

### `argocd/devops-lab-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application                 # Argo CD object: "keep this deployed"
metadata:
  name: devops-lab
  namespace: argocd               # Applications live in Argo CD's namespace
spec:
  project: default

  source:                         # WHAT (desired state)
    repoURL: https://github.com/rafaelxfernandes/DevOps-Lab.git
    targetRevision: main          # follow main
    path: charts/devops-lab       # the Helm chart
    helm:
      releaseName: devops-lab     # keeps resource names "devops-lab"

  destination:                    # WHERE
    server: https://kubernetes.default.svc   # the cluster Argo CD runs in
    namespace: devops-lab

  syncPolicy:
    automated:                    # sync automatically on git changes
      prune: true                 # delete resources removed from git
      selfHeal: true              # undo manual changes in the cluster
```

Bootstrap once: `kubectl apply -f argocd/devops-lab-app.yaml`. Before that, the Helm-CLI release was removed with `helm uninstall` so Argo CD owns everything cleanly.

### What I verified

| Test | Result |
|---|---|
| `kubectl scale deployment devops-lab --replicas=5` | Argo CD scaled it back to 2 (**selfHeal**) |
| `kubectl delete deployment devops-lab` | Recreated automatically |
| Release v1.5.0 → merge bump PR | Argo CD synced within ~3 min (or **Refresh** button) |
| Revert the bump PR on GitHub | Argo CD rolled back to the previous version |

Argo CD **polls** git every few minutes. Companies configure a GitHub **webhook** for instant syncs (impossible here: GitHub can't reach my laptop).

---

## 14. The complete `ci.yml`, annotated

```yaml
name: CI

on:
  push:
    branches: [main]                       # every push to main
    tags: ["v*"]                           # every release tag (v1.0.0, …)
  pull_request:
    branches: [main]                       # every PR targeting main
  workflow_dispatch:                       # manual "Run workflow" button

jobs:
  # ── 1. Unit tests on 2 Python versions ─────────────────────────────
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.12", "3.13"]
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v7
        with:
          python-version: ${{ matrix.python-version }}
          cache: pip
      - run: pip install -r requirements.txt
      - run: pytest -v

  # ── 2. Build the image and test inside it ──────────────────────────
  docker:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v7
      - run: docker build -t devops-lab:ci .
      - run: docker run --rm devops-lab:ci pytest -v

  # ── 3. Deploy the chart to a throwaway Kubernetes cluster ─────────
  k8s-test:
    runs-on: ubuntu-latest
    needs: docker
    steps:
      - uses: actions/checkout@v7

      - name: Create kind cluster
        uses: helm/kind-action@v1          # cluster + kubectl
        with:
          cluster_name: ci

      - name: Build image and load it into the cluster
        run: |
          docker build -t devops-lab:ci .
          kind load docker-image devops-lab:ci --name ci

      - name: Lint chart
        run: helm lint charts/devops-lab   # Helm is preinstalled on GitHub runners

      - name: Deploy with Helm (using the image we just built)
        run: |
          helm upgrade --install devops-lab charts/devops-lab \
            --namespace devops-lab --create-namespace \
            --set image.repository=devops-lab \
            --set image.tag=ci \
            --set service.type=ClusterIP \
            --wait --timeout 2m
          # CI-specific values: local image, no LoadBalancer in kind.
          # --wait = fail unless everything becomes Ready within 2 minutes.

      - name: Smoke test
        run: |
          kubectl port-forward -n devops-lab svc/devops-lab 8080:8080 &
          sleep 3
          curl -f http://localhost:8080/health
          curl -f http://localhost:8080/

      - name: Debug info (only if something failed)
        if: failure()
        run: |
          kubectl get all -n devops-lab
          kubectl describe pods -n devops-lab
          kubectl logs -n devops-lab deploy/devops-lab --all-containers --tail=50 || true

  # ── 4. Publish the image to ghcr.io ────────────────────────────────
  publish:
    runs-on: ubuntu-latest
    needs: [docker, k8s-test]              # only if it builds AND deploys
    if: github.event_name != 'pull_request'
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Generate image tags and labels
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha
            type=raw,value=latest,enable={{is_default_branch}}
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
      - uses: docker/build-push-action@v7
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ── 5. Open a PR that deploys the new version ─────────────────────
  bump-version:
    runs-on: ubuntu-latest
    needs: publish
    if: startsWith(github.ref, 'refs/tags/v')      # releases only
    permissions:
      contents: write                              # push a branch
      pull-requests: write                         # open a PR
    steps:
      - uses: actions/checkout@v7
        with:
          ref: main                                # edit current main, not the tag

      - name: Update chart to the new version
        run: |
          export VERSION="${GITHUB_REF_NAME#v}"
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"
          yq -i '.image.tag = strenv(VERSION)' charts/devops-lab/values.yaml
          yq -i '.appVersion = strenv(VERSION)' charts/devops-lab/Chart.yaml
          git diff

      - name: Open pull request
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          BRANCH="release/deploy-$VERSION"
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git checkout -b "$BRANCH"
          git commit -am "Deploy $VERSION"
          git push origin "$BRANCH"
          gh pr create \
            --base main \
            --head "$BRANCH" \
            --title "Deploy $VERSION" \
            --body "Automated bump after release $GITHUB_REF_NAME. Merging this PR deploys $VERSION."
```

Pipeline graph: **test (×2) → docker → k8s-test → publish → bump-version**.

---

## 15. How to release / roll back (day-to-day)

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

---

## 16. Command cheat sheet

### Git
```bash
git status
git checkout -b feature/x && git push -u origin feature/x   # then open PR
git tag v1.0.0 && git push origin v1.0.0
git pull
```

### Docker
```bash
docker build -t name:tag .
docker run -d -p 8080:5000 --name x name:tag
docker ps / docker ps -a / docker logs x / docker exec x <cmd>
docker rm -f x
docker inspect x --format '{{.State.ExitCode}}'   # 0 = clean exit, 137 = killed
```

### kubectl
```bash
kubectl config current-context
kubectl get all -n devops-lab
kubectl get pods -n devops-lab -w
kubectl describe pod <pod> -n devops-lab      # read Events at the bottom!
kubectl logs -n devops-lab deploy/devops-lab
kubectl port-forward -n devops-lab svc/devops-lab 8080:8080
kubectl port-forward svc/argocd-server -n argocd 8443:443
kubectl get applications -n argocd            # Argo CD apps + sync/health status
```

### Helm
```bash
helm lint charts/devops-lab
helm template devops-lab charts/devops-lab
helm template devops-lab charts/devops-lab --set image.tag=9.9.9   # preview a change
```

---

## 17. Problems I hit and what they taught me

1. **`Kubeconfig not found` popup in VS Code:** the Kubernetes extension activates on YAML files. Harmless; gone once Kubernetes is enabled.
2. **`docker login` fails in Git Bash:** not a real TTY. Use `--password-stdin` or log in once from PowerShell.
3. **`bash: $'\302\203docker': command not found`:** invisible character pasted from a web page. Type the command by hand.
4. **`docker build -t devops-lab>:sigfix .`:** stray `>` is a bash **redirect** (wrote a file `:sigfix`, tagged the image `latest`). Check `git status` before committing.
5. **Old Pods ended in `Error` during rolling updates (PID 1 signal handling):** terminating Pods showed `Error` exactly **30s** later. Kubernetes sends SIGTERM; `python app.py` ran as **PID 1**, which ignores signals without a handler → after the 30s grace period, SIGKILL → exit **137**. Fix: **gunicorn**. Verified with `docker inspect ... ExitCode`: 137 before, 0 after. During the first rollout *to* the fix, the old Pods still have the bug; it's visible from the next rollout on.
6. **Drift after `kubectl rollout undo`:** cluster ran 1.2.0, git said 1.3.0. The next apply would re-deploy the "broken" version. Solved for good by Argo CD (selfHeal).
7. **`ImagePullBackOff`:** pull secret missing/expired or wrong image name (must be lowercase). `kubectl describe pod` → Events.
8. **`the server doesn't have a resource type "deploment"`:** typo. kubectl errors are literal: read them first.
9. **`curl` still showed v1.3 right after `helm rollback`:** Helm returns when the change is *accepted*, not *finished*; old Pods kept serving during the rolling update. Use `--wait` or `kubectl rollout status`.
10. **`devops-lab-0.1.01.2.0` in `helm history`:** two columns (CHART + APP VERSION) squashed by a narrow terminal. Also: APP VERSION comes from `Chart.yaml`, not from the running image, so `--set image.tag` doesn't change it. Another reason to change versions in files, not on the command line.
11. **Helm refuses to adopt resources created by `kubectl`:** delete them first (`kubectl delete -f k8s/`) or migrate carefully.
12. **`helm list` empty after Argo CD took over:** expected. Argo CD renders the chart itself; it doesn't create Helm releases.
13. **Bump PR has no CI checks:** `GITHUB_TOKEN` events don't trigger workflows (anti-loop rule). See [section 4.1](#41-github_token-automatic-used-by-ci).

---

## 18. Next things to learn

- **Argo Rollouts**: canary releases (send 10% of traffic to the new version, auto-rollback on errors).
- **Argo CD managing itself / "app of apps"**: install Argo CD via Helm and let it manage its own config and all apps from git.
- **Sealed Secrets / External Secrets**: put secrets in git safely (encrypted) or pull them from a vault.
- **Multiple environments**: `values-dev.yaml` / `values-prod.yaml`, promotion between environments.
- **GitHub App token** for the bump job so bot PRs get CI checks.
- **Dependabot**: automatic PRs keeping `actions/*@vX`, base images and pip packages up to date.
- **Kustomize**: the other common way to vary manifests per environment.