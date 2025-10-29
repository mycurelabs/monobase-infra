/**
 * Kubernetes infrastructure setup
 * Namespace creation, gcpsm-secret creation
 */

import { readFileSync } from "fs";
import { loadKubeConfig } from "@/lib/k8s";
import { logInfo, logSuccess, logWarning } from "@/lib/prompts";
import type { CoreV1Api, V1Secret, V1Namespace } from "@kubernetes/client-node";

const EXTERNAL_SECRETS_NAMESPACE = "external-secrets-system";
const GCPSM_SECRET_NAME = "gcpsm-secret";

/**
 * Get Kubernetes Core API client
 */
function getCoreV1Api(kubeconfigPath?: string): CoreV1Api {
  const k8s = require("@kubernetes/client-node");
  const kc = loadKubeConfig(kubeconfigPath);
  return kc.makeApiClient(k8s.CoreV1Api);
}

/**
 * Check if namespace exists
 */
export async function namespaceExists(
  namespace: string,
  kubeconfigPath?: string
): Promise<boolean> {
  const api = getCoreV1Api(kubeconfigPath);

  try {
    await api.readNamespace(namespace);
    return true;
  } catch (error: any) {
    if (error.response?.statusCode === 404) {
      return false;
    }
    throw error;
  }
}

/**
 * Create namespace
 */
export async function createNamespace(
  namespace: string,
  kubeconfigPath?: string
): Promise<void> {
  if (await namespaceExists(namespace, kubeconfigPath)) {
    logSuccess(`Namespace already exists: ${namespace}`);
    return;
  }

  logInfo(`Creating namespace: ${namespace}`);
  const api = getCoreV1Api(kubeconfigPath);

  const namespaceManifest: V1Namespace = {
    metadata: {
      name: namespace,
    },
  };

  try {
    await api.createNamespace(namespaceManifest);
    logSuccess(`Created namespace: ${namespace}`);
  } catch (error: any) {
    throw new Error(`Failed to create namespace ${namespace}: ${error.message}`);
  }
}

/**
 * Check if secret exists
 */
export async function secretExists(
  name: string,
  namespace: string,
  kubeconfigPath?: string
): Promise<boolean> {
  const api = getCoreV1Api(kubeconfigPath);

  try {
    await api.readNamespacedSecret(name, namespace);
    return true;
  } catch (error: any) {
    if (error.response?.statusCode === 404) {
      return false;
    }
    throw error;
  }
}

/**
 * Create gcpsm-secret from service account key file
 */
export async function createGCPSMSecret(
  keyFilePath: string,
  kubeconfigPath?: string
): Promise<void> {
  if (await secretExists(GCPSM_SECRET_NAME, EXTERNAL_SECRETS_NAMESPACE, kubeconfigPath)) {
    logSuccess(`Secret already exists: ${GCPSM_SECRET_NAME}`);
    return;
  }

  logInfo(`Creating secret: ${GCPSM_SECRET_NAME}`);

  // Read service account key file
  let keyContent: string;
  try {
    keyContent = readFileSync(keyFilePath, "utf-8");
  } catch (error: any) {
    throw new Error(`Failed to read key file ${keyFilePath}: ${error.message}`);
  }

  const api = getCoreV1Api(kubeconfigPath);

  const secretManifest: V1Secret = {
    metadata: {
      name: GCPSM_SECRET_NAME,
      namespace: EXTERNAL_SECRETS_NAMESPACE,
    },
    type: "Opaque",
    stringData: {
      "secret-access-credentials": keyContent,
    },
  };

  try {
    await api.createNamespacedSecret(EXTERNAL_SECRETS_NAMESPACE, secretManifest);
    logSuccess(`Created secret: ${GCPSM_SECRET_NAME}`);
  } catch (error: any) {
    throw new Error(`Failed to create secret ${GCPSM_SECRET_NAME}: ${error.message}`);
  }
}

/**
 * Complete Kubernetes setup workflow
 */
export async function setupKubernetesInfrastructure(
  keyFilePath: string,
  kubeconfigPath?: string
): Promise<void> {
  // Create external-secrets-system namespace
  await createNamespace(EXTERNAL_SECRETS_NAMESPACE, kubeconfigPath);

  // Create gcpsm-secret
  await createGCPSMSecret(keyFilePath, kubeconfigPath);
}
