/**
 * Cluster validation
 * Validate ExternalSecrets are synced and K8s secrets exist
 */

import { loadKubeConfig } from "@/lib/k8s";
import { logInfo, logSuccess, logError, logWarning } from "@/lib/prompts";

interface ValidationResult {
  name: string;
  namespace: string;
  status: "success" | "error" | "warning";
  message: string;
}

/**
 * Get Custom Objects API client
 */
function getCustomObjectsApi(kubeconfigPath?: string) {
  const k8s = require("@kubernetes/client-node");
  const kc = loadKubeConfig(kubeconfigPath);
  return kc.makeApiClient(k8s.CustomObjectsApi);
}

/**
 * Get Core V1 API client
 */
function getCoreV1Api(kubeconfigPath?: string) {
  const k8s = require("@kubernetes/client-node");
  const kc = loadKubeConfig(kubeconfigPath);
  return kc.makeApiClient(k8s.CoreV1Api);
}

/**
 * Validate ExternalSecret resource
 */
async function validateExternalSecret(
  name: string,
  namespace: string,
  kubeconfigPath?: string
): Promise<ValidationResult> {
  const customApi = getCustomObjectsApi(kubeconfigPath);

  try {
    const response: any = await customApi.getNamespacedCustomObject(
      "external-secrets.io",
      "v1beta1",
      namespace,
      "externalsecrets",
      name
    );

    const status = response.body?.status;
    const conditions = status?.conditions || [];

    // Check if ExternalSecret is ready
    const readyCondition = conditions.find((c: any) => c.type === "Ready");

    if (readyCondition?.status === "True") {
      return {
        name,
        namespace,
        status: "success",
        message: "ExternalSecret is synced",
      };
    } else {
      const message = readyCondition?.message || "ExternalSecret not ready";
      return {
        name,
        namespace,
        status: "error",
        message,
      };
    }
  } catch (error: any) {
    if (error.response?.statusCode === 404) {
      return {
        name,
        namespace,
        status: "error",
        message: "ExternalSecret not found",
      };
    }
    return {
      name,
      namespace,
      status: "error",
      message: `Failed to check: ${error.message}`,
    };
  }
}

/**
 * Validate Kubernetes Secret exists
 */
async function validateKubernetesSecret(
  name: string,
  namespace: string,
  kubeconfigPath?: string
): Promise<ValidationResult> {
  const coreApi = getCoreV1Api(kubeconfigPath);

  try {
    await coreApi.readNamespacedSecret(name, namespace);
    return {
      name,
      namespace,
      status: "success",
      message: "Kubernetes Secret exists",
    };
  } catch (error: any) {
    if (error.response?.statusCode === 404) {
      return {
        name,
        namespace,
        status: "error",
        message: "Kubernetes Secret not found",
      };
    }
    return {
      name,
      namespace,
      status: "error",
      message: `Failed to check: ${error.message}`,
    };
  }
}

/**
 * List all ExternalSecrets in the cluster
 */
async function listAllExternalSecrets(
  kubeconfigPath?: string
): Promise<Array<{ name: string; namespace: string }>> {
  const k8s = require("@kubernetes/client-node");
  const kc = loadKubeConfig(kubeconfigPath);
  const customApi = kc.makeApiClient(k8s.CustomObjectsApi);

  try {
    // List ExternalSecrets across all namespaces (empty string = all namespaces)
    const response = await customApi.listNamespacedCustomObject(
      "external-secrets.io",
      "v1beta1",
      "",  // Empty namespace = all namespaces
      "externalsecrets"
    );

    const items = response.body?.items || [];
    return items.map((item: any) => ({
      name: item.metadata.name,
      namespace: item.metadata.namespace,
    }));
  } catch (error: any) {
    throw new Error(`Failed to list ExternalSecrets: ${error.message}`);
  }
}

/**
 * Validate all ExternalSecrets and their corresponding K8s Secrets
 */
export async function validateCluster(kubeconfigPath?: string): Promise<{
  success: boolean;
  results: ValidationResult[];
}> {
  logInfo("Listing ExternalSecrets...");
  const externalSecrets = await listAllExternalSecrets(kubeconfigPath);

  if (externalSecrets.length === 0) {
    logWarning("No ExternalSecrets found in cluster");
    return { success: true, results: [] };
  }

  logInfo(`Found ${externalSecrets.length} ExternalSecrets`);

  const results: ValidationResult[] = [];

  for (const { name, namespace } of externalSecrets) {
    logInfo(`\n📋 Validating: ${namespace}/${name}`);

    // Check ExternalSecret status
    const externalSecretResult = await validateExternalSecret(name, namespace, kubeconfigPath);
    results.push(externalSecretResult);

    if (externalSecretResult.status === "success") {
      logSuccess(`  ✓ ${externalSecretResult.message}`);
    } else {
      logError(`  ✗ ${externalSecretResult.message}`);
    }

    // Check corresponding K8s Secret
    const secretResult = await validateKubernetesSecret(name, namespace, kubeconfigPath);
    results.push(secretResult);

    if (secretResult.status === "success") {
      logSuccess(`  ✓ ${secretResult.message}`);
    } else {
      logError(`  ✗ ${secretResult.message}`);
    }
  }

  const hasErrors = results.some((r) => r.status === "error");
  return { success: !hasErrors, results };
}
