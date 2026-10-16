# Command cheat sheet

[← Back to README](../README.md)

The commands I use most, grouped by tool.

## Command cheat sheet

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
kubectl get cm argocd-cm -n argocd -o yaml    # Argo CD's live config
```

### Platform
```bash
bash scripts/bootstrap.sh                                  # rebuild / repair everything
CR_PAT=... GH_REPO_PAT=... bash scripts/bootstrap.sh       # same, tokens from env vars
```

### Helm
```bash
helm lint charts/devops-lab
helm template devops-lab charts/devops-lab
helm template devops-lab charts/devops-lab --set image.tag=9.9.9   # preview a change
```

### Kustomize (reference example in `kustomize/`)
```bash
kubectl kustomize kustomize/overlays/dev       # render (like helm template)
kubectl apply -k kustomize/overlays/dev        # render + apply
kubectl diff -k kustomize/overlays/prod        # what would change
diff <(kubectl kustomize kustomize/overlays/dev) <(kubectl kustomize kustomize/overlays/prod)
```

### Terraform
```bash
read -s GITHUB_TOKEN && export GITHUB_TOKEN   # token for the GitHub provider (per terminal)
terraform init                                # download providers (once per folder / after version changes)
terraform fmt && terraform validate           # format + check
terraform plan                                # what would change: READ IT
terraform apply                               # do it (asks "yes")
terraform plan -destroy                       # preview a destroy (safe)
terraform state list                          # what Terraform manages
terraform show                                # details from state
terraform apply -var 'enable_main_protection=false'   # override a variable once
terraform apply -replace=kubernetes_secret_v1.ghcr    # force recreate one resource
read -s TF_VAR_cr_pat && export TF_VAR_cr_pat         # set a Terraform variable from the env (T3)
grep -c "$TF_VAR_cr_pat" terraform.tfstate            # check a secret is NOT in state (expect 0)
```
