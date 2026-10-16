# Troubleshooting: problems I hit and what they taught me

[← Back to README](../README.md)

Real errors from building this project, with the cause and the fix.

## Problems I hit and what they taught me

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
13. **Bump PR has no CI checks:** `GITHUB_TOKEN` events don't trigger workflows (anti-loop rule). See [GITHUB_TOKEN (automatic, used by CI)](setup-and-tokens.md#github_token-automatic-used-by-ci).
14. **`$'\r': command not found` when running a script:** the file has Windows (CRLF) line endings. Fixed permanently by `.gitattributes` (`*.sh text eol=lf`); in VS Code, set the line ending to **LF** (bottom-right corner).
15. **`helm list -n argocd` still shows the bootstrap release:** expected. Helm installed Argo CD once; after that, the `argocd` Application owns it. Upgrades go through git, never `helm upgrade`.
16. **Bootstrap applied the root app but apps are missing:** the root app reads **git**, not my PC. Unpushed files don't exist for Argo CD. Push first.
17. **Terraform import turned on a setting I didn't mean to change (`has_wiki = false -> true`):** my code didn't match the existing repo and I applied without checking every `~` line. Rule: after an import, the plan must show **only intended changes**.
18. **`403 Upgrade to GitHub Pro or make this repository public` when creating a ruleset:** the account is on **GitHub Free** (check Settings → Billing: "Current plan"; Copilot Pro/Free is a separate product). Rulesets on private repos need a paid plan → made the repo public through Terraform.
19. **Apply failed halfway:** Terraform isn't all-or-nothing. What succeeded is saved in state; the next plan shows only what's left. Always read the apply output to the end.
20. **`Instance cannot be destroyed`:** `lifecycle { prevent_destroy = true }` working as intended on the repo. Not an error to fix.
21. **Tokens found in `terraform.tfstate` although the variables were `sensitive`:** `sensitive` only hides values on screen; state stores resource attributes. Fix: `ephemeral = true` variables + write-only `data_wo` arguments.
22. **Tokens still in state after switching `data` → `data_wo`:** the provider stops reading `data` but never clears the old value (Optional + Computed attribute). Fix: `terraform apply -replace=…` on the secrets, delete `terraform.tfstate.backup`, rotate the tokens. Lesson: state remembers; a secret that reached state counts as exposed.
23. **Plan on an existing cluster wants to create things that already exist / errors with "already exists":** the state doesn't match this cluster (e.g. after a reset, or the cluster was built with `bootstrap.sh`). Use one bootstrap method per cluster; after a reset, delete the old state before `terraform apply`.
