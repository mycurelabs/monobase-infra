# PhilCare Production Deployment

This directory serves as a registration marker for ArgoCD ApplicationSet auto-discovery.

The ApplicationSet scans `deployments/*` directories to determine which applications to create.
Actual configuration values are in: `values/deployments/philcare-production.yaml`

## Deployment Pattern

```
deployments/philcare-production/  ← Directory presence triggers ApplicationSet
values/deployments/philcare-production.yaml  ← Actual configuration values
```

This separation allows values to be centrally managed while deployments are auto-discovered.
