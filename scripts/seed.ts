#!/usr/bin/env bun
/**
 * Seed script for MyCure environments
 * Creates a demo organization with 7 role-based user accounts.
 *
 * Usage:
 *   bun scripts/seed.ts --env staging
 *   bun scripts/seed.ts --env preprod
 *   bun scripts/seed.ts --env production --confirm
 *   bun scripts/seed.ts --api-url https://custom-url.example.com
 */

import chalk from "chalk";
import ora from "ora";
import { parseArgs } from "util";

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const ENVS: Record<string, { api: string; cms: string }> = {
  staging: {
    api: "https://hapihub.stg.localfirsthealth.com",
    cms: "https://mycure.stg.localfirsthealth.com",
  },
  preprod: {
    api: "https://hapihub.preprod.localfirsthealth.com",
    cms: "https://mycure.preprod.localfirsthealth.com",
  },
  production: {
    api: "https://hapihub.localfirsthealth.com",
    cms: "https://mycure.localfirsthealth.com",
  },
};

function printUsage() {
  console.log(`
${chalk.bold("MyCure Seed Script")}
Creates a demo organization with 7 role-based user accounts.

${chalk.yellow("Usage:")}
  bun scripts/seed.ts --env <environment>
  bun scripts/seed.ts --api-url <url>

${chalk.yellow("Options:")}
  --env       Target environment: ${Object.keys(ENVS).join(", ")}
  --api-url   Override API URL (skips env lookup)
  --confirm   Required when targeting production
  --help      Show this help message

${chalk.yellow("Examples:")}
  bun scripts/seed.ts --env staging
  bun scripts/seed.ts --env production --confirm
  mise run seed -- --env preprod
`);
}

const { values: args } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    env: { type: "string" },
    "api-url": { type: "string" },
    confirm: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
  strict: true,
});

if (args.help) {
  printUsage();
  process.exit(0);
}

let API_URL: string;
let CMS_URL: string;

if (args["api-url"]) {
  API_URL = args["api-url"];
  CMS_URL = "(custom)";
} else if (args.env) {
  const env = ENVS[args.env];
  if (!env) {
    console.error(chalk.red(`Unknown environment: ${args.env}`));
    console.error(`Valid options: ${Object.keys(ENVS).join(", ")}`);
    process.exit(1);
  }
  if (args.env === "production" && !args.confirm) {
    console.error(chalk.red("Production requires --confirm flag"));
    process.exit(1);
  }
  API_URL = env.api;
  CMS_URL = env.cms;
} else {
  printUsage();
  process.exit(1);
}

const PASSWORD = "Mycure123";

// ---------------------------------------------------------------------------
// Role → privilege mapping (from @lfh/sdk organizations/constants)
// ---------------------------------------------------------------------------

const ROLE_PRIVILEGES: Record<string, string[]> = {
  admin: [
    "members", "org_configs", "partners", "analytics", "activityLogsRead",
    "attendanceRead", "attendanceWrite", "attendanceOpen", "attendanceClose",
    "mf_patientCreate", "mf_patientRead", "mf_patientUpdate",
    "queue_remove", "queue_items", "queue_ops", "queue_create", "queueMonitor",
    "mf_registrationKiosk", "aptmnt_items",
    "med_recordsRead", "frm_templatesRead", "med_recordsAnalytics",
    "mf_encounters",
    "bl_invoices", "bl_invoiceItems", "bl_payments", "mf_services",
    "bl_expenses", "bl_soas", "bl_analytics", "bl_reports",
    "wh_products", "wh_productTypes", "wh_productCategories",
    "wh_purchases", "wh_transfers", "wh_receiving", "wh_adjustments",
    "wh_packaging", "wh_stockAdjustmentReasons", "wh_reports", "wh_suppliers", "wh_pos",
    "pharmacy_reports",
    "lis_testsRead", "lis_ordersRead", "lis_resultsRead", "lis_analyzersRead",
    "lis_ordersUpdateFinalized", "lis_analytics",
    "ris_testsRead", "ris_ordersRead", "ris_resultsRead",
    "ris_ordersUpdateFinalized", "ris_analytics",
    "insurance_contractsRead", "insurance_contractsUpdate",
    "mf_dentalFixtures", "mf_reports", "sms_send",
  ],
  doctor: [
    "mf_patientRead", "queue_items", "queue_ops", "queueMonitor",
    "aptmnt_items", "med_records", "frm_templates", "med_recordsAnalytics",
    "mf_encounters", "bl_invoices", "bl_invoiceItems",
    "lis_testsRead", "lis_ordersRead", "lis_resultsRead",
    "ris_testsRead", "ris_ordersRead", "ris_resultsRead",
    "mf_dentalFixtures",
  ],
  nurse: [
    "mf_patientCreate", "mf_patientRead", "mf_patientUpdate",
    "queue_items", "queueMonitor", "mf_registrationKiosk", "aptmnt_items",
    "med_records", "frm_templates", "med_recordsAnalytics",
    "mf_encounters", "bl_invoices", "bl_invoiceItems", "bl_paymentsRead",
    "mf_servicesRead",
    "lis_testsRead", "lis_ordersRead", "lis_resultsRead",
    "ris_testsRead", "ris_ordersRead", "ris_resultsRead",
    "mf_dentalFixtures",
  ],
  billing: [
    "mf_patientRead",
    "bl_invoices", "bl_invoiceItems", "bl_payments", "bl_expenses",
    "mf_encounters", "mf_servicesRead", "queue_items",
  ],
  med_tech: [
    "mf_patientRead", "queue_items", "queueMonitor", "aptmnt_items",
    "mf_encountersRead",
    "bl_invoicesRead", "bl_invoiceItemsRead", "bl_paymentsRead",
    "lis_testsRead", "lis_orders", "lis_results",
    "lis_printClaimStub", "lis_printResults",
    "lis_ordersSendout", "lis_ordersComplete", "lis_ordersVerify",
  ],
  radiologic_tech: [
    "mf_patientRead", "queue_items", "queueMonitor", "aptmnt_items",
    "mf_encountersRead",
    "bl_invoicesRead", "bl_paymentsRead",
    "ris_testsRead", "frm_templatesRead",
    "ris_orders", "ris_results",
    "ris_ordersSendout", "ris_ordersComplete", "ris_ordersVerify",
  ],
};

