#!/usr/bin/env bun
/**
 * Provision Script - Unified Cluster Provisioning and Destruction
 *
 * Replaces:
 * - scripts/provision.sh
 * - scripts/teardown.sh
 *
 * Features:
 * - Cluster provisioning with Terraform/OpenTofu
 * - Kubeconfig extraction and merging
 * - Cluster connectivity verification
 * - Cluster destruction with state backup
 * - Interactive prompts with validation
 * - Progress indicators and colored output
 *
 * Usage:
 *   bun scripts/provision.ts --cluster <name>                    # Provision cluster
 *   bun scripts/provision.ts --cluster <name> --merge-kubeconfig # Provision + merge config
 *   bun scripts/provision.ts --destroy --cluster <name>          # Destroy cluster
 *   bun scripts/provision.ts --destroy --dry-run                 # Preview destruction
 */

import { $ } from "bun";
import { confirm, input, select } from "@inquirer/prompts";
import chalk from "chalk";
import ora, { type Ora } from "ora";
import { parseArgs } from "util";
import { existsSync, readdirSync } from "fs";
import { join } from "path";

// ===== Types =====

interface ProvisionConfig {
  cluster?: string;
  dryRun: boolean;
  autoApprove: boolean;
  mergeKubeconfig: boolean;
  destroy: boolean;
  keepKubeconfig: boolean;
}

// ===== Provision Class =====

class ClusterProvisioner {
  private config: ProvisionConfig;
  private clusterDir: string = '';
  private terraformCmd: string = '';

  constructor(config: ProvisionConfig) {
    this.config = config;
  }

  async run() {
    try {
      this.printHeader();

      if (this.config.destroy) {
        await this.destroy();
      } else {
        await this.provision();
      }
    } catch (error) {
      console.error(chalk.red('\n✗ Error:'), error instanceof Error ? error.message : error);
      process.exit(1);
    }
  }

  // ===== Provision Flow =====

  async provision() {
    console.log(chalk.blue('\n==> Provision Configuration'));
    console.log(`Cluster: ${this.config.cluster || 'will prompt'}`);
    console.log(`Merge kubeconfig: ${this.config.mergeKubeconfig}`);
    console.log(`Auto-approve: ${this.config.autoApprove}`);
    console.log(`Dry run: ${this.config.dryRun}`);

    await this.validatePrerequisites();
    await this.selectCluster();
    await this.validateClusterDirectory();
    await this.terraformInit();
    await this.terraformPlan();

    if (!this.config.dryRun) {
      await this.confirmApply();
      await this.terraformApply();
      await this.extractKubeconfig();

      if (this.config.mergeKubeconfig) {
        await this.mergeKubeconfig();
      }

      await this.verifyConnectivity();
    }

    await this.displayProvisionSummary();
  }

  // ===== Validation =====

  async validatePrerequisites() {
    console.log(chalk.blue('\n==> Step 1: Validate Prerequisites'));

    // Check for terraform or tofu
    try {
      await $`terraform version`.quiet();
      this.terraformCmd = 'terraform';
      console.log(chalk.green('✓ terraform found'));
    } catch {
      try {
        await $`tofu version`.quiet();
        this.terraformCmd = 'tofu';
        console.log(chalk.green('✓ tofu (OpenTofu) found'));
      } catch {
        throw new Error('Neither terraform nor tofu found in PATH');
      }
    }

    // Check kubectl
    try {
      await $`kubectl version --client --output=json`.quiet();
      console.log(chalk.green('✓ kubectl found'));
    } catch {
      throw new Error('kubectl not found in PATH');
    }
  }

  // ===== Cluster Selection =====

  async selectCluster() {
    if (this.config.cluster) {
      console.log(chalk.blue(`\n==> Using cluster: ${chalk.green(this.config.cluster)}`));
      return;
    }

    console.log(chalk.blue('\n==> Step 2: Select Cluster'));

    const clustersDir = 'clusters';
    if (!existsSync(clustersDir)) {
      throw new Error(`Clusters directory not found: ${clustersDir}`);
    }

    const clusters = readdirSync(clustersDir, { withFileTypes: true })
      .filter(dirent => dirent.isDirectory())
      .map(dirent => dirent.name)
      .filter(name => !name.startsWith('.'));

    if (clusters.length === 0) {
      throw new Error('No cluster configurations found in clusters/');
    }

    console.log(chalk.blue('Available clusters:'));
    clusters.forEach(cluster => {
      console.log(`  - ${cluster}`);
    });

    this.config.cluster = await select({
      message: 'Select cluster to provision:',
      choices: clusters.map(cluster => ({
        name: cluster,
        value: cluster
      }))
    });
  }

