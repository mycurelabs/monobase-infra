#!/usr/bin/env bun
/**
 * Secrets Management CLI
 * Provider-agnostic secrets management with GCP implementation
 */

import { parseArgs } from "util";
import { existsSync } from "fs";
import { join, resolve } from "path";
import { glob } from "glob";
import {
  intro,
  outro,
  log,
  logError,
  logInfo,
  logWarning,
  logSuccess,
  promptSelect,
  promptText,
  promptPassword,
  promptConfirm,
  clack,
} from "@/lib/prompts";
import { generatePassword, generateKey } from "@/lib/utils";
import { parseSecretsFile, resolveTargetNamespace } from "@/secrets/parser";
import { GCPProvider } from "@/secrets/providers/gcp";
import { generateClusterSecretStoreFile } from "@/secrets/generators/clustersecretstore";
import { generateExternalSecretFiles } from "@/secrets/generators/externalsecret";
import { setupGCPInfrastructure } from "@/secrets/gcp-setup";
import { setupKubernetesInfrastructure } from "@/secrets/k8s-setup";
import { setupTLSInfrastructure } from "@/secrets/tls-setup";
import { validateCluster } from "@/secrets/validate-cluster";
import type { ParsedSecretsFile, SecretKey } from "@/secrets/types";

// Parse command-line arguments
const { values, positionals } = parseArgs({
  args: process.argv.slice(2),
  options: {
    provider: { type: "string", short: "p", default: "gcp" },
    project: { type: "string" },
    kubeconfig: { type: "string" },
    "dry-run": { type: "boolean", default: false },
    full: { type: "boolean", default: false },
    help: { type: "boolean", short: "h" },
  },
  allowPositionals: true,
});

const command = positionals[0] || "help";

// Show help
if (values.help || command === "help") {
  console.log(`
Secrets Management CLI

Usage: bun scripts/secrets.ts <command> [options]

Commands:
  setup           Complete secrets setup (GCP + K8s + manifests)
  setup --full    Full infrastructure setup (GCP SA + K8s + TLS + manifests)
  generate        Generate ExternalSecret manifests only
  validate        Validate secrets.yaml files
  validate-cluster  Validate cluster state (ExternalSecrets synced)

Options:
  -p, --provider <name>   Provider name (default: gcp)
  --project <id>          GCP project ID (env: GCP_PROJECT_ID)
  --kubeconfig <path>     Path to kubeconfig (env: KUBECONFIG)
  --full                  Full setup including infrastructure bootstrapping
  --dry-run               Show what would be done without making changes
  -h, --help              Show this help message

Environment Variables:
  GCP_PROJECT_ID          Default GCP project ID
  KUBECONFIG              Default kubeconfig path

Examples:
  bun scripts/secrets.ts setup --provider gcp --project mc-v4-prod
  bun scripts/secrets.ts setup --full --project mc-v4-prod
  bun scripts/secrets.ts generate --dry-run
  bun scripts/secrets.ts validate
  bun scripts/secrets.ts validate-cluster
  
  # Using environment variables
  export GCP_PROJECT_ID=mc-v4-prod
  bun scripts/secrets.ts setup
`);
  process.exit(0);
}

/**
 * Get configuration from CLI args or environment variables
 */
function getProjectId(): string | undefined {
  return (values.project as string | undefined) || process.env.GCP_PROJECT_ID;
}

function getKubeconfigPath(): string | undefined {
  return (values.kubeconfig as string | undefined) || process.env.KUBECONFIG;
}

/**
 * Find all secrets.yaml files
 */
function findSecretsFiles(): string[] {
  const patterns = [
    "infrastructure/secrets.yaml",
    "deployments/*/secrets.yaml",
  ];

  const files: string[] = [];
  for (const pattern of patterns) {
    const matches = glob.sync(pattern, { cwd: process.cwd() });
    files.push(...matches.map((f) => resolve(f)));
  }

  return files;
}

/**
 * Validate command - check all secrets.yaml files
 */
