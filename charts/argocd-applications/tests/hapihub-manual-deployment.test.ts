import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parse, parseAllDocuments, stringify } from "yaml";

// Run from the repository root via mise; all renders are local, never cluster calls.
function render(chart: string, release: string, args: string[] = []) {
  const result = Bun.spawnSync([
    "helm", "template", release, `charts/${chart}`, "--dry-run", ...args,
  ]);
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
  return parseAllDocuments(result.stdout.toString()).map((doc) => {
    if (doc.errors.length) throw doc.errors[0];
    return doc.toJSON();
  }).filter(Boolean);
}

function root(env = "preprod", settings: string[] = []) {
  return render("argocd-applications", "test", [
    "-f", "values/deployments/base.yaml",
    "-f", `values/deployments/mycure-${env}.yaml`,
    "--set", "argocd.repoURL=lint,argocd.targetRevision=lint",
    ...settings.flatMap((setting) => ["--set", setting]),
  ]);
}

function application(docs: any[], suffix: string) {
  const app = docs.find((doc) => doc.kind === "Application" && doc.metadata.name.endsWith(`-${suffix}`));
  expect(app).toBeDefined();
  return app;
}

function child(app: any) {
  const dir = mkdtempSync(join(tmpdir(), "hapihub-manual-deployment-"));
  try {
    const file = join(dir, "values.yaml");
    writeFileSync(file, stringify(app.spec.source.helm.valuesObject));
    return render("hapihub", app.spec.source.helm.releaseName, ["-f", file]);
  } finally {
    rmSync(dir, { recursive: true });
  }
}

function hooks(docs: any[]) {
  return docs.filter((doc) => doc.metadata.annotations?.["argocd.argoproj.io/hook"] === "PreSync");
}

function assertManual(app: any) {
  expect(app.spec.syncPolicy.automated).toBeUndefined();
  expect(app.spec.syncPolicy.retry.limit).toBe(0);
  expect(app.spec.source.helm.valuesObject.manualDeployment).toBe(true);
}

function assertRetainedJobs(docs: any[]) {
  const jobs = hooks(docs).filter((doc) => doc.kind === "Job");
  expect(jobs.map((job) => job.metadata.name).sort()).toEqual([
    "hapihub-migrate", "hapihub-provision-db-roles",
  ]);
  for (const job of jobs) {
    expect(job.spec.backoffLimit).toBe(0);
    expect(job.spec.ttlSecondsAfterFinished).toBeUndefined();
    expect(job.spec.template.spec.restartPolicy).toBe("Never");
    expect(job.metadata.annotations["argocd.argoproj.io/hook-delete-policy"]).toBe("BeforeHookCreation");
    expect(job.metadata.annotations["helm.sh/hook-delete-policy"]).toBe("before-hook-creation");
  }
}

