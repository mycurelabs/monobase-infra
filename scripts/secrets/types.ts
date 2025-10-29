/**
 * Provider-agnostic secret schema types
 */

import { z } from "zod";

/**
 * Secret key schema
 */
export const SecretKeySchema = z.object({
  key: z.string().describe("Key name in Kubernetes secret"),
  remoteKey: z.string().describe("Key/name in provider's secret backend"),
  generate: z.boolean().optional().describe("Auto-generate value if true"),
  prompt: z.string().optional().describe("Custom prompt text for manual input"),
});

export type SecretKey = z.infer<typeof SecretKeySchema>;

/**
 * Secret schema
 */
export const SecretSchema = z.object({
  name: z.string().describe("Kubernetes secret name"),
  remoteRef: z.string().describe("Provider's secret reference (abstract)"),
  targetNamespace: z.string().optional().describe("Target namespace (inferred if not provided)"),
  keys: z.array(SecretKeySchema).min(1).describe("Secret keys to create"),
});

export type Secret = z.infer<typeof SecretSchema>;

/**
 * Secrets configuration schema
 */
export const SecretsConfigSchema = z.object({
  secrets: z.array(SecretSchema).describe("List of secrets to manage"),
});

export type SecretsConfig = z.infer<typeof SecretsConfigSchema>;

/**
 * Provider interface - implementations must map abstract schema to provider-specific resources
 */
export interface SecretProvider {
  /** Provider name (e.g., "gcp", "aws", "azure") */
  readonly name: string;

  /** Provider project/account ID */
  readonly projectId: string;

  /**
   * Initialize provider (authenticate, enable APIs, etc.)
   */
  initialize(): Promise<void>;

  /**
   * Check if a secret exists in the provider's backend
   */
  secretExists(remoteKey: string): Promise<boolean>;

  /**
   * Create a secret in the provider's backend
   */
  createSecret(remoteKey: string, value: string): Promise<void>;

  /**
   * Create service account and credentials for ESO
   */
  createServiceAccount(): Promise<string>;

  /**
   * Generate provider-specific ClusterSecretStore manifest
   */
  generateClusterSecretStore(name: string): string;

  /**
   * Generate provider-specific ExternalSecret manifest
   */
  generateExternalSecret(secret: Secret, namespace: string): string;
}

/**
 * Parsed secrets file with metadata
 */
export interface ParsedSecretsFile {
  filePath: string;
  deploymentName: string;
  defaultNamespace?: string;
  config: SecretsConfig;
}

/**
 * Secret value source (generated or prompted)
 */
export type SecretValueSource =
  | { type: "generate"; value: string }
  | { type: "prompt"; value: string }
  | { type: "existing" };
