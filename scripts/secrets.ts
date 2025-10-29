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
import type { ParsedSecretsFile, SecretKey } from "@/secrets/types";

// Parse command-line arguments
const { values, positionals } = parseArgs({
  args: process.argv.slice(2),
  options: {
    provider: { type: "string", short: "p", default: "gcp" },
    project: { type: "string" },
    "dry-run": { type: "boolean", default: false },
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
  setup      Complete secrets setup (GCP + K8s + manifests)
  generate   Generate ExternalSecret manifests only
  validate   Validate secrets.yaml files

Options:
  -p, --provider <name>   Provider name (default: gcp)
  --project <id>          GCP project ID
  --dry-run               Show what would be done without making changes
  -h, --help              Show this help message

Examples:
  bun scripts/secrets.ts setup --provider gcp --project mc-v4-prod
  bun scripts/secrets.ts generate --dry-run
  bun scripts/secrets.ts validate
`);
  process.exit(0);
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

  // Get GCP project ID
  let projectId = values.project as string | undefined;
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
  intro("🔐 Secrets Setup");

  // Get GCP project ID
  let projectId = values.project as string | undefined;
  if (!projectId) {
    projectId = await promptText({
      message: "GCP Project ID:",
      placeholder: "mc-v4-prod",
      validate: (value) => (value ? undefined : "Project ID is required"),
    });
  }

  const provider = new GCPProvider(projectId);

  // Initialize provider
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

  // Find and parse secrets files
  const files = findSecretsFiles();
  if (files.length === 0) {
    logWarning("No secrets.yaml files found");
    process.exit(1);
  }

  logInfo(`Found ${files.length} secrets.yaml files`);

  const parsed = files.map((f) => parseSecretsFile(f));

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

// Run command
async function main() {
  try {
    switch (command) {
      case "validate":
        await validateCommand();
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
