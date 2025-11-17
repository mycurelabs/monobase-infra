#!/usr/bin/env bun
/**
 * Admin Access Script - Port-forwarding to Kubernetes Admin UIs
 *
 * Replaces:
 * - scripts/admin-access.sh
 *
 * Features:
 * - Interactive kubeconfig and service selection
 * - Automatic credential extraction from secrets
 * - Port-forwarding to admin services
 * - Support for per-deployment services (MinIO, Mailpit)
 * - Context verification with confirmation
 * - Non-interactive mode for automation
 *
 * Usage:
 *   bun scripts/admin.ts                                      # Interactive mode
 *   bun scripts/admin.ts --service argocd                     # Direct service access
 *   bun scripts/admin.ts --service minio --namespace prod     # Specify namespace
 *   bun scripts/admin.ts --kubeconfig ~/.kube/prod argocd    # Legacy positional
 */

import { $ } from "bun";
import { confirm, select } from "@inquirer/prompts";
import chalk from "chalk";
import ora from "ora";
import { parseArgs } from "util";
import { existsSync, readdirSync } from "fs";
import { join } from "path";

// ===== Types =====

interface ServiceConfig {
  namespace: string | null; // null = per-deployment
  serviceName: string;
  localPort: number;
  remotePort: number;
  displayName: string;
  credentials?: {
    secret: string;
    username?: string; // static username
    usernameKey?: string; // secret key for username
    passwordKey: string;
  } | null;
  note?: string;
}

interface AdminConfig {
  service?: string;
  kubeconfig?: string;
  namespace?: string;
  noCredentials: boolean;
}

// ===== Service Configurations =====

const SERVICES: Record<string, ServiceConfig> = {
  argocd: {
    namespace: 'argocd',
    serviceName: 'argocd-server',
    localPort: 8080,
    remotePort: 80,
    displayName: 'ArgoCD',
    credentials: {
      secret: 'argocd-initial-admin-secret',
      username: 'admin',
      passwordKey: 'password'
    }
  },
  grafana: {
    namespace: 'monitoring',
    serviceName: 'monitoring-kube-prometheus-grafana',
    localPort: 8080,
    remotePort: 80,
    displayName: 'Grafana',
    credentials: {
      secret: 'monitoring-grafana',
      username: 'admin',
      passwordKey: 'admin-password'
    }
  },
  prometheus: {
    namespace: 'monitoring',
    serviceName: 'monitoring-kube-prometheus-prometheus',
    localPort: 9090,
    remotePort: 9090,
    displayName: 'Prometheus',
    credentials: null
  },
  alertmanager: {
    namespace: 'monitoring',
    serviceName: 'monitoring-kube-prometheus-alertmanager',
    localPort: 9093,
    remotePort: 9093,
    displayName: 'Alertmanager',
    credentials: null,
    note: 'Alertmanager may be disabled in some environments'
  },
  longhorn: {
    namespace: 'longhorn-system',
    serviceName: 'longhorn-frontend',
    localPort: 8080,
    remotePort: 80,
    displayName: 'Longhorn UI',
    credentials: null
  },
  minio: {
    namespace: null, // per-deployment
    serviceName: 'minio',
    localPort: 9001,
    remotePort: 9001,
    displayName: 'MinIO Console',
    credentials: {
      secret: 'minio',
      usernameKey: 'root-user',
      passwordKey: 'root-password'
    }
  },
  mailpit: {
    namespace: null, // per-deployment
    serviceName: 'mailpit-http',
    localPort: 8025,
    remotePort: 80,
    displayName: 'Mailpit UI',
    credentials: null,
    note: 'No authentication required (dev/staging only)'
  }
};

// ===== Admin Access Class =====

class AdminAccess {
  private config: AdminConfig;
  private selectedService!: ServiceConfig;
  private selectedServiceKey!: string;
  private namespace!: string;

  constructor(config: AdminConfig) {
    this.config = config;
  }

  async run() {
    try {
      this.printHeader();

      await this.selectKubeconfig();
      await this.verifyClusterConnection();
      await this.selectService();
      await this.selectNamespace();
      await this.verifyContext();
      await this.checkServiceExists();
      await this.displayAccessInfo();
      await this.startPortForward();
    } catch (error) {
      console.error(chalk.red('\n✗ Error:'), error instanceof Error ? error.message : error);
      process.exit(1);
    }
  }

  // ===== Kubeconfig Selection =====

