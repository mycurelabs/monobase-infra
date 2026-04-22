# AI Briefing: Fix `mycureapp:10.6.1` — Caddy Brotli module missing at runtime

> **How to use this file:** copy everything below the `---` (but keep it formatted) and paste it as the initial prompt into an AI assistant (Claude, Copilot chat, etc.) that is working inside the **mycureapp** repo (the frontend that ships as `ghcr.io/mycurelabs/mycureapp`).
>
> The AI will have no context from the mono-infra side. Everything it needs to fix the image is in the brief below. The fix should ship as `10.6.2`.

---

## Role

You are working in the mycureapp repository — the frontend that is shipped as the container image `ghcr.io/mycurelabs/mycureapp`. Your job is to ship a patched image (tag `10.6.2`) that fixes a startup crash in `10.6.1`.

## Problem

`ghcr.io/mycurelabs/mycureapp:10.6.1` **cannot start.** Every pod crashes during container init, before the readiness probe ever passes.

Confirmed on two Kubernetes environments (mycure staging + preprod), on two different nodes, on three different pod restarts. The behavior is deterministic — it's a build issue, not an environmental one.

### The exact error

```
Generated /tmp/config.json with:
  api_url: https://hapihub.<env>.localfirsthealth.com
  hapihub_url: https://hapihub.<env>.localfirsthealth.com
{"level":"info","ts":1776787765.3069317,"msg":"using config from file","file":"/etc/caddy/Caddyfile"}
Error: adapting config using caddyfile: parsing caddyfile tokens for 'encode':
  finding encoder module '': module not registered: http.encoders.br,
  at /etc/caddy/Caddyfile:11
```

### What this error means

- The image runs **Caddy** as its web server. Caddy reads `/etc/caddy/Caddyfile` at startup.
- **Line 11** of the Caddyfile contains an `encode` directive that lists `br` (Brotli) as one of the compression encoders. The exact directive is probably one of:

  ```
  encode zstd br gzip
  # or
  encode br gzip
  # or
  encode br
  ```

- Caddy's **mainline binary** (the one you get from `FROM caddy:...` in Docker) **does not include** the Brotli encoder module (`http.encoders.br`). Brotli is *not* built into mainline Caddy upstream and has to be added explicitly.

- Result: at startup, Caddy tries to resolve the `br` token in the `encode` directive, can't find `http.encoders.br` in its compiled module registry, and refuses to start.

### What we know this is **not**

- Not a Kubernetes / pod issue. Memory and CPU requests are fine. Readiness probe path (`/`) and port (8080) match previous working versions (10.4.4 works on these same pods, same nodes, same cluster).
- Not a config injection issue. `API_URL` and `HAPIHUB_URL` env vars are set correctly; the log line `Generated /tmp/config.json with: api_url=...` confirms the init script produced `/tmp/config.json` successfully.
- Not a Helm/chart issue. The Helm chart in the infra repo does **not** own `/etc/caddy/Caddyfile`; it only provides env vars and mounts empty `/tmp`, `/data`, `/config` volumes. The Caddyfile is baked into this image.
- Not an infra-side regression. The previous image tag `10.4.4` runs cleanly on the same cluster with the same Helm values.

The fix is **entirely inside this repo** (Dockerfile + Caddyfile + possibly a Caddy build tool).

## Your fix options (pick one)

### Option A — Build Caddy with a Brotli module (keeps `br` in the Caddyfile)

This is the right choice **if** the team wants to keep Brotli compression. Brotli typically compresses HTML/JS/CSS ~20% smaller than gzip and is supported by all modern browsers, so it's worth keeping.

In the Dockerfile, replace the `FROM caddy:<ver>` base with a two-stage build that uses `xcaddy` to compile a custom Caddy binary with a Brotli module, then copy it into a minimal runtime image. Example:

```dockerfile
# ---- Stage 1: build a custom Caddy with Brotli ----
FROM caddy:2.8-builder AS caddy-builder

RUN xcaddy build \
    --with github.com/dunglas/caddy-cbrotli \
    # add any other modules you're currently using
    # --with github.com/caddyserver/transform-encoder \
    # ...

# ---- Stage 2: runtime ----
FROM caddy:2.8-alpine  # or whatever base you were using before

# Replace the stock caddy binary with the xcaddy-built one.
COPY --from=caddy-builder /usr/bin/caddy /usr/bin/caddy

# (rest of your Dockerfile unchanged: copy /etc/caddy/Caddyfile, copy the
#  built frontend bundle, set CMD, etc.)
```

