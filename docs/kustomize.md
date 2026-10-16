# Kustomize: multiple environments (reference)

[← Back to README](../README.md)

A standalone example of **Kustomize**, the main alternative to Helm, using the same app in two environments: **dev** and **prod**.

> **Not part of the live flow.** Nothing references the `kustomize/` folder: CI ignores it and Argo CD doesn't deploy it (only `argocd/apps/` is deployed). The real app still uses the Helm chart. This folder is for learning and for later reference.

**Contents**

- [Where Kustomize fits](#where-kustomize-fits)
- [Folder structure](#folder-structure)
- [The files, explained](#the-files-explained)
- [Try it](#try-it)
- [Promotion: dev → prod](#promotion-dev--prod)
- [Deploying the overlays with Argo CD](#deploying-the-overlays-with-argo-cd)
- [The same thing with Helm](#the-same-thing-with-helm)
- [Helm vs Kustomize: when to use which](#helm-vs-kustomize-when-to-use-which)
- [Commands](#commands)

---

## Where Kustomize fits

Kustomize replaces **Helm**, not Argo CD. They work at different layers:

```
WHAT to deploy (how the YAML is written)     →  Helm  OR  Kustomize
HOW it gets to the cluster (who applies it)  →  Argo CD  (or Flux, or kubectl)
```

Argo CD understands both: a folder with `Chart.yaml` → it runs Helm; a folder with `kustomization.yaml` → it runs Kustomize.

**The problem both solve:** the same app, with small differences per environment (replicas, image tag, resources…).

- **Helm:** templates with variables (`{{ .Values.replicaCount }}`) + a values file per environment.
- **Kustomize:** **plain YAML** (the *base*) + small **overlays** that patch only what differs. No templates.

Kustomize is built into kubectl (`kubectl kustomize`, `kubectl apply -k`), so there's nothing to install.

---

## Folder structure

```
kustomize/
├── base/                        # shared by every environment: plain, valid Kubernetes YAML
│   ├── kustomization.yaml       #   "these files are the base"
│   ├── deployment.yaml          #   replicas: 2, image tag 1.4.0, normal resources
│   └── service.yaml             #   LoadBalancer on port 8080
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml   # base + namespace devops-lab-dev, 1 replica, tag 1.5.0, port 8081
    │   └── namespace.yaml
    └── prod/
        ├── kustomization.yaml   # base + namespace devops-lab-prod, 3 replicas, tag 1.4.0, port 8082
        ├── namespace.yaml
        └── resources-patch.yaml # more CPU/memory
```

| | base | dev | prod |
|---|---|---|---|
| Namespace | (none) | `devops-lab-dev` | `devops-lab-prod` |
| Replicas | 2 | **1** | **3** |
| Image tag | 1.4.0 | **1.5.0** (newer, tested first) | **1.4.0** (proven) |
| Resources | 50m/64Mi → 250m/128Mi | same as base | **100m/128Mi → 500m/256Mi** |
| Port on localhost | 8080 | **8081** | **8082** |
| Extra label | | `environment: dev` | `environment: prod` |

Dev and prod use ports 8081/8082 so they can run next to the live app (8080) without clashing.

---

## The files, explained

### `base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:          # the plain YAML files that make up the base
  - deployment.yaml
  - service.yaml
```

`base/deployment.yaml` and `base/service.yaml` are normal Kubernetes YAML: the same content the Helm chart renders, without `{{ }}`. Each works on its own with `kubectl apply -f`.

### `overlays/prod/kustomization.yaml` (dev is the same idea)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: devops-lab-prod          # put EVERY resource in this namespace

resources:
  - ../../base                      # start from the base
  - namespace.yaml                  # + create the namespace

labels:
  - pairs:
      environment: prod             # add this label to every resource
    includeTemplates: true          # ...and to the Pods

images:
  - name: ghcr.io/rafaelxfernandes/devops-lab
    newTag: "1.4.0"                 # change only the tag

replicas:
  - name: devops-lab
    count: 3

patches:
  - path: resources-patch.yaml      # strategic merge patch (file)
  - target:                         # JSON 6902 patch (inline)
      kind: Service
      name: devops-lab
    patch: |-
      - op: replace
        path: /spec/ports/0/port
        value: 8082
```

### The Kustomize features used

| Field | What it does | Helm equivalent |
|---|---|---|
| `resources` | which files/folders to include (`../../base` pulls in the whole base) | the `templates/` folder |
| `namespace` | sets the namespace on every resource | `-n` at install time |
| `labels` | adds labels everywhere; `includeTemplates` also adds them to Pods | labels in each template |
| `images` | changes image name/tag without touching the base | `image.tag` in values |
| `replicas` | changes replica counts by Deployment name | `replicaCount` in values |
| `patches` (file) | **strategic merge**: write a *piece* of the resource; Kustomize merges it in | a value + a template using it |
| `patches` (inline, `op:`) | **JSON 6902**: precise operations (`replace`, `add`, `remove`) on a path | same |

**Two kinds of patch:**

- **Strategic merge** (`resources-patch.yaml`): looks like the real resource. Lists are merged smartly: containers are matched **by name**, so only `web`'s `resources` change.
- **JSON 6902** (`op: replace`): exact path, exact operation. Used for the Service port because a strategic merge on `ports` would *add* a second port instead of changing it (ports are merged by port number, and 8082 is a new number).

`labels` keeps `includeSelectors: false` (the default): selectors are **immutable** on a Deployment, so changing them would break updates.

> Older tutorials use `commonLabels`. It's deprecated: it also changes selectors. Use `labels`.

---

## Try it

### 1. See what each overlay produces (nothing is deployed)

```bash
kubectl kustomize kustomize/overlays/dev
kubectl kustomize kustomize/overlays/prod
```

This is the Kustomize equivalent of `helm template`: it prints the final YAML.

### 2. Compare the environments

```bash
diff <(kubectl kustomize kustomize/overlays/dev) <(kubectl kustomize kustomize/overlays/prod)
```

`<( … )` is bash "process substitution": it hands a command's output to `diff` as if it were a file. Works in Git Bash. You'll see only the differences: namespace, label, replicas, tag, resources, port.

### 3. Optional: deploy both by hand

The private image needs `ghcr-secret` **in each namespace** (Secrets don't cross namespaces), so create namespace + secret first:

```bash
read -s CR_PAT
for env in dev prod; do
  kubectl create namespace devops-lab-$env
  kubectl create secret docker-registry ghcr-secret -n devops-lab-$env \
    --docker-server=ghcr.io --docker-username=rafaelxfernandes --docker-password="$CR_PAT"
done

kubectl apply -k kustomize/overlays/dev       # -k = "build with Kustomize, then apply"
kubectl apply -k kustomize/overlays/prod

kubectl get pods -n devops-lab-dev            # 1 Pod
kubectl get pods -n devops-lab-prod           # 3 Pods
curl http://localhost:8081/                   # dev  → 1.5.0 greeting
curl http://localhost:8082/                   # prod → 1.4.0 greeting
```

Clean up (deleting the namespace also deletes its Secret):

```bash
kubectl delete -k kustomize/overlays/dev
kubectl delete -k kustomize/overlays/prod
```

> Applying by hand is fine for learning. In the real flow, Argo CD would apply them (next sections).

---

## Promotion: dev → prod

The typical multi-environment workflow:

1. A new version is released → it goes to **dev** first (`newTag` in `overlays/dev`).
2. It's tested in dev.
3. **Promotion** = a PR changing `newTag` in `overlays/prod` to the same version. Reviewed, merged, deployed.

Each environment's version is one line in git, so "what runs where" is always visible, and promotions have history and approvals.

---

## Deploying the overlays with Argo CD

To make Argo CD manage dev and prod, add one Application per environment to `argocd/apps/`. The root app (app of apps) picks them up automatically:

```yaml
# argocd/apps/devops-lab-dev.yaml   (copy it for prod: change "dev" → "prod")
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devops-lab-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/rafaelxfernandes/DevOps-Lab.git
    targetRevision: main
    path: kustomize/overlays/dev       # a folder with kustomization.yaml → Argo CD runs Kustomize
  destination:
    server: https://kubernetes.default.svc
    namespace: devops-lab-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Things to know before doing it:
- `ghcr-secret` must exist in `devops-lab-dev` / `devops-lab-prod` (add them to `scripts/bootstrap.sh` so a rebuild creates them).
- Each environment is a separate Application with its own sync and health status in the UI.
- The automated bump PR (`bump-version` job) only edits the Helm chart today; for Kustomize, the job would run `kustomize edit set image ...` in `overlays/dev` instead of `yq`.

---

## The same thing with Helm

For comparison: multiple environments with the existing Helm chart need **no template changes**, just one values file per environment.

```yaml
# charts/devops-lab/values-dev.yaml   (only what differs from values.yaml)
replicaCount: 1
image:
  tag: "1.5.0"
service:
  port: 8081
```

```yaml
# charts/devops-lab/values-prod.yaml
replicaCount: 3
image:
  tag: "1.4.0"
service:
  port: 8082
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 256Mi }
```

Helm merges `values.yaml` + `values-<env>.yaml` (later files win). Rendering: `helm template devops-lab charts/devops-lab -f charts/devops-lab/values-prod.yaml`.

With Argo CD, the Application adds the values file and creates the namespace:

```yaml
spec:
  source:
    path: charts/devops-lab
    helm:
      releaseName: devops-lab
      valueFiles:
        - values-prod.yaml          # relative to the chart folder
  destination:
    namespace: devops-lab-prod
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true        # the chart has no Namespace resource
```

---

## Helm vs Kustomize: when to use which

| | Helm | Kustomize |
|---|---|---|
| Style | templates + variables | plain YAML + patches |
| Readability | `{{ }}` everywhere | files are real Kubernetes YAML |
| Differences per environment | values files (must be anticipated in templates) | patches (can change **anything**, no template needed) |
| Packaging / sharing / versions | ✅ charts, repos, versions | ❌ not designed for it |
| Release history / rollback | ✅ built in | ❌ (git + Argo CD handle it) |
| Install | separate tool | built into kubectl |
| Typical use | **third-party software** (Argo CD, databases, monitoring); own apps too | **own apps**, environment overlays |

Common in companies: **Helm for third-party charts, Helm or Kustomize for their own apps.** Some even combine them (Kustomize patching the output of a Helm chart). If a repo has `kustomization.yaml` files or `base/` + `overlays/` folders, it's Kustomize.

---

## Commands

```bash
kubectl kustomize <dir>             # render (like helm template)
kubectl apply -k <dir>              # render + apply
kubectl delete -k <dir>             # render + delete
kubectl diff -k <dir>               # what would change in the cluster

# Standalone kustomize CLI (optional, not needed with kubectl):
kustomize build <dir>               # same as kubectl kustomize
kustomize edit set image ghcr.io/rafaelxfernandes/devops-lab:1.6.0   # edit newTag (run inside an overlay)
```