  async validateClusterDirectory() {
    this.clusterDir = join('clusters', this.config.cluster!);

    if (!existsSync(this.clusterDir)) {
      throw new Error(`Cluster directory not found: ${this.clusterDir}`);
    }

    // Check for required Terraform files
    const requiredFiles = ['main.tf'];
    const missingFiles = requiredFiles.filter(file =>
      !existsSync(join(this.clusterDir, file))
    );

    if (missingFiles.length > 0) {
      throw new Error(`Missing required files in ${this.clusterDir}: ${missingFiles.join(', ')}`);
    }

    console.log(chalk.green(`✓ Cluster directory validated: ${this.clusterDir}`));
  }

  // ===== Terraform Operations =====

  async terraformInit() {
    console.log(chalk.blue('\n==> Step 3: Terraform Init'));

    const spinner = ora('Initializing Terraform...').start();

    try {
      const result = await $`cd ${this.clusterDir} && ${this.terraformCmd} init`.text();

      if (result.includes('Terraform has been successfully initialized')) {
        spinner.succeed('Terraform initialized');
      } else if (result.includes('has been successfully initialized')) {
        spinner.succeed('Terraform already initialized');
      } else {
        spinner.succeed('Terraform init complete');
      }
    } catch (error) {
      spinner.fail('Terraform init failed');
      throw error;
    }
  }

  async terraformPlan() {
    console.log(chalk.blue('\n==> Step 4: Terraform Plan'));

    const spinner = ora('Generating plan...').start();
    const planFile = 'tfplan';

    try {
      const result = await $`cd ${this.clusterDir} && ${this.terraformCmd} plan -out=${planFile}`.text();

      spinner.succeed('Plan generated');

      // Parse plan output for changes
      const lines = result.split('\n');
      const planSummary = lines.find(line =>
        line.includes('Plan:') || line.includes('No changes')
      );

      if (planSummary) {
        console.log(chalk.cyan(`\n${planSummary.trim()}`));
      }

      // Show if this is first run
      if (result.includes('Plan: ') && result.includes(' to add')) {
        const match = result.match(/Plan: (\d+) to add/);
        if (match && parseInt(match[1]) > 0) {
          console.log(chalk.yellow('\n⚠️  This appears to be a first-time provision'));
        }
      }

      if (this.config.dryRun) {
        console.log(chalk.gray('\nDry run: Plan saved but will not be applied'));
      }
    } catch (error) {
      spinner.fail('Plan generation failed');
      throw error;
    }
  }

  async confirmApply() {
    if (this.config.autoApprove) {
      console.log(chalk.yellow('\n⚠️  Auto-approve enabled, applying changes...'));
      return;
    }

    console.log(chalk.blue('\n==> Confirm Apply'));

    const confirmed = await confirm({
      message: 'Do you want to apply these changes?',
      default: false
    });

    if (!confirmed) {
      throw new Error('Apply cancelled by user');
    }
  }

  async terraformApply() {
    console.log(chalk.blue('\n==> Step 5: Terraform Apply'));

    const spinner = ora('Applying infrastructure changes...').start();

    try {
      await $`cd ${this.clusterDir} && ${this.terraformCmd} apply tfplan`.quiet();
      spinner.succeed('Infrastructure provisioned successfully');

      // Clean up plan file
      try {
        await $`cd ${this.clusterDir} && rm -f tfplan`.quiet();
      } catch {}
    } catch (error) {
      spinner.fail('Terraform apply failed');
      throw error;
    }
  }

  // ===== Kubeconfig Management =====

  async extractKubeconfig() {
    console.log(chalk.blue('\n==> Step 6: Extract Kubeconfig'));

    const spinner = ora('Extracting kubeconfig...').start();
    const kubeconfigPath = join(process.env.HOME || '~', '.kube', this.config.cluster!);

    try {
      // Get kubeconfig from terraform output
      const kubeconfig = await $`cd ${this.clusterDir} && ${this.terraformCmd} output -raw kubeconfig`.text();

      // Save to file
      await Bun.write(kubeconfigPath, kubeconfig);

      // Set secure permissions
      await $`chmod 600 ${kubeconfigPath}`.quiet();

      spinner.succeed(`Kubeconfig saved: ${kubeconfigPath}`);
      console.log(chalk.gray(`Export: export KUBECONFIG=${kubeconfigPath}`));
    } catch (error) {
      spinner.fail('Failed to extract kubeconfig');
      throw error;
    }
  }