  async selectKubeconfig() {
    if (this.config.kubeconfig) {
      // Validate provided kubeconfig
      if (!existsSync(this.config.kubeconfig)) {
        throw new Error(`Kubeconfig file not found: ${this.config.kubeconfig}`);
      }
      process.env.KUBECONFIG = this.config.kubeconfig;
      console.log(chalk.blue(`Using kubeconfig: ${this.config.kubeconfig}\n`));
      return;
    }

    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.yellow('  Select Kubernetes Cluster'));
    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    const kubeconfigs = this.findKubeconfigs();

    if (kubeconfigs.length === 0) {
      throw new Error('No kubeconfig files found in ~/.kube/');
    }

    const currentKubeconfig = process.env.KUBECONFIG || join(process.env.HOME || '~', '.kube', 'config');

    // Check if non-interactive
    if (!process.stdin.isTTY) {
      const config = kubeconfigs.find(k => k.path === currentKubeconfig) || kubeconfigs[0];
      console.log(chalk.yellow(`Non-interactive mode: Using ${config.name}`));
      process.env.KUBECONFIG = config.path;
      return;
    }

    const choices = [
      ...kubeconfigs.map(k => ({
        name: k.path === currentKubeconfig ? `${k.name} ${chalk.green('(current)')}` : k.name,
        value: k.path
      })),
      {
        name: chalk.gray(`Use current KUBECONFIG (${process.env.KUBECONFIG || 'not set'})`),
        value: 'current'
      }
    ];

    const selected = await select({
      message: 'Select kubeconfig:',
      choices
    });

    if (selected !== 'current') {
      process.env.KUBECONFIG = selected;
      console.log(chalk.green(`\nUsing kubeconfig: ${selected}`));
    } else if (!process.env.KUBECONFIG) {
      console.log(chalk.yellow('KUBECONFIG not set, using kubectl default'));
    }