Notes:

- Pin `caddy:2.X-builder` and `caddy:2.X-alpine` to the same minor version to avoid ABI / module mismatches.
- `github.com/dunglas/caddy-cbrotli` is the de-facto Brotli module for Caddy v2 (uses the cgo brotli lib — smaller and faster than the pure-Go alternatives). If you can't use cgo, try `github.com/ueffel/caddy-brotli` instead.
- `xcaddy build` needs Go toolchain in the build stage. The `caddy:*-builder` image includes it; if you're using a vanilla Go base for stage 1 you'll need `golang:1.22+`.
- Verify the final binary has Brotli registered: `caddy list-modules | grep brotli` should show `http.encoders.br`.

### Option B — Remove `br` from the Caddyfile (ships faster, loses Brotli compression)

This is the right choice **if** the team would rather just unblock the release and not bother with xcaddy.

1. Open the Caddyfile in this repo (look for it under `caddy/`, `docker/`, or adjacent to the Dockerfile).
2. Find line 11 — the one with `encode ...`.
3. Remove the `br` token. Example:

    ```diff
    - encode zstd br gzip
    + encode zstd gzip
    ```

4. That's it. The stock `caddy:2.X` image already registers `http.encoders.gzip` and `http.encoders.zstd`, so this will start cleanly.

Clients that would have received Brotli will get gzip instead — slightly larger responses, no functional impact.

## What to verify before tagging 10.6.2

**Locally (before pushing the image):**

```bash
# 1. Build the image
docker build -t mycureapp:test .

# 2. Start it with fake env vars (matching what the real Helm chart provides)
docker run --rm -p 8080:8080 \
  -e API_URL="https://hapihub.example.com" \
  -e HAPIHUB_URL="https://hapihub.example.com" \
  mycureapp:test

# 3. Verify Caddy started and is serving. You should NOT see the
#    "module not registered: http.encoders.br" error in the logs.

# 4. In another terminal, curl the root path:
curl -i http://localhost:8080/

# For Option A, also verify Brotli works:
curl -H "Accept-Encoding: br" -I http://localhost:8080/
# Should see "content-encoding: br" in the response headers.

# For Option B, verify gzip is the fallback:
curl -H "Accept-Encoding: gzip" -I http://localhost:8080/
# Should see "content-encoding: gzip".
```

**In CI:** the build + container-run + `/` response check should be automatable if it isn't already. This exact class of "Caddyfile references a module the binary doesn't have" bug is trivially caught by starting the container and waiting for it to become healthy.

## What to deliver

1. A new image tag `ghcr.io/mycurelabs/mycureapp:10.6.2` that fixes the startup crash.
2. A commit message / PR title like `fix(caddy): restore Brotli encoder module (or drop from Caddyfile) — fixes 10.6.1 startup crash`.
3. Leave any comment or internal note that explains *why* the fix was needed, so the next person adding `encode` directives doesn't hit the same trap.

## What NOT to do

- **Do not** touch the mono-infra repo (Helm charts, values files, ArgoCD apps). The infra side is fine and will pick up the new image tag automatically once ops bumps `tag: "10.6.2"` in `values/deployments/mycure-{staging,preprod}.yaml`.
- **Do not** change the readiness/liveness probe paths, the `/tmp/config.json` generator script, the env-var names (`API_URL`, `HAPIHUB_URL`), or the port (8080). Those are contracts the infra charts rely on.
- **Do not** ship the fix as a new major/minor version. This is a patch (`10.6.1 → 10.6.2`).
- **Do not** bundle unrelated changes into this fix. Keep the blast radius minimal — ops needs to be able to bump back to 10.6.x with confidence.

## Escalation / questions

If you need help:

- To see the full Caddyfile that's currently baked in, `docker run --rm --entrypoint cat ghcr.io/mycurelabs/mycureapp:10.6.1 /etc/caddy/Caddyfile` will show it (Caddy never starts, but the file is in the image).
- If `xcaddy build` fails because an existing Caddy module you depend on conflicts with `caddy-cbrotli`, list all currently-used modules first (`caddy list-modules` on a running 10.4.4 container) and bring them along to the builder.
- If the Caddyfile has more than one `encode` directive (e.g., one per route), check all of them for `br`.

That's everything. Good luck.
