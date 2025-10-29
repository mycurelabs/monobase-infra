/**
 * TLS infrastructure setup
 * ClusterIssuer configuration for Let's Encrypt with Cloudflare DNS
 */

import { logInfo, logSuccess, logWarning, clack } from "@/lib/prompts";
import type { SecretProvider } from "./types";

export interface TLSConfig {
  email: string;
  cloudflareApiTokenSecretName: string;
  cloudflareApiTokenSecretKey: string;
}

/**
 * Prompt for TLS configuration
 */
export async function promptTLSConfig(): Promise<TLSConfig | null> {
  const configureTLS = await clack.confirm({
    message: "Configure TLS (Let's Encrypt with Cloudflare DNS)?",
    initialValue: true,
  });

  if (!configureTLS) {
    logWarning("Skipping TLS configuration");
    return null;
  }

  const email = await clack.text({
    message: "Email for Let's Encrypt notifications:",
    placeholder: "admin@example.com",
    validate: (value) => {
      if (!value) return "Email is required";
      if (!value.includes("@")) return "Invalid email format";
      return undefined;
    },
  });

  const cloudflareApiTokenSecretName = await clack.text({
    message: "Cloudflare API token secret name:",
    placeholder: "mycure-cloudflare-api-token",
    initialValue: "mycure-cloudflare-api-token",
    validate: (value) => (value ? undefined : "Secret name is required"),
  });

  const cloudflareApiTokenSecretKey = await clack.text({
    message: "Cloudflare API token secret key:",
    placeholder: "api-token",
    initialValue: "api-token",
    validate: (value) => (value ? undefined : "Secret key is required"),
  });

  return {
    email: email as string,
    cloudflareApiTokenSecretName: cloudflareApiTokenSecretName as string,
    cloudflareApiTokenSecretKey: cloudflareApiTokenSecretKey as string,
  };
}

/**
 * Generate ClusterIssuer manifest for Let's Encrypt staging
 */
export function generateStagingClusterIssuer(config: TLSConfig): string {
  return `apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: ${config.email}
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: ${config.cloudflareApiTokenSecretName}
              key: ${config.cloudflareApiTokenSecretKey}
`;
}

/**
 * Generate ClusterIssuer manifest for Let's Encrypt production
 */
export function generateProductionClusterIssuer(config: TLSConfig): string {
  return `apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${config.email}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: ${config.cloudflareApiTokenSecretName}
              key: ${config.cloudflareApiTokenSecretKey}
`;
}

/**
 * Generate both ClusterIssuer manifests
 */
export function generateClusterIssuers(config: TLSConfig): {
  staging: string;
  production: string;
} {
  return {
    staging: generateStagingClusterIssuer(config),
    production: generateProductionClusterIssuer(config),
  };
}

/**
 * Complete TLS setup workflow
 */
export async function setupTLSInfrastructure(
  outputDir: string = "infrastructure/cert-manager"
): Promise<void> {
  const config = await promptTLSConfig();

  if (!config) {
    return; // User skipped TLS configuration
  }

  const { mkdirSync, writeFileSync } = await import("fs");
  const { join } = await import("path");

  // Ensure output directory exists
  mkdirSync(outputDir, { recursive: true });

  const manifests = generateClusterIssuers(config);

  // Write staging issuer
  const stagingPath = join(outputDir, "letsencrypt-staging-clusterissuer.yaml");
  writeFileSync(stagingPath, manifests.staging, "utf-8");
  logSuccess(`Generated: ${stagingPath}`);

  // Write production issuer
  const productionPath = join(outputDir, "letsencrypt-prod-clusterissuer.yaml");
  writeFileSync(productionPath, manifests.production, "utf-8");
  logSuccess(`Generated: ${productionPath}`);

  logInfo("⚠️  Note: ClusterIssuers will be created when cert-manager is deployed");
}
