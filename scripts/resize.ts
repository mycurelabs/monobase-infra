#!/usr/bin/env bun
/**
 * Resize Script - StatefulSet PVC Resizing Without Downtime
 *
 * Replaces:
 * - scripts/resize-statefulset-storage.sh
 *
 * Features:
 * - Safe PVC expansion for StatefulSets
 * - Orphan deletion (pods keep running)
 * - Automatic backup before changes
 * - Rolling restart with health checks
 * - Interactive confirmation with preview
 *
 * Usage:
 *   bun scripts/resize.ts --statefulset postgresql --namespace prod --size 200Gi
 *   bun scripts/resize.ts --statefulset minio --namespace prod --size 500Gi --auto-approve
 */

import { $ } from "bun";
import { confirm } from "@inquirer/prompts";
import chalk from "chalk";
import ora from "ora";
import { parseArgs } from "util";
import { existsSync } from "fs";

// ===== Types =====

interface ResizeConfig {
  statefulset: string;
  namespace: string;
  size: string;
  autoApprove: boolean;
}

interface StatefulSetInfo {
  replicas: number;
  pvcTemplate: string;
  currentSize: string;
}

// ===== Resize Class =====

class StatefulSetResizer {
  private config: ResizeConfig;
  private info!: StatefulSetInfo;
  private backupFile: string = '';

  constructor(config: ResizeConfig) {
    this.config = config;
  }

