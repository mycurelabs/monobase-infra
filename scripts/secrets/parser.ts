/**
 * Parse and validate secrets.yaml files
 */

import { parseYamlFile } from "@/lib/yaml";
import { inferDeploymentName, inferNamespace } from "@/lib/utils";
import { SecretsConfigSchema, type ParsedSecretsFile, type SecretsConfig } from "./types";

/**
 * Parse a secrets.yaml file
 */
export function parseSecretsFile(filePath: string): ParsedSecretsFile {
  // Parse YAML
  const raw = parseYamlFile(filePath);

  // Validate against schema
  const config = SecretsConfigSchema.parse(raw) as SecretsConfig;

  // Infer metadata from file path
  const deploymentName = inferDeploymentName(filePath);
  const defaultNamespace = inferNamespace(deploymentName);

  return {
    filePath,
    deploymentName,
    defaultNamespace,
    config,
  };
}

/**
 * Parse multiple secrets.yaml files
 */
export function parseSecretsFiles(filePaths: string[]): ParsedSecretsFile[] {
  return filePaths.map((filePath) => parseSecretsFile(filePath));
}

/**
 * Resolve target namespace for a secret
 * Priority: secret.targetNamespace > file.defaultNamespace > "default"
 */
export function resolveTargetNamespace(
  secret: { targetNamespace?: string },
  fileDefaultNamespace?: string
): string {
  return secret.targetNamespace || fileDefaultNamespace || "default";
}
