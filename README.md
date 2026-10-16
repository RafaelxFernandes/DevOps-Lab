# DevOps Lab

A small personal project to learn how a real CI/CD pipeline is built from scratch:
**GitHub Actions** (CI/CD) → **Docker** (containers) → **Kubernetes** (orchestration).

The app itself is deliberately tiny (a Flask app with two endpoints) so the focus stays on the pipeline around it.

```
push / PR ──► unit tests (Python 3.12 + 3.13)
          ──► Docker build + tests inside the image
          ──► deploy to a throwaway Kubernetes cluster (kind) + smoke test
          ──► publish versioned image to ghcr.io        (main and v* tags only)
                         │
                         ▼
          local Kubernetes (Docker Desktop): rolling updates, rollbacks, self-healing
```

---

## Table of contents

1. [Project structure](#1-project-structure)
2. [Environment](#2-environment)
3. [Step 1 – The app](#3-step-1--the-app)
4. [Step 2 – Docker](#4-step-2--docker)
5. [Step 3 – GitHub Actions: CI](#5-step-3--github-actions-ci)
6. [Step 4 – Publishing the image to ghcr.io](#6-step-4--publishing-the-image-to-ghcrio)
7. [Step 5 – Kubernetes](#7-step-5--kubernetes)
8. [Bonus – Testing Kubernetes in CI with kind](#8-bonus--testing-kubernetes-in-ci-with-kind)
9. [How to release a new version](#9-how-to-release-a-new-version)
10. [Command cheat sheet](#10-command-cheat-sheet)
11. [Problems I hit and what they taught me](#11-problems-i-hit-and-what-they-taught-me)
12. [Next things to learn](#12-next-things-to-learn)

---

## 1. Project structure

```
DevOps-Lab/
├── app.py                     # The Flask web app
├── test_app.py                # Unit tests (pytest)
├── requirements.txt           # Python dependencies
├── Dockerfile                 # How to build the container image
├── .dockerignore              # Files Docker must NOT copy into the image
├── .gitignore                 # Files git must NOT track
├── .github/
│   └── workflows/
│       └── ci.yml             # The whole CI/CD pipeline
└── k8s/
    ├── deployment.yaml        # Kubernetes: what to run and how many copies
    └── service.yaml           # Kubernetes: how to reach it
```

> The annotated file copies in this README explain each line. The real files in the repo are always the source of truth.

---

## 2. Environment

| Tool | Notes |
|---|---|
| Windows 11 | |
| Git Bash | Main terminal. Same shell (bash) as the GitHub Actions Linux runners, so commands transfer 1:1. |
| Docker Desktop | Provides Docker **and** a single-node Kubernetes cluster (`docker-desktop` context). |
| VS Code | With the **GitHub Actions** extension (workflow autocomplete/validation). |
| GitHub Pro | Private repo; Actions minutes and private ghcr.io packages included. |

---

## 3. Step 1 – The app

### `app.py`

```python
from flask import Flask

app = Flask(__name__)            # create the web application object

@app.route("/")                  # when someone visits "/", run hello()
def hello():
    return "Hello from my DevOps lab!"   # (greeting text changes between versions)

@app.route("/health")            # health endpoint: used later by Kubernetes probes
def health():
    return {"status": "ok"}      # Flask turns a dict into a JSON response

if __name__ == "__main__":       # only when run directly with `python app.py`
    app.run(host="0.0.0.0", port=5000)   # 0.0.0.0 = listen on all interfaces (needed in containers)
```

**Why `/health`?** Kubernetes needs a cheap URL to ask "are you alive / ready?". See [Step 5](#7-step-5--kubernetes).

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
gunicorn     # production web server (added later – see "PID 1" problem)
```

### `.gitignore`

```
.venv/            # local virtual environment
__pycache__/      # Python bytecode cache
.pytest_cache/    # pytest cache
```

### Run it locally (without Docker)

```bash
python -m venv .venv               # create an isolated Python environment
source .venv/Scripts/activate      # activate it (Git Bash on Windows)
pip install -r requirements.txt
pytest                             # expect: 2 passed
python app.py                      # open http://localhost:5000 and /health
```

---

## 4. Step 2 – Docker

### `Dockerfile`

```dockerfile
FROM python:3.12-slim
# Base image: official, small Python image. Everything else is built on top of it.

WORKDIR /app
# All following commands run inside /app in the container (created if missing).

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Copy ONLY requirements first, then install.
# Docker caches each step ("layer"). If only app code changes, this slow
# pip install layer is reused (you see "CACHED" in the build output).
# --no-cache-dir keeps pip's download cache out of the image (smaller image).

COPY . .
# Now copy the rest of the code (respecting .dockerignore).

RUN useradd --create-home appuser
USER appuser
# Don't run as root inside the container. Good security practice.
# Check with: docker exec <container> whoami   → appuser

EXPOSE 5000
# Documentation only: says the app listens on 5000. It does NOT publish the port.

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
# Command that runs when the container starts.
# gunicorn = production server; handles SIGTERM properly (graceful shutdown).
# "app:app" = in file app.py, use the object named app.
# (Originally this was CMD ["python", "app.py"] – see problem #4 below for why it changed.)
```

### `.dockerignore`

```
.venv/
__pycache__/
.pytest_cache/
.git/
```

Works like `.gitignore` but for `docker build`. Without it, the whole `.venv` folder would be copied into the image.

### Commands

```bash
docker build -t devops-lab:1.0 .        # -t = name:tag, "." = build context (this folder)
docker run -d -p 8080:5000 --name devops-lab devops-lab:1.0
#   -d          run in background (detached)
#   -p 8080:5000  host port 8080 → container port 5000
#   --name      friendly name instead of a random one
curl http://localhost:8080/health

docker ps                               # running containers
docker logs devops-lab                  # app output
docker exec devops-lab whoami           # run a command inside the container
docker images                           # local images
docker run --rm devops-lab:1.0 pytest   # run tests INSIDE the image; --rm deletes container after
docker stop devops-lab && docker rm devops-lab
```

**Layer caching experiment:** change only `app.py`, rebuild → the `pip install` step shows `CACHED`.

---

## 5. Step 3 – GitHub Actions: CI

### Core concepts

| Term | Meaning |
|---|---|
| **Workflow** | A YAML file in `.github/workflows/`. |
| **`on`** | Events that trigger it (push, pull_request, manual button, tag…). |
| **Job** | A group of steps. Each job runs on a **fresh VM** (runner). Jobs run **in parallel** unless chained with `needs`. |
| **Step** | One command in a job. Either `uses:` (a ready-made action, like importing a library) or `run:` (shell commands). |
| **`${{ ... }}`** | Expression; GitHub replaces it with a value before the step runs. |
| **Matrix** | Turns one job definition into several parallel jobs (e.g. one per Python version). |
| **`needs`** | "Only run this job if these jobs succeeded." Failed dependency → this job is **skipped**. |

YAML rule: **indentation is everything**. Spaces only, never tabs.

The complete, final `ci.yml` is explained in [section 8](#the-complete-ciyml-annotated).

### What I practised
- Pushed → watched the run in the **Actions** tab (job graph + logs per step).
- Broke a test on purpose → red ❌, the `docker` job was **skipped** because of `needs`.
- Opened a pull request from a branch → CI checks appear directly on the PR.

---

## 6. Step 4 – Publishing the image to ghcr.io

### Concepts

| Term | Meaning |
|---|---|
| **ghcr.io** | GitHub Container Registry. Stores Docker images next to the repo. Private repo → private package. |
| **`GITHUB_TOKEN`** | Temporary token GitHub creates for **every run**; expires when the job ends. No passwords to manage. |
| **`permissions`** | What `GITHUB_TOKEN` may do. Default is restricted; we grant `packages: write` only to the publishing job. |
| **`if:`** | Condition on a job. We never publish from pull requests (`github.event_name != 'pull_request'`). |
| **Image tags** | One image, several names: `sha-abc1234` (exact commit), `latest` (main branch), `1.2.0` + `1.2` (from git tag `v1.2.0`). |

Find the package: GitHub profile → **Packages** tab → `devops-lab`.

### Pulling the private image to my PC

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → scope **`read:packages`** only, with an expiration.
2. Log in. In Git Bash, `docker login` can't prompt interactively, so pipe the token:

```bash
read -s CR_PAT            # paste token, Enter (hidden, stays out of history)
echo "$CR_PAT" | docker login ghcr.io -u rafaelxfernandes --password-stdin
```

(Alternative: in PowerShell, `docker login ghcr.io -u rafaelxfernandes` prompts normally. Credentials are stored by Docker Desktop, so it's a one-time thing for both terminals.)

```bash
docker pull ghcr.io/rafaelxfernandes/devops-lab:latest
```

Image names on ghcr.io must be **lowercase**.

---

## 7. Step 5 – Kubernetes

### Setup

Docker Desktop → **Settings → Kubernetes → Enable Kubernetes** (single-node / kubeadm) → **Apply & restart**.

```bash
kubectl config current-context   # docker-desktop
kubectl get nodes                # 1 node, Ready
```

This also creates `C:\Users\rafaf\.kube\config` (before that, VS Code's Kubernetes extension complained "Kubeconfig not found". Harmless).

### Core objects

| Object | What it is |
|---|---|
| **Namespace** | A folder inside the cluster grouping this project's resources. |
| **Deployment** | "I want N copies of this container running." Kubernetes keeps it that way. |
| **ReplicaSet** | Created by the Deployment for each version; you rarely touch it. |
| **Pod** | One running instance of the container. Disposable, replaced automatically. |
| **Service** | A stable address in front of the Pods (Pods come and go, their IPs change). |
| **Secret** | Sensitive data (here: credentials to pull from ghcr.io). |

**Labels connect everything:** the Deployment stamps `app: devops-lab` on each Pod; the Service finds Pods by that same label.

### Namespace + pull Secret (created by command, never committed)

```bash
kubectl create namespace devops-lab

read -s CR_PAT
kubectl create secret docker-registry ghcr-secret \
  --namespace devops-lab \
  --docker-server=ghcr.io \
  --docker-username=rafaelxfernandes \
  --docker-password="$CR_PAT"
```

> Secrets must **never** be committed to git. Real companies use a vault or sealed-secrets.

### `k8s/deployment.yaml`

```yaml
apiVersion: apps/v1                 # API group/version for Deployments
kind: Deployment                    # type of object
metadata:
  name: devops-lab                  # name of this Deployment
  namespace: devops-lab             # which namespace it lives in
spec:
  replicas: 2                       # desired number of Pods
  selector:
    matchLabels:
      app: devops-lab               # "the Pods I manage are the ones with this label"
  template:                         # blueprint for every Pod
    metadata:
      labels:
        app: devops-lab             # must match the selector above
    spec:
      imagePullSecrets:
        - name: ghcr-secret         # use this Secret to pull the private image
      containers:
        - name: web
          image: ghcr.io/rafaelxfernandes/devops-lab:1.2.0
          # Pinned version, never "latest" → always know exactly what's running.
          ports:
            - containerPort: 5000
          readinessProbe:           # "Is it READY to receive traffic?"
            httpGet:                #   Not ready → removed from the Service, not restarted.
              path: /health         #   Makes rolling updates zero-downtime.
              port: 5000
            initialDelaySeconds: 3  # wait 3s after start before first check
            periodSeconds: 5        # then check every 5s
          livenessProbe:            # "Is it still ALIVE?"
            httpGet:                #   Fails repeatedly → container is restarted.
              path: /health
              port: 5000
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:               # what the scheduler RESERVES for the Pod
              cpu: 50m              # 50 millicores = 5% of one CPU core
              memory: 64Mi
            limits:                 # hard CEILING (over memory limit → killed)
              cpu: 250m
              memory: 128Mi
```

### `k8s/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: devops-lab
  namespace: devops-lab
spec:
  type: LoadBalancer      # Docker Desktop exposes LoadBalancer services on localhost
  selector:
    app: devops-lab       # send traffic to Pods carrying this label
  ports:
    - port: 8080          # port exposed on localhost
      targetPort: 5000    # port inside the container
```

### Deploy

```bash
kubectl apply -f k8s/                 # create/update everything in the folder (declarative)
kubectl get all -n devops-lab
curl http://localhost:8080/health

# If EXTERNAL-IP stays <pending>:
kubectl port-forward -n devops-lab svc/devops-lab 8080:8080
```

### Exercises I did

Keep a watch window open: `kubectl get pods -n devops-lab -w`

| Exercise | How | What happens |
|---|---|---|
| **Self-healing** | `kubectl delete pod -n devops-lab <pod>` | A replacement Pod appears within seconds. |
| **Scaling** | change `replicas`, `kubectl apply -f k8s/` | Pods added/removed to match. |
| **Rolling update** | change image tag, `kubectl apply -f k8s/`, `kubectl rollout status ...` | New Pods start and old ones stop **one at a time**: zero downtime. |
| **Rollback** | `kubectl rollout undo deployment/devops-lab -n devops-lab` | Previous version restored. |
| **History** | `kubectl rollout history deployment/devops-lab -n devops-lab` | List of revisions. |

**After a rollback, fix the drift:** `rollout undo` changes the cluster but not the YAML in git. Set the image tag in `deployment.yaml` back to the running version, then `kubectl apply -f k8s/` should print **`unchanged`**. That's the proof git and cluster agree. Commit it.

### Cleanup

```bash
kubectl delete namespace devops-lab   # deletes Deployment, Service, Pods and Secret together
```

---

## 8. Bonus – Testing Kubernetes in CI with kind

**kind** = "Kubernetes IN Docker": a full cluster inside a Docker container. Starts in ~30s on a GitHub runner, then is thrown away.

- The image is built in the job and **loaded directly into the cluster** (`kind load`), so no registry or Secret is needed.
- `sed` swaps the ghcr.io image in the manifest for the freshly built one (Kustomize/Helm do this properly in real projects).
- `publish` now needs `k8s-test` → an image is only published if it **actually deploys and answers HTTP**.

**Break-it exercise:** changed the readiness probe path to `/healthz` on a branch → Pods never became Ready → `rollout status` timed out → the debug step showed `Readiness probe failed: HTTP probe failed with statuscode: 404` → `publish` skipped. Bug caught before reaching any cluster.

### The complete `ci.yml`, annotated

```yaml
name: CI                                   # name shown in the Actions tab

on:                                        # TRIGGERS
  push:
    branches: [main]                       # every push to main
    tags: ["v*"]                           # every tag starting with v (v1.0.0, v1.2.0…)
  pull_request:
    branches: [main]                       # every PR targeting main
  workflow_dispatch:                       # "Run workflow" button in the UI

jobs:
  # ── Job 1: unit tests on 2 Python versions ─────────────────────────
  test:
    runs-on: ubuntu-latest                 # fresh Linux VM provided by GitHub
    strategy:
      matrix:
        python-version: ["3.12", "3.13"]   # job runs twice, in parallel
    steps:
      - uses: actions/checkout@v7          # download the repo code onto the runner
      - uses: actions/setup-python@v7      # install the requested Python
        with:
          python-version: ${{ matrix.python-version }}
          cache: pip                       # reuse downloaded packages between runs
      - run: pip install -r requirements.txt
      - run: pytest -v                     # -v = verbose (one line per test)

  # ── Job 2: build the image and test inside it ──────────────────────
  docker:
    runs-on: ubuntu-latest
    needs: test                            # only if ALL test jobs passed
    steps:
      - uses: actions/checkout@v7
      - run: docker build -t devops-lab:ci .
      - run: docker run --rm devops-lab:ci pytest -v

  # ── Job 3: deploy to a throwaway Kubernetes cluster ───────────────
  k8s-test:
    runs-on: ubuntu-latest
    needs: docker
    steps:
      - uses: actions/checkout@v7

      - name: Create kind cluster
        uses: helm/kind-action@v1          # creates cluster + installs kubectl
        with:
          cluster_name: ci

      - name: Build image and load it into the cluster
        run: |                             # "|" = multi-line shell script
          docker build -t devops-lab:ci .
          kind load docker-image devops-lab:ci --name ci

      - name: Create namespace
        run: kubectl create namespace devops-lab

      - name: Validate manifests against the real API server
        run: kubectl apply --dry-run=server -f k8s/
        # full validation by the API server, creates nothing

      - name: Deploy (swap in the image we just built)
        run: |
          sed "s|image: ghcr.io/.*|image: devops-lab:ci|" k8s/deployment.yaml > /tmp/deployment.yaml
          kubectl apply -f /tmp/deployment.yaml -f k8s/service.yaml

      - name: Wait for the rollout
        run: kubectl rollout status deployment/devops-lab -n devops-lab --timeout=120s
        # fail instead of hanging forever if Pods never become Ready

      - name: Smoke test
        run: |
          kubectl port-forward -n devops-lab svc/devops-lab 8080:8080 &   # & = run in background
          sleep 3
          curl -f http://localhost:8080/health   # -f = fail on HTTP errors
          curl -f http://localhost:8080/

      - name: Debug info (only if something failed)
        if: failure()                      # runs ONLY when a previous step failed
        run: |
          kubectl get all -n devops-lab
          kubectl describe pods -n devops-lab
          kubectl logs -n devops-lab deploy/devops-lab --all-containers --tail=50 || true

  # ── Job 4: publish the image to ghcr.io ────────────────────────────
  publish:
    runs-on: ubuntu-latest
    needs: [docker, k8s-test]              # only if the image builds AND deploys
    if: github.event_name != 'pull_request'   # never publish from PRs

    permissions:
      contents: read                       # to check out the code
      packages: write                      # to push to ghcr.io

    steps:
      - uses: actions/checkout@v7

      - name: Set up Docker Buildx         # advanced builder (caching, multi-platform)
        uses: docker/setup-buildx-action@v4

      - name: Log in to ghcr.io
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}               # who triggered the run
          password: ${{ secrets.GITHUB_TOKEN }}       # automatic temporary token

      - name: Generate image tags and labels
        id: meta                           # id lets later steps read this step's outputs
        uses: docker/metadata-action@v6    # also lowercases the name + links image to repo
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha                                   # sha-abc1234
            type=raw,value=latest,enable={{is_default_branch}}   # latest, only on main
            type=semver,pattern={{version}}            # v1.2.0 → 1.2.0
            type=semver,pattern={{major}}.{{minor}}    # v1.2.0 → 1.2

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}        # output from the "meta" step
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha             # reuse layers from previous CI runs
          cache-to: type=gha,mode=max
```

Pipeline graph in the Actions tab: **test (×2) → docker → k8s-test → publish**.

---

## 9. How to release a new version

```bash
# 1. Change code + tests, commit, push to main → CI runs
git add .
git commit -m "Describe the change"
git push

# 2. Tag the release → CI publishes 1.x.y and 1.x to ghcr.io
git tag v1.3.0
git push origin v1.3.0
# wait for the green run in the Actions tab

# 3. Deploy: edit k8s/deployment.yaml → image: ...:1.3.0
kubectl apply -f k8s/
kubectl rollout status deployment/devops-lab -n devops-lab
curl http://localhost:8080/

# 4. Commit the manifest so git matches the cluster
git add k8s/ && git commit -m "Deploy 1.3.0" && git push

# Something wrong? Roll back, then fix the drift in git:
kubectl rollout undo deployment/devops-lab -n devops-lab
```

---

## 10. Command cheat sheet

### Git
```bash
git status
git checkout -b feature/x           # new branch
git push -u origin feature/x        # push branch (then open PR on GitHub)
git tag v1.0.0 && git push origin v1.0.0
git commit -am "msg"                # stage modified tracked files + commit
```

### Docker
```bash
docker build -t name:tag .
docker run -d -p 8080:5000 --name x name:tag
docker ps / docker ps -a            # running / all containers
docker logs x
docker exec x <command>
docker stop x && docker rm x
docker rm -f x                      # stop + remove in one go
docker images
docker inspect x --format '{{.State.ExitCode}}'   # 0 = clean exit, 137 = killed
```

### kubectl
```bash
kubectl config current-context
kubectl get nodes
kubectl apply -f k8s/
kubectl apply --dry-run=server -f k8s/        # validate without creating
kubectl get all -n devops-lab
kubectl get pods -n devops-lab -w             # -w = watch live
kubectl describe pod <pod> -n devops-lab      # read the Events at the bottom!
kubectl logs -n devops-lab deploy/devops-lab
kubectl rollout status deployment/devops-lab -n devops-lab
kubectl rollout history deployment/devops-lab -n devops-lab
kubectl rollout undo deployment/devops-lab -n devops-lab
kubectl rollout restart deployment/devops-lab -n devops-lab   # new Pods, same version
kubectl port-forward -n devops-lab svc/devops-lab 8080:8080
kubectl delete namespace devops-lab
```

---

## 11. Problems I hit and what they taught me

### 1. `Kubeconfig not found` popup in VS Code
The Kubernetes extension activates on any YAML file and looks for `~/.kube/config`. Harmless; disappears once Kubernetes is enabled in Docker Desktop.

### 2. `docker login` fails in Git Bash
Git Bash's terminal isn't a real TTY for Docker's password prompt. Use `--password-stdin` (see [section 6](#6-step-4--publishing-the-image-to-ghcrio)) or log in once from PowerShell.

### 3. `bash: $'\302\203docker': command not found`
An **invisible character** was pasted from a web page in front of `docker`. Fix: type the command by hand (or paste into VS Code first).

### 4. `docker build -t devops-lab>:sigfix .`
A stray `>` is a bash **redirect**: it built the image as `devops-lab:latest` and wrote the build output into a file named `:sigfix`. Check `git status` for unexpected files before committing.

### 5. Old Pods ending in `Error` during rolling updates (PID 1 signal handling)
**Symptom:** terminating Pods showed `Error` exactly **30 seconds** after `Terminating`.

**Cause:**
1. To stop a Pod, Kubernetes sends **SIGTERM** ("please shut down").
2. The container ran `python app.py` as **PID 1**. Linux ignores signals for PID 1 unless the process installs a handler; Flask's dev server doesn't → SIGTERM ignored.
3. Kubernetes waits the **30s grace period**, then sends **SIGKILL** → exit code **137** → shown as `Error`.

**Fix:** run **gunicorn** (handles SIGTERM gracefully). Verified with exit codes:
```bash
docker stop sigtest
docker inspect sigtest --format '{{.State.ExitCode}}'   # 137 before fix, 0 after
```
Note: during the first rollout *to* the fixed version, the old Pods being stopped still have the bug. The fix is visible from the following rollout on.

### 6. Drift after `kubectl rollout undo`
The cluster ran 1.2.0 while `deployment.yaml` in git still said 1.3.0: the next `kubectl apply` would have re-deployed the "broken" version. Always bring git back in line; `kubectl apply` printing `unchanged` proves they agree. Tools like Argo CD (GitOps) solve this automatically.

### 7. `ImagePullBackOff`
Almost always the pull Secret or the image name (must be lowercase, correct tag). `kubectl describe pod <pod> -n devops-lab` → Events at the bottom tell you exactly why.

### 8. `error: the server doesn't have a resource type "deploment"`
Just a typo (`deploment` → `deployment`). kubectl's errors are usually literal. Read them first.

---

## 12. Next things to learn

- **Kustomize / Helm**: proper way to vary manifests per environment (replaces the `sed` trick in CI).
- **Dependabot**: automatic PRs to keep `actions/checkout@v7` & co. up to date.
- **Argo CD**: GitOps: the cluster syncs itself from git, eliminating drift.
- **GitHub Pages**: a static status/docs page for the project, deployed by Actions.