  async run() {
    try {
      this.printHeader();

      await this.validatePrerequisites();
      await this.validateArguments();
      await this.getStatefulSetInfo();
      await this.displayCurrentState();
      await this.confirmResize();
      await this.backupStatefulSet();
      await this.deleteStatefulSetOrphan();
      await this.verifyPodsRunning();
      await this.expandPVCs();
      await this.recreateStatefulSet();
      await this.rollingRestart();
      await this.displayVerificationSteps();

      console.log(chalk.green('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
      console.log(chalk.green('✓ Storage resize complete!'));
      console.log(chalk.green('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    } catch (error) {
      console.error(chalk.red('\n✗ Error:'), error instanceof Error ? error.message : error);
      process.exit(1);
    }
  }

  // ===== Validation =====

  async validatePrerequisites() {
    const spinner = ora('Validating prerequisites...').start();

    try {
      await $`kubectl version --client --output=json`.quiet();
      spinner.succeed('kubectl found');
    } catch {
      spinner.fail('kubectl not found');
      throw new Error('kubectl not found in PATH');
    }
  }

  async validateArguments() {
    // Validate size format
    if (!this.validateSizeFormat(this.config.size)) {
      throw new Error(`Invalid size format: ${this.config.size}. Use format like: 100Gi, 1Ti`);
    }

    // Check StatefulSet exists
    try {
      await $`kubectl get statefulset ${this.config.statefulset} -n ${this.config.namespace}`.quiet();
    } catch {
      throw new Error(`StatefulSet '${this.config.statefulset}' not found in namespace '${this.config.namespace}'`);
    }
  }

  validateSizeFormat(size: string): boolean {
    return /^[0-9]+[GT]i$/.test(size);
  }

  // ===== StatefulSet Info =====

  async getStatefulSetInfo() {
    const spinner = ora('Getting StatefulSet information...').start();

    try {
      // Get replicas
      const replicasResult = await $`kubectl get statefulset ${this.config.statefulset} -n ${this.config.namespace} -o jsonpath='{.spec.replicas}'`.text();
      const replicas = parseInt(replicasResult.trim());

      // Get PVC template name
      const pvcTemplateResult = await $`kubectl get statefulset ${this.config.statefulset} -n ${this.config.namespace} -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}'`.text();
      const pvcTemplate = pvcTemplateResult.trim();

      // Get current size
      const pvcName = `${pvcTemplate}-${this.config.statefulset}-0`;
      let currentSize = 'unknown';
      try {
        const sizeResult = await $`kubectl get pvc ${pvcName} -n ${this.config.namespace} -o jsonpath='{.spec.resources.requests.storage}'`.text();
        currentSize = sizeResult.trim();
      } catch {
        // PVC might not exist yet
      }

      this.info = {
        replicas,
        pvcTemplate,
        currentSize
      };

      spinner.succeed('StatefulSet information retrieved');
    } catch (error) {
      spinner.fail('Failed to get StatefulSet information');
      throw error;
    }
  }

  // ===== Display Current State =====

  async displayCurrentState() {
    console.log(chalk.blue('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.blue('  StatefulSet Storage Resize'));
    console.log(chalk.blue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    console.log(`StatefulSet:  ${chalk.green(this.config.statefulset)}`);
    console.log(`Namespace:    ${chalk.green(this.config.namespace)}`);
    console.log(`New Size:     ${chalk.green(this.config.size)}`);
    console.log(`Current replicas: ${chalk.green(this.info.replicas)}`);
    console.log(`PVC template: ${chalk.green(this.info.pvcTemplate)}`);
    console.log(`Current size: ${chalk.yellow(this.info.currentSize)} → New size: ${chalk.green(this.config.size)}\n`);

    // List current PVCs
    console.log(chalk.yellow('Current PVCs:'));
    try {
      const pvcs = await $`kubectl get pvc -n ${this.config.namespace} -l app.kubernetes.io/name=${this.config.statefulset} -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase`.text();
      console.log(pvcs);
    } catch {
      console.log(chalk.gray('Could not list PVCs'));
    }
  }

  // ===== Confirmation =====

  async confirmResize() {
    console.log(chalk.yellow('⚠️  This will:'));
    console.log('  1. Temporarily delete the StatefulSet (pods keep running)');
    console.log(`  2. Expand all ${this.info.replicas} PVCs to ${this.config.size}`);
    console.log('  3. Recreate the StatefulSet with new size');
    console.log('  4. Perform rolling restart of pods\n');

    if (this.config.autoApprove) {
      console.log(chalk.yellow('Auto-approve enabled, proceeding...\n'));
      return;
    }

    const confirmed = await confirm({
      message: 'Continue?',
      default: false
    });

    if (!confirmed) {
      console.log(chalk.yellow('Aborted'));
      process.exit(0);
    }

    console.log();
  }

  // ===== Backup =====

  async backupStatefulSet() {
    console.log(chalk.blue('[1/5] Backing up StatefulSet definition...'));

    const spinner = ora('Creating backup...').start();

    try {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').split('T')[0] + '-' +
                        new Date().toTimeString().split(' ')[0].replace(/:/g, '');
      this.backupFile = `/tmp/${this.config.statefulset}-backup-${timestamp}.yaml`;

      const yaml = await $`kubectl get statefulset ${this.config.statefulset} -n ${this.config.namespace} -o yaml`.text();
      await Bun.write(this.backupFile, yaml);

      spinner.succeed(`Backup saved to ${this.backupFile}`);
    } catch (error) {
      spinner.fail('Backup failed');
      throw error;
    }
  }

  // ===== StatefulSet Deletion =====

  async deleteStatefulSetOrphan() {
    console.log(chalk.blue('\n[2/5] Deleting StatefulSet (--cascade=orphan)...'));
    console.log(chalk.yellow('  (Pods will keep running)'));

    const spinner = ora('Deleting StatefulSet...').start();

    try {
      await $`kubectl delete statefulset ${this.config.statefulset} -n ${this.config.namespace} --cascade=orphan`.quiet();
      spinner.succeed('StatefulSet deleted (pods still running)');
    } catch (error) {
      spinner.fail('StatefulSet deletion failed');
      throw error;
    }
  }

  async verifyPodsRunning() {
    const spinner = ora('Verifying pods still running...').start();

    try {
      await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds

      const result = await $`kubectl get pods -n ${this.config.namespace} -l app.kubernetes.io/name=${this.config.statefulset} --field-selector=status.phase=Running --no-headers`.text();
      const runningPods = result.trim().split('\n').filter(line => line).length;

      spinner.succeed(`Running pods: ${chalk.green(runningPods)}/${this.info.replicas}`);

      if (runningPods < this.info.replicas) {
        console.log(chalk.yellow(`  Warning: Expected ${this.info.replicas} pods, found ${runningPods} running`));
      }
    } catch (error) {
      spinner.warn('Could not verify running pods');
    }
  }

  // ===== PVC Expansion =====

  async expandPVCs() {
    console.log(chalk.blue('\n[3/5] Expanding PVCs...'));

    for (let i = 0; i < this.info.replicas; i++) {
      const pvcName = `${this.info.pvcTemplate}-${this.config.statefulset}-${i}`;
      const spinner = ora(`Expanding ${pvcName}...`).start();

      try {
        const patch = JSON.stringify([{
          op: 'replace',
          path: '/spec/resources/requests/storage',
          value: this.config.size
        }]);

        await $`kubectl patch pvc ${pvcName} -n ${this.config.namespace} --type=json -p ${patch}`.quiet();
        spinner.succeed(`Expanded ${pvcName}`);
      } catch (error) {
        spinner.fail(`Failed to expand ${pvcName}`);
        throw error;
      }
    }

    console.log(chalk.green('✓ All PVCs patched'));

    // Wait for expansion
    const waitSpinner = ora('Waiting for storage expansion (this may take a minute)...').start();
    await new Promise(resolve => setTimeout(resolve, 10000)); // Wait 10 seconds
    waitSpinner.succeed('Expansion wait complete');
  }

  // ===== StatefulSet Recreation =====

  async recreateStatefulSet() {
    console.log(chalk.blue('\n[4/5] Recreating StatefulSet with new size...'));

    const spinner = ora('Updating StatefulSet definition...').start();

    try {
      // Read backup file
      const backupContent = await Bun.file(this.backupFile).text();

      // Replace old size with new size
      const updatedContent = backupContent.replace(
        new RegExp(`storage: ${this.info.currentSize}`, 'g'),
        `storage: ${this.config.size}`
      );

      // Write updated file
      const updatedFile = this.backupFile.replace('.yaml', '-updated.yaml');
      await Bun.write(updatedFile, updatedContent);

      spinner.text = 'Applying StatefulSet...';

      // Apply updated StatefulSet
      await $`kubectl apply -f ${updatedFile}`.quiet();

      spinner.succeed('StatefulSet recreated');
    } catch (error) {
      spinner.fail('StatefulSet recreation failed');
      throw error;
    }
  }

  // ===== Rolling Restart =====

  async rollingRestart() {
    console.log(chalk.blue('\n[5/5] Performing rolling restart...'));

    // Restart in reverse order (highest replica first)
    for (let i = this.info.replicas - 1; i >= 0; i--) {
      const podName = `${this.config.statefulset}-${i}`;
      const spinner = ora(`Restarting ${podName}...`).start();

      try {
        // Delete pod
        await $`kubectl delete pod ${podName} -n ${this.config.namespace}`.quiet();

        // Wait for pod to be ready
        await $`kubectl wait --for=condition=ready pod ${podName} -n ${this.config.namespace} --timeout=600s`.quiet();

        spinner.succeed(`Restarted ${podName}`);

        // Wait between restarts
        if (i > 0) {
          await new Promise(resolve => setTimeout(resolve, 5000)); // 5 second delay
        }
      } catch (error) {
        spinner.fail(`Failed to restart ${podName} (check manually)`);
        console.log(chalk.yellow('  Continuing with remaining pods...'));
      }
    }
  }

  // ===== Verification =====

  async displayVerificationSteps() {
    console.log(chalk.yellow('\nVerification:\n'));
    console.log('1. Check PVC sizes:');
    console.log(chalk.blue(`   kubectl get pvc -n ${this.config.namespace} -l app.kubernetes.io/name=${this.config.statefulset}\n`));
    console.log('2. Verify in pods:');
    console.log(chalk.blue(`   kubectl exec -it ${this.config.statefulset}-0 -n ${this.config.namespace} -- df -h\n`));
    console.log('3. Check StatefulSet:');
    console.log(chalk.blue(`   kubectl get statefulset ${this.config.statefulset} -n ${this.config.namespace}\n`));
    console.log(chalk.green(`All PVCs should now show: ${this.config.size}\n`));
  }

  // ===== Utility =====

  printHeader() {
    console.log(chalk.bold.blue('\n╔════════════════════════════════════════╗'));
    console.log(chalk.bold.blue('║  StatefulSet Storage Resize           ║'));
    console.log(chalk.bold.blue('╚════════════════════════════════════════╝\n'));
  }
}

// ===== CLI Parsing =====

function printHelp() {
  console.log(`
${chalk.bold('StatefulSet Storage Resize')}

${chalk.bold('USAGE:')}
  bun scripts/resize.ts [OPTIONS]

${chalk.bold('OPTIONS:')}
  ${chalk.cyan('--help')}                    Show this help message
  ${chalk.cyan('--statefulset <name>')}      StatefulSet name (required)
  ${chalk.cyan('--namespace <name>')}        Kubernetes namespace (required)
  ${chalk.cyan('--size <size>')}             New storage size (required)
  ${chalk.cyan('--auto-approve')}            Skip confirmation prompt

${chalk.bold('SIZE FORMAT:')}
  Must match pattern: [0-9]+[GT]i
  Examples: 100Gi, 200Gi, 1Ti, 2Ti

${chalk.bold('EXAMPLES:')}
  ${chalk.gray('# Resize PostgreSQL PVCs to 200Gi')}
  bun scripts/resize.ts --statefulset postgresql --namespace prod --size 200Gi

  ${chalk.gray('# Resize MinIO PVCs to 500Gi (auto-approve)')}
  bun scripts/resize.ts --statefulset minio --namespace prod --size 500Gi --auto-approve

  ${chalk.gray('# Resize MongoDB PVCs to 1Ti')}
  bun scripts/resize.ts --statefulset mongodb --namespace staging --size 1Ti

${chalk.bold('WARNING:')}
  This script performs the following operations:
  1. Temporarily deletes the StatefulSet (pods keep running)
  2. Expands all PVCs to the new size
  3. Recreates the StatefulSet
  4. Performs rolling restart of all pods

  A backup of the StatefulSet is created before any changes.
`);
}

function parseCliArgs(): ResizeConfig {
  const { values } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      help: { type: 'boolean', default: false },
      statefulset: { type: 'string' },
      namespace: { type: 'string' },
      size: { type: 'string' },
      'auto-approve': { type: 'boolean', default: false },
    },
    strict: true,
  });

  if (values.help) {
    printHelp();
    process.exit(0);
  }

  if (!values.statefulset || !values.namespace || !values.size) {
    console.error(chalk.red('Error: Missing required arguments\n'));
    printHelp();
    process.exit(1);
  }

  return {
    statefulset: values.statefulset,
    namespace: values.namespace,
    size: values.size,
    autoApprove: values['auto-approve'] || false,
  };
}

// ===== Main =====

async function main() {
  const config = parseCliArgs();
  const resizer = new StatefulSetResizer(config);
  await resizer.run();
}

main();
