# Part 3: platform as code (step 9)

[← Back to README](../README.md)

The platform-team view: rebuild everything with one command, and let Argo CD manage itself from git.

## Step 9 – Platform as code (bootstrap + Argo CD manages itself)

The goal: what a **platform team** does. The whole cluster setup lives in git and is rebuilt with one command; after that, nobody touches the cluster directly. Not even to change Argo CD.

### The idea: bootstrap once, then git takes over

Some things **can't** come from git, because Argo CD needs them before it can read git:
- the **Secrets** (tokens must never be in git)
- **Argo CD itself** (something has to install the thing that reads git)

So the script does only those, then hands over:

```
bash scripts/bootstrap.sh
  │
  ├─ 1. checks tools + refuses to run on any cluster except docker-desktop
  ├─ 2. asks for CR_PAT + GH_REPO_PAT (hidden, never written to disk)
  ├─ 3. namespaces: argocd, devops-lab
  ├─ 4. secrets:    ghcr-secret, repo-devops-lab
  ├─ 5. helm install Argo CD (official chart, pinned version, our values file)
  ├─ 6. kubectl apply argocd/root-app.yaml     ← the LAST manual action
  └─ 7. waits until devops-lab is Healthy, prints the login
                │
                ▼
      root app ──► deploys every file in argocd/apps/
                     ├─ devops-lab.yaml  → the app (our Helm chart)
                     └─ argocd.yaml      → Argo CD itself (takes over from the Helm install)
```

### Pattern 1: "app of apps" (`argocd/root-app.yaml`)

One Application whose job is to deploy **other Applications**. It points at the folder `argocd/apps/`, so:

- **new app** = add a file to `argocd/apps/` + merge
- **remove an app** = delete its file + merge (`prune: true`)

The bootstrap applies only this one file. Everything else follows from git.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/rafaelxfernandes/DevOps-Lab.git
    targetRevision: main
    path: argocd/apps            # a plain folder of Application manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd            # Applications live in Argo CD's namespace
  syncPolicy:
    automated:
      prune: true                # file removed from argocd/apps → Application removed
      selfHeal: true
```

`root-app.yaml` sits **outside** `argocd/apps/` on purpose, so the root app doesn't manage itself.

### Pattern 2: Argo CD manages itself (`argocd/apps/argocd.yaml`)

The bootstrap installs Argo CD with Helm (release name `argocd`). Then this Application renders the **same chart, same version, same release name, same values**, so it matches what's running and takes ownership:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  project: default
  sources:                                              # TWO sources:
    - repoURL: https://argoproj.github.io/argo-helm     # 1. official chart
      chart: argo-cd
      targetRevision: 10.7.1                            #    pinned chart version
      helm:
        releaseName: argocd
        valueFiles:
          - $values/platform/argocd/values.yaml         #    values from source 2
    - repoURL: https://github.com/rafaelxfernandes/DevOps-Lab.git
      targetRevision: main
      ref: values                                       # 2. our repo, named "$values"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false        # SAFETY: a mistake in git must never delete Argo CD itself
      selfHeal: true
    syncOptions:
      - ServerSideApply=true   # Argo CD's CRDs are too big for client-side apply
```

| Piece | Meaning |
|---|---|
| `sources:` (plural) | **Multi-source** Application: chart from one repo, values from another |
| `ref: values` / `$values/...` | name a source, then use its files from the other source |
| `prune: false` | deliberate exception: for the tool that runs everything, refuse automatic deletion |
| `ServerSideApply=true` | same reason as `--server-side` in the manual install |

**Version pinning:** chart `10.7.1` appears in **three places**: `argocd/apps/argocd.yaml`, `ARGOCD_CHART_VERSION` in `scripts/bootstrap.sh`, and (since Terraform step T3) `argocd_chart_version` in `terraform/cluster/variables.tf`. Keep them equal, or a fresh bootstrap installs a different version than git describes (Argo CD would then upgrade or downgrade itself right after).

### `platform/argocd/values.yaml`: Argo CD's own config, in git

```yaml
dex:
  enabled: false                  # no SSO in the lab: log in with the admin account
notifications:
  enabled: false                  # no Slack/email notifications in the lab
configs:
  cm:
    timeout.reconciliation: 60s   # check git every 60s (+ up to 60s jitter), default 120s
```

Anything under `configs.cm` goes into Argo CD's main ConfigMap (`argocd-cm`). All options are in the chart's [values.yaml](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd).

### `scripts/bootstrap.sh`: notable techniques

| Technique | Why |
|---|---|
| `set -euo pipefail` | stop at the first error, catch undefined variables, fail on errors inside pipes |
| context check (`docker-desktop` only) | a bootstrap script must never run against the wrong cluster by accident |
| `read -rsp` | hidden token input; tokens can also come from env vars (`CR_PAT=... bash scripts/bootstrap.sh`) |
| `kubectl create ... --dry-run=client -o yaml \| kubectl apply -f -` | **create-or-update**: running the script twice doesn't fail on "already exists" |
| `kubectl label ... --overwrite` | idempotent labelling |
| `helm upgrade --install --wait` | install-or-upgrade, and wait until Argo CD is ready |
| `kubectl wait --for=jsonpath='{.status.health.status}'=Healthy` | wait for a specific field value on any resource |
| `cd "$(dirname "$0")/.."` | works no matter which folder you run it from |

**Idempotent** = running it again changes nothing if everything is already right. That's what makes it safe as a "fix whatever is broken" button.

### `.gitattributes`: line endings

```
*.sh text eol=lf
```

Windows editors save files with **CRLF** line endings; bash reads the extra `\r` as part of the commands and fails (`$'\r': command not found`). This makes git always store and check out `.sh` files with **LF**. In VS Code, also check the bottom-right corner shows **LF** for the script.

### Migration from the step 8 setup

1. Added the new files, `git rm argocd/devops-lab-app.yaml` (replaced by `argocd/apps/devops-lab.yaml`), committed and pushed. **The root app reads from git, so everything must be pushed before bootstrapping.**
2. Docker Desktop → **Reset Kubernetes cluster** (the real "from scratch" test).
3. `bash scripts/bootstrap.sh`

### Tests to prove it works

| Test | Expected result |
|---|---|
| Fresh cluster → `bash scripts/bootstrap.sh` | App Healthy; three apps in the UI: `root`, `argocd`, `devops-lab` |
| Run the script a second time | No errors, nothing changes (idempotent) |
| Change `platform/argocd/values.yaml` (e.g. `timeout.reconciliation: 30s`) + merge | The `argocd` app syncs; `kubectl get cm argocd-cm -n argocd -o yaml` shows the new value |
| `kubectl delete application devops-lab -n argocd` | The root app recreates it |
