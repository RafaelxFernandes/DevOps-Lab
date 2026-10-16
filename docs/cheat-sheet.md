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
