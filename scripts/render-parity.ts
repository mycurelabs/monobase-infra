#!/usr/bin/env bun
/**
 * Render-Parity Script — Migration Safety Net
 *
 * Captures deterministic `helm template` output for every chart × deployment
 * combination, both before and after structural refactors. Diffs the two trees
 * to verify a migration produces functionally identical Kubernetes manifests.
 *
 * Designed for the migrate/medicard-shape branch but reusable for any future
 * structural change.
 *
 * Usage:
 *   bun scripts/render-parity.ts --mode=before
 *   bun scripts/render-parity.ts --mode=after
 *   bun scripts/render-parity.ts --diff
 *
 * Output layout:
 *   rendered/<mode>/_apps/<env>.yaml            # ApplicationSet/Application render per env
 *   rendered/<mode>/_infra.yaml                 # infrastructure ArgoCD apps render
 *   rendered/<mode>/<env>/<chart>.yaml          # per-chart render with deployment values
 *   rendered/<mode>/_infra/<chart>.yaml         # per-chart render with infrastructure values
 */

import { $ } from "bun";
import chalk from "chalk";
import { parseArgs } from "util";
import { existsSync, mkdirSync, readdirSync, statSync, rmSync } from "fs";
import { join, basename } from "path";

const REPO_ROOT = process.cwd();
const RENDERED = join(REPO_ROOT, "rendered");

interface Args {
  mode: "before" | "after" | undefined;
  diff: boolean;
}

function parseCliArgs(): Args {
  const { values } = parseArgs({
    args: process.argv.slice(2),
    options: {
      mode: { type: "string" },
      diff: { type: "boolean", default: false },
    },
    strict: false,
  });
  const mode = values.mode as Args["mode"];
  if (!values.diff && mode !== "before" && mode !== "after") {
    console.error(chalk.red("error:") + " must pass --mode=before|after or --diff");
    process.exit(2);
  }
  return { mode, diff: Boolean(values.diff) };
}

function listLocalCharts(): string[] {
  const charts: string[] = [];
  for (const entry of readdirSync(join(REPO_ROOT, "charts"))) {
    const p = join(REPO_ROOT, "charts", entry);
    if (statSync(p).isDirectory() && existsSync(join(p, "Chart.yaml"))) {
      charts.push(entry);
    }
  }
  return charts.sort();
}

function listDeployments(): string[] {
  const deployments: string[] = [];
  const dir = join(REPO_ROOT, "values", "deployments");
  if (!existsSync(dir)) return deployments;
  for (const entry of readdirSync(dir)) {
    if (!entry.endsWith(".yaml")) continue;
    if (entry.startsWith("example-")) continue;
    deployments.push(entry.replace(/\.yaml$/, ""));
  }
  return deployments.sort();
}

function findArgoApplicationsChart(): string | null {
  // The applications "chart" lives in argocd/applications/ pre-migration
  // and in charts/argocd-applications/ post-migration. Return whichever exists.
  const candidates = [
    join(REPO_ROOT, "charts", "argocd-applications"),
    join(REPO_ROOT, "argocd", "applications"),
  ];
  return candidates.find((p) => existsSync(join(p, "Chart.yaml"))) ?? null;
}

function findArgoInfrastructureChart(): string | null {
  const candidates = [
    join(REPO_ROOT, "charts", "argocd-infrastructure"),
    join(REPO_ROOT, "argocd", "infrastructure"),
  ];
  return candidates.find((p) => existsSync(join(p, "Chart.yaml"))) ?? null;
}

const REPO_URL = "https://github.com/mycurelabs/monobase-infra.git";

async function ensureChartDeps(chartPath: string): Promise<void> {
  // Charts with `dependencies:` in Chart.yaml need a one-time `helm dependency build`
  // before `helm template` can succeed. Idempotent — skips when charts/ subdir already populated.
  const chartFile = join(chartPath, "Chart.yaml");
  if (!existsSync(chartFile)) return;
  const content = await Bun.file(chartFile).text();
  if (!/^dependencies:\s*$/m.test(content) && !/^dependencies:\s*\n\s+-/m.test(content)) return;
  // Skip if charts/ subdir already has tgz files from a prior run
  const depDir = join(chartPath, "charts");
  if (existsSync(depDir) && readdirSync(depDir).some((f) => f.endsWith(".tgz"))) return;
  await $`helm dependency build ${chartPath}`.nothrow().quiet();
}

async function helmTemplate(
  release: string,
  chartPath: string,
  valuesFiles: string[],
  outFile: string,
): Promise<{ ok: boolean; stderr: string }> {
  await ensureChartDeps(chartPath);
  const args = ["template", release, chartPath, "--include-crds", "--set", `argocd.repoURL=${REPO_URL}`];
  for (const vf of valuesFiles) args.push("-f", vf);
  const result = await $`helm ${args}`.nothrow().quiet();
  if (result.exitCode !== 0) {
    return { ok: false, stderr: result.stderr.toString() };
  }
  await Bun.write(outFile, result.stdout);
  return { ok: true, stderr: "" };
}

