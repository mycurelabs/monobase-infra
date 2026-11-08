# Agent Guidance

Repository guidance (structure, conventions, safety rules, skills):
see @CLAUDE.md.

## Amp Orbs (Kubernetes Ops Box)

Orbs for the `mycure/monobase-infra` Amp project are set up as an ops box
for this repo.

- **Tooling:** `.agents/setup` installs every tool pinned in `mise.toml`
  (terraform, tofu, kubectl, helm, trivy, doctl, linters), plus gcloud with
  `gke-gcloud-auth-plugin` and bun dependencies. The tools are on `PATH` in
  login shells via mise shims. Setup never writes credentials, because its
  output is saved in a snapshot shared across threads.
- **Cluster access:** `.agents/resume` runs on every orb start and wake. It
  decodes the `KUBECONFIG_B64` project secret into `~/.kube/config` and logs
  the result to `~/.cache/amp/logs/resume.log`.
  - The only context is `do-sgp1-mycure-doks-main`, the **production**
    cluster (`mycure-doks-main`).
  - The credential has **cluster-admin** rights, including reading Secrets.
  - `mycure-onprem-vanaheim` (tailnet-only) and `mycure-contabo-demo` are
    not reachable from orbs.
- **Default to read-only.** Use `get`, `describe`, `logs`, `top`, and
  `auth can-i` freely. Ask the user before any command that changes the
  cluster (`apply`, `delete`, `edit`, `patch`, `scale`, `rollout restart`,
  `exec` into pods, `helm upgrade`). Never print Secret values. Prefer
  changing `values/` through Git, because ArgoCD self-heal reverts direct
  changes.
- **If kubectl fails:** check `resume.log` first. The usual causes are a
  missing or expired `KUBECONFIG_B64` (DigitalOcean kubeconfig tokens can
  expire) or an API server that is down. After the user updates the secret,
  run `amp orb restart-processes`, then `.agents/resume`.