describe("hapihub manualDeployment root and child render contract", () => {
  test("actual preprod opts in for both Applications and retains fail-fast hooks", () => {
    const values = parse(readFileSync("values/deployments/mycure-preprod.yaml", "utf8"));
    expect(values.hapihub.manualDeployment).toBe(true);
    const docs = root();
    for (const suffix of ["hapihub", "hapihub-worker"]) assertManual(application(docs, suffix));
    assertRetainedJobs(child(application(docs, "hapihub")));
    expect(hooks(child(application(docs, "hapihub-worker")))).toEqual([]);
  });

  test("explicit gate true enforces zero retries even over nonzero hook overrides", () => {
    const docs = root("preprod", [
      "hapihub.manualDeployment=true",
      "hapihub.roleSplit.provision.backoffLimit=7",
      "hapihub.roleSplit.migrateJob.backoffLimit=7",
    ]);
    for (const suffix of ["hapihub", "hapihub-worker"]) assertManual(application(docs, suffix));
    assertRetainedJobs(child(application(docs, "hapihub")));
  });

  test("child gate alone retains both Jobs with literal zero backoff", () => {
    const app = application(root(), "hapihub");
    app.spec.source.helm.valuesObject.manualDeployment = true;
    assertRetainedJobs(child(app));
  });

  test("worker cannot override the shared gate or enable duplicate hooks", () => {
    const docs = root("preprod", [
      "hapihub.manualDeployment=true", "hapihubWorker.manualDeployment=false",
      "hapihubWorker.roleSplit.enabled=true",
      "hapihubWorker.roleSplit.provision.enabled=true",
      "hapihubWorker.roleSplit.migrateJob.enabled=true",
    ]);
    const worker = application(docs, "hapihub-worker");
    assertManual(worker);
    expect(worker.spec.source.helm.valuesObject.roleSplit.provision.enabled).toBe(false);
    expect(worker.spec.source.helm.valuesObject.roleSplit.migrateJob.enabled).toBe(false);
    expect(hooks(child(worker))).toEqual([]);
    assertRetainedJobs(child(application(docs, "hapihub")));
  });

  test("provision configuration, provision Job, then migration have one owner", () => {
    const docs = root("preprod", ["hapihub.manualDeployment=true"]);
    const mainHooks = hooks(child(application(docs, "hapihub")));
    expect(mainHooks.map((hook) => [hook.kind, hook.metadata.name,
      hook.metadata.annotations["helm.sh/hook-weight"]]).sort()).toEqual([
      ["ConfigMap", "hapihub-provision-db-roles", "-6"],
      ["Job", "hapihub-migrate", "0"],
      ["Job", "hapihub-provision-db-roles", "-5"],
    ]);
    expect(hooks(child(application(docs, "hapihub-worker")))).toEqual([]);
  });

  for (const gate of ["false", "null"]) {
    test(`gate ${gate === "null" ? "absent" : gate} preserves automation and default hook policy`, () => {
      const docs = root("preprod", [`hapihub.manualDeployment=${gate}`]);
      for (const suffix of ["hapihub", "hapihub-worker"]) {
        const app = application(docs, suffix);
        expect(app.spec.syncPolicy.automated).toEqual({ prune: true, selfHeal: true });
        expect(app.spec.syncPolicy.retry.limit).toBe(5);
        expect(app.spec.source.helm.valuesObject.manualDeployment).toBeUndefined();
      }
      const jobs = hooks(child(application(docs, "hapihub"))).filter((doc) => doc.kind === "Job");
      expect(jobs).toHaveLength(2);
      for (const job of jobs) {
        expect(job.spec.backoffLimit).toBe(job.metadata.name.endsWith("-migrate") ? 0 : 3);
        expect(job.spec.ttlSecondsAfterFinished).toBe(86400);
      }
    });
  }

  test("false and absent render identically; worker cannot opt in independently", () => {
    const absent = root("preprod", ["hapihub.manualDeployment=null"]);
    expect(root("preprod", ["hapihub.manualDeployment=false"])).toEqual(absent);
    expect(root("preprod", ["hapihub.manualDeployment=null", "hapihubWorker.manualDeployment=true"])).toEqual(absent);
  });

  for (const env of ["production", "staging"]) {
    test(`${env} remains automatic with no opt-in`, () => {
      const values = parse(readFileSync(`values/deployments/mycure-${env}.yaml`, "utf8"));
      expect(values.hapihub?.manualDeployment).not.toBe(true);
      const docs = root(env);
      const suffixes = values.hapihubWorker?.enabled ? ["hapihub", "hapihub-worker"] : ["hapihub"];
      for (const suffix of suffixes) {
        const app = application(docs, suffix);
        expect(app.spec.syncPolicy.automated).toEqual({ prune: true, selfHeal: true });
        expect(app.spec.syncPolicy.retry.limit).toBe(5);
        expect(app.spec.source.helm.valuesObject.manualDeployment).toBeUndefined();
      }
      if (!values.hapihubWorker?.enabled) {
        expect(docs.some((doc) => doc.metadata.name.endsWith("-hapihub-worker"))).toBe(false);
      }
    });
  }
});
