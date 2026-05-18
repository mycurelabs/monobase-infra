// Input Validation Functions

import { $ } from 'bun';
import { logWarning, logInfo } from '@/lib/prompts';
import type { Provider } from './providers';

/**
 * Validate cluster name format
 */
export function validateClusterName(val: string): string | void {
  if (!val || val.length < 3) {
    return 'Cluster name must be at least 3 characters';
  }
  if (val.length > 40) {
    return 'Cluster name must be less than 40 characters';
  }
  if (!/^[a-z0-9-]+$/.test(val)) {
    return 'Use lowercase letters, numbers, and hyphens only';
  }
  if (val.startsWith('-') || val.endsWith('-')) {
    return 'Cannot start or end with hyphen';
  }
  if (val.includes('--')) {
    return 'Cannot contain consecutive hyphens';
  }
}

/**
 * Validate GCP project ID format
 */
export function validateGcpProjectId(val: string): string | void {
  if (!val || val.length < 6) {
    return 'Project ID must be at least 6 characters';
  }
  if (val.length > 30) {
    return 'Project ID must be less than 30 characters';
  }
  if (!/^[a-z][a-z0-9-]*[a-z0-9]$/.test(val)) {
    return 'Project ID must start with a letter, contain only lowercase letters, numbers, and hyphens';
  }
}

/**
 * Check if AWS credentials are configured
 */
export async function checkAwsCredentials(): Promise<boolean> {
  const hasKeys =
    process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY;
  const hasProfile = process.env.AWS_PROFILE;

  if (!hasKeys && !hasProfile) {
    logWarning('AWS credentials not detected');
    logInfo('Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY');
    logInfo('Or configure AWS_PROFILE via: aws configure');
    return false;
  }

  return true;
}

/**
 * Check if DigitalOcean token is configured
 */
export async function checkDoToken(): Promise<boolean> {
  if (!process.env.DIGITALOCEAN_TOKEN && !process.env.DIGITALOCEAN_ACCESS_TOKEN) {
    logWarning('DigitalOcean token not detected');
    logInfo('Set DIGITALOCEAN_TOKEN environment variable');
    logInfo('Get token: https://cloud.digitalocean.com/account/api/tokens');
    return false;
  }

  return true;
}

/**
 * Check if GCP credentials are configured
 */
export async function checkGcpCredentials(): Promise<boolean> {
  try {
    // Check if gcloud is available and authenticated
    await $`gcloud auth application-default print-access-token`.quiet();
    return true;
  } catch {
    logWarning('GCP credentials not detected');
    logInfo('Run: gcloud auth application-default login');
    logInfo('Or set GOOGLE_APPLICATION_CREDENTIALS');
    return false;
  }
}

/**
 * Check if Docker is running (for k3d)
 */
export async function checkDocker(): Promise<boolean> {
  try {
    await $`docker version`.quiet();
    return true;
  } catch {
    logWarning('Docker not found or not running');
    logInfo('k3d requires Docker to be installed and running');
    return false;
  }
}

/**
 * Check if k3d is installed
 */
export async function checkK3d(): Promise<boolean> {
  try {
    await $`k3d version`.quiet();
    return true;
  } catch {
    logWarning('k3d not found');
    logInfo('Install k3d: brew install k3d (macOS)');
    logInfo('Or: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash');
    return false;
  }
}

/**
 * Check provider prerequisites
 */
export async function checkProviderPrerequisites(provider: Provider): Promise<boolean> {
  switch (provider) {
    case 'aws-eks':
      return await checkAwsCredentials();
    case 'do-doks':
      return await checkDoToken();
    case 'gcp-gke':
      return await checkGcpCredentials();
    case 'k3d':
      const hasDocker = await checkDocker();
      const hasK3d = await checkK3d();
      return hasDocker && hasK3d;
    default:
      return true;
  }
}

/**
 * GCP Project information from gcloud
 */
export interface GcloudProject {
  projectId: string;
  name: string;
  projectNumber?: string;
}

/**
 * Get list of GCP projects from gcloud
 */
export async function getGcloudProjects(): Promise<GcloudProject[]> {
  try {
    const output = await $`gcloud projects list --format=json`.text();
    const projects = JSON.parse(output);

    return projects.map((p: any) => ({
      projectId: p.projectId,
      name: p.name || p.projectId,
      projectNumber: p.projectNumber,
    }));
  } catch (error) {
    throw new Error('Failed to fetch GCP projects. Ensure gcloud is installed and authenticated.');
  }
}

/**
 * Get current active GCP project from gcloud config
 */
export async function getCurrentGcloudProject(): Promise<string | null> {
  try {
    const output = await $`gcloud config get-value project`.text();
    const project = output.trim();
    return project === '(unset)' || !project ? null : project;
  } catch {
    return null;
  }
}

/**
 * Check if gcloud CLI is available
 */
export async function isGcloudAvailable(): Promise<boolean> {
  try {
    await $`gcloud version`.quiet();
    return true;
  } catch {
    return false;
  }
}
