# Part 1: everything by hand (steps 1–5 + bonus)

[← Back to README](../README.md)

Building each piece manually to understand it: the app, Docker, GitHub Actions, ghcr.io, Kubernetes, and testing Kubernetes in CI.

**Contents**

- [Step 1 – The app](#step-1--the-app)
- [Step 2 – Docker](#step-2--docker)
- [Step 3 – GitHub Actions: CI](#step-3--github-actions-ci)
- [Step 4 – Publishing the image to ghcr.io](#step-4--publishing-the-image-to-ghcrio)
- [Step 5 – Kubernetes by hand](#step-5--kubernetes-by-hand)
- [Bonus – Testing Kubernetes in CI with kind](#bonus--testing-kubernetes-in-ci-with-kind)

## Step 1 – The app

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

## Step 2 – Docker

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

## Step 3 – GitHub Actions: CI

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

Full annotated workflow: [The complete ci.yml, annotated](ci-pipeline.md#the-complete-ciyml-annotated).

---

## Step 4 – Publishing the image to ghcr.io

| Term | Meaning |
|---|---|
| **ghcr.io** | GitHub Container Registry. Private repo → private package (Profile → Packages). |
| **`permissions`** | What `GITHUB_TOKEN` may do in that job (see [GITHUB_TOKEN (automatic, used by CI)](setup-and-tokens.md#github_token-automatic-used-by-ci)). |
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

## Step 5 – Kubernetes by hand

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

## Bonus – Testing Kubernetes in CI with kind

**kind** = "Kubernetes IN Docker": a full cluster inside a container, ~30s to start on a runner, thrown away afterwards.

- Image built in the job and loaded with `kind load docker-image` → no registry/secret needed.
- Since step 6 it deploys the **Helm chart** with CI-specific values (`--set image.tag=ci --set service.type=ClusterIP`).
- `publish` needs `k8s-test` → an image is only published if it **actually deploys and answers HTTP**.
- `if: failure()` debug step dumps `kubectl get all / describe / logs` when something breaks.

Break-it exercise: readiness probe path `/healthz` → Pods never Ready → job failed with `Readiness probe failed: ... statuscode: 404` → `publish` skipped.