  async mergeKubeconfig() {
    console.log(chalk.blue('\n==> Step 7: Merge Kubeconfig'));

    const spinner = ora('Checking existing contexts...').start();
    const contextName = this.config.cluster!;

    try {
      // Check if context already exists
      try {
        await $`kubectl config get-contexts ${contextName}`.quiet();
        spinner.info(`Context '${contextName}' already exists in ~/.kube/config`);

        const switchContext = await confirm({
          message: `Switch to context '${contextName}'?`,
          default: true
        });

        if (switchContext) {
          await $`kubectl config use-context ${contextName}`.quiet();
          console.log(chalk.green(`✓ Switched to context: ${contextName}`));
        }

        return;
      } catch {
        // Context doesn't exist, merge it
      }

      spinner.text = 'Merging kubeconfig...';

      // Backup existing config
      const backupPath = join(process.env.HOME || '~', '.kube', `config.backup.${Date.now()}`);
      try {
        await $`cp ~/.kube/config ${backupPath}`.quiet();
        console.log(chalk.gray(`Backup created: ${backupPath}`));
      } catch {}

      // Merge configs
      const kubeconfigPath = join(process.env.HOME || '~', '.kube', this.config.cluster!);
      await $`KUBECONFIG=~/.kube/config:${kubeconfigPath} kubectl config view --flatten > ~/.kube/config.tmp`.quiet();
      await $`mv ~/.kube/config.tmp ~/.kube/config`.quiet();

      // Switch to new context
      await $`kubectl config use-context ${contextName}`.quiet();

      spinner.succeed(`Kubeconfig merged and switched to context: ${contextName}`);
    } catch (error) {
      spinner.fail('Failed to merge kubeconfig');
      throw error;
    }
  }

  async verifyConnectivity() {
    console.log(chalk.blue('\n==> Step 8: Verify Connectivity'));

    const spinner = ora('Testing cluster connection...').start();
    const kubeconfigPath = join(process.env.HOME || '~', '.kube', this.config.cluster!);

    try {
      // Test connection
      await $`KUBECONFIG=${kubeconfigPath} kubectl cluster-info`.quiet();
      spinner.text = 'Fetching node status...';

      // Get nodes
      const nodes = await $`KUBECONFIG=${kubeconfigPath} kubectl get nodes`.text();

      spinner.succeed('Cluster is accessible');
      console.log(chalk.blue('\nNode Status:'));
      console.log(nodes);
    } catch (error) {
      spinner.fail('Failed to connect to cluster');
      throw error;
    }
  }

  async displayProvisionSummary() {
    console.log(chalk.blue('\n==> Provision Summary'));

    if (this.config.dryRun) {
      console.log(chalk.yellow('Dry run completed - no changes applied'));
      return;
    }

    try {
      const outputs = await $`cd ${this.clusterDir} && ${this.terraformCmd} output -json`.text();
      const parsed = JSON.parse(outputs);

      console.log(chalk.blue('\nTerraform Outputs:'));
      Object.entries(parsed).forEach(([key, value]: [string, any]) => {
        if (key !== 'kubeconfig' && value.value) {
          console.log(`  ${chalk.cyan(key)}: ${value.value}`);
        }
      });
    } catch {
      console.log(chalk.yellow('Could not fetch terraform outputs'));
    }

    console.log(chalk.blue('\n==> Next Steps'));
    const kubeconfigPath = join(process.env.HOME || '~', '.kube', this.config.cluster!);
    console.log(`1. Export kubeconfig: export KUBECONFIG=${kubeconfigPath}`);
    console.log(`2. Bootstrap cluster: mise run bootstrap`);
    console.log(`3. Monitor deployments: kubectl get nodes`);
  }

  // ===== Destroy Flow =====

