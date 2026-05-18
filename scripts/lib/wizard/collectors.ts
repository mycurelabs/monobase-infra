// Configuration Collection Functions

import { select, text } from '@clack/prompts';
import {
  AWS_REGIONS,
  DO_REGIONS,
  GCP_REGIONS,
  DEPLOYMENT_PROFILES,
  type Provider,
} from './providers';
import {
  validateClusterName,
  validateGcpProjectId,
  getGcloudProjects,
  getCurrentGcloudProject,
  isGcloudAvailable,
  type GcloudProject,
} from './validators';
import { logWarning, logInfo } from '@/lib/prompts';
import type { WizardFlags } from './index';

// Configuration interfaces
export interface AwsConfig {
  clusterName: string;
  region: string;
  deploymentProfile: string;
}

export interface DoConfig {
  clusterName: string;
  region: string;
  deploymentProfile: string;
  haControlPlane: boolean;
}

export interface GcpConfig {
  clusterName: string;
  projectId: string;
  region: string;
}

export interface K3dConfig {
  clusterName: string;
  agents: number;
}

export type ProviderConfig = AwsConfig | DoConfig | GcpConfig | K3dConfig;

/**
 * Collect AWS EKS configuration
 */
export async function collectAwsConfig(flags: WizardFlags = {}): Promise<AwsConfig> {
  let clusterName: string;

  // Use flag or prompt for cluster name
  if (flags.clusterName) {
    logInfo(`Using cluster name: ${flags.clusterName}`);
    clusterName = flags.clusterName;
  } else {
    const result = await text({
      message: 'Cluster name',
      placeholder: 'monobase-main',
      initialValue: 'monobase-main',
      validate: validateClusterName,
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    clusterName = result as string;
  }

  let region: string;

  // Use flag or prompt for region
  if (flags.region) {
    logInfo(`Using region: ${flags.region}`);
    region = flags.region;
  } else {
    const result = await select({
      message: 'AWS region',
      options: AWS_REGIONS.map((r) => ({ value: r.value, label: r.label })),
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    region = result as string;
  }

  let deploymentProfile: string;

  // Use flag or prompt for deployment profile
  if (flags.deploymentProfile) {
    logInfo(`Using deployment profile: ${flags.deploymentProfile}`);
    deploymentProfile = flags.deploymentProfile;
  } else {
    const result = await select({
      message: 'Deployment size',
      options: DEPLOYMENT_PROFILES.map((p) => ({
        value: p.value,
        label: p.label,
        hint: p.hint,
      })),
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    deploymentProfile = result as string;
  }

  return {
    clusterName,
    region,
    deploymentProfile,
  };
}

/**
 * Collect DigitalOcean DOKS configuration
 */
export async function collectDoConfig(flags: WizardFlags = {}): Promise<DoConfig> {
  let clusterName: string;

  // Use flag or prompt for cluster name
  if (flags.clusterName) {
    logInfo(`Using cluster name: ${flags.clusterName}`);
    clusterName = flags.clusterName;
  } else {
    const result = await text({
      message: 'Cluster name',
      placeholder: 'monobase-main',
      initialValue: 'monobase-main',
      validate: validateClusterName,
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    clusterName = result as string;
  }

  let region: string;

  // Use flag or prompt for region
  if (flags.region) {
    logInfo(`Using region: ${flags.region}`);
    region = flags.region;
  } else {
    const result = await select({
      message: 'DigitalOcean region',
      options: DO_REGIONS.map((r) => ({ value: r.value, label: r.label })),
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    region = result as string;
  }

  let deploymentProfile: string;

  // Use flag or prompt for deployment profile
  if (flags.deploymentProfile) {
    logInfo(`Using deployment profile: ${flags.deploymentProfile}`);
    deploymentProfile = flags.deploymentProfile;
  } else {
    const result = await select({
      message: 'Deployment size',
      options: DEPLOYMENT_PROFILES.map((p) => ({
        value: p.value,
        label: p.label,
        hint: p.hint,
      })),
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    deploymentProfile = result as string;
  }

  const haControlPlane = await select({
    message: 'High availability control plane?',
    options: [
      { value: false, label: 'No (Standard)' },
      { value: true, label: 'Yes (HA - Higher cost)' },
    ],
  });

  if (typeof haControlPlane === 'symbol') {
    throw new Error('Configuration cancelled');
  }

  return {
    clusterName,
    region,
    deploymentProfile,
    haControlPlane: haControlPlane as boolean,
  };
}

/**
 * Collect GCP GKE configuration with gcloud integration
 */
export async function collectGcpConfig(flags: WizardFlags = {}): Promise<GcpConfig> {
  let clusterName: string;

  // Use flag or prompt for cluster name
  if (flags.clusterName) {
    logInfo(`Using cluster name: ${flags.clusterName}`);
    clusterName = flags.clusterName;
  } else {
    const result = await text({
      message: 'Cluster name',
      placeholder: 'monobase-main',
      initialValue: 'monobase-main',
      validate: validateClusterName,
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    clusterName = result as string;
  }

  // Try to get projects from gcloud
  let projectId: string;

  // Use flag or prompt for project ID
  if (flags.projectId) {
    logInfo(`Using GCP project ID: ${flags.projectId}`);
    projectId = flags.projectId;
  } else {
    const hasGcloud = await isGcloudAvailable();

    if (hasGcloud) {
      try {
        const projects = await getGcloudProjects();
        const currentProject = await getCurrentGcloudProject();

        if (projects.length > 0) {
          logInfo(`Found ${projects.length} GCP project(s)`);

          // Show interactive selection
          const selectedProject = await select({
            message: 'Select GCP project',
            options: projects.map((p: GcloudProject) => ({
              value: p.projectId,
              label: `${p.projectId} (${p.name})`,
              hint: p.projectId === currentProject ? 'current' : undefined,
            })),
          });

          if (typeof selectedProject === 'symbol') {
            throw new Error('Configuration cancelled');
          }

          projectId = selectedProject as string;
        } else {
          // No projects found - fallback to manual input
          logWarning('No GCP projects found');
          const manualProjectId = await text({
            message: 'GCP project ID',
            placeholder: 'my-project-123456',
            validate: validateGcpProjectId,
          });

          if (typeof manualProjectId === 'symbol') {
            throw new Error('Configuration cancelled');
          }

          projectId = manualProjectId as string;
        }
      } catch (error) {
        // Error fetching projects - fallback to manual input
        logWarning('Failed to fetch projects from gcloud');
        const manualProjectId = await text({
          message: 'GCP project ID',
          placeholder: 'my-project-123456',
          validate: validateGcpProjectId,
        });

        if (typeof manualProjectId === 'symbol') {
          throw new Error('Configuration cancelled');
        }

        projectId = manualProjectId as string;
      }
    } else {
      // gcloud not available - manual input
      logWarning('gcloud CLI not found, using manual input');
      logInfo('Install: https://cloud.google.com/sdk/docs/install');

      const manualProjectId = await text({
        message: 'GCP project ID',
        placeholder: 'my-project-123456',
        validate: validateGcpProjectId,
      });

      if (typeof manualProjectId === 'symbol') {
        throw new Error('Configuration cancelled');
      }

      projectId = manualProjectId as string;
    }
  }

  let region: string;

  // Use flag or prompt for region
  if (flags.region) {
    logInfo(`Using region: ${flags.region}`);
    region = flags.region;
  } else {
    const result = await select({
      message: 'GCP region',
      options: GCP_REGIONS.map((r) => ({ value: r.value, label: r.label })),
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    region = result as string;
  }

  return {
    clusterName,
    projectId,
    region,
  };
}

/**
 * Collect k3d local configuration
 */
export async function collectK3dConfig(flags: WizardFlags = {}): Promise<K3dConfig> {
  let clusterName: string;

  // Use flag or prompt for cluster name
  if (flags.clusterName) {
    logInfo(`Using cluster name: ${flags.clusterName}`);
    clusterName = flags.clusterName;
  } else {
    const result = await text({
      message: 'Cluster name',
      placeholder: 'k3d-local',
      initialValue: 'k3d-local',
      validate: validateClusterName,
    });

    if (typeof result === 'symbol') {
      throw new Error('Configuration cancelled');
    }

    clusterName = result as string;
  }

  const agents = await select({
    message: 'Number of agent nodes',
    options: [
      { value: 1, label: '1 node (minimal)' },
      { value: 3, label: '3 nodes (recommended)' },
      { value: 5, label: '5 nodes (larger workloads)' },
    ],
  });

  if (typeof agents === 'symbol') {
    throw new Error('Configuration cancelled');
  }

  return {
    clusterName,
    agents: agents as number,
  };
}

/**
 * Collect provider-specific configuration
 */
export async function collectProviderConfig(
  provider: Provider,
  flags: WizardFlags = {}
): Promise<ProviderConfig> {
  switch (provider) {
    case 'aws-eks':
      return await collectAwsConfig(flags);
    case 'do-doks':
      return await collectDoConfig(flags);
    case 'gcp-gke':
      return await collectGcpConfig(flags);
    case 'k3d':
      return await collectK3dConfig(flags);
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}