    console.log();
  }

  findKubeconfigs(): Array<{ name: string; path: string }> {
    const kubeDir = join(process.env.HOME || '~', '.kube');
    const configs: Array<{ name: string; path: string }> = [];

    if (!existsSync(kubeDir)) {
      return configs;
    }

    // Add default config if exists
    const defaultConfig = join(kubeDir, 'config');
    if (existsSync(defaultConfig)) {
      configs.push({
        name: 'Default (~/.kube/config)',
        path: defaultConfig
      });
    }

    // Find other configs
    const files = readdirSync(kubeDir, { withFileTypes: true });
    for (const file of files) {
      if (file.isFile() && file.name !== 'config' && !file.name.includes('.backup.')) {
        configs.push({
          name: file.name,
          path: join(kubeDir, file.name)
        });
      }
    }

    return configs;
  }

  // ===== Cluster Connection =====

  async verifyClusterConnection() {
    const spinner = ora('Verifying cluster connection...').start();

    try {
      await $`kubectl cluster-info`.quiet();
      const context = await $`kubectl config current-context`.text();
      spinner.succeed(`Connected to cluster: ${chalk.green(context.trim())}`);
    } catch {
      spinner.fail('Cannot connect to cluster');
      throw new Error('Failed to connect to Kubernetes cluster');
    }
  }

  // ===== Service Selection =====

  async selectService() {
    if (this.config.service) {
      const service = SERVICES[this.config.service];
      if (!service) {
        throw new Error(`Unknown service: ${this.config.service}`);
      }
      this.selectedService = service;
      this.selectedServiceKey = this.config.service;
      console.log(chalk.blue(`Selected service: ${chalk.green(service.displayName)}\n`));
      return;
    }

    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.yellow('  Select Service'));
    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    // Check if non-interactive
    if (!process.stdin.isTTY) {
      throw new Error('Service must be specified via --service flag in non-interactive mode');
    }

    const choices = Object.entries(SERVICES).map(([key, service]) => ({
      name: `${service.displayName} (${service.namespace || 'per-deployment'})`,
      value: key,
      description: `Port ${service.localPort} → ${service.remotePort}`
    }));

    const selected = await select({
      message: 'Select service to access:',
      choices
    });

    this.selectedService = SERVICES[selected];
    this.selectedServiceKey = selected;
    console.log();
  }

  // ===== Namespace Selection =====

  async selectNamespace() {
    // Use provided namespace if available
    if (this.config.namespace) {
      this.namespace = this.config.namespace;
      console.log(chalk.blue(`Using namespace: ${chalk.green(this.namespace)}\n`));
      return;
    }

    // Use default namespace if service has one
    if (this.selectedService.namespace) {
      this.namespace = this.selectedService.namespace;
      return;
    }

    // Per-deployment service - scan for namespaces
    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.yellow(`  Select Deployment for ${this.selectedService.displayName}`));
    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    const spinner = ora('Scanning namespaces...').start();

    const namespaces = await this.findServiceNamespaces(this.selectedService.serviceName);

    if (namespaces.length === 0) {
      spinner.fail('No deployments found');
      throw new Error(`Service '${this.selectedService.serviceName}' not found in any namespace`);
    }

    spinner.succeed(`Found ${namespaces.length} deployment(s)`);

    // If only one namespace, use it
    if (namespaces.length === 1) {
      this.namespace = namespaces[0];
      console.log(chalk.green(`Using deployment: ${this.namespace}\n`));
      return;
    }

    // Check if non-interactive
    if (!process.stdin.isTTY) {
      this.namespace = namespaces[0];
      console.log(chalk.yellow(`Non-interactive mode: Using ${this.namespace}\n`));
      return;
    }

    // Interactive selection
    const currentNs = await this.getCurrentNamespace();
    const choices = namespaces.map(ns => ({
      name: ns === currentNs ? `${ns} ${chalk.green('(current)')}` : ns,
      value: ns
    }));

    this.namespace = await select({
      message: 'Select deployment:',
      choices
    });

    console.log();
  }

  async findServiceNamespaces(serviceName: string): Promise<string[]> {
    try {
      const allNamespaces = await $`kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'`.text();
      const namespaceList = allNamespaces.trim().split(/\s+/);

      const found: string[] = [];
      for (const ns of namespaceList) {
        try {
          await $`kubectl get svc -n ${ns} ${serviceName}`.quiet();
          found.push(ns);
        } catch {
          // Service not in this namespace
        }
      }

      return found;
    } catch {
      return [];
    }
  }

  async getCurrentNamespace(): Promise<string> {
    try {
      const ns = await $`kubectl config view --minify --output jsonpath='{..namespace}'`.text();
      return ns.trim() || 'default';
    } catch {
      return 'default';
    }
  }

  // ===== Context Verification =====

  async verifyContext() {
    // Skip if namespace was explicitly provided or kubeconfig was specified
    if (this.config.namespace || this.config.kubeconfig) {
      return;
    }

    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.yellow('  Context Verification'));
    console.log(chalk.yellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    const context = await $`kubectl config current-context`.text();
    console.log(`Current context: ${chalk.green(context.trim())}\n`);

    // Check if non-interactive
    if (!process.stdin.isTTY) {
      console.log(chalk.yellow('Non-interactive mode: Continuing with current context\n'));
      return;
    }

    const confirmed = await confirm({
      message: 'Continue with this context?',
      default: true
    });

    if (!confirmed) {
      console.log(chalk.blue('\nAvailable contexts:'));
      const contexts = await $`kubectl config get-contexts`.text();
      console.log(contexts);
      console.log(chalk.yellow('\nTo switch context, use:'));
      console.log('  kubectl config use-context <context-name>\n');
      process.exit(0);
    }

    console.log();
  }

  // ===== Service Check =====

  async checkServiceExists() {
    const spinner = ora(`Checking service '${this.selectedService.serviceName}'...`).start();

    try {
      await $`kubectl get svc ${this.selectedService.serviceName} -n ${this.namespace}`.quiet();
      spinner.succeed('Service found');
    } catch {
      spinner.fail('Service not found');
      console.log(chalk.red(`\nService '${this.selectedService.serviceName}' not found in namespace '${this.namespace}'`));
      console.log(chalk.blue('\nCheck if service is deployed:'));
      console.log(`  kubectl get svc -n ${this.namespace}\n`);
      throw new Error('Service not found');
    }
  }

  // ===== Credentials =====

  async displayAccessInfo() {
    console.log(chalk.blue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.blue(`  ${this.selectedService.displayName} Access`));
    console.log(chalk.blue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    if (this.selectedService.note) {
      console.log(chalk.yellow(`Note: ${this.selectedService.note}\n`));
    }

    if (!this.config.noCredentials && this.selectedService.credentials) {
      await this.extractAndDisplayCredentials();
    }

    const url = `http://localhost:${this.selectedService.localPort}`;
    console.log(chalk.green(`URL: ${url}\n`));
  }

  async extractAndDisplayCredentials() {
    const spinner = ora('Getting credentials...').start();
    const creds = this.selectedService.credentials!;

    try {
      // Get username
      let username = creds.username || 'admin';
      if (creds.usernameKey) {
        try {
          const userResult = await $`kubectl get secret ${creds.secret} -n ${this.namespace} -o jsonpath='{.data.${creds.usernameKey}}'`.text();
          username = Buffer.from(userResult.trim(), 'base64').toString('utf-8');
        } catch {
          username = 'admin';
        }
      }

      // Get password
      let password = 'Not found';
      try {
        const passResult = await $`kubectl get secret ${creds.secret} -n ${this.namespace} -o jsonpath='{.data.${creds.passwordKey}}'`.text();
        password = Buffer.from(passResult.trim(), 'base64').toString('utf-8');
      } catch {
        password = 'Secret not found';
      }

      spinner.stop();

      console.log(`Username: ${chalk.green(username)}`);
      console.log(`Password: ${chalk.green(password)}\n`);
    } catch (error) {
      spinner.fail('Failed to get credentials');
      console.log(chalk.yellow('Could not extract credentials from secret\n'));
    }
  }

  // ===== Port Forward =====

  async startPortForward() {
    console.log(chalk.yellow('Starting port-forward...'));
    console.log(chalk.yellow('Press Ctrl+C to stop\n'));
    console.log(chalk.blue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    const portMapping = `${this.selectedService.localPort}:${this.selectedService.remotePort}`;
    const svcTarget = `svc/${this.selectedService.serviceName}`;

    try {
      // Use execa for better process handling
      const proc = Bun.spawn(
        ['kubectl', 'port-forward', '-n', this.namespace, svcTarget, portMapping],
        {
          stdout: 'inherit',
          stderr: 'inherit',
          stdin: 'inherit'
        }
      );

      // Handle signals for cleanup
      process.on('SIGINT', () => {
        proc.kill();
        console.log(chalk.yellow('\n\nPort-forward stopped'));
        process.exit(0);
      });

      process.on('SIGTERM', () => {
        proc.kill();
        process.exit(0);
      });

      await proc.exited;
    } catch (error) {
      console.error(chalk.red('\nPort-forward failed'));
      throw error;
    }
  }

  // ===== Utility =====

  printHeader() {
    console.log(chalk.bold.blue('\n╔════════════════════════════════════════╗'));
    console.log(chalk.bold.blue('║  Kubernetes Admin Access              ║'));
    console.log(chalk.bold.blue('╚════════════════════════════════════════╝\n'));
  }
}

// ===== CLI Parsing =====

function printHelp() {
  console.log(`
${chalk.bold('Kubernetes Admin Access')}

${chalk.bold('USAGE:')}
  bun scripts/admin.ts [OPTIONS] [SERVICE]

${chalk.bold('OPTIONS:')}
  ${chalk.cyan('--help')}                    Show this help message
  ${chalk.cyan('--service <name>')}          Service to access
  ${chalk.cyan('--kubeconfig <path>')}       Path to kubeconfig file
  ${chalk.cyan('--namespace <name>')}        Namespace (for per-deployment services)
  ${chalk.cyan('--no-credentials')}          Don't display credentials

${chalk.bold('SERVICES:')}
  ${chalk.cyan('argocd')}        ArgoCD UI (port 8080)
  ${chalk.cyan('grafana')}       Grafana UI (port 8080)
  ${chalk.cyan('prometheus')}    Prometheus UI (port 9090)
  ${chalk.cyan('alertmanager')}  Alertmanager UI (port 9093)
  ${chalk.cyan('longhorn')}      Longhorn UI (port 8080)
  ${chalk.cyan('minio')}         MinIO Console (port 9001) - per-deployment
  ${chalk.cyan('mailpit')}       Mailpit UI (port 8025) - per-deployment

${chalk.bold('EXAMPLES:')}
  ${chalk.gray('# Interactive mode')}
  bun scripts/admin.ts

  ${chalk.gray('# Direct service access')}
  bun scripts/admin.ts --service argocd

  ${chalk.gray('# Legacy positional argument')}
  bun scripts/admin.ts argocd

  ${chalk.gray('# Specify kubeconfig')}
  bun scripts/admin.ts --service grafana --kubeconfig ~/.kube/prod

  ${chalk.gray('# Per-deployment service with namespace')}
  bun scripts/admin.ts --service minio --namespace example-production
`);
}

function parseCliArgs(): AdminConfig {
  const { values, positionals } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      help: { type: 'boolean', default: false },
      service: { type: 'string' },
      kubeconfig: { type: 'string' },
      namespace: { type: 'string' },
      'no-credentials': { type: 'boolean', default: false },
    },
    strict: false,
    allowPositionals: true
  });

  if (values.help) {
    printHelp();
    process.exit(0);
  }

  // Support legacy positional argument for service
  let service = values.service;
  if (!service && positionals.length > 0) {
    service = positionals[0];
  }

  return {
    service,
    kubeconfig: values.kubeconfig,
    namespace: values.namespace,
    noCredentials: values['no-credentials'] || false,
  };
}

// ===== Main =====

async function main() {
  const config = parseCliArgs();
  const admin = new AdminAccess(config);
  await admin.run();
}

main();
