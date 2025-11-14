# PhilCare Staging Deployment

This directory serves as a registration marker for ArgoCD ApplicationSet auto-discovery.

The ApplicationSet scans `deployments/*` directories to determine which applications to create.
Actual configuration values are in: `values/deployments/philcare-staging.yaml`

## Deployment Pattern

```
deployments/philcare-staging/  ← Directory presence triggers ApplicationSet
values/deployments/philcare-staging.yaml  ← Actual configuration values
```

This separation allows values to be centrally managed while deployments are auto-discovered.
