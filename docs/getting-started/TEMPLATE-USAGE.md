# Template Usage Guide

This document explains how to use and maintain the Monobase Infrastructure template.

## Overview

The Monobase Infrastructure template is designed for a **fork-based workflow**:

- **Base Template** (this repo) - Generic, reusable infrastructure maintained by us
- **Client Forks** - Clients fork the template and add their configuration

## For Template Maintainers (Us)

### Maintaining the Base Template

**What goes in the base template:**
✅ Generic Helm charts (100% parameterized)
✅ Infrastructure templates (.yaml.template files)
✅ Reference configuration (deployments/example.com/)
✅ Documentation
✅ Scripts

**What does NOT go in the base template:**
❌ Client-specific values
❌ Real domains (only example.com)
❌ Secrets or credentials
❌ Client configuration (except example.com reference)

### Updating the Template

```bash
# 1. Make changes to base template
vim charts/api/Chart.yaml

# 2. Update reference config if needed
vim deployments/example.com/values-production.yaml

# 3. Update documentation (co-located with code)
vim charts/api/README.md  # If API parameters changed
vim deployments/README.md  # If deployment-level parameters changed

# 4. Test with example.com config
helm template test charts/api \\
  -f deployments/example.com/values-production.yaml

# 5. Commit and tag
git add .
git commit -m "feat(api): Add new feature X"
git tag -a v1.1.0 -m "Version 1.1.0"
git push --tags

# 6. Announce to clients
# Send notification: "Template v1.1.0 available, sync with upstream"
```

## For Clients

### Forking the Template

See **[CLIENT-ONBOARDING.md](CLIENT-ONBOARDING.md)** for detailed fork workflow.

### Syncing Upstream Changes

Clients can pull template updates from the base repository:

```bash
# One-time setup
git remote add upstream https://github.com/YOUR-ORG/monobase-infra.git

# Pull latest updates
git fetch upstream
git merge upstream/main

# Resolve conflicts (usually: keep your deployments/, accept upstream changes)
git push origin main
```

### Contributing Back

If you implement a useful feature or fix, contribute it back!

```bash
# 1. Make changes in your fork
# 2. Remove client-specific values (replace with {{ .Values.* }})
# 3. Test with example.com config
# 4. Submit pull request to base template
```
