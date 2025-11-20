/**
 * Shared utility functions for all scripts
 */

import { randomBytes } from "crypto";
import { resolve, basename, dirname } from "path";

/**
 * Generate a secure random password
 */
export function generatePassword(length: number = 32): string {
  return randomBytes(length).toString("base64").slice(0, length);
}

/**
 * Generate a secure random key (hex format)
 */
export function generateKey(length: number = 32): string {
  return randomBytes(length).toString("hex");
}

/**
 * Infer deployment name from file path
 * Examples:
 *   /path/to/deployments/example-staging/secrets.yaml → example-staging
 *   /path/to/infrastructure/secrets.yaml → infrastructure
 */
export function inferDeploymentName(filePath: string): string {
  const normalized = resolve(filePath);
  const dir = dirname(normalized);
  const parentDir = basename(dirname(dir));

  // If parent directory is "deployments", use the directory name
  if (parentDir === "deployments") {
    return basename(dir);
  }

  // If directory is "infrastructure", return "infrastructure"
  if (basename(dir) === "infrastructure") {
    return "infrastructure";
  }

  // Fallback to directory name
  return basename(dir);
}

/**
 * Infer target namespace from deployment name
 * infrastructure → undefined (cross-namespace)
 * example-staging → example-staging
 */
export function inferNamespace(deploymentName: string): string | undefined {
  if (deploymentName === "infrastructure") {
    return undefined;
  }
  return deploymentName;
}

/**
 * Format bytes to human-readable size
 */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
}

/**
 * Sleep for specified milliseconds
 */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
