/**
 * Kubernetes client utilities (shared across all scripts)
 */

import * as k8s from "@kubernetes/client-node";
import { homedir } from "os";
import { join } from "path";
import { existsSync } from "fs";

/**
 * Load kubeconfig from specified path or default locations
 */
export function loadKubeConfig(kubeconfigPath?: string): k8s.KubeConfig {
  const kc = new k8s.KubeConfig();

  if (kubeconfigPath) {
    // Load from specified path
    kc.loadFromFile(kubeconfigPath);
  } else {
    // Try default locations
    kc.loadFromDefault();
  }

  return kc;
}

/**
 * Get current context name
 */
export function getCurrentContext(kc: k8s.KubeConfig): string {
  return kc.getCurrentContext();
}

/**
 * Get all context names
 */
export function getContexts(kc: k8s.KubeConfig): string[] {
  return kc.getContexts().map((ctx) => ctx.name);
}

/**
 * Switch to a different context
 */
export function setCurrentContext(kc: k8s.KubeConfig, contextName: string): void {
  kc.setCurrentContext(contextName);
}

/**
 * Create a Core V1 API client
 */
export function createCoreV1Client(kc: k8s.KubeConfig): k8s.CoreV1Api {
  return kc.makeApiClient(k8s.CoreV1Api);
}

/**
 * Check if namespace exists
 */
export async function namespaceExists(
  client: k8s.CoreV1Api,
  namespace: string
): Promise<boolean> {
  try {
    await client.readNamespace(namespace);
    return true;
  } catch (error: any) {
    if (error.statusCode === 404) {
      return false;
    }
    throw error;
  }
}

/**
 * Create namespace if it doesn't exist
 */
export async function ensureNamespace(
  client: k8s.CoreV1Api,
  namespace: string
): Promise<void> {
  const exists = await namespaceExists(client, namespace);
  if (!exists) {
    await client.createNamespace({
      metadata: {
        name: namespace,
      },
    });
  }
}

/**
 * Check if secret exists
 */
export async function secretExists(
  client: k8s.CoreV1Api,
  name: string,
  namespace: string
): Promise<boolean> {
  try {
    await client.readNamespacedSecret(name, namespace);
    return true;
  } catch (error: any) {
    if (error.statusCode === 404) {
      return false;
    }
    throw error;
  }
}

/**
 * Create or update a secret
 */
export async function createOrUpdateSecret(
  client: k8s.CoreV1Api,
  name: string,
  namespace: string,
  data: Record<string, string>,
  type: string = "Opaque"
): Promise<void> {
  // Ensure namespace exists
  await ensureNamespace(client, namespace);

  const secret: k8s.V1Secret = {
    metadata: {
      name,
      namespace,
    },
    type,
    data: {},
  };

  // Base64 encode all values
  for (const [key, value] of Object.entries(data)) {
    secret.data![key] = Buffer.from(value).toString("base64");
  }

  const exists = await secretExists(client, name, namespace);

  if (exists) {
    await client.replaceNamespacedSecret(name, namespace, secret);
  } else {
    await client.createNamespacedSecret(namespace, secret);
  }
}

/**
 * Delete a secret
 */
export async function deleteSecret(
  client: k8s.CoreV1Api,
  name: string,
  namespace: string
): Promise<void> {
  try {
    await client.deleteNamespacedSecret(name, namespace);
  } catch (error: any) {
    if (error.statusCode !== 404) {
      throw error;
    }
  }
}

/**
 * Get default kubeconfig path
 */
export function getDefaultKubeconfigPath(): string {
  return process.env.KUBECONFIG || join(homedir(), ".kube", "config");
}

/**
 * Find all kubeconfig files in ~/.kube/
 */
export function findKubeconfigFiles(): string[] {
  const kubeDir = join(homedir(), ".kube");
  if (!existsSync(kubeDir)) {
    return [];
  }

  const files: string[] = [];
  const entries = Bun.file(kubeDir).text();

  // For now, just return common patterns
  const commonFiles = ["config", "cluster-main", "k3d-main"];

  for (const file of commonFiles) {
    const filePath = join(kubeDir, file);
    if (existsSync(filePath)) {
      files.push(filePath);
    }
  }

  return files;
}
