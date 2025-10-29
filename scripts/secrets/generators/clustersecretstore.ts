/**
 * ClusterSecretStore manifest generator
 */

import { writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";
import type { SecretProvider } from "../types";
import { logSuccess } from "@/lib/prompts";

/**
 * Generate ClusterSecretStore manifest file
 */
export function generateClusterSecretStoreFile(
  provider: SecretProvider,
  storeName: string,
  outputPath: string
): void {
  const manifest = provider.generateClusterSecretStore(storeName);

  // Ensure directory exists
  mkdirSync(dirname(outputPath), { recursive: true });

  // Write manifest
  writeFileSync(outputPath, manifest, "utf-8");
  logSuccess(`Generated ClusterSecretStore: ${outputPath}`);
}