  async destroy() {
    console.log(chalk.red('\n==> Cluster Destruction'));
    console.log(chalk.yellow('⚠️  This will destroy all cluster infrastructure\n'));

    await this.validatePrerequisites();
    await this.selectCluster();
    await this.validateClusterDirectory();
    await this.checkTerraformState();
    await this.terraformInit();
    await this.showDestroyPlan();

    if (!this.config.dryRun) {
      await this.confirmDestruction();
      await this.backupState();
      await this.terraformDestroy();

      if (!this.config.keepKubeconfig) {
        await this.cleanupKubeconfig();
      }
    }

    await this.displayDestroySummary();
  }

  async checkTerraformState() {
    const stateFile = join(this.clusterDir, 'terraform.tfstate');

    if (!existsSync(stateFile)) {
      console.log(chalk.yellow('\n⚠️  Warning: terraform.tfstate not found'));
      console.log(chalk.yellow('No infrastructure state detected for this cluster'));

      if (!this.config.autoApprove) {
        const continueAnyway = await confirm({
          message: 'Continue anyway?',
          default: false
        });

        if (!continueAnyway) {
          throw new Error('Destruction cancelled');
        }
      }
    } else {
      console.log(chalk.green('✓ Terraform state found'));
    }
  }

  async showDestroyPlan() {
    console.log(chalk.blue('\n==> Destroy Plan'));

    const spinner = ora('Generating destroy plan...').start();

    try {
      const result = await $`cd ${this.clusterDir} && ${this.terraformCmd} plan -destroy`.text();

      spinner.succeed('Destroy plan generated');

      // Parse plan output for changes
      const lines = result.split('\n');
      const planSummary = lines.find(line =>
        line.includes('Plan:') || line.includes('No changes')
      );

      if (planSummary) {
        console.log(chalk.red(`\n${planSummary.trim()}`));
      }

      if (this.config.dryRun) {
        console.log(chalk.gray('\nDry run: Plan generated but will not be executed'));
      }
    } catch (error) {
      spinner.fail('Destroy plan generation failed');
      throw error;
    }
  }

  async confirmDestruction() {
    console.log(chalk.red('\n==> Confirmation Required'));
    console.log(chalk.yellow('⚠️  This action is IRREVERSIBLE'));
    console.log(chalk.yellow('⚠️  All cluster resources will be permanently deleted\n'));

    // First confirmation: Type cluster name
    const clusterName = await input({
      message: `Type the cluster name '${chalk.red(this.config.cluster!)}' to confirm:`,
      validate: (val) => val === this.config.cluster || `Must type exactly: ${this.config.cluster}`
    });

    // Second confirmation: Type DESTROY
    const destroyConfirm = await input({
      message: `Type ${chalk.red('DESTROY')} to proceed:`,
      validate: (val) => val === 'DESTROY' || 'Must type exactly: DESTROY'
    });

    console.log(chalk.red('\n⚠️  Proceeding with destruction...'));
  }

  async backupState() {
    console.log(chalk.blue('\n==> Backing Up State'));

    const spinner = ora('Creating state backup...').start();

    try {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const backupDir = 'backups/terraform-state';
      const backupFile = `${this.config.cluster}-${timestamp}.tfstate`;

      await $`mkdir -p ${backupDir}`.quiet();
      await $`cp ${this.clusterDir}/terraform.tfstate ${backupDir}/${backupFile}`.quiet();

      spinner.succeed(`State backed up: ${backupDir}/${backupFile}`);
    } catch (error) {
      spinner.warn('State backup failed (continuing anyway)');
    }
  }

  async terraformDestroy() {
    console.log(chalk.blue('\n==> Destroying Infrastructure'));

    const spinner = ora('Running terraform destroy...').start();

    try {
      await $`cd ${this.clusterDir} && ${this.terraformCmd} destroy -auto-approve`.quiet();
      spinner.succeed('Infrastructure destroyed successfully');
    } catch (error) {
      spinner.fail('Terraform destroy failed');
      console.log(chalk.yellow('\n⚠️  Check state backup in backups/terraform-state/'));
      throw error;
    }
  }

