// Cluster Setup Wizard - Main Orchestrator

import { $ } from 'bun';
import { existsSync } from 'fs';
import { intro, outro, note, confirm, select } from '@clack/prompts';
import ora from 'ora';
import { PROVIDERS, PROVIDER_SETUP_INSTRUCTIONS, type Provider } from './providers';
import { collectProviderConfig, type ProviderConfig } from './collectors';
import {
  generateTfvars,
  generateGcpMainTf,
  generateGcpVariablesTf,
  generateGcpOutputsTf,
  generateAwsMainTf,
  generateAwsVariablesTf,
  generateAwsOutputsTf,
  generateDoMainTf,
  generateK3dMainTf,
  generateK3dVariablesTf,
  generateK3dOutputsTf,
} from './generators';
import { checkProviderPrerequisites } from './validators';
import { logSuccess, logInfo, logWarning, logError } from '@/lib/prompts';

export interface WizardFlags {
  provider?: string;
  projectId?: string;
  region?: string;
  clusterName?: string;
  deploymentProfile?: string;
}

export class ClusterSetupWizard {
  private flags: WizardFlags;

  constructor(flags: WizardFlags = {}) {
    this.flags = flags;
  }

  /**
   * Run the interactive cluster setup wizard
   */
  async run(): Promise<void> {
    intro('Cluster Setup Wizard');

    try {
      // Step 1: Select provider
      const provider = await this.selectProvider();

      // Step 2: Check prerequisites (with warnings, not blocking)
      await this.checkPrerequisites(provider);

      // Step 3: Collect configuration
      const config = await collectProviderConfig(provider, this.flags);

      // Step 4: Generate cluster directory
      await this.generateClusterDirectory(provider, config);

      // Step 5: Show next steps and confirm provisioning
      const shouldProceed = await this.confirmProvisioning(provider);

      if (!shouldProceed) {
        outro('Setup complete. Run provision when ready.');
        process.exit(0);
      }

      outro('Starting provision...');
    } catch (error) {
      if (error instanceof Error) {
        if (error.message.includes('cancelled')) {
          outro('Setup cancelled');
          process.exit(1);
        }
        logError(error.message);
      }
      throw error;
    }
  }

  /**
   * Step 1: Select cloud provider
   */
  private async selectProvider(): Promise<Provider> {
    // If provider flag is set, use it and skip prompt
    if (this.flags.provider) {
      const validProviders = ['aws-eks', 'do-doks', 'gcp-gke', 'k3d'];
      if (!validProviders.includes(this.flags.provider)) {
        throw new Error(`Invalid provider: ${this.flags.provider}. Must be one of: ${validProviders.join(', ')}`);
      }
      logInfo(`Using provider: ${this.flags.provider}`);
      return this.flags.provider as Provider;
    }

    const provider = await select({
      message: 'Select cloud provider',
      options: PROVIDERS.map((p) => ({
        value: p.value,
        label: p.label,
        hint: p.hint,
      })),
    });

    if (typeof provider === 'symbol') {
      throw new Error('Provider selection cancelled');
    }

    return provider as Provider;
  }

  /**
   * Step 2: Check provider prerequisites
   */
  private async checkPrerequisites(provider: Provider): Promise<void> {
    const spinner = ora('Checking prerequisites...').start();

    try {
      const hasPrereqs = await checkProviderPrerequisites(provider);

      if (!hasPrereqs) {
        spinner.warn('Prerequisites check completed with warnings');

        // Show setup instructions
        const instructions = PROVIDER_SETUP_INSTRUCTIONS[provider];
        note(instructions.steps.join('\n'), instructions.title);

        if (instructions.docs) {
          logInfo(`Documentation: ${instructions.docs}`);
        }

        // Ask if user wants to continue
        const shouldContinue = await confirm({
          message: 'Continue anyway?',
          initialValue: true,
        });

        if (!shouldContinue || typeof shouldContinue === 'symbol') {
          throw new Error('Setup cancelled');
        }
      } else {
        spinner.succeed('Prerequisites check passed');
      }
    } catch (error) {
      spinner.fail('Prerequisites check failed');
      throw error;
    }
  }