async function validateCommand() {
  intro("🔍 Validating secrets.yaml files");

  const files = findSecretsFiles();

  if (files.length === 0) {
    logWarning("No secrets.yaml files found");
    process.exit(1);
  }

  logInfo(`Found ${files.length} secrets.yaml files`);

  let hasErrors = false;

  for (const file of files) {
    try {
      const parsed = parseSecretsFile(file);
      logSuccess(`✓ ${file} (${parsed.config.secrets.length} secrets)`);
    } catch (error: any) {
      logError(`✗ ${file}: ${error.message}`);
      hasErrors = true;
    }
  }

  if (hasErrors) {
    outro("❌ Validation failed");
    process.exit(1);
  } else {
    outro("✅ All secrets.yaml files are valid");
  }
}

/**
 * Generate command - create ExternalSecret manifests
 */
async function generateCommand() {
  intro("📝 Generating ExternalSecret manifests");

  // Get GCP project ID from CLI args, env vars, or prompt
  let projectId = getProjectId();
  if (!projectId) {
    projectId = await promptText({
      message: "GCP Project ID:",
      placeholder: "mc-v4-prod",
      validate: (value) => (value ? undefined : "Project ID is required"),
    });
  }

  const provider = new GCPProvider(projectId);

  // Find and parse secrets files
  const files = findSecretsFiles();
  if (files.length === 0) {
    logWarning("No secrets.yaml files found");
    process.exit(1);
  }

  const parsed = files.map((f) => parseSecretsFile(f));

  // Generate ClusterSecretStore
  const clusterSecretStorePath = "infrastructure/external-secrets/gcp-secretstore.yaml";

  if (values["dry-run"]) {
    logInfo(`[DRY RUN] Would generate: ${clusterSecretStorePath}`);
  } else {
    generateClusterSecretStoreFile(provider, "gcp-secretstore", clusterSecretStorePath);
  }

  // Generate ExternalSecrets
  const externalsecrets: Array<{
    secret: any;
    namespace: string;
    outputPath: string;
  }> = [];

  for (const file of parsed) {
    for (const secret of file.config.secrets) {
      const namespace = resolveTargetNamespace(secret, file.defaultNamespace);
      const outputPath = `infrastructure/external-secrets/${secret.name}-externalsecret.yaml`;

      externalsecrets.push({ secret, namespace, outputPath });

      if (values["dry-run"]) {
        logInfo(`[DRY RUN] Would generate: ${outputPath}`);
      }
    }
  }

  if (!values["dry-run"]) {
    generateExternalSecretFiles(provider, externalsecrets);
  }

  outro(
    values["dry-run"]
      ? "🎯 Dry run complete"
      : `✅ Generated ${externalsecrets.length + 1} manifests`
  );
}

/**
 * Setup command - full secrets setup
 */
