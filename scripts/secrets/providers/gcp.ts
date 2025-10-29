/**
 * GCP Secret Manager provider implementation
 * Maps provider-agnostic schema to GCP-specific ESO resources
 */

import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import type { SecretProvider, Secret } from "../types";
import { logInfo, logSuccess, logWarning } from "@/lib/prompts";

export class GCPProvider implements SecretProvider {
  readonly name = "gcp";
  readonly projectId: string;
  private client: SecretManagerServiceClient;

  constructor(projectId: string) {
    this.projectId = projectId;
    this.client = new SecretManagerServiceClient();
  }

  /**
   * Initialize GCP provider (check authentication, enable APIs)
   */
  async initialize(): Promise<void> {
    logInfo(`Initializing GCP provider for project: ${this.projectId}`);

    // Test authentication by listing secrets (limit 1)
    try {
      const parent = `projects/${this.projectId}`;
      const [secrets] = await this.client.listSecrets({
        parent,
        pageSize: 1,
      });
      logSuccess("GCP authentication successful");
    } catch (error: any) {
      if (error.code === 7) {
        // PERMISSION_DENIED
        throw new Error(
          `Permission denied accessing project ${this.projectId}. ` +
            `Make sure you're authenticated (gcloud auth application-default login) ` +
            `and have Secret Manager API enabled.`
        );
      }
      throw error;
    }
  }

  /**
   * Check if secret exists in GCP Secret Manager
   */
  async secretExists(remoteKey: string): Promise<boolean> {
    try {
      const name = `projects/${this.projectId}/secrets/${remoteKey}`;
      await this.client.getSecret({ name });
      return true;
    } catch (error: any) {
      if (error.code === 5) {
        // NOT_FOUND
        return false;
      }
      throw error;
    }
  }

  /**
   * Create secret in GCP Secret Manager
   */
  async createSecret(remoteKey: string, value: string): Promise<void> {
    const parent = `projects/${this.projectId}`;
    const secretId = remoteKey;

    // Check if secret already exists
    const exists = await this.secretExists(remoteKey);

    if (exists) {
      // Add new version to existing secret
      const secretName = `${parent}/secrets/${secretId}`;
      await this.client.addSecretVersion({
        parent: secretName,
        payload: {
          data: Buffer.from(value, "utf8"),
        },
      });
      logInfo(`Updated secret: ${remoteKey}`);
    } else {
      // Create new secret
      const [secret] = await this.client.createSecret({
        parent,
        secretId,
        secret: {
          replication: {
            automatic: {},
          },
        },
      });

      // Add first version
      await this.client.addSecretVersion({
        parent: secret.name!,
        payload: {
          data: Buffer.from(value, "utf8"),
        },
      });
      logSuccess(`Created secret: ${remoteKey}`);
    }
  }

  /**
   * Create GCP service account for External Secrets Operator
   */
  async createServiceAccount(): Promise<string> {
    // This would require @google-cloud/iam, which we'll implement if needed
    // For now, return instructions for manual creation
    logWarning(
      "Service account creation not yet implemented. " +
        "Please create manually using: " +
        "gcloud iam service-accounts create external-secrets " +
        "--project=" +
        this.projectId
    );
    return "";
  }

  /**
   * Generate GCP-specific ClusterSecretStore manifest
   */
  generateClusterSecretStore(name: string): string {
    return `apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: ${name}
spec:
  provider:
    gcpsm:
      projectID: ${this.projectId}
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcpsm-secret
            key: secret-access-credentials
            namespace: external-secrets-system
`;
  }

  /**
   * Generate GCP-specific ExternalSecret manifest
   * Maps abstract schema to GCP Secret Manager references
   */
  generateExternalSecret(secret: Secret, namespace: string): string {
    const dataEntries = secret.keys
      .map(
        (k) => `  - secretKey: ${k.key}
    remoteRef:
      key: ${k.remoteKey}`
      )
      .join("\n");

    return `apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${secret.name}
  namespace: ${namespace}
spec:
  secretStoreRef:
    name: gcp-secretstore
    kind: ClusterSecretStore
  target:
    name: ${secret.name}
    creationPolicy: Owner
  refreshInterval: 1h
  data:
${dataEntries}
`;
  }
}