async function render(mode: "before" | "after"): Promise<void> {
  const outRoot = join(RENDERED, mode);
  if (existsSync(outRoot)) rmSync(outRoot, { recursive: true });
  mkdirSync(outRoot, { recursive: true });

  const charts = listLocalCharts();
  const deployments = listDeployments();
  const infraValues = join(REPO_ROOT, "values", "infrastructure", "main.yaml");
  const appsChart = findArgoApplicationsChart();
  const infraChart = findArgoInfrastructureChart();

  console.log(chalk.cyan(`▸ mode=${mode}`));
  console.log(chalk.dim(`  charts=${charts.length} deployments=${deployments.length}`));
  console.log(chalk.dim(`  apps-chart=${appsChart ?? "(missing)"}`));
  console.log(chalk.dim(`  infra-chart=${infraChart ?? "(missing)"}`));

  let ok = 0;
  let fail = 0;
  const failures: string[] = [];

  // 1. ApplicationSet renders per deployment
  mkdirSync(join(outRoot, "_apps"), { recursive: true });
  if (appsChart) {
    for (const env of deployments) {
      const envValues = join(REPO_ROOT, "values", "deployments", `${env}.yaml`);
      const out = join(outRoot, "_apps", `${env}.yaml`);
      const r = await helmTemplate("apps", appsChart, [envValues], out);
      if (r.ok) ok++;
      else { fail++; failures.push(`apps/${env}: ${r.stderr.split("\n")[0]}`); }
    }
  }

  // 2. Infrastructure ArgoCD apps render
  if (infraChart && existsSync(infraValues)) {
    const out = join(outRoot, "_infra.yaml");
    const r = await helmTemplate("infra", infraChart, [infraValues], out);
    if (r.ok) ok++;
    else { fail++; failures.push(`infra: ${r.stderr.split("\n")[0]}`); }
  }

  // 3. Per-chart × per-deployment renders (catches any chart-level changes
  //    independent of ApplicationSet structure).
  for (const env of deployments) {
    const envOut = join(outRoot, env);
    mkdirSync(envOut, { recursive: true });
    const envValues = join(REPO_ROOT, "values", "deployments", `${env}.yaml`);
    for (const chart of charts) {
      if (chart.startsWith("argocd-")) continue; // covered by _apps/_infra above
      const out = join(envOut, `${chart}.yaml`);
      const r = await helmTemplate(
        chart,
        join(REPO_ROOT, "charts", chart),
        [envValues],
        out,
      );
      if (r.ok) ok++;
      else { fail++; failures.push(`${env}/${chart}: ${r.stderr.split("\n")[0]}`); }
    }
  }

  // 4. Per-chart renders against infrastructure values (catches infra chart drift).
  //    Only argocd-bootstrap and argocd-infrastructure consume main.yaml directly.
  //    argocd-applications consumes deployment-values (covered by step 1 _apps/).
  if (existsSync(infraValues)) {
    const infraOut = join(outRoot, "_infra");
    mkdirSync(infraOut, { recursive: true });
    for (const chart of charts) {
      if (chart !== "argocd-bootstrap" && chart !== "argocd-infrastructure") continue;
      const out = join(infraOut, `${chart}.yaml`);
      const r = await helmTemplate(
        chart,
        join(REPO_ROOT, "charts", chart),
        [infraValues],
        out,
      );
      if (r.ok) ok++;
      else { fail++; failures.push(`_infra/${chart}: ${r.stderr.split("\n")[0]}`); }
    }
  }

  console.log(chalk.green(`✓ rendered ${ok} OK`) + (fail ? chalk.yellow(`, ${fail} failed`) : ""));
  if (fail) {
    console.log(chalk.yellow("first 20 failures:"));
    for (const f of failures.slice(0, 20)) console.log(chalk.dim("  " + f));
  }
}

async function diff(): Promise<void> {
  const before = join(RENDERED, "before");
  const after = join(RENDERED, "after");
  if (!existsSync(before) || !existsSync(after)) {
    console.error(chalk.red("error:") + " run with --mode=before and --mode=after first");
    process.exit(2);
  }
  // Single recursive diff; preserves filenames and quiets noise via -q for summary.
  const summary = await $`diff -qr ${before} ${after}`.nothrow().quiet();
  if (summary.exitCode === 0) {
    console.log(chalk.green("✓ rendered/before and rendered/after are byte-identical"));
    return;
  }
  console.log(chalk.yellow("differing files:"));
  console.log(summary.stdout.toString());
  console.log(chalk.dim("for detailed unified diff: diff -ur rendered/before rendered/after"));
  process.exit(1);
}

const args = parseCliArgs();
if (args.diff) {
  await diff();
} else if (args.mode) {
  await render(args.mode);
}