  async cleanupKubeconfig() {
    console.log(chalk.blue('\n==> Cleaning Up Kubeconfig'));

    const spinner = ora('Removing kubeconfig files...').start();
    const kubeconfigPath = join(process.env.HOME || '~', '.kube', this.config.cluster!);

    try {
      // Remove standalone kubeconfig file
      try {
        await $`rm -f ${kubeconfigPath}`.quiet();
        spinner.succeed(`Removed: ${kubeconfigPath}`);
      } catch {}

      // Check if context exists in merged config
      try {
        await $`kubectl config get-contexts ${this.config.cluster}`.quiet();

        const removeContext = await confirm({
          message: `Remove context '${this.config.cluster}' from ~/.kube/config?`,
          default: true
        });

        if (removeContext) {
          await $`kubectl config delete-context ${this.config.cluster}`.quiet();
          await $`kubectl config delete-cluster ${this.config.cluster}`.quiet();
          await $`kubectl config delete-user ${this.config.cluster}`.quiet();
          console.log(chalk.green('✓ Context removed from ~/.kube/config'));
        }
      } catch {
        // Context doesn't exist in merged config
      }
    } catch (error) {
      spinner.warn('Kubeconfig cleanup had issues');
    }
  }

  async displayDestroySummary() {
    console.log(chalk.blue('\n==> Destruction Summary'));

    if (this.config.dryRun) {
      console.log(chalk.yellow('Dry run completed - no resources destroyed'));
      return;
    }

    console.log(chalk.green('✓ Cluster infrastructure destroyed'));
    console.log(chalk.gray('\nState backup location: backups/terraform-state/'));

    if (this.config.keepKubeconfig) {
      const kubeconfigPath = join(process.env.HOME || '~', '.kube', this.config.cluster!);
      console.log(chalk.yellow(`\nKubeconfig preserved: ${kubeconfigPath}`));
    }
  }

  // ===== Utility =====

  printHeader() {
    const title = this.config.destroy ? 'Cluster Destruction' : 'Cluster Provisioning';
    console.log(chalk.bold.blue('\n╔════════════════════════════════════════╗'));
    console.log(chalk.bold.blue(`║  ${title.padEnd(36)} ║`));
    console.log(chalk.bold.blue('╚════════════════════════════════════════╝\n'));
  }
}

// ===== CLI Parsing =====

function printHelp() {
  console.log(`
${chalk.bold('Monobase Infrastructure Provisioning')}

${chalk.bold('USAGE:')}
  bun scripts/provision.ts [OPTIONS]

${chalk.bold('OPTIONS:')}
  ${chalk.cyan('--help')}                    Show this help message
  ${chalk.cyan('--cluster <name>')}          Cluster name (directory in clusters/)
  ${chalk.cyan('--dry-run')}                 Preview changes without executing
  ${chalk.cyan('--auto-approve')}            Skip confirmation prompts
  ${chalk.cyan('--merge-kubeconfig')}        Merge kubeconfig into ~/.kube/config

  ${chalk.bold('Destroy Options:')}
  ${chalk.cyan('--destroy')}                 Destroy cluster infrastructure
  ${chalk.cyan('--keep-kubeconfig')}         Don't remove kubeconfig files (destroy mode)

${chalk.bold('EXAMPLES:')}
  ${chalk.gray('# Provision cluster')}
  bun scripts/provision.ts --cluster mycure-prod

  ${chalk.gray('# Provision with kubeconfig merge')}
  bun scripts/provision.ts --cluster mycure-prod --merge-kubeconfig

  ${chalk.gray('# Dry run provision')}
  bun scripts/provision.ts --cluster mycure-prod --dry-run

  ${chalk.gray('# Destroy cluster (interactive)')}
  bun scripts/provision.ts --destroy --cluster mycure-prod

  ${chalk.gray('# Preview destroy plan')}
  bun scripts/provision.ts --destroy --cluster mycure-prod --dry-run
`);
}

function parseCliArgs(): ProvisionConfig {
  const { values } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      help: { type: 'boolean', default: false },
      cluster: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
      'auto-approve': { type: 'boolean', default: false },
      'merge-kubeconfig': { type: 'boolean', default: false },
      destroy: { type: 'boolean', default: false },
      'keep-kubeconfig': { type: 'boolean', default: false },
    },
    strict: true,
  });

  if (values.help) {
    printHelp();
    process.exit(0);
  }

  return {
    cluster: values.cluster,
    dryRun: values['dry-run'] || false,
    autoApprove: values['auto-approve'] || false,
    mergeKubeconfig: values['merge-kubeconfig'] || false,
    destroy: values.destroy || false,
    keepKubeconfig: values['keep-kubeconfig'] || false,
  };
}

// ===== Main =====

async function main() {
  const config = parseCliArgs();
  const provisioner = new ClusterProvisioner(config);
  await provisioner.run();
}

main();
