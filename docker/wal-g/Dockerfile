# wal-g for PostgreSQL WAL archiving / PITR (mycure-production, mycure-preprod).
#
# Two roles:
#   1. initContainer — copies the binary onto a shared emptyDir, because the
#      Bitnami PostgreSQL container runs with readOnlyRootFilesystem: true and
#      ships no S3-capable tool (no curl/wget/python/aws/mc/rclone).
#   2. runner image for `wal-g backup-push` / `wal-g delete` CronJobs.
#
# Base is debian:12-slim to match the Bitnami PostgreSQL image (glibc 2.36).
# The upstream build is the ubuntu-22.04 one (glibc 2.35) — forward-compatible.
# Do NOT use the 24.04 build: glibc 2.39 will not load on Debian 12.
#
# Build (host may be arm64; cluster nodes are amd64):
#   curl -sLO https://github.com/wal-g/wal-g/releases/download/v3.0.9/wal-g-pg-22.04-amd64.tar.gz
#   tar xzf wal-g-pg-22.04-amd64.tar.gz && mv wal-g-pg-22.04-amd64 wal-g
#   docker buildx build --platform linux/amd64 -t ghcr.io/mycurelabs/wal-g:v3.0.9 --push .
#
# Upstream sha256 of wal-g-pg-22.04-amd64.tar.gz (v3.0.9), verify before building:
#   4f03ee4679db7f660bfd1b2b8291ac5df247cd2ec48074b60c112f4897299f24
FROM debian:12-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY wal-g /usr/local/bin/wal-g
RUN chmod 0755 /usr/local/bin/wal-g
USER 1001:1001
ENTRYPOINT ["/usr/local/bin/wal-g"]
