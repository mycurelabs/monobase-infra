/**
 * GCP Secret Manager provider (placeholder)
 * Full implementation will be added in next phase
 */

import type { SecretProvider, Secret } from "../types";

export class GCPProvider implements SecretProvider {
  readonly name = "gcp";
  readonly projectId: string;

  constructor(projectId: string) {
    this.projectId = projectId;
  }

  async initialize(): Promise<void> {
    throw new Error("Not implemented yet");
  }

  async secretExists(remoteKey: string): Promise<boolean> {
    throw new Error("Not implemented yet");
  }

  async createSecret(remoteKey: string, value: string): Promise<void> {
    throw new Error("Not implemented yet");
  }

  async createServiceAccount(): Promise<string> {
    throw new Error("Not implemented yet");
  }

  generateClusterSecretStore(name: string): string {
    throw new Error("Not implemented yet");
  }

  generateExternalSecret(secret: Secret, namespace: string): string {
    throw new Error("Not implemented yet");
  }
}
