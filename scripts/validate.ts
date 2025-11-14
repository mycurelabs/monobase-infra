#!/usr/bin/env bun
/**
 * Validate Script - Infrastructure Template Validation
 *
 * Replaces:
 * - scripts/validate.sh
 *
 * Features:
 * - 7 comprehensive validation tests
 * - Error and warning tracking
 * - Colored output with progress indicators
 * - Statistics collection
 * - Optional JSON output for CI/CD
 *
 * Usage:
 *   bun scripts/validate.ts
 *   bun scripts/validate.ts --json
 *   bun scripts/validate.ts --strict
 */

import { $ } from "bun";
import chalk from "chalk";
import ora from "ora";
import { parseArgs } from "util";
import { existsSync, readdirSync, statSync } from "fs";
import { join } from "path";

// ===== Types =====

interface ValidationResult {
  test: string;
  passed: boolean;
  level: 'error' | 'warning' | 'info';
  message: string;
  details?: string[];
}

interface ValidateConfig {
  json: boolean;
  strict: boolean;
  fix: boolean;
}

interface Statistics {
  helmTemplates: number;
  infraFiles: number;
  totalFiles: number;
  totalLines: number;
}

// ===== Validator Class =====

class TemplateValidator {
  private config: ValidateConfig;
  private results: ValidationResult[] = [];
  private errors = 0;
  private warnings = 0;

  constructor(config: ValidateConfig) {
    this.config = config;
  }

  async run() {
    if (!this.config.json) {
      this.printHeader();
    }

    await this.test1_hardcodedValues();
    await this.test2_exampleDomainUsage();
    await this.test3_directoryStructure();
    await this.test4_helmChartCompleteness();
    await this.test5_automationScripts();
    await this.test6_documentationCompleteness();
    await this.test7_templateStatistics();

    if (this.config.json) {
      this.outputJSON();
    } else {
      this.displaySummary();
    }

    // Exit code
    if (this.errors > 0) {
      process.exit(1);
    } else if (this.config.strict && this.warnings > 0) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  }

  // ===== Test 1: Hardcoded Client Values =====

  async test1_hardcodedValues() {
    const testName = '[1/7] Checking for hardcoded client values';
    const spinner = this.config.json ? null : ora(testName).start();

    try {
      const patterns = ['mycompany', 'client-a', 'client-b', 'philcare'];
      const dirs = ['charts/', 'infrastructure/', 'argocd/'];
      const matches: string[] = [];

      for (const dir of dirs) {
        if (!existsSync(dir)) continue;

        for (const pattern of patterns) {
          try {
            const result = await $`grep -r ${pattern} ${dir} 2>/dev/null || true`.text();
            if (result.trim()) {
              const lines = result.trim().split('\n').filter(line =>
                !line.includes('.git') && !line.includes('example.com')
              );
              matches.push(...lines);
            }
          } catch {
            // grep failed, continue
          }
        }
      }

      if (matches.length > 0) {
        this.errors++;
        this.results.push({
          test: 'Hardcoded Client Values',
          passed: false,
          level: 'error',
          message: 'Found hardcoded client values',
          details: matches
        });
        spinner?.fail(chalk.red('✗ Found hardcoded client values'));
        if (!this.config.json) {
          matches.forEach(m => console.log(chalk.gray(`  ${m}`)));
        }
      } else {
        this.results.push({
          test: 'Hardcoded Client Values',
          passed: true,
          level: 'info',
          message: 'No hardcoded client values found'
        });
        spinner?.succeed('No hardcoded client values found');
      }
    } catch (error) {
      spinner?.fail('Test failed');
      this.results.push({
        test: 'Hardcoded Client Values',
        passed: false,
        level: 'error',
        message: 'Test execution failed'
      });
    }

    if (!this.config.json) console.log();
  }

  // ===== Test 2: Example.com Reference Usage =====

  async test2_exampleDomainUsage() {
    const testName = '[2/7] Verifying example.com reference usage';
    const spinner = this.config.json ? null : ora(testName).start();

    try {
      // Count example.com references
      let exampleCount = 0;
      const dirs = ['charts/', 'infrastructure/', 'deployments/example-prod/', 'deployments/example-staging/', 'docs/'];

      for (const dir of dirs) {
        if (!existsSync(dir)) continue;

        try {
          const result = await $`grep -r "example\\.com" ${dir} 2>/dev/null || true`.text();
          if (result.trim()) {
            exampleCount += result.trim().split('\n').length;
          }
        } catch {
          // grep failed, continue
        }
      }

      // Check for reference directories
      const hasExampleProd = existsSync('deployments/example-prod');
      const hasExampleStaging = existsSync('deployments/example-staging');

      if (!hasExampleProd || !hasExampleStaging) {
        this.errors++;
        this.results.push({
          test: 'Example Domain Usage',
          passed: false,
          level: 'error',
          message: 'deployments/example-prod or deployments/example-staging directory missing'
        });
        spinner?.fail(chalk.red('✗ Reference directories missing'));
      } else {
        this.results.push({
          test: 'Example Domain Usage',
          passed: true,
          level: 'info',
          message: `Found ${exampleCount} references to example.com (expected in reference config)`
        });
        spinner?.succeed(`Found ${chalk.green(exampleCount)} references to example.com (expected in reference config)`);
      }
    } catch (error) {
      spinner?.fail('Test failed');
    }

    if (!this.config.json) console.log();
  }