async function setupCommand() {
  intro(values.full ? "🔐 Full Infrastructure Setup" : "🔐 Secrets Setup");

  // Get GCP project ID from CLI args, env vars, or prompt
  let projectId = getProjectId();
  if (!projectId) {
    projectId = await promptText({
      message: "GCP Project ID:",
      placeholder: "mc-v4-prod",
      validate: (value) => (value ? undefined : "Project ID is required"),
    });
  }

  const kubeconfigPath = getKubeconfigPath();

  // Phase 1: GCP Infrastructure Setup (if --full and not dry-run)
  if (values.full && !values["dry-run"]) {
    logInfo("\n📦 Phase 1: GCP Infrastructure Setup");
    try {
      const gcpResult = await setupGCPInfrastructure(projectId);
      logSuccess("GCP infrastructure configured");

      // Phase 2: Kubernetes Infrastructure Setup
      logInfo("\n☸️  Phase 2: Kubernetes Infrastructure Setup");
      await setupKubernetesInfrastructure(gcpResult.keyFilePath, kubeconfigPath);
      logSuccess("Kubernetes infrastructure configured");

      // Phase 3: TLS Setup
      logInfo("\n🔒 Phase 3: TLS Setup");
      await setupTLSInfrastructure();
    } catch (error: any) {
      logError(error.message);
      process.exit(1);
    }
  } else if (values.full && values["dry-run"]) {
    logWarning("\n⚠️  Skipping infrastructure setup in dry-run mode");
    logInfo("Infrastructure setup would include:");
    logInfo("  - GCP service account creation");
    logInfo("  - IAM permissions");
    logInfo("  - Service account key generation");
    logInfo("  - Kubernetes namespace and secrets");
    logInfo("  - TLS ClusterIssuer manifests");
  }

  // Phase 4: Secrets Setup
  logInfo(values.full ? "\n🔑 Phase 4: Secrets Setup" : "\n🔑 Secrets Setup");

  const provider = new GCPProvider(projectId);

  // Initialize provider (skip in dry-run mode)
  if (!values["dry-run"]) {
    const spinner = clack.spinner();
    spinner.start("Initializing GCP provider");
    try {
      await provider.initialize();
      spinner.stop("GCP provider initialized");
    } catch (error: any) {
      spinner.stop("Failed to initialize GCP provider");
      logError(error.message);
      process.exit(1);
    }
  } else {
    logInfo("Skipping GCP provider initialization (dry-run mode)");
  }

  // Find and parse secrets files
  const files = findSecretsFiles();
  if (files.length === 0) {
    logWarning("No secrets.yaml files found");
    process.exit(1);
  }

  logInfo(`Found ${files.length} secrets.yaml files`);

  const parsed = files.map((f) => parseSecretsFile(f));

  // In dry-run mode, skip secret checking and creation
  if (values["dry-run"]) {
    logInfo("\n⚠️  Skipping secret checking and creation in dry-run mode");
    
    // Still generate manifests in dry-run
    logInfo("\n📝 Generating manifests");
    await generateCommand();
    outro("🎯 Dry run complete");
    return;
  }

  // Collect all secret keys that need values
  const secretsToCreate: Array<{ remoteKey: string; value: string }> = [];

  for (const file of parsed) {
    logInfo(`\n📁 Processing: ${file.deploymentName}`);

    for (const secret of file.config.secrets) {
      log(`  Secret: ${secret.name}`);

      for (const key of secret.keys) {
        // Check if secret already exists
        const exists = await provider.secretExists(key.remoteKey);

        if (exists) {
          logInfo(`    ✓ ${key.key} (exists)`);
          continue;
        }

        // Generate or prompt for value
        let value: string;

        if (key.generate) {
          // Auto-generate
          if (key.key.includes("password")) {
            value = generatePassword(32);
          } else if (key.key.includes("key")) {
            value = generateKey(32);
          } else {
            value = generatePassword(32);
          }
          logInfo(`    ⚙ ${key.key} (generated)`);
        } else {
          // Prompt for value
          const promptMessage = key.prompt || `Enter value for ${key.key}:`;
          value = await promptPassword({ message: `    ${promptMessage}` });
        }

        secretsToCreate.push({ remoteKey: key.remoteKey, value });
      }
    }
  }

  // Confirm before creating
  if (secretsToCreate.length > 0 && !values["dry-run"]) {
    const confirmed = await promptConfirm({
      message: `Create ${secretsToCreate.length} secrets in GCP?`,
      initialValue: true,
    });

    if (!confirmed) {
      outro("❌ Cancelled");
      process.exit(0);
    }

    // Create secrets
    spinner.start(`Creating ${secretsToCreate.length} secrets`);
    for (const { remoteKey, value } of secretsToCreate) {
      await provider.createSecret(remoteKey, value);
    }
    spinner.stop(`Created ${secretsToCreate.length} secrets`);
  }

  // Generate manifests
  logInfo("\n📝 Generating manifests");
  await generateCommand();

  outro("✅ Setup complete");
}

/**
 * Validate cluster command - check ExternalSecrets sync status
 */
async function validateClusterCommand() {
  intro("☸️  Validating cluster state");

  const kubeconfigPath = getKubeconfigPath();
  
  const { success, results } = await validateCluster(kubeconfigPath);

  if (success) {
    outro("✅ All ExternalSecrets are synced");
  } else {
    outro("❌ Some ExternalSecrets are not synced");
    process.exit(1);
  }
}

// Run command
async function main() {
  try {
    switch (command) {
      case "validate":
        await validateCommand();
        break;
      case "validate-cluster":
        await validateClusterCommand();
        break;
      case "generate":
        await generateCommand();
        break;
      case "setup":
        await setupCommand();
        break;
      default:
        logError(`Unknown command: ${command}`);
        logInfo("Run with --help for usage information");
        process.exit(1);
    }
  } catch (error: any) {
    logError(error.message);
    if (error.stack) {
      console.error(error.stack);
    }
    process.exit(1);
  }
}

main();