// ---------------------------------------------------------------------------
// User definitions
// ---------------------------------------------------------------------------

interface SeedUser {
  email: string;
  name: string;
  roleId: string | null;
  superadmin: boolean;
}

const USERS: SeedUser[] = [
  { email: "superadmin@mycure.test", name: "Super Admin",    roleId: null,              superadmin: true },
  { email: "admin@mycure.test",      name: "Org Admin",      roleId: "admin",           superadmin: false },
  { email: "doctor@mycure.test",     name: "Dr. Juan Cruz",  roleId: "doctor",          superadmin: false },
  { email: "nurse@mycure.test",      name: "Maria Santos",   roleId: "nurse",           superadmin: false },
  { email: "cashier@mycure.test",    name: "Ana Reyes",      roleId: "billing",         superadmin: false },
  { email: "laboratory@mycure.test", name: "Lab Tech",       roleId: "med_tech",        superadmin: false },
  { email: "imaging@mycure.test",    name: "Imaging Tech",   roleId: "radiologic_tech", superadmin: false },
];

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

let sessionCookie = "";

async function api(
  method: string,
  path: string,
  body?: unknown,
): Promise<unknown> {
  const url = `${API_URL}${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (sessionCookie) headers["Cookie"] = sessionCookie;

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
    redirect: "manual",
  });

  // Capture set-cookie for session
  const setCookie = res.headers.getSetCookie?.() ?? [];
  for (const c of setCookie) {
    if (c.startsWith("better-auth.session_token=") || c.startsWith("__Secure-better-auth.session_token=")) {
      sessionCookie = c.split(";")[0];
    }
  }

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${path} → ${res.status}: ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

// ---------------------------------------------------------------------------
// Seed logic
// ---------------------------------------------------------------------------

async function signUp(email: string, password: string, name: string) {
  return (await api("POST", "/auth/sign-up/email", {
    email,
    password,
    name,
  })) as { user?: { id: string }; token?: string };
}

async function signIn(email: string, password: string) {
  return (await api("POST", "/auth/sign-in/email", {
    email,
    password,
  })) as { user?: { id: string }; token?: string };
}

async function createOrganization(name: string, type: string) {
  return (await api("POST", "/organizations", {
    name,
    type,
    description: "MyCure demo clinic for staging verification",
  })) as { id?: string };
}

async function createMember(
  uid: string,
  organization: string,
  user: SeedUser,
) {
  const privileges: Record<string, boolean> = {};

  if (user.superadmin) {
    privileges.superadmin = true;
  } else if (user.roleId && ROLE_PRIVILEGES[user.roleId]) {
    for (const priv of ROLE_PRIVILEGES[user.roleId]) {
      privileges[priv] = true;
    }
  }

  const body: Record<string, unknown> = {
    uid,
    organization,
    roles: user.superadmin ? ["admin"] : user.roleId ? [user.roleId] : [],
    superadmin: user.superadmin,
    admin: user.superadmin || user.roleId === "admin",
    ...privileges,
  };

  return api("POST", "/organization-members", body);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  console.log(`\n${chalk.bold("MyCure Seed Script")}`);
  console.log(`${chalk.gray("API:")} ${API_URL}\n`);

  // Step 1: Sign up all users
  const spinner = ora("Creating user accounts...").start();
  const userIds: Record<string, string> = {};

  for (let i = 0; i < USERS.length; i++) {
    const user = USERS[i];
    if (i > 0) await new Promise((r) => setTimeout(r, 2000));
    spinner.text = `Creating ${user.email}...`;
    try {
      sessionCookie = "";
      const result = await signUp(user.email, PASSWORD, user.name);
      userIds[user.email] = result.user?.id ?? "";
    } catch (err: unknown) {
      const msg = (err as Error).message;
      if (msg.includes("already exists") || msg.includes("UNIQUE") || msg.includes("duplicate")) {
        sessionCookie = "";
        const signInResult = await signIn(user.email, PASSWORD);
        userIds[user.email] = signInResult.user?.id ?? "";
      } else if (msg.includes("429")) {
        spinner.text = `Rate limited on ${user.email}, waiting 10s...`;
        await new Promise((r) => setTimeout(r, 10000));
        i--;
        continue;
      } else {
        spinner.fail(`Failed: ${user.email}: ${msg}`);
        process.exit(1);
      }
    }
  }
  spinner.succeed(`Created ${Object.keys(userIds).length} user accounts`);

  // Step 2: Sign in as superadmin
  const authSpinner = ora("Signing in as superadmin...").start();
  sessionCookie = "";
  await signIn("superadmin@mycure.test", PASSWORD);
  authSpinner.succeed("Authenticated as superadmin");

  // Step 3: Create organization
  const orgSpinner = ora("Creating organization...").start();
  let orgId: string;
  try {
    const org = await createOrganization("MyCure Demo Clinic", "facility");
    orgId = org.id ?? "";
    orgSpinner.succeed(`Organization created (${orgId})`);
  } catch (err: unknown) {
    const msg = (err as Error).message;
    orgSpinner.warn(`Create failed: ${msg}`);
    console.log(chalk.gray("   Looking for existing org..."));
    const orgs = (await api("GET", "/organizations?name=MyCure Demo Clinic")) as
      { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const orgList = Array.isArray(orgs) ? orgs : orgs.data ?? [];
    if (orgList.length > 0) {
      orgId = orgList[0].id;
      console.log(chalk.green(`   Found existing org (${orgId})`));
    } else {
      console.error(chalk.red("   Could not find or create organization. Aborting."));
      process.exit(1);
    }
  }

  // Step 4: Create organization members
  const memberSpinner = ora("Creating organization members...").start();
  for (const user of USERS) {
    const uid = userIds[user.email];
    if (!uid) {
      memberSpinner.warn(`${user.email}: no user ID, skipping`);
      continue;
    }
    memberSpinner.text = `Adding ${user.email}...`;
    try {
      await createMember(uid, orgId!, user);
    } catch (err: unknown) {
      const msg = (err as Error).message;
      if (!(msg.includes("duplicate") || msg.includes("UNIQUE") || msg.includes("already"))) {
        memberSpinner.fail(`${user.email}: ${msg}`);
        process.exit(1);
      }
    }
  }
  memberSpinner.succeed("All members assigned");

  // Summary
  console.log(`\n${"=".repeat(64)}`);
  console.log(chalk.bold("SEED COMPLETE"));
  console.log(`${"=".repeat(64)}`);
  console.log(`\n${chalk.gray("Organization:")} MyCure Demo Clinic (${orgId!})`);
  console.log(`\n${chalk.gray("Accounts")} (password: ${chalk.yellow(PASSWORD)}):`);
  console.log("-".repeat(64));
  console.log(
    `${"Email".padEnd(32)} ${"Role".padEnd(18)} ${"Privileges"}`,
  );
  console.log("-".repeat(64));
  for (const user of USERS) {
    const role = user.superadmin ? "superadmin" : user.roleId ?? "—";
    const privCount = user.superadmin
      ? "ALL"
      : String(ROLE_PRIVILEGES[user.roleId!]?.length ?? 0);
    console.log(
      `${user.email.padEnd(32)} ${role.padEnd(18)} ${privCount}`,
    );
  }
  console.log("-".repeat(64));
  console.log(`\n${chalk.gray("Login at:")} ${CMS_URL}`);
}

main().catch((err) => {
  console.error(chalk.red("\nFatal error:"), err);
  process.exit(1);
});