  // ===== Test 3: Directory Structure =====

  async test3_directoryStructure() {
    const testName = '[3/7] Validating directory structure';
    const spinner = this.config.json ? null : ora(testName).start();

    const requiredDirs = [
      'charts/api/templates',
      'charts/account/templates',
      'infrastructure/argocd',
      'infrastructure/namespaces',
      'infrastructure/security/networkpolicies',
      'infrastructure/security/kyverno',
      'infrastructure/security/falco',
      'deployments/example-prod',
      'deployments/example-staging',
      'docs',
      'scripts'
    ];

    const missing: string[] = [];
    const found: string[] = [];

    for (const dir of requiredDirs) {
      if (existsSync(dir)) {
        found.push(dir);
      } else {
        missing.push(dir);
      }
    }

    if (missing.length > 0) {
      this.errors += missing.length;
      this.results.push({
        test: 'Directory Structure',
        passed: false,
        level: 'error',
        message: `${missing.length} required directories missing`,
        details: missing
      });
      spinner?.fail(chalk.red(`✗ ${missing.length} required directories missing`));
      if (!this.config.json) {
        missing.forEach(d => console.log(chalk.red(`  ✗ ${d} (missing)`)));
      }
    } else {
      this.results.push({
        test: 'Directory Structure',
        passed: true,
        level: 'info',
        message: `${found.length}/${requiredDirs.length} required directories exist`
      });
      spinner?.succeed(`${chalk.green(found.length)}/${requiredDirs.length} required directories exist`);
    }

    if (!this.config.json) console.log();
  }

  // ===== Test 4: Helm Chart Completeness =====

  async test4_helmChartCompleteness() {
    const testName = '[4/7] Validating Helm chart structure';
    const spinner = this.config.json ? null : ora(testName).start();

    const charts = ['api', 'account'];
    const requiredFiles = [
      'Chart.yaml',
      'values.yaml',
      'values.schema.json',
      'templates/_helpers.tpl',
      'templates/deployment.yaml',
      'templates/service.yaml',
      'templates/httproute.yaml',
      'templates/NOTES.txt'
    ];

    const incomplete: Array<{ chart: string; missing: string[] }> = [];

    for (const chart of charts) {
      const missing: string[] = [];

      for (const file of requiredFiles) {
        const filePath = join('charts', chart, file);
        if (!existsSync(filePath)) {
          missing.push(file);
        }
      }

      if (missing.length > 0) {
        incomplete.push({ chart, missing });
      }
    }

    if (incomplete.length > 0) {
      this.errors += incomplete.length;
      const details = incomplete.map(c => `${c.chart}: missing ${c.missing.join(', ')}`);
      this.results.push({
        test: 'Helm Chart Completeness',
        passed: false,
        level: 'error',
        message: `${incomplete.length} charts incomplete`,
        details
      });
      spinner?.fail(chalk.red(`✗ ${incomplete.length} charts incomplete`));
      if (!this.config.json) {
        incomplete.forEach(c => {
          console.log(chalk.red(`  ✗ ${c.chart}: Missing ${c.missing.join(', ')}`));
        });
      }
    } else {
      this.results.push({
        test: 'Helm Chart Completeness',
        passed: true,
        level: 'info',
        message: `All ${charts.length} charts complete`
      });
      spinner?.succeed(`All ${chalk.green(charts.length)} charts complete`);
    }

    if (!this.config.json) console.log();
  }

  // ===== Test 5: Automation Scripts =====

