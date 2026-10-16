#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh: rebuild the whole DevOps Lab platform on an EMPTY cluster.
#
# Usage (from the repo, in Git Bash):   bash scripts/bootstrap.sh
#
# What it does:
#   1. checks tools + makes sure we're talking to the right cluster
#   2. asks for the two tokens (never written to disk)
#   3. creates the namespaces
#   4. creates the two Secrets that can't live in git
#   5. installs Argo CD from its official Helm chart
#   6. applies the "root" app: from here on, Argo CD deploys EVERYTHING
#      from git (including itself)
#   7. waits until the app is Healthy and prints how to log in
#
# Safe to run again: every step is idempotent (create-or-update).
# Tokens can also be passed as env vars:  CR_PAT=... GH_REPO_PAT=... bash scripts/bootstrap.sh
# =============================================================================
set -euo pipefail
#  -e  stop at the first failing command
#  -u  error on undefined variables (catches typos)
#  -o pipefail  a pipeline fails if ANY command in it fails

# --- Configuration ------------------------------------------------------------
GITHUB_USER="rafaelxfernandes"
REPO_URL="https://github.com/${GITHUB_USER}/DevOps-Lab.git"
EXPECTED_CONTEXT="docker-desktop"
ARGOCD_CHART_VERSION="10.7.1"   # keep in sync with argocd/apps/argocd.yaml

# --- Helpers (coloured output) ------------------------------------------------
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mOK\033[0m  %s\n' "$*"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Always run from the repo root, wherever the script was called from
cd "$(dirname "$0")/.."

# --- 1. Prerequisites ---------------------------------------------------------
step "1/7 Checking prerequisites"
for cmd in kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' not found. Install it first (docs/setup-and-tokens.md)."
  ok "$cmd found"
done

CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[[ "$CONTEXT" == "$EXPECTED_CONTEXT" ]] \
  || fail "kubectl context is '$CONTEXT', expected '$EXPECTED_CONTEXT'. Refusing to touch another cluster."
ok "kubectl context: $CONTEXT"

kubectl get nodes >/dev/null 2>&1 \
  || fail "Cluster not reachable. Is Kubernetes enabled (and green) in Docker Desktop?"
ok "cluster reachable"

[[ -f argocd/root-app.yaml && -f platform/argocd/values.yaml ]] \
  || fail "Run this from the DevOps-Lab repo (argocd/root-app.yaml not found)."

# --- 2. Tokens ----------------------------------------------------------------
step "2/7 Tokens (input is hidden)"
if [[ -z "${CR_PAT:-}" ]]; then
  read -rsp "    CR_PAT      (classic PAT, read:packages): " CR_PAT; echo
fi
if [[ -z "${GH_REPO_PAT:-}" ]]; then
  read -rsp "    GH_REPO_PAT (fine-grained, Contents read-only): " GH_REPO_PAT; echo
fi
[[ -n "$CR_PAT" && -n "$GH_REPO_PAT" ]] || fail "Both tokens are required (docs/setup-and-tokens.md)."
ok "tokens received (kept in memory only)"

# --- 3. Namespaces ------------------------------------------------------------
# "create --dry-run=client -o yaml | apply" = create-or-update, never errors if it exists
step "3/7 Namespaces"
for ns in argocd devops-lab; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  ok "namespace $ns"
done

# --- 4. Secrets (the only things NOT in git) ----------------------------------
step "4/7 Secrets"
kubectl create secret docker-registry ghcr-secret \
  --namespace devops-lab \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USER" \
  --docker-password="$CR_PAT" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "ghcr-secret        (cluster can pull the private image)"

kubectl create secret generic repo-devops-lab \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="$REPO_URL" \
  --from-literal=username="$GITHUB_USER" \
  --from-literal=password="$GH_REPO_PAT" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label secret repo-devops-lab -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
ok "repo-devops-lab    (Argo CD can read the private repo)"

# --- 5. Argo CD ---------------------------------------------------------------
step "5/7 Installing Argo CD (Helm chart argo-cd $ARGOCD_CHART_VERSION, takes a few minutes)"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd \
  --values platform/argocd/values.yaml \
  --wait --timeout 10m >/dev/null
ok "Argo CD is running"

# --- 6. Hand over to GitOps ---------------------------------------------------
step "6/7 Applying the root app (app of apps)"
kubectl apply -f argocd/root-app.yaml >/dev/null
ok "Argo CD now manages everything in argocd/apps/ (itself included)"

# --- 7. Wait for the app ------------------------------------------------------
step "7/7 Waiting for devops-lab to be Healthy"
for _ in $(seq 1 60); do                       # up to ~5 min for the root app to create it
  kubectl get application devops-lab -n argocd >/dev/null 2>&1 && break
  sleep 5
done
kubectl get application devops-lab -n argocd >/dev/null 2>&1 \
  || fail "Application 'devops-lab' never appeared. Check the 'root' app in the Argo CD UI."

kubectl wait application/devops-lab -n argocd \
  --for=jsonpath='{.status.health.status}'=Healthy --timeout=10m >/dev/null \
  || fail "devops-lab not Healthy after 10 min. Check: kubectl describe pods -n devops-lab"
ok "devops-lab is Healthy"

# --- Done ---------------------------------------------------------------------
PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"

cat <<EOF

$(printf '\033[1;32m')Platform ready.$(printf '\033[0m')

  App:      curl http://localhost:8080/
  Argo CD:  run in a separate window:
              kubectl port-forward svc/argocd-server -n argocd 8443:443
            then open https://localhost:8443
            user: admin   password: $PASSWORD

  From now on, every change goes through git:
    - app versions:      merge the "Deploy x.y.z" PR
    - Argo CD settings:  edit platform/argocd/values.yaml + merge
    - new apps:          add a file to argocd/apps/ + merge
EOF
