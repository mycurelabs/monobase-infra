# Chart Inventory

## Healthcare Applications

### hapihub
- **Purpose**: HapiHub — Healthcare API service (compliance, interoperability)
- **Runtime**: Bun
- **Database**: MongoDB (replicaset)
- **Key values**: `image.tag`, `replicaCount`, `gateway.hostname`, `gateway.sectionName`, `externalSecrets`, `mongodb`, `autoscaling`, `betterAuth`
- **Templates**: deployment, service, httproute, externalsecret, hpa, pdb, servicemonitor, networkpolicy
- **Dependencies**: MongoDB (bitnami subchart), optional Valkey, optional MinIO, optional Mailpit
- **Reference implementation** — most complete chart with all patterns

### syncd
- **Purpose**: SyncD — Real-time synchronization service (WebSocket)
- **Runtime**: Bun
- **Database**: MongoDB (shared with hapihub)
- **Key values**: `image.tag`, `replicaCount`, `gateway.hostname`, `gateway.sectionName`, `externalSecrets`, `mongodb`, `autoscaling`
- **Templates**: deployment, service, httproute, externalsecret, hpa, pdb

### mycure
- **Purpose**: MyCure — Patient-facing healthcare frontend
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`, `config.HAPIHUB_URL`
- **Templates**: deployment, service, httproute, configmap

### mycurev8
- **Purpose**: MyCure v8 — Legacy patient-facing frontend
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`
- **Templates**: deployment, service, httproute, configmap

### mycurelocal
- **Purpose**: MyCure Local — Local-first patient-facing frontend
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`
- **Templates**: deployment, service, httproute

### mycure-myaccount
- **Purpose**: MyCure MyAccount — Account management portal
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`
- **Templates**: deployment, service, httproute, configmap

### mycure-deploydash
- **Purpose**: MyCure DeployDash — Deployment dashboard
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`
- **Templates**: deployment, service, httproute, configmap

### dentalemon
- **Purpose**: DentaLemon — Dental healthcare application
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`
- **Templates**: deployment, service, httproute, configmap

### dentalemon-myaccount
- **Purpose**: DentaLemon MyAccount — Account management for DentaLemon
- **Runtime**: Vue.js (static serving)
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`
- **Templates**: deployment, service, httproute, configmap

### dentalemon-website
- **Purpose**: DentaLemon Website — Marketing website
- **Runtime**: Static website
- **Key values**: `image.tag`, `gateway.hostname`, `gateway.sectionName`, `config.API_URL`, `config.ACCOUNT_URL`
- **Templates**: deployment, service, httproute, configmap

## Core Services

### api
- **Purpose**: Monobase API — Backend service
- **Runtime**: Hono/Bun
- **Database**: PostgreSQL
- **Key values**: `image.tag`, `replicaCount`, `gateway.hostname`, `externalSecrets`, `postgresql`, `autoscaling`, `backup`
- **Templates**: deployment, service, httproute, externalsecret, hpa, pdb, servicemonitor
- **Dependencies**: PostgreSQL (bitnami subchart), optional Mailpit

### account
- **Purpose**: Monobase Account App — Account management frontend
- **Runtime**: React/Vite
- **Key values**: `image.tag`, `gateway.hostname`, `config.API_URL`
- **Templates**: deployment, service, httproute, configmap

## Infrastructure Charts

### namespace
- **Purpose**: Namespace creation with security and resource quota configuration
- **Key values**: `podSecurityStandards.enabled`, `podSecurityStandards.level`, `resourceQuotas`
- **Templates**: namespace, resourcequota

### gateway
- **Purpose**: Shared Gateway for multi-tenant routing
- **Key values**: `gateway.domain`, `gateway.gateway.listeners`, `gateway.gateway.additionalListeners`, `tls`, `envoyPatchPolicy`, `httpRedirect`
- **Templates**: gateway, gatewayclass, namespace, certificate, additional-certificates, http-redirect, envoy-patch-policy

### envoy-proxy-config
- **Purpose**: Cloud-specific LoadBalancer settings for Envoy Gateway
- **Key values**: `cloudProvider`, `azure.*`, `aws.*`, `gcp.*`, `digitalocean.*`
- **Templates**: envoyproxy (EnvoyProxy CRD with service annotations)

### cert-manager-issuers
- **Purpose**: Multi-provider ClusterIssuer management
- **Key values**: `issuers[]` (name, email, server, provider)
- **Templates**: clusterissuer (HTTP-01 and DNS-01 challenge types)

### database-secrets
- **Purpose**: External Secrets for database credentials
- **Key values**: Database-specific secret mappings
- **Templates**: externalsecret for PostgreSQL, MongoDB, MinIO, Valkey credentials

### external-dns
- **Purpose**: Automatic DNS record management from HTTPRoutes
- **Key values**: Provider config (Cloudflare), source types
- **Templates**: deployment, rbac, serviceaccount

### grafana
- **Purpose**: Grafana with Gateway API integration
- **Key values**: `grafana.admin`, `grafana.persistence`, `gateway.enabled`, `gateway.hostname`
- **Templates**: httproute, wraps bitnami/grafana subchart
- **Dependencies**: Bitnami Grafana subchart

### security-baseline
- **Purpose**: NetworkPolicies and RBAC for zero-trust networking
- **Key values**: NetworkPolicy rules
- **Templates**: networkpolicy (default-deny, allow-gateway, allow-db, allow-storage)

### mailpit
- **Purpose**: Email testing tool (dev/staging environments)
- **Key values**: `gateway.enabled`, `gateway.hostname`
- **Templates**: deployment, service, httproute (web UI + SMTP service)