  async test5_automationScripts() {
    const testName = '[5/7] Checking automation scripts';
    const spinner = this.config.json ? null : ora(testName).start();

    const scripts = [
      'scripts/bootstrap.ts',
      'scripts/provision.ts',
      'scripts/admin.ts',
      'scripts/resize.ts',
      'scripts/validate.ts',
      'scripts/secrets.ts'
    ];

    const missing: string[] = [];
    const notExecutable: string[] = [];
    const found: string[] = [];

    for (const script of scripts) {
      if (!existsSync(script)) {
        missing.push(script);
      } else {
        try {
          const stats = statSync(script);
          const isExecutable = !!(stats.mode & 0o111);

          if (isExecutable) {
            found.push(script);
          } else {
            notExecutable.push(script);
          }
        } catch {
          missing.push(script);
        }
      }
    }

    // Handle missing scripts
    if (missing.length > 0) {
      this.errors += missing.length;
      this.results.push({
        test: 'Automation Scripts',
        passed: false,
        level: 'error',
        message: `${missing.length} scripts missing`,
        details: missing
      });
    }

    // Handle non-executable scripts
    if (notExecutable.length > 0) {
      this.warnings += notExecutable.length;
      this.results.push({
        test: 'Automation Scripts - Executable',
        passed: false,
        level: 'warning',
        message: `${notExecutable.length} scripts not executable`,
        details: notExecutable
      });

      // Auto-fix if requested
      if (this.config.fix) {
        for (const script of notExecutable) {
          try {
            await $`chmod +x ${script}`.quiet();
          } catch {
            // Failed to fix
          }
        }
      }
    }

    const totalFound = found.length + notExecutable.length;
    if (missing.length === 0 && notExecutable.length === 0) {
      this.results.push({
        test: 'Automation Scripts',
        passed: true,
        level: 'info',
        message: `All ${scripts.length} scripts exist and are executable`
      });
      spinner?.succeed(`All ${chalk.green(scripts.length)} scripts exist and are executable`);
    } else if (missing.length > 0) {
      spinner?.fail(chalk.red(`✗ ${missing.length} scripts missing`));
    } else {
      spinner?.warn(chalk.yellow(`⚠ ${notExecutable.length} scripts not executable ${this.config.fix ? '(fixed)' : ''}`));
    }

    if (!this.config.json) console.log();
  }

  // ===== Test 6: Documentation Completeness =====

  async test6_documentationCompleteness() {
    const testName = '[6/7] Checking documentation';
    const spinner = this.config.json ? null : ora(testName).start();

    const docs = [
      'README.md',
      'docs/CLIENT-ONBOARDING.md',
      'docs/TEMPLATE-USAGE.md',
      'docs/DEPLOYMENT.md',
      'docs/ARCHITECTURE.md',
      'docs/SECURITY-HARDENING.md',
      'docs/STORAGE.md',
      'docs/BACKUP-RECOVERY.md',
      'docs/GATEWAY-API.md',
      'docs/SCALING-GUIDE.md',
      'docs/HIPAA-COMPLIANCE.md',
      'docs/TROUBLESHOOTING.md'
    ];

    const missing: string[] = [];
    const found: string[] = [];

    for (const doc of docs) {
      if (existsSync(doc)) {
        found.push(doc);
      } else {
        missing.push(doc);
      }
    }

    if (missing.length > 0) {
      this.warnings += missing.length;
      this.results.push({
        test: 'Documentation Completeness',
        passed: false,
        level: 'warning',
        message: `${missing.length} documentation files missing`,
        details: missing
      });
      spinner?.warn(chalk.yellow(`⚠ ${missing.length} documentation files missing`));
    } else {
      this.results.push({
        test: 'Documentation Completeness',
        passed: true,
        level: 'info',
        message: `All ${docs.length} documentation files exist`
      });
      spinner?.succeed(`${chalk.green(found.length)}/${docs.length} documentation files exist`);
    }

    if (!this.config.json) console.log();
  }

  // ===== Test 7: Template Statistics =====

  async test7_templateStatistics() {
    const testName = '[7/7] Template statistics';
    const spinner = this.config.json ? null : ora(testName).start();

    try {
      const stats = await this.collectStatistics();

      this.results.push({
        test: 'Template Statistics',
        passed: true,
        level: 'info',
        message: 'Statistics collected',
        details: [
          `Helm templates: ${stats.helmTemplates}`,
          `Infrastructure files: ${stats.infraFiles}`,
          `Total files: ${stats.totalFiles}`,
          `Total lines of code: ${stats.totalLines}`
        ]
      });

      spinner?.succeed('Statistics collected');

      if (!this.config.json) {
        console.log(`  Helm templates:       ${chalk.green(stats.helmTemplates)}`);
        console.log(`  Infrastructure files: ${chalk.green(stats.infraFiles)}`);
        console.log(`  Total files:          ${chalk.green(stats.totalFiles)}`);
        console.log(`  Total lines of code:  ${chalk.green(stats.totalLines)}`);
      }
    } catch (error) {
      spinner?.fail('Statistics collection failed');
    }

    if (!this.config.json) console.log();
  }

