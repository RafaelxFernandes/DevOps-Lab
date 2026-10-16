# Part 2: the tools companies use (steps 6–8)

[← Back to README](../README.md)

Replacing the manual parts: Helm, an automated version-bump PR, and GitOps with Argo CD.

**Contents**

- [Step 6 – Helm](#step-6--helm)
- [Step 7 – Automated version-bump PR](#step-7--automated-version-bump-pr)
- [Step 8 – GitOps with Argo CD](#step-8--gitops-with-argo-cd)

## Step 6 – Helm

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

## Step 7 – Automated version-bump PR

After a release image is published, CI opens a PR changing `image.tag` and `appVersion`. A human reviews and merges it.

```
git tag v1.4.0 ─► test ─► docker ─► k8s-test ─► publish 1.4.0 ─► bump-version
                                                                    │
                                     PR "Deploy 1.4.0" ◄────────────┘
                                     (values.yaml: tag 1.3.0 → 1.4.0, Chart.yaml: appVersion)
```

Key pieces (full job in [The complete ci.yml, annotated](ci-pipeline.md#the-complete-ciyml-annotated)):

| Piece | Meaning |
|---|---|
| `if: startsWith(github.ref, 'refs/tags/v')` | only for release tags |
| `ref: main` on checkout | edit the current `main`, not the tagged commit |
| `${GITHUB_REF_NAME#v}` | `v1.4.0` → `1.4.0` (bash: strip leading `v`) |
| `echo "VERSION=..." >> "$GITHUB_ENV"` | make a variable available to **later steps** |
| `yq -i '.image.tag = strenv(VERSION)'` | YAML-aware edit (preinstalled on runners) |
| `gh pr create` | GitHub CLI (preinstalled), authenticated with `GH_TOKEN` |
| bot identity | `github-actions[bot]` as commit author |

Required repo setting + token behaviour: [GITHUB_TOKEN (automatic, used by CI)](setup-and-tokens.md#github_token-automatic-used-by-ci).

---

## Step 8 – GitOps with Argo CD

### What it does

Argo CD runs **inside the cluster** and loops forever:
1. reads **desired state** from git (`charts/devops-lab` on `main`)
2. reads **live state** from the cluster
3. different → **OutOfSync** → syncs the cluster to match git

**Pull model:** the cluster pulls from git; CI never needs cluster credentials (security win).
Argo CD uses Helm only as a **template engine** → `helm list` is empty; history lives in git + the Argo CD UI.

### Install + access (how it was done by hand in step 8)

> Since step 9, `scripts/bootstrap.sh` installs Argo CD from its **Helm chart** instead. The manual install below is kept to show what happens underneath.

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# --server-side: some Argo CD CRDs are too big for client-side apply

kubectl port-forward svc/argocd-server -n argocd 8443:443      # separate window
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
# https://localhost:8443 → admin / <password>
```

Repo credentials: [GH_REPO_PAT: fine-grained PAT, Contents read-only](setup-and-tokens.md#gh_repo_pat-fine-grained-pat-contents-read-only).

### `argocd/apps/devops-lab.yaml` (was `argocd/devops-lab-app.yaml` until step 9)

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

In step 8 it was applied once by hand with `kubectl apply`, after removing the Helm-CLI release (`helm uninstall`) so Argo CD owned everything cleanly. Since step 9, the root app deploys it automatically.

### What I verified

| Test | Result |
|---|---|
| `kubectl scale deployment devops-lab --replicas=5` | Argo CD scaled it back to 2 (**selfHeal**) |
| `kubectl delete deployment devops-lab` | Recreated automatically |
| Release v1.5.0 → merge bump PR | Argo CD synced within ~3 min (or **Refresh** button) |
| Revert the bump PR on GitHub | Argo CD rolled back to the previous version |

Argo CD **polls** git every few minutes. Companies configure a GitHub **webhook** for instant syncs (impossible here: GitHub can't reach my laptop).
