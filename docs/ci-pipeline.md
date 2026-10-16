# The CI/CD pipeline (`ci.yml`), annotated

[← Back to README](../README.md)

Every job and step of `.github/workflows/ci.yml`, explained line by line.

> The repo has a second workflow, `.github/workflows/terraform.yml` (Terraform fmt / validate / TFLint), documented in [terraform.md](terraform.md#step-t4--terraform-in-ci).

## The complete `ci.yml`, annotated

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
          # dev follows every release too (added with Terraform T5); prod is promoted by hand:
          yq -i '(.images[] | select(.name == "ghcr.io/rafaelxfernandes/devops-lab")).newTag = strenv(VERSION)' kustomize/overlays/dev/kustomization.yaml
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
