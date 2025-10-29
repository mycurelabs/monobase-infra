/**
 * GCP infrastructure setup
 * Service account creation, IAM permissions, key generation
 */

import { execSync } from "child_process";
import { existsSync, mkdirSync, writeFileSync, chmodSync } from "fs";
import { join, dirname } from "path";
import { homedir } from "os";
import { logInfo, logSuccess, logWarning, logError, clack } from "@/lib/prompts";
import { sleep } from "@/lib/utils";

const SERVICE_ACCOUNT_NAME = "external-secrets";
const IAM_ROLE = "roles/secretmanager.secretAccessor";

/**
 * Check if gcloud CLI is available
 */
export function checkGcloudInstalled(): boolean {
  try {
    execSync("gcloud --version", { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/**
 * Enable Secret Manager API
 */
export async function enableSecretManagerAPI(projectId: string): Promise<void> {
  logInfo("Checking Secret Manager API...");

  try {
    // Check if API is already enabled
    const result = execSync(
      `gcloud services list --project=${projectId} --filter="name:secretmanager.googleapis.com" --format="value(name)"`,
      { encoding: "utf-8" }
    );

    if (result.trim()) {
      logSuccess("Secret Manager API already enabled");
      return;
    }

    // Enable API
    const spinner = clack.spinner();
    spinner.start("Enabling Secret Manager API");
    execSync(`gcloud services enable secretmanager.googleapis.com --project=${projectId}`, {
      stdio: "ignore",
    });
    spinner.stop("Secret Manager API enabled");
  } catch (error: any) {
    throw new Error(`Failed to enable Secret Manager API: ${error.message}`);
  }
}

/**
 * Get service account email
 */
export function getServiceAccountEmail(projectId: string): string {
  return `${SERVICE_ACCOUNT_NAME}@${projectId}.iam.gserviceaccount.com`;
}

/**
 * Check if service account exists
 */
export function serviceAccountExists(projectId: string): boolean {
  const email = getServiceAccountEmail(projectId);

  try {
    execSync(`gcloud iam service-accounts describe ${email} --project=${projectId}`, {
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Create GCP service account for External Secrets Operator
 */
export async function createServiceAccount(projectId: string): Promise<string> {
  const email = getServiceAccountEmail(projectId);

  if (serviceAccountExists(projectId)) {
    logSuccess(`Service account already exists: ${SERVICE_ACCOUNT_NAME}`);
    return email;
  }

  logInfo(`Creating service account: ${SERVICE_ACCOUNT_NAME}`);

  try {
    execSync(
      `gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} ` +
        `--display-name="External Secrets Operator" ` +
        `--project=${projectId}`,
      { stdio: "ignore" }
    );

    logSuccess(`Created service account: ${SERVICE_ACCOUNT_NAME}`);

    // Wait for propagation
    logInfo("Waiting for service account propagation...");
    await sleep(5000);

    return email;
  } catch (error: any) {
    throw new Error(`Failed to create service account: ${error.message}`);
  }
}

/**
 * Grant IAM permissions with retry logic
 */
export async function grantIAMPermissions(
  projectId: string,
  serviceAccountEmail: string
): Promise<void> {
  logInfo(`Granting ${IAM_ROLE} permissions...`);

  const maxRetries = 5;
  let retryCount = 0;
  let retryDelay = 2000; // Start with 2 seconds

  while (retryCount < maxRetries) {
    try {
      execSync(
        `gcloud projects add-iam-policy-binding ${projectId} ` +
          `--member="serviceAccount:${serviceAccountEmail}" ` +
          `--role="${IAM_ROLE}" ` +
          `--condition=None`,
        { stdio: "ignore" }
      );

      logSuccess(`Granted ${IAM_ROLE} role`);
      return;
    } catch (error: any) {
      retryCount++;

      if (retryCount >= maxRetries) {
        throw new Error(
          `Failed to grant IAM permissions after ${maxRetries} retries: ${error.message}`
        );
      }

      logWarning(`Retry ${retryCount}/${maxRetries} after ${retryDelay}ms`);
      await sleep(retryDelay);
      retryDelay *= 2; // Exponential backoff
    }
  }
}

/**
 * Get service account key file path
 */
export function getKeyFilePath(projectId: string): string {
  return join(homedir(), ".gcp", `external-secrets-${projectId}.json`);
}

/**
 * Check if service account key file exists
 */
export function keyFileExists(projectId: string): boolean {
  return existsSync(getKeyFilePath(projectId));
}

/**
 * Create service account key
 */
export async function createServiceAccountKey(
  projectId: string,
  serviceAccountEmail: string
): Promise<string> {
  const keyFilePath = getKeyFilePath(projectId);

  if (keyFileExists(projectId)) {
    logSuccess(`Service account key already exists: ${keyFilePath}`);
    return keyFilePath;
  }

  logInfo("Creating service account key...");

  try {
    // Ensure directory exists
    const keyDir = dirname(keyFilePath);
    if (!existsSync(keyDir)) {
      mkdirSync(keyDir, { recursive: true });
    }

    // Create key
    execSync(
      `gcloud iam service-accounts keys create ${keyFilePath} ` +
        `--iam-account=${serviceAccountEmail} ` +
        `--project=${projectId}`,
      { stdio: "ignore" }
    );

    // Set proper permissions (600)
    chmodSync(keyFilePath, 0o600);

    logSuccess(`Created service account key: ${keyFilePath}`);
    return keyFilePath;
  } catch (error: any) {
    throw new Error(`Failed to create service account key: ${error.message}`);
  }
}

/**
 * Complete GCP setup workflow
 */
export async function setupGCPInfrastructure(projectId: string): Promise<{
  serviceAccountEmail: string;
  keyFilePath: string;
}> {
  // Check gcloud CLI
  if (!checkGcloudInstalled()) {
    throw new Error(
      "gcloud CLI not found. Please install: https://cloud.google.com/sdk/docs/install"
    );
  }

  // Enable API
  await enableSecretManagerAPI(projectId);

  // Create service account
  const serviceAccountEmail = await createServiceAccount(projectId);

  // Grant IAM permissions
  await grantIAMPermissions(projectId, serviceAccountEmail);

  // Create key
  const keyFilePath = await createServiceAccountKey(projectId, serviceAccountEmail);

  return { serviceAccountEmail, keyFilePath };
}
