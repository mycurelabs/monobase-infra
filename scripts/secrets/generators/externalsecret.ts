/**
 * ExternalSecret manifest generator
 */

import { writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";
import type { SecretProvider, Secret } from "../types";
import { logSuccess } from "@/lib/prompts";

/**
 * Generate ExternalSecret manifest file
 */
export function generateExternalSecretFile(
  provider: SecretProvider,
  secret: Secret,
  namespace: string,
  outputPath: string
): void {
  const manifest = provider.generateExternalSecret(secret, namespace);

  // Ensure directory exists
  mkdirSync(dirname(outputPath), { recursive: true });

  // Write manifest
  writeFileSync(outputPath, manifest, "utf-8");
  logSuccess(`Generated ExternalSecret: ${outputPath}`);
}

/**
 * Generate multiple ExternalSecret manifests
 */
export function generateExternalSecretFiles(
  provider: SecretProvider,
  secrets: Array<{ secret: Secret; namespace: string; outputPath: string }>
): void {
  for (const { secret, namespace, outputPath } of secrets) {
    generateExternalSecretFile(provider, secret, namespace, outputPath);
  }
}