  /**
   * Step 4: Generate cluster directory
   */
  private async generateClusterDirectory(
    provider: Provider,
    config: ProviderConfig
  ): Promise<void> {
    const spinner = ora('Creating cluster configuration...').start();

    try {
      // Check if values/cluster/ already exists
      if (existsSync('values/cluster')) {
        spinner.stop();

        const shouldOverwrite = await confirm({
          message: 'values/cluster/ directory already exists. Overwrite?',
          initialValue: false,
        });

        if (!shouldOverwrite || typeof shouldOverwrite === 'symbol') {
          throw new Error('Setup cancelled - values/cluster/ directory exists');
        }

        // Backup existing values/cluster/
        const backupName = `cluster.backup.${Date.now()}`;
        await $`mv values/cluster ${backupName}`.quiet();
        logInfo(`Existing values/cluster/ backed up to ${backupName}`);

        spinner.start('Creating cluster configuration...');
      }

      // Create cluster directory
      await $`mkdir -p values/cluster`.quiet();

      // Generate Terraform files based on provider
      switch (provider) {
        case 'gcp-gke':
          await Bun.write('values/cluster/main.tf', generateGcpMainTf());
          await Bun.write('values/cluster/variables.tf', generateGcpVariablesTf());
          await Bun.write('values/cluster/outputs.tf', generateGcpOutputsTf());
          break;
        case 'aws-eks':
          await Bun.write('values/cluster/main.tf', generateAwsMainTf());
          await Bun.write('values/cluster/variables.tf', generateAwsVariablesTf());
          await Bun.write('values/cluster/outputs.tf', generateAwsOutputsTf());
          break;
        case 'do-doks':
          await Bun.write('values/cluster/main.tf', generateDoMainTf());
          break;
        case 'k3d':
          await Bun.write('values/cluster/main.tf', generateK3dMainTf());
          await Bun.write('values/cluster/variables.tf', generateK3dVariablesTf());
          await Bun.write('values/cluster/outputs.tf', generateK3dOutputsTf());
          break;
      }

      // Generate terraform.tfvars
      const tfvarsContent = generateTfvars(provider, config);
      await Bun.write('values/cluster/terraform.tfvars', tfvarsContent);

      spinner.succeed('Cluster configuration created');
      logSuccess('Files created in values/cluster/');

      // Show created files
      const files = await $`ls -1 values/cluster`.text();
      logInfo('Created files:\n' + files.trim().split('\n').map(f => `  - ${f}`).join('\n'));
    } catch (error) {
      spinner.fail('Failed to create configuration');
      throw error;
    }
  }

  /**
   * Step 5: Show next steps and confirm provisioning
   */
  private async confirmProvisioning(provider: Provider): Promise<boolean> {
    const nextSteps = this.getNextSteps(provider);

    note(nextSteps.join('\n'), 'Setup Complete');

    const shouldProceed = await confirm({
      message: 'Proceed with provisioning now?',
      initialValue: false,
    });

    if (typeof shouldProceed === 'symbol') {
      return false;
    }

    return shouldProceed;
  }

  /**
   * Get provider-specific next steps
   */
  private getNextSteps(provider: Provider): string[] {
    const commonSteps = [
      '1. Review generated terraform.tfvars in values/cluster/',
      '2. Ensure cloud provider credentials are configured',
      '3. Provision infrastructure',
    ];

    const providerSteps: Record<Provider, string[]> = {
      'aws-eks': [
        ...commonSteps,
        '',
        'After provisioning:',
        '- Run: mise run secrets setup --full',
        '- Run: mise run bootstrap',
      ],
      'do-doks': [
        ...commonSteps,
        '',
        'After provisioning:',
        '- Run: mise run secrets setup --full',
        '- Run: mise run bootstrap',
      ],
      'gcp-gke': [
        ...commonSteps,
        '',
        'After provisioning:',
        '- Run: mise run secrets setup --full --project YOUR_PROJECT_ID',
        '- Run: mise run bootstrap',
      ],
      'k3d': [
        ...commonSteps,
        '',
        'After provisioning:',
        '- Run: mise run bootstrap (skip secrets setup for local)',
      ],
    };

    return providerSteps[provider] || commonSteps;
  }
}