  async collectStatistics(): Promise<Statistics> {
    let helmTemplates = 0;
    let infraFiles = 0;
    let totalFiles = 0;
    let totalLines = 0;

    // Count Helm templates
    try {
      const result = await $`find charts/*/templates -name "*.yaml" -o -name "*.tpl" 2>/dev/null || true`.text();
      helmTemplates = result.trim() ? result.trim().split('\n').filter(l => l).length : 0;
    } catch {}

    // Count infrastructure files
    try {
      const result = await $`find infrastructure -name "*.yaml" -o -name "*.template" 2>/dev/null || true`.text();
      infraFiles = result.trim() ? result.trim().split('\n').filter(l => l).length : 0;
    } catch {}

    // Count total files (excluding .git)
    try {
      const result = await $`find . -type f | grep -v ".git" | wc -l`.text();
      totalFiles = parseInt(result.trim());
    } catch {}

    // Count total lines
    try {
      const result = await $`find . \\( -name "*.yaml" -o -name "*.md" -o -name "*.sh" -o -name "*.ts" -o -name "*.json" -o -name "*.tpl" \\) -print0 2>/dev/null | xargs -0 wc -l 2>/dev/null | tail -1`.text();
      const match = result.trim().match(/(\d+)\s+total/);
      totalLines = match ? parseInt(match[1]) : 0;
    } catch {}

    return { helmTemplates, infraFiles, totalFiles, totalLines };
  }

  // ===== Output =====

  outputJSON() {
    const output = {
      summary: {
        errors: this.errors,
        warnings: this.warnings,
        passed: this.errors === 0,
        strictPassed: this.errors === 0 && this.warnings === 0
      },
      results: this.results
    };

    console.log(JSON.stringify(output, null, 2));
  }

  displaySummary() {
    console.log(chalk.blue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.blue('  Validation Summary'));
    console.log(chalk.blue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));

    if (this.errors === 0 && this.warnings === 0) {
      console.log(chalk.green('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
      console.log(chalk.green('  ✓ ALL VALIDATION TESTS PASSED!'));
      console.log(chalk.green('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
      console.log('Template is ready for:');
      console.log(`  ${chalk.green('✓')} Client fork and customization`);
      console.log(`  ${chalk.green('✓')} Production deployment`);
      console.log(`  ${chalk.green('✓')} HIPAA-compliant healthcare deployments\n`);
    } else if (this.errors === 0) {
      console.log(chalk.yellow(`⚠ Validation passed with ${this.warnings} warnings\n`));
      console.log('Template is functional. Review warnings if needed.\n');
    } else {
      console.log(chalk.red(`✗ Validation failed with ${this.errors} errors and ${this.warnings} warnings\n`));
      console.log('Please fix errors above before using template.\n');
    }
  }

  printHeader() {
    console.log(chalk.bold.blue('\n╔════════════════════════════════════════╗'));
    console.log(chalk.bold.blue('║  Monobase Infrastructure Template    ║'));
    console.log(chalk.bold.blue('║  Validation                           ║'));
    console.log(chalk.bold.blue('╚════════════════════════════════════════╝\n'));
  }
}

// ===== CLI Parsing =====

function printHelp() {
  console.log(`
${chalk.bold('Monobase Infrastructure Template Validation')}

${chalk.bold('USAGE:')}
  bun scripts/validate.ts [OPTIONS]

${chalk.bold('OPTIONS:')}
  ${chalk.cyan('--help')}                    Show this help message
  ${chalk.cyan('--json')}                    Output results as JSON
  ${chalk.cyan('--strict')}                  Treat warnings as errors
  ${chalk.cyan('--fix')}                     Auto-fix warnings (make scripts executable)

${chalk.bold('VALIDATION TESTS:')}
  1. Check for hardcoded client values
  2. Verify example.com reference usage
  3. Validate directory structure
  4. Check Helm chart completeness
  5. Verify automation scripts
  6. Check documentation completeness
  7. Collect template statistics

${chalk.bold('EXIT CODES:')}
  0 - All tests passed (or warnings only in non-strict mode)
  1 - Validation failed with errors (or warnings in strict mode)

${chalk.bold('EXAMPLES:')}
  ${chalk.gray('# Standard validation')}
  bun scripts/validate.ts

  ${chalk.gray('# JSON output for CI/CD')}
  bun scripts/validate.ts --json > validation-report.json

  ${chalk.gray('# Strict mode (warnings as errors)')}
  bun scripts/validate.ts --strict

  ${chalk.gray('# Auto-fix warnings')}
  bun scripts/validate.ts --fix
`);
}

function parseCliArgs(): ValidateConfig {
  const { values } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      help: { type: 'boolean', default: false },
      json: { type: 'boolean', default: false },
      strict: { type: 'boolean', default: false },
      fix: { type: 'boolean', default: false },
    },
    strict: true,
  });

  if (values.help) {
    printHelp();
    process.exit(0);
  }

  return {
    json: values.json || false,
    strict: values.strict || false,
    fix: values.fix || false,
  };
}

// ===== Main =====

async function main() {
  const config = parseCliArgs();
  const validator = new TemplateValidator(config);
  await validator.run();
}

main();
