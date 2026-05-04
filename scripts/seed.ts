#!/usr/bin/env bun
/**
 * Seed script for MyCure environments
 * Creates a demo organization with 7 role-based user accounts.
 *
 * Usage:
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
  --reset     Delete all existing seed data before re-seeding (idempotent
              wipe of seed users + their memberships + the seed orgs).
              Requires the current PASSWORD to still match what was used
              when superadmin@mycure.test was created. If the password
              has been rotated since the original seed, manually clear
              the seed user from the DB instead.
  --patients  Seed N random demo patients on the PARENT facility only
              (branches share via the parent-child org hierarchy — see
              medical-patients $includeOrganizationChildren). Verbose
              Filipino demographics: name, dob, age, sex, contact, address,
              blood type, vitals (BP, HR, RR, temp), marital status,
              religion, emergency contact, employment, AND insurance cards
              (PhilHealth + private HMO with realistic Maxicare /
              Intellicare / Medicard providers and card numbers).
              Idempotent: each patient gets a deterministic externalId
              (SEED-PATIENT-1-<NNN>) so reruns skip dupes.
              Default: 25 patients on the parent.
              Pass --patients 0 to skip patient seeding entirely.

  --patient-accounts
              Seed Better-Auth user accounts for the first N random
              patients + the fixed demo patient. Each account is tagged
              ['pxp', 'seed', 'patient'] (the 'pxp' tag is hapihub's
              convention for self-claiming patient accounts) and the
              corresponding medical-patient row is PATCHed with
              account=<uid>. Passwords are the same Mycure123! used for
              staff. Default: 5 (= 6 total accounts including the fixed).
              Pass --patient-accounts 0 to skip.

  Services    Always seeded — a fixed catalog (~30 entries) covering all
              7 service types (fee, clinical-consultation, clinical-procedure,
              diagnostic, pe, dental, package) is created in BOTH facilities.
              Idempotent via externalId (SEED-SVC-<type>-<NN>); reruns skip
              existing rows. --reset removes them along with users/orgs.

  Always-on system fixtures (shared installation-wide, no org scope):
    - 15 countries (PH first, ASEAN, US, JP, KR, CA, GB, KSA, UAE)
    - 37 PH address components (17 regions + 20 common provinces)
    - 50 common ICD-10 codes for primary-care / OPD / PE clinic billing
    - 12 PH PRC-recognised health professions (MD, DDS, RN, RPh, etc.)
    - 20 medical specialties (IM, Peds, OBG, Cardio, Endo, etc.)

  Always-on settings seeded into ALL 3 facilities (idempotent, --reset wipes):
    Inventory:
      - Suppliers (5 PH-based pharma / supplies vendors)
      - Adjustment Reasons, Stock Rooms, Product Types
        (org-level JSON arrays, merged with existing)
      - Products: 200 inventory-variants per facility covering all 6
        product types (Medicine, Medical Supplies, Lab Reagent, PPE,
        Office Supply, Equipment) — verbose with realistic PHP unitCost,
        unitPrice, manufacturer, barcode, initialStock, reorderLevel,
        and stockRoom assignment. Refrigerated items (vaccines, insulin)
        go to Cold Storage; lab consumables to Lab Stock Room.
    Billing:
      - Payment Methods (Cash + 6 PH digital/card/cheque options)
      - Tax Types (VAT 12%, VAT 0%, Percentage Tax 3%)
      - Service Providers (doctor/nurse/imaging linked to relevant
        services with reader's-fee commissions, requires --services)
      - Withholding Taxes (doctor 10%, nurse 5%)
    Partners:
      - HMOs (Maxicare, Intellicare, Medicard, PhilCare, etc. — 8)
      - Companies (Ayala, San Miguel, Globe, BDO, etc. — 8)
      - Government (PhilHealth, GSIS, SSS, DOH, PCSO — 5)
      - Diagnostic Centers (Hi-Precision, Healthway, etc. — 5)
    Registration:
      - Queues: hapihub auto-creates 8 defaults per facility when the org
        is flagged with types=clinic (Cashier, End Of Encounter, Front
        Desk, Nurse, Doctor, Laboratory, Imaging X-ray, Imaging Ultrasound).
        On top we add a Procedure Room queue + 3 per-doctor consult queues
        wired with writers=[member::<id>] for the UI's doctor↔queue
        auto-select feature (one queue per seed doctor).
      - Patient Tags (VIP, Senior Citizen, PWD, etc. — 10)
      - Privacy Notices (English + Tagalog kiosk consents)
    EMR:
      - Form Templates: ~30 starter presets imported from the sibling
        mycure repo at ../mycure/apps/mycure/src/pages/emr/. Covers
        med-cert, fit-cert, consent, waiver, questionnaire, general,
        claims. Skipped with a warning if mycure repo isn't checked
        out alongside mycure-infra.
      - Medicines: ~40 PH formulary staples (Paracetamol, Amoxicillin,
        Salbutamol, Metformin, Losartan, Atorvastatin, etc.) per facility
      - Favorite Medicines: prescription combinations (formulation +
        dispense + sig + frequency + note) for ~15 commonly prescribed
        meds — quick-pick for clinicians.
      - Dental Statuses: 19 curated dental-fixture entries (caries,
        missing, RCT, crown, implant, etc.) using the SDK's
        DENTAL_STATUS_TYPES enum.
    Demo charts:
      - 1 fixed demo patient (Pedro Demo Lopez, externalId
        SEED-PATIENT-FIXED-001) with 2 encounters and 9 medical records:
        vitals, chief complaint, HPI, 3 ICD-10 assessments (T2DM E11.9,
        HTN I10, follow-up impression), 2 medication orders (Metformin +
        Losartan starter regimen, then continued at follow-up).
        Always-on. Idempotent on externalId.

    PME:
      - Report Templates: 5 starter presets imported from the sibling
        mycure repo at ../mycure/apps/mycure/src/pages/pme/. If the
        repo is not checked out alongside mycure-infra, this step is
        skipped with a warning (everything else still runs).
    Laboratory (LIS):
      - Sections: Hematology, Chemistry, Microscopy, Immunology, Microbiology
      - Tests: 18 common Filipino-clinic lab tests (CBC, Urinalysis,
        FBS, HbA1c, Lipid Profile, Creatinine, BUN, SGPT, SGOT, etc.)
        with HL7 LOINC codes. Each linked to its section.
      - Measures: ~70 result-form measures across the lab tests
        (CBC has 13 — Hgb/Hct/RBC/MCV/MCH/MCHC/WBC/5-part diff/
        Platelets; UA has 14; Lipid Profile has 6 with TC/HDL/LDL/TG/
        VLDL/ratio; etc.) with PH-clinic reference ranges, units, and
        sex/age scoping per the OpenAPI DiagnosticMeasureReferenceRange
        spec. Result entry forms in /lab/orders pre-fill these fields.
      - Packages: 4 common groupings (Basic Health Screen, Diabetes
        Workup, Kidney+Liver, STD/Hep)
      - Analyzers: 6 stock entries (Sysmex, Beckman, Roche Cobas, etc.)
      - Report Templates: 8 starter presets imported from
        ../mycure/apps/mycure/src/pages/lis/.
    Imaging (RIS):
      - Sections: X-ray, Ultrasound, CT Scan, MRI, Mammography
      - Tests: 12 imaging studies (Chest X-ray, Abdominal UTZ, CT,
        MRI, Mammography) with HL7 LOINC codes.
      - Packages: 3 common groupings (Pre-Employment Imaging,
        Abdominal Workup, Prenatal Imaging)
      - Report Templates: 11 starter presets imported from
        ../mycure/apps/mycure/src/pages/ris/.
  --help      Show this help message

${chalk.yellow("Examples:")}
  bun scripts/seed.ts --env preprod
  bun scripts/seed.ts --env production --confirm
  bun scripts/seed.ts --api-url http://localhost:7500 --reset
  bun scripts/seed.ts --api-url http://localhost:7500 --patients 25
  mise run seed -- --env preprod
`);
}

const { values: args } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    env: { type: "string" },
    "api-url": { type: "string" },
    confirm: { type: "boolean", default: false },
    reset: { type: "boolean", default: false },
    // No default here — DEFAULT_PATIENT_COUNT is applied below if the flag
    // wasn't passed at all (vs. explicitly `--patients 0` to skip).
    patients: { type: "string" },
    // Same convention as --patients — DEFAULT_PATIENT_ACCOUNT_COUNT is
    // the source of truth, parsed below.
    "patient-accounts": { type: "string" },
    help: { type: "boolean", default: false },
  },
  strict: true,
});

// Default patient count: 25 per facility (75 total across the 3 demo orgs).
// Patients are part of a "complete" demo seed alongside services, products,
// partners, etc. — pass --patients 0 to skip, or --patients <N> to override.
const DEFAULT_PATIENT_COUNT = 25;
const PATIENT_COUNT = (() => {
  const raw = args.patients;
  if (raw == null) return DEFAULT_PATIENT_COUNT;
  const n = parseInt(raw, 10);
  if (Number.isNaN(n) || n < 0) return DEFAULT_PATIENT_COUNT;
  return n;
})();

// Patient-account count — see DEFAULT_PATIENT_ACCOUNT_COUNT (set when
// seedPatientAccounts is declared). Same parsing semantics as --patients.
const PATIENT_ACCOUNT_COUNT = (() => {
  const raw = args["patient-accounts"];
  // Default applied here is hardcoded to match DEFAULT_PATIENT_ACCOUNT_COUNT
  // declared further down — the const is referenced here before its
  // declaration in source order, but Bun hoists the binding.
  const FALLBACK = 5;
  if (raw == null) return FALLBACK;
  const n = parseInt(raw, 10);
  if (Number.isNaN(n) || n < 0) return FALLBACK;
  return n;
})();

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

const PASSWORD = "Mycure123!";

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
// Verbose personal-details (mobileNo, dob, sex, address, doctor PRC, etc.)
// are layered on after signup via PATCH /personal-details/{uid} — see
// USER_PROFILES below and seedUserProfiles().

interface SeedUser {
  email: string;
  name: string;
  /**
   * Org-member role ids — match ORGANIZATION_MEMBER_ROLES in
   * packages/sdk/src/organizations/constants/index.ts. Saved on the
   * member row's `roles` array; the UI gates feature visibility on
   * the presence of specific role ids (e.g. PME pages check
   * `roles.includes('doctor_pme')`). The FIRST entry is also the
   * source of the legacy single-role privilege flags via
   * ROLE_PRIVILEGES below.
   */
  roleIds: string[];
  superadmin: boolean;
}

const USERS: SeedUser[] = [
  // Each user gets a primary role + extra roles to unlock more demo
  // features. Picked from the SDK's role registry — clinic_manager,
  // doctor_pme (PE module access), nurse_head (nurse leadership UI),
  // lab_qc (LIS verifier role), imaging_qc (RIS verifier), etc.
  { email: "superadmin@mycure.test", name: "Carlos Tan",      roleIds: ["admin", "clinic_manager"],                        superadmin: true  },
  { email: "admin@mycure.test",      name: "Beatriz Lim",     roleIds: ["admin", "clinic_manager"],                        superadmin: false },
  // Three doctors to demonstrate per-doctor queue + writers wiring.
  // Each gets a different specialty so they map cleanly to their own
  // consultation queue (see seedDoctorQueues below).
  { email: "doctor@mycure.test",     name: "Juan Cruz",       roleIds: ["doctor", "doctor_pme", "medical_head"],            superadmin: false },
  { email: "pedia@mycure.test",      name: "Sofia Reyes",     roleIds: ["doctor"],                                          superadmin: false },
  { email: "familymd@mycure.test",   name: "Mateo Santos",    roleIds: ["doctor"],                                          superadmin: false },
  { email: "nurse@mycure.test",      name: "Maria Santos",    roleIds: ["nurse", "nurse_head", "frontdesk"],                superadmin: false },
  { email: "cashier@mycure.test",    name: "Ana Reyes",       roleIds: ["billing", "billing_encoder", "frontdesk"],         superadmin: false },
  { email: "laboratory@mycure.test", name: "Pedro Bautista",  roleIds: ["med_tech", "lab_tech", "lab_qc"],                  superadmin: false },
  { email: "imaging@mycure.test",    name: "Rosa Villanueva", roleIds: ["radiologic_tech", "imaging_tech", "imaging_qc"],   superadmin: false },
];

// ---------------------------------------------------------------------------
// Verbose user profiles — layered onto personal_details via PATCH after
// signup. The personal_details `id` equals the account `uid`
// (services/hapihub/src/services/account/accounts.ts:430), so we can target
// it directly without a separate lookup.
//
// Doctor users get the full clinician profile: PRC license, S2 (controlled
// drugs), PTR, PhilHealth PAN, specialties, professions, education,
// affiliations, e-signature URL — same fields the clinician profile UI
// reads (services/hapihub/src/services/person/details.schema.ts).

interface UserProfileExtras {
  mobileNo: string;
  sex: "male" | "female";
  dateOfBirth: string;        // ISO
  bloodType: string;
  nationality: string;
  maritalStatus: string;
  address: {
    street1: string;
    city: string;
    province: string;
    region?: string;
    country: string;
    zipCode?: string;
  };
  // Doctor-only (optional for everyone else)
  doc_PRCLicenseNo?: string;
  doc_PRCLicenseExp?: string;
  doc_PTRNumber?: string;
  doc_S2Number?: string;
  doc_philhealthPAN?: string;
  doc_practicingSince?: string;
  doc_title?: string;
  doc_bio?: string;
  doc_specialties?: string[];
  doc_professions?: string[];
  doc_education?: Array<{ school: string; degree: string; year: number }>;
  doc_affiliations?: Array<{ name: string; role?: string }>;
}

const USER_PROFILES: Record<string, UserProfileExtras> = {
  "superadmin@mycure.test": {
    mobileNo: "+639171234001",
    sex: "male",
    dateOfBirth: "1980-04-12",
    bloodType: "O+",
    nationality: "Filipino",
    maritalStatus: "married",
    address: {
      street1: "8 Acacia St, Bel-Air Village",
      city: "Makati",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1209",
    },
  },
  "admin@mycure.test": {
    mobileNo: "+639171234002",
    sex: "female",
    dateOfBirth: "1985-09-22",
    bloodType: "A+",
    nationality: "Filipino",
    maritalStatus: "single",
    address: {
      street1: "44 Sampaguita St, San Antonio",
      city: "Pasig",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1605",
    },
  },
  "doctor@mycure.test": {
    mobileNo: "+639171234003",
    sex: "male",
    dateOfBirth: "1978-06-15",
    bloodType: "B+",
    nationality: "Filipino",
    maritalStatus: "married",
    address: {
      street1: "12 Mahogany Lane, BF Homes",
      city: "Parañaque",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1700",
    },
    doc_title: "Dr.",
    doc_bio:
      "Internal medicine specialist with 15 years of clinical practice. " +
      "Subspecialty in adult endocrinology. Active consultant at MyCure Demo Clinic.",
    doc_PRCLicenseNo: "PRC-0098765",
    doc_PRCLicenseExp: "2028-12-31",
    doc_PTRNumber: "PTR-MNL-2026-001234",
    doc_S2Number: "S2-A-12345",
    doc_philhealthPAN: "PHIC-12-345678901-2",
    doc_practicingSince: "2010-07-01",
    doc_specialties: ["Internal Medicine", "Endocrinology", "Diabetes Care"],
    doc_professions: ["Physician", "Internist"],
    doc_education: [
      { school: "University of the Philippines College of Medicine", degree: "Doctor of Medicine", year: 2008 },
      { school: "University of Santo Tomas", degree: "Bachelor of Science in Biology", year: 2003 },
    ],
    doc_affiliations: [
      { name: "Philippine College of Physicians", role: "Fellow" },
      { name: "Philippine Society of Endocrinology, Diabetes and Metabolism", role: "Member" },
    ],
  },
  "pedia@mycure.test": {
    mobileNo: "+639171234008",
    sex: "female",
    dateOfBirth: "1983-04-22",
    bloodType: "A+",
    nationality: "Filipino",
    maritalStatus: "married",
    address: {
      street1: "33 Sampaguita St, Loyola Heights",
      city: "Quezon City",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1108",
    },
    doc_title: "Dr.",
    doc_bio:
      "Pediatrician with 12 years of practice in well-child care, " +
      "developmental assessments, and adolescent medicine. Active consultant " +
      "at MyCure Demo Clinic.",
    doc_PRCLicenseNo: "PRC-0123456",
    doc_PRCLicenseExp: "2027-06-30",
    doc_PTRNumber: "PTR-QC-2026-002345",
    doc_S2Number: "S2-A-23456",
    doc_philhealthPAN: "PHIC-12-234567890-3",
    doc_practicingSince: "2013-08-15",
    doc_specialties: ["Pediatrics", "Adolescent Medicine"],
    doc_professions: ["Physician", "Pediatrician"],
    doc_education: [
      { school: "University of the Philippines College of Medicine", degree: "Doctor of Medicine", year: 2011 },
      { school: "Ateneo de Manila University", degree: "Bachelor of Science in Biology", year: 2006 },
    ],
    doc_affiliations: [
      { name: "Philippine Pediatric Society", role: "Diplomate" },
    ],
  },
  "familymd@mycure.test": {
    mobileNo: "+639171234009",
    sex: "male",
    dateOfBirth: "1980-11-18",
    bloodType: "O+",
    nationality: "Filipino",
    maritalStatus: "married",
    address: {
      street1: "55 Lourdes St, Magallanes",
      city: "Makati",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1232",
    },
    doc_title: "Dr.",
    doc_bio:
      "Family medicine practitioner with 13 years' experience in primary " +
      "care, chronic disease management, and preventive medicine. Conducts " +
      "executive check-ups and corporate health programs.",
    doc_PRCLicenseNo: "PRC-0234567",
    doc_PRCLicenseExp: "2028-09-30",
    doc_PTRNumber: "PTR-MKT-2026-003456",
    doc_S2Number: "S2-A-34567",
    doc_philhealthPAN: "PHIC-12-345678902-4",
    doc_practicingSince: "2012-05-20",
    doc_specialties: ["Family Medicine", "Preventive Medicine"],
    doc_professions: ["Physician", "Family Physician"],
    doc_education: [
      { school: "University of Santo Tomas Faculty of Medicine and Surgery", degree: "Doctor of Medicine", year: 2010 },
      { school: "De La Salle University", degree: "Bachelor of Science in Health Sciences", year: 2005 },
    ],
    doc_affiliations: [
      { name: "Philippine Academy of Family Physicians", role: "Diplomate" },
      { name: "Occupational Health Nurses Association of the Philippines", role: "Affiliate Member" },
    ],
  },
  "nurse@mycure.test": {
    mobileNo: "+639171234004",
    sex: "female",
    dateOfBirth: "1990-03-08",
    bloodType: "O-",
    nationality: "Filipino",
    maritalStatus: "single",
    address: {
      street1: "27 Sta. Cruz St, Diliman",
      city: "Quezon City",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1101",
    },
  },
  "cashier@mycure.test": {
    mobileNo: "+639171234005",
    sex: "female",
    dateOfBirth: "1992-11-04",
    bloodType: "A-",
    nationality: "Filipino",
    maritalStatus: "single",
    address: {
      street1: "55 Aguinaldo Hwy",
      city: "Imus",
      province: "Cavite",
      region: "Region IV-A",
      country: "PHL",
      zipCode: "4103",
    },
  },
  "laboratory@mycure.test": {
    mobileNo: "+639171234006",
    sex: "male",
    dateOfBirth: "1988-02-19",
    bloodType: "AB+",
    nationality: "Filipino",
    maritalStatus: "married",
    address: {
      street1: "9 Bonifacio St",
      city: "Mandaluyong",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1550",
    },
  },
  "imaging@mycure.test": {
    mobileNo: "+639171234007",
    sex: "female",
    dateOfBirth: "1989-08-27",
    bloodType: "B-",
    nationality: "Filipino",
    maritalStatus: "married",
    address: {
      street1: "33 Roxas Blvd",
      city: "Pasay",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1300",
    },
  },
};

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

async function createOrganization(
  name: string,
  type: string,
  parent?: string,
  types?: string[],
) {
  return (await api("POST", "/organizations", {
    name,
    type,
    // hapihub gates default-queue creation and other facility behavior on
    // `types` (e.g., ['clinic']). Pass it on create so the auto-defaults
    // get created in the same transaction.
    ...(types && types.length > 0 ? { types } : {}),
    description: parent
      ? "MyCure demo branch (child facility for hierarchy testing)"
      : "MyCure demo clinic for environment verification",
    ...(parent ? { parent } : {}),
  })) as { id?: string };
}

// ---------------------------------------------------------------------------
// Verbose clinic / facility profiles. Layered onto the org via PATCH after
// creation. Mirrors the editable fields on the Facility Profile UI:
//   email/phone/website, full address, social media URLs, timezone, tags.
// Field names verified against organizations.schema.ts (top of file lists
// `email`, `phone`, `website`, `address`, `socialMediaURLs`, `timezone`,
// `tags`, `subtype`, `metadata`, `isPublic`).

interface OrgProfile {
  /** Human-readable name to find/create the org under. */
  name: string;
  /** "MyCure Demo Clinic" is the parent; the rest are child branches. */
  parentName?: string;
  description: string;
  /**
   * Facility classification — hapihub reads `types[]` (NOT `subtype`) to
   * gate behavior like default-queue auto-creation and pharmacy defaults.
   * See services/hapihub/src/services/organization/organizations.ts:400.
   * Setting `['clinic']` triggers creation of 8 default queues
   * (Cashier, End Of Encounter, Front Desk, Nurse, Doctor, Laboratory,
   * Imaging X-ray, Imaging Ultrasound) so we don't need to seed them
   * ourselves.
   */
  types: string[];
  email: string;
  phone: string;
  website?: string;
  timezone: string;
  address: {
    street1: string;
    street2?: string;
    city: string;
    province: string;
    region?: string;
    country: string;
    zipCode?: string;
  };
  socialMediaURLs?: Record<string, string>;
  tags?: string[];
}

const ORG_PROFILES: OrgProfile[] = [
  // Parent — must come first so branches can reference its id.
  {
    name: "MyCure Demo Clinic",
    description:
      "Flagship outpatient clinic of the MyCure demo network. Multi-specialty " +
      "care including general medicine, internal medicine, paediatrics, OB-Gyne, " +
      "laboratory, radiology and dental services. Demo data only — not a real facility.",
    types: ["clinic"],
    email: "main@mycure-demo.example.ph",
    phone: "+6328123450",
    website: "https://demo.mycure.example.ph",
    timezone: "Asia/Manila",
    address: {
      street1: "1 Ayala Avenue",
      street2: "Tower One, 12th Floor",
      city: "Makati",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1226",
    },
    socialMediaURLs: {
      facebook: "https://facebook.com/mycure-demo",
      instagram: "https://instagram.com/mycure.demo",
      twitter: "https://twitter.com/mycure_demo",
    },
    tags: ["demo", "seed", "flagship"],
  },
  // Branch 1 — Quezon City
  {
    name: "MyCure Demo Branch - QC",
    parentName: "MyCure Demo Clinic",
    description:
      "MyCure Demo Clinic — Quezon City branch. Outpatient services and walk-in PME clinic.",
    types: ["clinic"],
    email: "qc@mycure-demo.example.ph",
    phone: "+6329123451",
    website: "https://demo.mycure.example.ph/qc",
    timezone: "Asia/Manila",
    address: {
      street1: "120 Tomas Morato Avenue",
      city: "Quezon City",
      province: "Metro Manila",
      region: "NCR",
      country: "PHL",
      zipCode: "1103",
    },
    socialMediaURLs: {
      facebook: "https://facebook.com/mycure-demo-qc",
    },
    tags: ["demo", "seed", "branch"],
  },
  // Branch 2 — Cebu
  {
    name: "MyCure Demo Branch - Cebu",
    parentName: "MyCure Demo Clinic",
    description:
      "MyCure Demo Clinic — Cebu City branch. Provincial outpatient and diagnostic centre.",
    types: ["clinic"],
    email: "cebu@mycure-demo.example.ph",
    phone: "+6332123452",
    website: "https://demo.mycure.example.ph/cebu",
    timezone: "Asia/Manila",
    address: {
      street1: "88 Osmeña Boulevard",
      city: "Cebu City",
      province: "Cebu",
      region: "Region VII",
      country: "PHL",
      zipCode: "6000",
    },
    socialMediaURLs: {
      facebook: "https://facebook.com/mycure-demo-cebu",
    },
    tags: ["demo", "seed", "branch", "visayas"],
  },
];

async function createMember(
  uid: string,
  organization: string,
  user: SeedUser,
) {
  // Privileges: union from every role in roleIds that we have a mapping
  // for. Roles outside our ROLE_PRIVILEGES table (e.g. doctor_pme,
  // clinic_manager, nurse_head) still appear in the `roles` array — the
  // UI uses those for feature gates — but contribute no extra
  // privilege flags here. Operators can refine via the Members UI.
  const privileges: Record<string, boolean> = {};
  if (user.superadmin) {
    privileges.superadmin = true;
    privileges.admin = true;
  }
  for (const roleId of user.roleIds) {
    const privs = ROLE_PRIVILEGES[roleId];
    if (privs) {
      for (const priv of privs) privileges[priv] = true;
    }
    if (roleId === "admin") privileges.admin = true;
  }

  const body: Record<string, unknown> = {
    uid,
    organization,
    roles: user.roleIds,
    superadmin: user.superadmin,
    admin:
      user.superadmin ||
      user.roleIds.includes("admin") ||
      user.roleIds.includes("clinic_manager"),
    ...privileges,
  };

  // Hapihub auto-creates a superadmin org-member when an org is created
  // (services/hapihub/src/services/organization/organizations.ts:365),
  // so the POST below 409s for the very first member of every new org.
  // Detect that case and PATCH the existing membership instead — that
  // way the auto-created row gets our `roles[]` and privilege flags.
  try {
    return await api("POST", "/organization-members", body);
  } catch (err: unknown) {
    const msg = (err as Error).message;
    const isConflict =
      msg.includes("already a member") ||
      msg.includes("already exists") ||
      msg.includes("409") ||
      msg.includes("UNIQUE") ||
      msg.includes("duplicate");
    if (!isConflict) throw err;

    // Find the existing member id, then PATCH with our role + privileges.
    let memberId: string | undefined;
    try {
      const res = (await api(
        "GET",
        `/organization-members?uid=${encodeURIComponent(uid)}&organization=${encodeURIComponent(organization)}&%24limit=1`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      memberId = list[0]?.id;
    } catch {
      // ignore — we'll bail below
    }
    if (!memberId) throw err;

    // PATCH body — strip the immutable `uid` + `organization` keys so
    // the request body validation doesn't reject them.
    const { uid: _uid, organization: _organization, ...patchBody } = body;
    return api("PATCH", `/organization-members/${memberId}`, patchBody);
  }
}

// ---------------------------------------------------------------------------
// Patient generator
// ---------------------------------------------------------------------------
// Creates verbose Filipino-context patients for demo data. Deterministic
// externalId per (facilityIndex, sequence) so reruns are idempotent —
// existing patients are looked up by externalId and skipped.

const FIRST_NAMES_M = [
  "Juan", "Pedro", "Jose", "Carlos", "Miguel", "Ricardo", "Antonio", "Luis",
  "Manuel", "Ramon", "Eduardo", "Roberto", "Enrique", "Felipe", "Francisco",
  "Mario", "Diego", "Rafael", "Alfredo", "Gabriel", "Andres", "Ernesto",
  "Bernardo", "Salvador", "Ferdinand", "Hector", "Mateo", "Nestor",
];
const FIRST_NAMES_F = [
  "Maria", "Anna", "Sofia", "Catalina", "Elena", "Rosa", "Carmen", "Teresa",
  "Lourdes", "Luz", "Cristina", "Patricia", "Veronica", "Beatriz", "Angela",
  "Isabel", "Margarita", "Diana", "Liwayway", "Imelda", "Corazon", "Aurora",
  "Concepcion", "Rosario", "Dolores", "Gloria", "Esperanza", "Felicidad",
];
const MIDDLE_NAMES = [
  "Santos", "Reyes", "Cruz", "Garcia", "Mendoza", "Torres", "Tomas", "Andrada",
  "Domingo", "Castillo", "Flores", "Villanueva", "Ramos", "Aquino", "Bautista",
  "Diaz", "Lopez", "Pascual", "Salazar", "Soriano", "Tan", "Velasco",
];
const LAST_NAMES = [
  "Dela Cruz", "Reyes", "Santos", "Garcia", "Mendoza", "Torres", "Castillo",
  "Flores", "Villanueva", "Ramos", "Aquino", "Bautista", "Diaz", "Lopez",
  "Pascual", "Salazar", "Soriano", "Tan", "Velasco", "Manalang", "Galvez",
  "Hernandez", "Marquez", "Ocampo", "Pineda", "Quizon", "Tagaro", "Ynares",
];
const PH_LOCATIONS = [
  { city: "Manila", province: "Metro Manila", region: "NCR", zip: "1000" },
  { city: "Quezon City", province: "Metro Manila", region: "NCR", zip: "1100" },
  { city: "Makati", province: "Metro Manila", region: "NCR", zip: "1200" },
  { city: "Pasig", province: "Metro Manila", region: "NCR", zip: "1600" },
  { city: "Taguig", province: "Metro Manila", region: "NCR", zip: "1630" },
  { city: "Cebu City", province: "Cebu", region: "Region VII", zip: "6000" },
  { city: "Davao City", province: "Davao del Sur", region: "Region XI", zip: "8000" },
  { city: "Iloilo City", province: "Iloilo", region: "Region VI", zip: "5000" },
  { city: "Baguio", province: "Benguet", region: "CAR", zip: "2600" },
  { city: "Cagayan de Oro", province: "Misamis Oriental", region: "Region X", zip: "9000" },
  { city: "Bacolod", province: "Negros Occidental", region: "Region VI", zip: "6100" },
  { city: "Zamboanga", province: "Zamboanga del Sur", region: "Region IX", zip: "7000" },
];
const STREETS = [
  "Mabini St", "Rizal Ave", "Aguinaldo Hwy", "Bonifacio St", "Quezon Ave",
  "Roxas Blvd", "EDSA", "Ortigas Ave", "Shaw Blvd", "Aurora Blvd",
  "Taft Ave", "Sen. Gil Puyat Ave", "España Blvd", "Buendia", "Kalayaan Ave",
];
const VILLAGES = [
  "San Antonio", "Bagong Pag-asa", "San Roque", "Mariana", "Pinyahan",
  "Bagong Lipunan", "Diliman", "Cubao", "New Manila", "Greenmeadows",
];
const RELIGIONS = ["Catholic", "Christian", "Iglesia ni Cristo", "Muslim", "Buddhist", "Other"];
const MARITAL_STATUSES = ["single", "married", "widowed", "separated", "divorced"];
const BLOOD_TYPES = ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"];
const NATIONALITIES = ["Filipino"]; // could expand
const RELATIONSHIPS = ["spouse", "parent", "sibling", "child", "guardian", "friend"];
const COMPANIES = [
  "ABS-CBN Corporation", "PLDT Inc.", "San Miguel Corporation", "Ayala Corp",
  "SM Investments", "Globe Telecom", "Metro Pacific", "Jollibee Foods Corp",
  "BDO Unibank", "BPI", "Robinsons Land", "JG Summit Holdings",
];

function randomItem<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}
function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
function randomDateBetween(yearsAgoMin: number, yearsAgoMax: number): Date {
  const now = Date.now();
  const minMs = now - yearsAgoMax * 365.25 * 24 * 60 * 60 * 1000;
  const maxMs = now - yearsAgoMin * 365.25 * 24 * 60 * 60 * 1000;
  return new Date(randomInt(minMs, maxMs));
}
function slugify(s: string): string {
  return s.toLowerCase().replace(/[^a-z]/g, "");
}

interface SeedPatient {
  facility: string;
  externalId: string;
  creatingDevice: "web";
  tags: string[];
  personalDetails: Record<string, unknown>;
}

// PhilHealth-style 12-digit PIN number (formatted as XX-XXXXXXXXX-X)
function generatePhilHealthPIN(): string {
  const a = randomInt(10, 99);
  const b = randomInt(100000000, 999999999);
  const c = randomInt(0, 9);
  return `${a}-${b}-${c}`;
}

const HMO_PROVIDERS = [
  "Maxicare Healthcare Corporation",
  "Intellicare",
  "Medicard Philippines",
  "Philhealth Care, Inc. (PhilCare)",
  "Cocolife Healthcare",
  "Pacific Cross Health Care",
  "EastWest Healthcare",
  "Insular Health Care",
];

const RELIGIONS_FULL = [
  "Roman Catholic",
  "Iglesia ni Cristo",
  "Christian (Born Again / Evangelical)",
  "Seventh-day Adventist",
  "Aglipayan",
  "Muslim (Islam)",
  "Buddhist",
  "Other",
];

function generatePatient(facility: string, externalId: string): SeedPatient {
  const sex = Math.random() < 0.5 ? "male" : "female";
  const firstName = sex === "male"
    ? randomItem(FIRST_NAMES_M)
    : randomItem(FIRST_NAMES_F);
  const middleName = randomItem(MIDDLE_NAMES);
  const lastName = randomItem(LAST_NAMES);

  // Most patients adult; ~10% pediatric for variety
  const dob = Math.random() < 0.1
    ? randomDateBetween(2, 17)
    : randomDateBetween(18, 80);

  const loc = randomItem(PH_LOCATIONS);
  const street = `${randomInt(1, 999)} ${randomItem(STREETS)}`;
  const village = randomItem(VILLAGES);
  const phMobile = () => `+639${randomInt(100000000, 999999999)}`;

  // Email = first.last+ext@mycure.test for uniqueness across reruns
  const emailLocal = `${slugify(firstName)}.${slugify(lastName)}.${externalId.toLowerCase()}`;
  const email = `${emailLocal}@mycure.test`;

  const isAdult = (Date.now() - dob.getTime()) > 18 * 365.25 * 24 * 60 * 60 * 1000;
  const maritalStatus = isAdult ? randomItem(MARITAL_STATUSES) : "single";
  const ageYears = Math.floor(
    (Date.now() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000),
  );

  // ~70% of adults carry PhilHealth, ~40% have a private HMO. Pediatrics
  // are usually dependents — give them PhilHealth via parent (no HMO).
  const insuranceCards: Array<Record<string, unknown>> = [];
  if (isAdult) {
    if (Math.random() < 0.7) {
      insuranceCards.push({
        provider: "PhilHealth",
        kind: "government",
        cardNumber: generatePhilHealthPIN(),
        memberType: Math.random() < 0.7 ? "Employed (Direct Contributor)" : "Indirect Contributor",
        validUntil: new Date(Date.now() + randomInt(30, 730) * 24 * 60 * 60 * 1000).toISOString(),
      });
    }
    if (Math.random() < 0.4) {
      insuranceCards.push({
        provider: randomItem(HMO_PROVIDERS),
        kind: "hmo",
        cardNumber: `HMO-${randomInt(100000000, 999999999)}`,
        planName: randomItem(["Standard", "Premier", "Executive", "Family"]),
        validUntil: new Date(Date.now() + randomInt(30, 365) * 24 * 60 * 60 * 1000).toISOString(),
      });
    }
  } else {
    // pediatric → PhilHealth dependent
    insuranceCards.push({
      provider: "PhilHealth",
      kind: "government",
      cardNumber: generatePhilHealthPIN(),
      memberType: "Dependent",
    });
  }

  // Loose vital signs / clinical seed values for demo charts
  const vitals = isAdult
    ? {
        heightCm: randomInt(150, 185),
        weightKg: randomInt(45, 95),
        systolic: randomInt(100, 145),
        diastolic: randomInt(65, 95),
        heartRate: randomInt(60, 95),
        temperature: 36 + Math.random() * 1.5,    // 36–37.5°C
        respiratoryRate: randomInt(12, 20),
      }
    : {
        heightCm: randomInt(85, 165),
        weightKg: randomInt(12, 55),
        systolic: randomInt(85, 115),
        diastolic: randomInt(55, 75),
        heartRate: randomInt(80, 120),
        temperature: 36 + Math.random() * 1.5,
        respiratoryRate: randomInt(18, 28),
      };

  return {
    facility,
    externalId,
    creatingDevice: "web",
    tags: ["seed", "demo", isAdult ? "adult" : "pediatric"],
    personalDetails: {
      type: "medical-patients",
      name: {
        firstName,
        middleName,
        lastName,
        suffix: isAdult && Math.random() < 0.05 ? randomItem(["Jr.", "Sr.", "III"]) : undefined,
      },
      sex,
      dateOfBirth: dob.toISOString(),
      age: ageYears,
      mobileNo: phMobile(),
      email,
      bloodType: randomItem(BLOOD_TYPES),
      maritalStatus,
      nationality: randomItem(NATIONALITIES),
      religion: randomItem(RELIGIONS_FULL),
      height: vitals.heightCm,
      weight: vitals.weightKg,
      vitals,
      address: {
        street1: street,
        village,
        city: loc.city,
        province: loc.province,
        region: loc.region,
        country: "PHL",
        zipCode: loc.zip,
      },
      emergencyContactName: `${randomItem([...FIRST_NAMES_M, ...FIRST_NAMES_F])} ${lastName}`,
      emergencyContactRelationship: randomItem(RELATIONSHIPS),
      emergencyContactMobileNo: phMobile(),
      insuranceCards,
      ...(isAdult ? {
        companies: [
          {
            name: randomItem(COMPANIES),
            position: randomItem([
              "Software Engineer", "Accountant", "Sales Manager",
              "Operations Lead", "HR Specialist", "Customer Support",
              "Marketing Officer", "Project Manager", "Branch Manager",
              "Field Engineer", "Research Analyst", "Compliance Officer",
            ]),
            since: new Date(Date.now() - randomInt(180, 4000) * 24 * 60 * 60 * 1000).toISOString(),
          },
        ],
      } : {}),
      tags: ["seed", "demo"],
    },
  };
}

async function patientExists(facility: string, externalId: string): Promise<boolean> {
  try {
    const res = (await api(
      "GET",
      `/medical-patients?facility=${encodeURIComponent(facility)}&externalId=${encodeURIComponent(externalId)}&$limit=1`,
    )) as { data?: Array<unknown> } | Array<unknown>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list.length > 0;
  } catch {
    return false;
  }
}

async function seedPatients(
  facilities: Array<{ id: string; label: string; profile: OrgProfile }>,
  count: number,
): Promise<void> {
  if (count <= 0) return;

  // Patients are seeded on the PARENT facility only — branches access them
  // via the parent-child organization hierarchy (the medical-patients
  // service supports `includeOrganizationChildren` to fan out from the
  // parent). Mirrors the inventory-products pattern: one source of truth
  // on the main warehouse / facility, branches share via hierarchy.
  const parentFacility = facilities.find((f) => !f.profile.parentName);
  if (!parentFacility) {
    console.warn(chalk.yellow("⚠  Patients skipped — no parent facility in ORG_PROFILES."));
    return;
  }

  const spinner = ora(`Seeding ${count} patients on parent facility '${parentFacility.profile.name}'...`).start();
  let created = 0;
  let skipped = 0;

  for (let i = 1; i <= count; i++) {
    // Keep the legacy `-1-` segment in the externalId so reset
    // patterns (`SEED-PATIENT-` regex) and prior seed data continue to
    // match. The "1" is the parent index — historically we seeded on
    // facility 1 first, and it's now the only one we use.
    const externalId = `SEED-PATIENT-1-${String(i).padStart(3, "0")}`;
    spinner.text = `[${parentFacility.label}] ${externalId} (${created + skipped + 1}/${count})`;

    if (await patientExists(parentFacility.id, externalId)) {
      skipped++;
      continue;
    }
    const patient = generatePatient(parentFacility.id, externalId);
    try {
      await api("POST", "/medical-patients", patient);
      created++;
    } catch (err: unknown) {
      const msg = (err as Error).message;
      spinner.fail(`Failed to create ${externalId}: ${msg.slice(0, 200)}`);
      process.exit(1);
    }
  }

  spinner.succeed(
    `Patients: ${created} new, ${skipped} skipped (already existed) — ${count} target on parent (shared with ${facilities.length - 1} branch${facilities.length - 1 === 1 ? "" : "es"} via hierarchy)`,
  );
}

// ---------------------------------------------------------------------------
// Fixed demo patient — deterministic name + externalId, populated with two
// encounters and a representative set of medical records (vitals, chief
// complaint, assessment with ICD-10 codes, medication orders). Lets demo
// users always have a known patient with a real chart to click through.
// ---------------------------------------------------------------------------
//
// Storyline: 42yo male with newly-diagnosed Type 2 diabetes + hypertension.
// Visit 1 (~30 days ago): initial diagnosis. Visit 2 (~7 days ago):
// follow-up showing improvement on Metformin + Losartan.
//
// All records use Dr. Juan Cruz (doctor@mycure.test) as the provider.
// Idempotent on externalId: if the patient already exists, the entire
// encounter+record chain is skipped (no partial runs).

const FIXED_PATIENT_EXTERNAL_ID = "SEED-PATIENT-FIXED-001";
const FIXED_PATIENT_DOCTOR_EMAIL = "doctor@mycure.test";

interface CreatedPatientResponse {
  id?: string;
  $populated?: { personalDetails?: { id?: string } };
}
interface CreatedRecordResponse { id?: string }

async function seedFixedPatient(
  facilities: Array<{ id: string; label: string; profile: OrgProfile }>,
  userIds: Record<string, string>,
): Promise<void> {
  const parentFacility = facilities.find((f) => !f.profile.parentName);
  if (!parentFacility) {
    console.warn(chalk.yellow("⚠  Fixed patient skipped — no parent facility."));
    return;
  }
  const facilityId = parentFacility.id;
  const doctorUid = userIds[FIXED_PATIENT_DOCTOR_EMAIL];
  if (!doctorUid) {
    console.warn(
      chalk.yellow(`⚠  Fixed patient skipped — no uid for ${FIXED_PATIENT_DOCTOR_EMAIL}.`),
    );
    return;
  }

  const spinner = ora(`Seeding fixed demo patient (Pedro Demo Lopez)...`).start();

  // Idempotency: if the patient with this externalId already exists, the
  // whole chart was seeded on a previous run — skip everything.
  if (await patientExists(facilityId, FIXED_PATIENT_EXTERNAL_ID)) {
    spinner.succeed(
      `Fixed patient already exists (externalId=${FIXED_PATIENT_EXTERNAL_ID}) — skipped`,
    );
    return;
  }

  // ── 1. Create the patient ───────────────────────────────────────
  spinner.text = "creating patient row...";
  let patientId: string;
  try {
    const created = (await api("POST", "/medical-patients", {
      facility: facilityId,
      externalId: FIXED_PATIENT_EXTERNAL_ID,
      creatingDevice: "web",
      tags: ["seed", "demo", "fixed", "adult"],
      personalDetails: {
        type: "medical-patients",
        name: {
          firstName: "Pedro",
          middleName: "Reyes",
          lastName: "Demo Lopez",
          suffix: "Jr.",
        },
        sex: "male",
        dateOfBirth: new Date("1983-05-15T00:00:00.000Z").toISOString(),
        age: 42,
        mobileNo: "+639171234100",
        email: "pedro.demo.lopez@mycure.test",
        bloodType: "O+",
        maritalStatus: "married",
        nationality: "Filipino",
        religion: "Roman Catholic",
        height: 172,
        weight: 88,
        address: {
          street1: "1 Demo Street, Bel-Air Village",
          city: "Makati",
          province: "Metro Manila",
          region: "NCR",
          country: "PHL",
          zipCode: "1209",
        },
        emergencyContactName: "Maria Demo Lopez",
        emergencyContactRelationship: "spouse",
        emergencyContactMobileNo: "+639171234101",
        insuranceCards: [
          {
            provider: "PhilHealth",
            kind: "government",
            cardNumber: "12-345678901-0",
            memberType: "Employed (Direct Contributor)",
            validUntil: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
          },
          {
            provider: "Maxicare Healthcare Corporation",
            kind: "hmo",
            cardNumber: "HMO-100200300",
            planName: "Premier",
            validUntil: new Date(Date.now() + 180 * 24 * 60 * 60 * 1000).toISOString(),
          },
        ],
        companies: [
          {
            name: "Ayala Corporation",
            position: "Senior Project Manager",
            since: new Date("2015-01-15T00:00:00.000Z").toISOString(),
          },
        ],
        tags: ["seed", "demo", "fixed"],
      },
    })) as CreatedPatientResponse;
    patientId = created.id ?? "";
    if (!patientId) throw new Error("patient create returned no id");
  } catch (err: unknown) {
    spinner.fail(`Failed to create fixed patient: ${(err as Error).message.slice(0, 200)}`);
    process.exit(1);
  }

  // ── 2. Two encounters: initial-diagnosis (30 days ago) +
  //       follow-up (7 days ago) ────────────────────────────────────
  const now = Date.now();
  const t1 = new Date(now - 30 * 24 * 60 * 60 * 1000); // initial visit
  const t2 = new Date(now - 7 * 24 * 60 * 60 * 1000);  // follow-up

  spinner.text = "creating initial-visit encounter...";
  let encounter1Id: string;
  try {
    const enc = (await api("POST", "/medical-encounters", {
      type: "outpatient",
      facility: facilityId,
      patient: patientId,
      encounterType: "new",
      doctors: [doctorUid],
      providers: [doctorUid],
      tags: ["seed", "fixed", "initial-diagnosis"],
      finishedAt: t1.toISOString(),
      finishedBy: doctorUid,
    })) as CreatedRecordResponse;
    encounter1Id = enc.id ?? "";
    if (!encounter1Id) throw new Error("encounter 1 returned no id");
  } catch (err: unknown) {
    spinner.fail(`Failed to create initial encounter: ${(err as Error).message.slice(0, 200)}`);
    process.exit(1);
  }

  spinner.text = "creating follow-up encounter...";
  let encounter2Id: string;
  try {
    const enc = (await api("POST", "/medical-encounters", {
      type: "outpatient",
      facility: facilityId,
      patient: patientId,
      encounterType: "follow-up",
      preceding: encounter1Id,
      doctors: [doctorUid],
      providers: [doctorUid],
      tags: ["seed", "fixed", "follow-up"],
      finishedAt: t2.toISOString(),
      finishedBy: doctorUid,
    })) as CreatedRecordResponse;
    encounter2Id = enc.id ?? "";
    if (!encounter2Id) throw new Error("encounter 2 returned no id");
  } catch (err: unknown) {
    spinner.fail(`Failed to create follow-up encounter: ${(err as Error).message.slice(0, 200)}`);
    process.exit(1);
  }

  // ── 3. Records for each encounter ───────────────────────────────
  // Helper that POSTs a /medical-records body with the common fields
  // already wired up. Each record links back to the encounter, patient,
  // facility, and provider.
  //
  // PER-RECORD TOLERANT: medication-order records can fail on hapihub
  // builds where the `emr_status` column was added to the schema but the
  // SQLite migration was deferred (the refactor/emr-layout branch ships
  // PG-only migrations for it). One bad record shouldn't kill the rest
  // of the chart, so we log a warning and continue.
  let recordsCreated = 0;
  let recordsFailed = 0;
  const postRecord = async (encounterId: string, finalizedAt: Date, body: Record<string, unknown>) => {
    try {
      await api("POST", "/medical-records", {
        facility: facilityId,
        patient: patientId,
        encounter: encounterId,
        provider: doctorUid,
        providerType: "doctor",
        finalizedAt: finalizedAt.toISOString(),
        finalizedBy: doctorUid,
        tags: ["seed", "fixed"],
        ...body,
      });
      recordsCreated++;
    } catch (err: unknown) {
      const msg = (err as Error).message;
      const trimmed = msg.length > 160 ? `${msg.slice(0, 160)}…` : msg;
      console.warn(
        chalk.yellow(
          `  ⚠  record skipped (type=${body.type}${body.subtype ? "/" + body.subtype : ""}): ${trimmed}`,
        ),
      );
      recordsFailed++;
    }
  };

  // Encounter 1 — initial diagnosis
  spinner.text = "writing records for initial encounter...";
  {
    // Vitals — elevated BP, mildly overweight
    await postRecord(encounter1Id, t1, {
      type: "vitals",
      takenAt: t1.toISOString(),
      height: 172,
      heightUnitDisplayed: "cm",
      weight: 88,
      weightUnitDisplayed: "kg",
      pulse: 84,
      respiration: 16,
      temperature: 36.7,
      bpSystolic: 152,
      bpDiastolic: 96,
      o2sats: 98,
    });

    // Chief complaint
    await postRecord(encounter1Id, t1, {
      type: "chief-complaint",
      text:
        "Increased thirst and frequent urination for the past 2 weeks. Patient also " +
        "reports fatigue and 3kg unintentional weight loss over the same period. " +
        "Family history positive for type 2 diabetes (father, paternal uncle).",
      doctor: doctorUid,
      signsAndSymptoms: [
        { code: "polydipsia", text: "Polydipsia (increased thirst)", duration: "2 weeks", severity: 6 },
        { code: "polyuria",   text: "Polyuria (frequent urination)",  duration: "2 weeks", severity: 6 },
        { code: "fatigue",    text: "Fatigue",                         duration: "2 weeks", severity: 5 },
        { code: "weight-loss", text: "Unintentional weight loss",      duration: "2 weeks", severity: 5 },
      ],
    });

    // Assessment — primary diagnosis (T2DM) + secondary (HTN)
    await postRecord(encounter1Id, t1, {
      type: "assessment",
      subtype: "diagnosis",
      diagnosis: "Type 2 diabetes mellitus, newly diagnosed",
      diagnosisCode: "E11.9",
      diagnosisText: "Type 2 diabetes mellitus without complications",
      icd10: "E11.9",
      text: "FBS 248 mg/dL, HbA1c 9.2%. Started on metformin and lifestyle modifications.",
    });
    await postRecord(encounter1Id, t1, {
      type: "assessment",
      subtype: "diagnosis",
      diagnosis: "Essential hypertension, stage 1",
      diagnosisCode: "I10",
      diagnosisText: "Essential (primary) hypertension",
      icd10: "I10",
      text: "Average BP 152/96 over 3 readings. Initiating ARB.",
    });

    // Medication order — Metformin + Losartan starter regimen
    await postRecord(encounter1Id, t1, {
      type: "medication-order",
      note: "Starter regimen for newly-diagnosed T2DM + HTN. Reassess at 4-week follow-up.",
      validUntil: new Date(t1.getTime() + 60 * 24 * 60 * 60 * 1000).toISOString(),
      startedAt: t1.toISOString(),
      items: [
        {
          genericName: "Metformin",
          brandName: "Glucophage",
          formulation: "500mg tablet",
          dispense: "60 tablets",
          dosageSig: "1 tablet",
          frequency: "twice daily with meals",
          duration: 30,
          durationUnit: "day",
          afterFood: "Take with or right after meals to reduce GI upset.",
          reasonForPrescription: "T2DM glycemic control",
          startedAt: t1.toISOString(),
        },
        {
          genericName: "Losartan",
          brandName: "Cozaar",
          formulation: "50mg tablet",
          dispense: "30 tablets",
          dosageSig: "1 tablet",
          frequency: "once daily in the morning",
          duration: 30,
          durationUnit: "day",
          reasonForPrescription: "Stage 1 hypertension",
          startedAt: t1.toISOString(),
        },
      ],
    });
  }

  // Encounter 2 — follow-up
  spinner.text = "writing records for follow-up encounter...";
  {
    // Vitals — improved BP, slight weight loss
    await postRecord(encounter2Id, t2, {
      type: "vitals",
      takenAt: t2.toISOString(),
      height: 172,
      heightUnitDisplayed: "cm",
      weight: 86,
      weightUnitDisplayed: "kg",
      pulse: 78,
      respiration: 16,
      temperature: 36.6,
      bpSystolic: 138,
      bpDiastolic: 88,
      o2sats: 99,
    });

    // HPI / progress note
    await postRecord(encounter2Id, t2, {
      type: "hpi",
      text:
        "Patient reports good adherence to metformin and losartan. Polydipsia and " +
        "polyuria have largely resolved. Energy levels improving. No GI side effects " +
        "from metformin. Lost 2kg since last visit. Home BP readings averaging 135/85.",
      doctor: doctorUid,
    });

    // Assessment — improving
    await postRecord(encounter2Id, t2, {
      type: "assessment",
      subtype: "impression",
      diagnosis: "Type 2 diabetes — improving on Metformin",
      diagnosisCode: "E11.9",
      diagnosisText: "Type 2 diabetes mellitus without complications",
      icd10: "E11.9",
      text: "Continue current regimen. Schedule HbA1c repeat in 3 months. Reinforce diet/exercise.",
    });

    // Medication order — continue same regimen
    await postRecord(encounter2Id, t2, {
      type: "medication-order",
      note: "Continue starter regimen. Reassess at 3-month HbA1c.",
      validUntil: new Date(t2.getTime() + 90 * 24 * 60 * 60 * 1000).toISOString(),
      startedAt: t2.toISOString(),
      items: [
        {
          genericName: "Metformin",
          brandName: "Glucophage",
          formulation: "500mg tablet",
          dispense: "180 tablets",
          dosageSig: "1 tablet",
          frequency: "twice daily with meals",
          duration: 90,
          durationUnit: "day",
          reasonForPrescription: "T2DM (continuing)",
          startedAt: t2.toISOString(),
        },
        {
          genericName: "Losartan",
          brandName: "Cozaar",
          formulation: "50mg tablet",
          dispense: "90 tablets",
          dosageSig: "1 tablet",
          frequency: "once daily in the morning",
          duration: 90,
          durationUnit: "day",
          reasonForPrescription: "Hypertension (continuing)",
          startedAt: t2.toISOString(),
        },
      ],
    });
  }

  if (recordsFailed > 0) {
    spinner.warn(
      `Fixed patient: Pedro Demo Lopez (${FIXED_PATIENT_EXTERNAL_ID}) — 2 encounters, ${recordsCreated}/${recordsCreated + recordsFailed} medical records (${recordsFailed} skipped — see warnings above)`,
    );
  } else {
    spinner.succeed(
      `Fixed patient: Pedro Demo Lopez (${FIXED_PATIENT_EXTERNAL_ID}) — 2 encounters, ${recordsCreated} medical records (vitals, chief-complaint, hpi, assessments, medication orders)`,
    );
  }
}

// ---------------------------------------------------------------------------
// Patient accounts — sign up Better-Auth accounts for the fixed patient
// + the first N random patients, tag the accounts as `pxp` (the
// PXP-mobile-app self-claim convention from
// services/hapihub/src/services/account/accounts.schema.ts:39), and link
// each medical-patient row to its account via the `account` field.
//
// Why only N and not all? In a real clinic most walk-in patients never
// register a self-service account; mirroring that for demo realism. Pass
// --patient-accounts <N> to override the default of 5.
// ---------------------------------------------------------------------------

const DEFAULT_PATIENT_ACCOUNT_COUNT = 5;

interface SeededPatientAccount {
  externalId: string;
  email: string;
  isFixed: boolean;
  /** "new" | "existing" | "skipped" */
  status: "new" | "existing" | "skipped";
}

async function seedPatientAccounts(
  facilities: Array<{ id: string; label: string; profile: OrgProfile }>,
  randomCount: number,
): Promise<SeededPatientAccount[]> {
  const parentFacility = facilities.find((f) => !f.profile.parentName);
  if (!parentFacility) return [];
  const facilityId = parentFacility.id;

  // Build the list of (patientId, externalId, isFixed) targets.
  const targets: Array<{ patientId: string; externalId: string; isFixed: boolean }> = [];

  // Fixed patient first (if it was seeded).
  try {
    const res = (await api(
      "GET",
      `/medical-patients?facility=${encodeURIComponent(facilityId)}&externalId=${encodeURIComponent(FIXED_PATIENT_EXTERNAL_ID)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    if (list[0]?.id) {
      targets.push({ patientId: list[0].id, externalId: FIXED_PATIENT_EXTERNAL_ID, isFixed: true });
    }
  } catch {
    // ignore — fixed patient may not exist on this run
  }

  // Then the first N random patients (SEED-PATIENT-1-001 onwards). They
  // must already exist (seedPatients runs earlier in main()).
  for (let i = 1; i <= randomCount; i++) {
    const externalId = `SEED-PATIENT-1-${String(i).padStart(3, "0")}`;
    try {
      const res = (await api(
        "GET",
        `/medical-patients?facility=${encodeURIComponent(facilityId)}&externalId=${encodeURIComponent(externalId)}&%24limit=1`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      if (list[0]?.id) {
        targets.push({ patientId: list[0].id, externalId, isFixed: false });
      }
    } catch {
      // ignore — patient may not have been seeded
    }
  }

  if (targets.length === 0) return [];

  const spinner = ora(`Seeding ${targets.length} patient accounts (1 fixed + ${targets.length - 1} random)...`).start();

  // Capture the superadmin session — sign-up + sign-in mutate sessionCookie,
  // and we need superadmin auth for the PATCH calls afterwards.
  const superadminCookie = sessionCookie;

  let accountsCreated = 0;
  let accountsExisting = 0;
  let patientsLinked = 0;
  let skipped = 0;
  let progress = 0;
  // Per-target results so main() can render a final-breakdown row for
  // each patient account (email + status).
  const results: SeededPatientAccount[] = [];

  for (const target of targets) {
    progress++;
    spinner.text = `[${target.externalId}] (${progress}/${targets.length})`;

    // 1. Pull the patient's email + name from personal_details. Recall:
    //    medical-patient.id == personal_details.id (same convention as
    //    account.uid). The Better-Auth signup email is what the patient
    //    will use to log in.
    let email: string | undefined;
    let displayName: string | undefined;
    try {
      const pd = (await api("GET", `/personal-details/${target.patientId}`)) as {
        email?: string;
        name?: { firstName?: string; lastName?: string };
      };
      email = pd?.email;
      displayName = [pd?.name?.firstName, pd?.name?.lastName].filter(Boolean).join(" ").trim();
    } catch {
      skipped++;
      results.push({ externalId: target.externalId, email: "", isFixed: target.isFixed, status: "skipped" });
      continue;
    }
    if (!email) {
      skipped++;
      results.push({ externalId: target.externalId, email: "", isFixed: target.isFixed, status: "skipped" });
      continue;
    }
    const name = displayName || "Patient";

    // 2. Sign up. If the account already exists (rerun), sign in instead.
    sessionCookie = "";
    let uid: string | undefined;
    let outcome: "new" | "existing" | "skipped" = "skipped";
    try {
      const result = await signUp(email, PASSWORD, name);
      uid = result.user?.id;
      if (uid) {
        accountsCreated++;
        outcome = "new";
      }
    } catch (err: unknown) {
      const msg = (err as Error).message;
      if (
        msg.includes("already exists") ||
        msg.includes("UNIQUE") ||
        msg.includes("duplicate") ||
        msg.includes("already")
      ) {
        sessionCookie = "";
        try {
          const result = await signIn(email, PASSWORD);
          uid = result.user?.id;
          if (uid) {
            accountsExisting++;
            outcome = "existing";
          }
        } catch (err2: unknown) {
          const msg2 = (err2 as Error).message;
          console.warn(
            chalk.yellow(`  ⚠  ${target.externalId}: signin fallback failed — ${msg2.slice(0, 120)}`),
          );
          skipped++;
          results.push({ externalId: target.externalId, email, isFixed: target.isFixed, status: "skipped" });
          continue;
        }
      } else if (msg.includes("429")) {
        // Rate limit on Better-Auth signup — wait and retry once.
        await new Promise((r) => setTimeout(r, 10_000));
        try {
          sessionCookie = "";
          const result = await signUp(email, PASSWORD, name);
          uid = result.user?.id;
          if (uid) {
            accountsCreated++;
            outcome = "new";
          }
        } catch (err2: unknown) {
          console.warn(
            chalk.yellow(`  ⚠  ${target.externalId}: signup rate-limit retry failed`),
          );
          skipped++;
          results.push({ externalId: target.externalId, email, isFixed: target.isFixed, status: "skipped" });
          continue;
        }
      } else {
        console.warn(
          chalk.yellow(`  ⚠  ${target.externalId}: signup failed — ${msg.slice(0, 120)}`),
        );
        skipped++;
        results.push({ externalId: target.externalId, email, isFixed: target.isFixed, status: "skipped" });
        continue;
      }
    }
    if (!uid) {
      skipped++;
      results.push({ externalId: target.externalId, email, isFixed: target.isFixed, status: "skipped" });
      continue;
    }
    // Account secured (new or existing) — record a successful row even
    // before tagging/linking lands so the breakdown shows the working
    // login credential.
    results.push({ externalId: target.externalId, email, isFixed: target.isFixed, status: outcome });

    // 3. Restore superadmin session for the PATCH calls (signing in as
    //    the patient gave us a patient session, which can't PATCH random
    //    accounts/patients).
    sessionCookie = superadminCookie;

    // 4. Tag the account: ['pxp', 'seed', 'patient']. The 'pxp' tag is
    //    hapihub's existing convention for accounts that claim a medical
    //    patient (per accounts.schema.ts comment about PXP mobile signup);
    //    we set it eagerly here so feature flags / queries that filter on
    //    that tag work end-to-end in the demo.
    try {
      await api("PATCH", `/accounts/${uid}`, {
        tags: ["pxp", "seed", "patient"],
      });
    } catch (err: unknown) {
      const msg = (err as Error).message;
      console.warn(
        chalk.yellow(`  ⚠  ${target.externalId}: failed to tag account — ${msg.slice(0, 120)}`),
      );
      // tags are non-critical, continue with the link
    }

    // 5. Link the medical-patient row to the account.
    try {
      await api("PATCH", `/medical-patients/${target.patientId}`, {
        account: uid,
      });
      patientsLinked++;
    } catch (err: unknown) {
      const msg = (err as Error).message;
      console.warn(
        chalk.yellow(`  ⚠  ${target.externalId}: failed to link account to patient — ${msg.slice(0, 120)}`),
      );
    }
  }

  // Restore superadmin so subsequent steps proceed cleanly.
  sessionCookie = superadminCookie;

  const accountSummary = `${accountsCreated} new + ${accountsExisting} existing`;
  if (skipped > 0) {
    spinner.warn(
      `Patient accounts: ${accountSummary} (skipped ${skipped}); ${patientsLinked}/${targets.length} medical-patients linked`,
    );
  } else {
    spinner.succeed(
      `Patient accounts: ${accountSummary}, ${patientsLinked}/${targets.length} medical-patients linked (account uids tagged ['pxp','seed','patient'])`,
    );
  }
  return results;
}

// ---------------------------------------------------------------------------
// Service catalog (multiple entries per service type, PHP-pricing realism)
// ---------------------------------------------------------------------------
// Service types per CreateServiceServiceRequest enum
// (apis/hapihub/src/services/components/schemas/CreateServiceServiceRequest.yaml):
//   fee | clinical-consultation | clinical-procedure | diagnostic | pe | dental | package
//
// Each service is identified by a deterministic externalId
// `SEED-SVC-<typeSlug>-<index>` so reruns are idempotent (lookup-first by
// (facility, externalId)). Same catalog seeded into both parent + branch.

interface ServiceTemplate {
  type:
    | "fee"
    | "clinical-consultation"
    | "clinical-procedure"
    | "diagnostic"
    | "pe"
    | "dental"
    | "package";
  name: string;
  description: string;
  subtype?: string;
  category?: string;
  price: number;          // PHP
  performNTimes?: number;
  normalTime?: number;     // minutes
  tags?: string[];
  /**
   * Names of EMR consent-form presets to attach to this service. Looked up
   * by `name` from the EMR FORM_TEMPLATE_PRESETS we seeded earlier (must
   * exist before services run — see ordering in main()). When omitted, a
   * sensible default is chosen based on the service type.
   */
  consentFormNames?: string[];
  /**
   * PE services only — names of the lab + imaging diagnostic-packages this
   * exam should book queue slots for. Looked up after LIS/RIS packages are
   * seeded. Resolved to the package id at POST time.
   */
  peLabPackage?: string;
  peImagingPackage?: string;
}

// Default consent-form bundle by service type. References EMR
// FORM_TEMPLATE_PRESETS names (apps/mycure/src/pages/emr/formTemplatePresets.ts).
const DEFAULT_CONSENT_FORMS_BY_TYPE: Record<ServiceTemplate["type"], string[]> = {
  fee: [],
  "clinical-consultation": [
    "General Consent for Treatment",
    "Data Privacy Consent (RA 10173)",
  ],
  "clinical-procedure": [
    "General Consent for Treatment",
    "Data Privacy Consent (RA 10173)",
    "Financial Responsibility Acknowledgment",
  ],
  diagnostic: [
    "General Consent for Treatment",
    "Data Privacy Consent (RA 10173)",
  ],
  pe: [
    "General Consent for Treatment",
    "Data Privacy Consent (RA 10173)",
    "Financial Responsibility Acknowledgment",
    "Release of Information to Third Party",
  ],
  dental: [
    "General Consent for Treatment",
    "Data Privacy Consent (RA 10173)",
  ],
  package: [
    "General Consent for Treatment",
    "Data Privacy Consent (RA 10173)",
  ],
};

const SERVICE_TEMPLATES: ServiceTemplate[] = [
  // ─── fee ──────────────────────────────────────────────────────
  { type: "fee", name: "Registration Fee", description: "One-time clinic registration", price: 50, tags: ["admin"] },
  { type: "fee", name: "Records Transcript Fee", description: "Per-page medical record copy", price: 100, tags: ["admin"] },
  { type: "fee", name: "Late Payment Fee", description: "Surcharge for overdue invoices", price: 300, tags: ["admin"] },
  { type: "fee", name: "Booking Cancellation Fee", description: "No-show / late cancellation", price: 250, tags: ["admin"] },

  // ─── clinical-consultation ────────────────────────────────────
  { type: "clinical-consultation", name: "General Consultation", description: "Walk-in OPD consult by GP", subtype: "gp", category: "outpatient", price: 700, normalTime: 20, tags: ["consult"] },
  { type: "clinical-consultation", name: "Follow-up Consultation", description: "Subsequent visit, same complaint", subtype: "follow-up", price: 500, normalTime: 15, tags: ["consult"] },
  { type: "clinical-consultation", name: "Specialist Consultation", description: "Internal medicine / pediatrics / OB-Gyne", subtype: "specialist", price: 1500, normalTime: 30, tags: ["consult", "specialist"] },
  {
    type: "clinical-consultation", name: "Telemedicine Consultation",
    description: "Online video consultation", subtype: "tele",
    price: 800, normalTime: 20, tags: ["consult", "tele"],
    // Telehealth has its own dedicated consent that supersedes the generic.
    consentFormNames: [
      "Telehealth Consultation Consent",
      "Data Privacy Consent (RA 10173)",
    ],
  },

  // ─── clinical-procedure ───────────────────────────────────────
  // Generic procedures (subtype is informational only).
  { type: "clinical-procedure", name: "Suturing (minor)",          description: "Wound suturing, simple lacerations",            subtype: "minor-surgery", price: 1500, normalTime: 30, tags: ["procedure"] },
  { type: "clinical-procedure", name: "IV Insertion / IVF Drip",   description: "Hydration, medication delivery",                subtype: "infusion",      price: 600,  normalTime: 20, tags: ["procedure"] },
  { type: "clinical-procedure", name: "Nebulization",              description: "Bronchodilator nebulization, single session",   subtype: "respiratory",   price: 350,  normalTime: 15, tags: ["procedure"] },
  { type: "clinical-procedure", name: "Wound Dressing",            description: "Sterile wound cleaning + dressing change",      subtype: "wound-care",    price: 400,  normalTime: 15, tags: ["procedure"] },
  { type: "clinical-procedure", name: "Removal of Sutures",        description: "Standard suture removal",                       subtype: "wound-care",    price: 500,  normalTime: 15, tags: ["procedure"] },
  // Procedures with PROCEDURE_ORDER_TYPES subtypes — these unlock
  // dedicated record forms / print templates in the EMR. Subtype enum
  // verified at packages/sdk/src/procedure/composables/procedures.ts:6.
  { type: "clinical-procedure", name: "Audiometry (Pure-Tone)",    description: "Pure-tone audiometry — hearing threshold testing for both ears (PEME requirement).", subtype: "audiometry",            price: 850,  normalTime: 30, tags: ["procedure", "peme"] },
  { type: "clinical-procedure", name: "Spirometry (Pulmonary Function Test)", description: "Spirometry / PFT — FVC, FEV1, FEV1/FVC ratio, pre/post bronchodilator (PEME requirement).", subtype: "spirometry",            price: 950,  normalTime: 30, tags: ["procedure", "peme"] },
  { type: "clinical-procedure", name: "Treadmill Stress Test",     description: "Bruce / modified Bruce protocol exercise stress ECG with cardiologist supervision.", subtype: "treadmill",             price: 3500, normalTime: 60, tags: ["procedure", "cardiology"] },
  { type: "clinical-procedure", name: "Ambulatory BP Monitoring (24-hour)", description: "24-hour automated BP monitoring using a wearable cuff, with day/night summary.", subtype: "ambulatory-bp-monitoring", price: 2800, normalTime: 30, tags: ["procedure", "cardiology"] },
  { type: "clinical-procedure", name: "Physical Therapy Session",  description: "One-on-one PT session — per session, 45 minutes.",                subtype: "physical-therapy",      price: 800,  normalTime: 45, tags: ["procedure", "rehab"] },

  // ─── diagnostic / lab (subtype=lab) ────────────────────────────
  // SDK uses `diagnostic/lab` as the type-pair; we POST `type=diagnostic`
  // + `subtype=lab` so the UI's filter shows them under Laboratory.
  // Name aligned to SEED_LIS_TESTS so service.ref lookup matches the test row.
  { type: "diagnostic", name: "Complete Blood Count (CBC)",          description: "Hematology panel — RBC, WBC, platelets, hgb",      subtype: "lab", category: "hematology",          price: 350,  normalTime: 30, tags: ["lab", "hematology"] },
  { type: "diagnostic", name: "Hemoglobin",                          description: "Hgb level — anemia screen",                         subtype: "lab", category: "hematology",          price: 180,  normalTime: 20, tags: ["lab", "hematology"] },
  { type: "diagnostic", name: "Platelet Count",                       description: "Platelet count for clotting/bleeding assessment",   subtype: "lab", category: "hematology",          price: 200,  normalTime: 20, tags: ["lab", "hematology"] },
  { type: "diagnostic", name: "Blood Typing (ABO/Rh)",                description: "ABO + Rh blood typing",                             subtype: "lab", category: "hematology",          price: 250,  normalTime: 30, tags: ["lab", "hematology"] },
  { type: "diagnostic", name: "Urinalysis",                           description: "Routine urinalysis",                                subtype: "lab", category: "clinical-microscopy", price: 200,  normalTime: 30, tags: ["lab"] },
  { type: "diagnostic", name: "Fecalysis",                            description: "Stool exam — parasitology + ova-cyst",              subtype: "lab", category: "clinical-microscopy", price: 220,  normalTime: 30, tags: ["lab"] },
  { type: "diagnostic", name: "Fasting Blood Sugar (FBS)",            description: "Glucose test, fasting",                             subtype: "lab", category: "chemistry",           price: 250,  normalTime: 30, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "HbA1c",                                description: "Glycated hemoglobin for diabetes monitoring",       subtype: "lab", category: "chemistry",           price: 850,  normalTime: 60, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "Lipid Profile",                        description: "Total cholesterol, HDL, LDL, triglycerides",         subtype: "lab", category: "chemistry",           price: 850,  normalTime: 60, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "Creatinine",                           description: "Renal function indicator",                          subtype: "lab", category: "chemistry",           price: 250,  normalTime: 30, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "BUN (Blood Urea Nitrogen)",            description: "Renal function — urea level",                       subtype: "lab", category: "chemistry",           price: 250,  normalTime: 30, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "SGPT/ALT",                             description: "Alanine aminotransferase — hepatic function",       subtype: "lab", category: "chemistry",           price: 280,  normalTime: 30, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "SGOT/AST",                             description: "Aspartate aminotransferase — hepatic function",     subtype: "lab", category: "chemistry",           price: 280,  normalTime: 30, tags: ["lab", "chemistry"] },
  { type: "diagnostic", name: "HBsAg (Hep B Surface Ag)",             description: "Hepatitis B surface antigen — screening",           subtype: "lab", category: "immunology",          price: 350,  normalTime: 30, tags: ["lab", "immunology"] },
  { type: "diagnostic", name: "HIV Screening",                        description: "Anti-HIV 1/2 rapid screening",                      subtype: "lab", category: "immunology",          price: 450,  normalTime: 30, tags: ["lab", "immunology"] },
  { type: "diagnostic", name: "Pregnancy Test (β-hCG)",               description: "Urine / serum hCG pregnancy test",                  subtype: "lab", category: "immunology",          price: 250,  normalTime: 20, tags: ["lab", "immunology"] },
  { type: "diagnostic", name: "Urine Culture & Sensitivity",          description: "Bacterial culture + antimicrobial susceptibility",  subtype: "lab", category: "microbiology",        price: 950,  normalTime: 4320, tags: ["lab", "microbiology"] },
  { type: "diagnostic", name: "Sputum Culture",                       description: "Sputum bacterial culture (TB, pneumonia)",          subtype: "lab", category: "microbiology",        price: 950,  normalTime: 4320, tags: ["lab", "microbiology"] },

  // ─── diagnostic / imaging (subtype=imaging) ────────────────────
  { type: "diagnostic", name: "Chest X-ray (PA view)",                description: "Single-view PA chest radiograph",                   subtype: "imaging", category: "radiology",       price: 600,  normalTime: 20, tags: ["imaging", "radiology"] },
  { type: "diagnostic", name: "Chest X-ray (PA + Lateral)",           description: "Two-view chest X-ray for thoracic evaluation",       subtype: "imaging", category: "radiology",       price: 850,  normalTime: 25, tags: ["imaging", "radiology"] },
  { type: "diagnostic", name: "Abdominal X-ray (Flat plate)",         description: "Plain abdominal radiograph",                        subtype: "imaging", category: "radiology",       price: 700,  normalTime: 20, tags: ["imaging", "radiology"] },
  { type: "diagnostic", name: "12-lead ECG",                          description: "Resting ECG with cardiologist reading",             subtype: "imaging", category: "cardiology",      price: 700,  normalTime: 20, tags: ["imaging", "cardiology"] },
  { type: "diagnostic", name: "Abdominal Ultrasound",                 description: "UTZ of liver, gallbladder, kidneys, pancreas",       subtype: "imaging", category: "ultrasound",      price: 1500, normalTime: 30, tags: ["imaging", "ultrasound"] },
  { type: "diagnostic", name: "Whole Abdomen Ultrasound",             description: "Comprehensive whole-abdomen UTZ",                   subtype: "imaging", category: "ultrasound",      price: 2200, normalTime: 45, tags: ["imaging", "ultrasound"] },
  { type: "diagnostic", name: "Pelvic Ultrasound (Female)",           description: "UTZ of female pelvic organs",                       subtype: "imaging", category: "ultrasound",      price: 1800, normalTime: 30, tags: ["imaging", "ultrasound"] },
  { type: "diagnostic", name: "Obstetric Ultrasound",                 description: "Pregnancy scan (transabdominal / transvaginal)",     subtype: "imaging", category: "ultrasound",      price: 1800, normalTime: 30, tags: ["imaging", "ultrasound", "obstetrics"] },
  { type: "diagnostic", name: "CT Scan — Cranial (Plain)",            description: "Non-contrast head CT",                              subtype: "imaging", category: "ct",              price: 5500, normalTime: 30, tags: ["imaging", "ct"] },
  { type: "diagnostic", name: "CT Scan — Whole Abdomen w/ Contrast",  description: "Contrast-enhanced abdominal CT",                    subtype: "imaging", category: "ct",              price: 8500, normalTime: 45, tags: ["imaging", "ct"] },
  { type: "diagnostic", name: "MRI — Brain (Plain + Contrast)",       description: "Brain MRI with gadolinium contrast",                subtype: "imaging", category: "mri",             price: 12500,normalTime: 60, tags: ["imaging", "mri"] },
  { type: "diagnostic", name: "MRI — Lumbar Spine",                   description: "Lumbosacral spine MRI",                             subtype: "imaging", category: "mri",             price: 11500,normalTime: 60, tags: ["imaging", "mri"] },
  { type: "diagnostic", name: "Mammography (Bilateral)",              description: "Bilateral mammogram screening",                     subtype: "imaging", category: "mammography",     price: 3500, normalTime: 30, tags: ["imaging", "mammography"] },

  // ─── pe (Physical Examination packages by use case) ──────────
  // PE services route patients through multiple queues (lab, imaging,
  // doctor) — each queue carries a diagnostic-package reference so the
  // examiner sees a pre-filled order set. Package names below MUST match
  // SEED_LIS_PACKAGES / SEED_RIS_PACKAGES.
  {
    type: "pe", name: "Pre-Employment PE",
    description: "Standard PE for employment clearance",
    subtype: "pre-employment", price: 1800, normalTime: 60,
    tags: ["pe", "occupational"],
    peLabPackage: "Basic Health Screen",
    peImagingPackage: "Pre-Employment Imaging",
  },
  {
    type: "pe", name: "Annual PE",
    description: "Yearly health check-up",
    subtype: "annual", price: 2200, normalTime: 60,
    tags: ["pe"],
    peLabPackage: "Basic Health Screen",
    peImagingPackage: "Pre-Employment Imaging",
  },
  {
    type: "pe", name: "Maritime / Seafarer PE",
    description: "PEME-style check for seafarers",
    subtype: "maritime", price: 3500, normalTime: 90,
    tags: ["pe", "maritime"],
    // Seafarers need diabetes screening per PEME guidance.
    peLabPackage: "Diabetes Workup",
    peImagingPackage: "Pre-Employment Imaging",
  },
  {
    type: "pe", name: "Driver's License PE",
    description: "LTO medical certificate",
    subtype: "drivers", price: 600, normalTime: 30,
    tags: ["pe", "drivers"],
    // Driver's PE is light — no imaging by default; just basic blood work.
    peLabPackage: "Basic Health Screen",
  },

  // ─── dental ───────────────────────────────────────────────────
  { type: "dental", name: "Oral Prophylaxis (Cleaning)", description: "Routine dental cleaning", subtype: "preventive", price: 1200, normalTime: 45, tags: ["dental"] },
  { type: "dental", name: "Tooth Extraction (simple)", description: "Erupted tooth, no complications", subtype: "surgery", price: 1500, normalTime: 30, tags: ["dental"] },
  { type: "dental", name: "Pasta Filling (composite)", description: "Light-cure composite restoration, per tooth", subtype: "restorative", price: 1800, normalTime: 45, tags: ["dental"] },
  { type: "dental", name: "Dental Crown (porcelain)", description: "Single porcelain crown", subtype: "prosthodontics", price: 12000, normalTime: 60, tags: ["dental"] },

  // ─── package ──────────────────────────────────────────────────
  { type: "package", name: "Executive APE Package", description: "Comprehensive annual physical exam — includes CBC, urinalysis, FBS, lipid profile, chest X-ray, ECG, GP consult", price: 5500, normalTime: 120, tags: ["package", "ape"] },
  { type: "package", name: "Basic Blood Panel", description: "CBC + urinalysis + FBS bundled", price: 700, normalTime: 60, tags: ["package", "lab"] },
  { type: "package", name: "Pre-Employment Package", description: "Pre-employment PE + chest X-ray + drug test bundle", price: 2500, normalTime: 120, tags: ["package", "occupational"] },
];

function serviceSlug(template: ServiceTemplate, index: number): string {
  // Stable slug derived from (type, sequence within type) for deterministic
  // externalIds across reruns. The `index` is the position in SERVICE_TEMPLATES.
  return `${template.type}-${String(index).padStart(2, "0")}`;
}

// Per-facility lookup tables — built once before seedServices runs from
// the entities seeded in earlier steps (form-templates, queues, packages).
// All keyed by name → id with one map per facility. `undefined` is a
// best-effort signal that the lookup turned up empty (the seed continues
// without the reference rather than aborting).
interface ServiceRefs {
  /** form-template id by display name (covers ALL types — consent, EMR, PME, LIS, RIS). */
  consentFormByName: Map<string, string>;
  /** queue id by name. */
  queueByName: Map<string, string>;
  /** queue id by type — used for "first queue with type X" fallback. */
  queueByType: Map<string, string>;
  /** lab package id by name. */
  labPackageByName: Map<string, string>;
  /** radiology package id by name. */
  imagingPackageByName: Map<string, string>;
  /**
   * diagnostic-test id by (kind, name). Used to populate `service.ref` on
   * lab/imaging billing services so hapihub can auto-link the two — see
   * services/hapihub/src/services/service/services.ts:313 (when ref is
   * set, testSection + testSectionCode get populated from the test row).
   */
  labTestByName: Map<string, string>;
  imagingTestByName: Map<string, string>;
}

async function buildServiceRefsForFacility(facilityId: string): Promise<ServiceRefs> {
  // form-templates: fetch all for this facility, index by name. Server
  // applies the includeQueryFields whitelist to /form-templates so we
  // can't filter by name. Client-side dedup is fine here.
  const consentFormByName = new Map<string, string>();
  try {
    const res = (await api(
      "GET",
      `/form-templates?facility=${encodeURIComponent(facilityId)}&%24limit=500`,
    )) as { data?: Array<{ id: string; name?: string }> } | Array<{ id: string; name?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    for (const t of list) if (t.name && t.id) consentFormByName.set(t.name, t.id);
  } catch { /* leave empty — services proceed without consent refs */ }

  // queues: fetch all for this facility, index by name AND by type.
  const queueByName = new Map<string, string>();
  const queueByType = new Map<string, string>();
  try {
    const res = (await api(
      "GET",
      `/queues?organization=${encodeURIComponent(facilityId)}&%24limit=500`,
    )) as { data?: Array<{ id: string; name?: string; type?: string }> } | Array<{ id: string; name?: string; type?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    for (const q of list) {
      if (q.name && q.id) queueByName.set(q.name, q.id);
      if (q.type && q.id && !queueByType.has(q.type)) queueByType.set(q.type, q.id);
    }
  } catch { /* leave empty — PE queueing skipped */ }

  // diagnostic-packages: fetch ALL for this facility (both lab and radiology
  // come back in one call — split client-side by `type`).
  const labPackageByName = new Map<string, string>();
  const imagingPackageByName = new Map<string, string>();
  try {
    const res = (await api(
      "GET",
      `/diagnostic-packages?facility=${encodeURIComponent(facilityId)}&%24limit=500`,
    )) as { data?: Array<{ id: string; name?: string; type?: string }> } | Array<{ id: string; name?: string; type?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    for (const p of list) {
      if (!p.name || !p.id) continue;
      if (p.type === "laboratory") labPackageByName.set(p.name, p.id);
      else if (p.type === "radiology") imagingPackageByName.set(p.name, p.id);
    }
  } catch { /* leave empty */ }

  // diagnostic-tests: split client-side by `type` (laboratory|radiology).
  const labTestByName = new Map<string, string>();
  const imagingTestByName = new Map<string, string>();
  try {
    const res = (await api(
      "GET",
      `/diagnostic-tests?facility=${encodeURIComponent(facilityId)}&%24limit=500`,
    )) as { data?: Array<{ id: string; name?: string; type?: string }> } | Array<{ id: string; name?: string; type?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    for (const t of list) {
      if (!t.name || !t.id) continue;
      if (t.type === "laboratory") labTestByName.set(t.name, t.id);
      else if (t.type === "radiology") imagingTestByName.set(t.name, t.id);
    }
  } catch { /* leave empty — diagnostic services lose ref linkage */ }

  return {
    consentFormByName,
    queueByName,
    queueByType,
    labPackageByName,
    imagingPackageByName,
    labTestByName,
    imagingTestByName,
  };
}

function buildServiceBody(
  facility: string,
  template: ServiceTemplate,
  index: number,
  refs: ServiceRefs,
): Record<string, unknown> {
  const slug = serviceSlug(template, index);

  // Resolve consent forms: per-template override wins, otherwise default
  // by service type. Names that don't resolve are silently dropped.
  const consentNames = template.consentFormNames ?? DEFAULT_CONSENT_FORMS_BY_TYPE[template.type];
  const consentForms = consentNames
    .map((n) => refs.consentFormByName.get(n))
    .filter((id): id is string => !!id);

  // PE queueing: build [lab, imaging, doctor] queue entries pointing to
  // the configured packages. Each entry mirrors the SDK's serialize
  // shape (queueing → { queue, queues, queueTypes, meta }) — see
  // packages/sdk/src/services/composables/services.ts.
  const queueing: Array<Record<string, unknown>> = [];
  if (template.type === "pe") {
    const labQueueId = refs.queueByType.get("lab");
    const imagingQueueId = refs.queueByType.get("imaging");
    const doctorQueueId = refs.queueByType.get("doctor");

    if (template.peLabPackage && labQueueId) {
      const pkgId = refs.labPackageByName.get(template.peLabPackage);
      if (pkgId) {
        queueing.push({
          queue: labQueueId,
          queues: [labQueueId],
          queueTypes: ["lab"],
          meta: { testPackage: pkgId },
        });
      }
    }
    if (template.peImagingPackage && imagingQueueId) {
      const pkgId = refs.imagingPackageByName.get(template.peImagingPackage);
      if (pkgId) {
        queueing.push({
          queue: imagingQueueId,
          queues: [imagingQueueId],
          queueTypes: ["imaging"],
          meta: { testPackage: pkgId },
        });
      }
    }
    if (doctorQueueId) {
      queueing.push({
        queue: doctorQueueId,
        queues: [doctorQueueId],
        queueTypes: ["doctor"],
      });
    }
  }

  // Diagnostic services link to their matching diagnostic-test row via
  // `ref`. Hapihub auto-populates testSection + testSectionCode from the
  // referenced test (services.ts:313). Lookup is by name within the
  // matching kind (lab → labTestByName, imaging → imagingTestByName).
  let ref: string | undefined;
  if (template.type === "diagnostic") {
    const lookup =
      template.subtype === "lab"
        ? refs.labTestByName
        : template.subtype === "imaging"
          ? refs.imagingTestByName
          : undefined;
    ref = lookup?.get(template.name);
  }

  return {
    facility,
    type: template.type,
    name: template.name,
    description: template.description,
    externalId: `SEED-SVC-${slug}`,
    ...(template.subtype ? { subtype: template.subtype } : {}),
    ...(template.category ? { category: template.category } : {}),
    ...(ref ? { ref } : {}),
    price: template.price,
    priceCurrency: "PHP",
    ...(template.performNTimes ? { performNTimes: template.performNTimes } : {}),
    ...(template.normalTime ? { normalTime: template.normalTime } : {}),
    tags: ["seed", "demo", ...(template.tags ?? [])],
    metadata: {
      seed: true,
      seedTemplate: slug,
    },
    isPublic: false,
    isGlobal: false,
    requireBillingItemProvider: false,
    ...(consentForms.length > 0 ? { consentForms } : {}),
    ...(queueing.length > 0 ? { queueing } : {}),
  };
}

async function serviceExists(facility: string, externalId: string): Promise<boolean> {
  try {
    const res = (await api(
      "GET",
      `/services?facility=${encodeURIComponent(facility)}&externalId=${encodeURIComponent(externalId)}&$limit=1`,
    )) as { data?: Array<unknown> } | Array<unknown>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list.length > 0;
  } catch {
    return false;
  }
}

async function seedServices(facilities: { id: string; label: string }[]): Promise<void> {
  const total = SERVICE_TEMPLATES.length * facilities.length;
  const spinner = ora(
    `Seeding ${total} services (${SERVICE_TEMPLATES.length} per facility, across all 7 types)...`,
  ).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;
  let consentRefsApplied = 0;
  let queueingApplied = 0;
  let unresolvedConsent = 0;
  let unresolvedQueueing = 0;
  let testRefsApplied = 0;
  let unresolvedTestRef = 0;

  for (const facility of facilities) {
    spinner.text = `[${facility.label}] resolving service references (consent forms, queues, packages)...`;
    const refs = await buildServiceRefsForFacility(facility.id);

    for (let i = 0; i < SERVICE_TEMPLATES.length; i++) {
      const template = SERVICE_TEMPLATES[i];
      const slug = serviceSlug(template, i);
      const externalId = `SEED-SVC-${slug}`;
      progress++;
      spinner.text = `[${facility.label}] ${template.type} / ${template.name} (${progress}/${total})`;

      if (await serviceExists(facility.id, externalId)) {
        skipped++;
        continue;
      }

      const body = buildServiceBody(facility.id, template, i, refs);

      // Telemetry for the summary line
      const expectedConsents =
        template.consentFormNames ?? DEFAULT_CONSENT_FORMS_BY_TYPE[template.type];
      const actualConsents = (body.consentForms as string[] | undefined)?.length ?? 0;
      if (actualConsents > 0) consentRefsApplied++;
      if (expectedConsents.length > 0 && actualConsents < expectedConsents.length) {
        unresolvedConsent += expectedConsents.length - actualConsents;
      }
      if (template.type === "pe") {
        const actualQueues = (body.queueing as unknown[] | undefined)?.length ?? 0;
        if (actualQueues > 0) queueingApplied++;
        // For PE we expect lab + imaging + doctor (3 ideal, 2 if no imaging
        // configured). Treat anything below the configured count as unresolved.
        const expected =
          (template.peLabPackage ? 1 : 0) +
          (template.peImagingPackage ? 1 : 0) +
          1; // doctor queue is always added when a doctor queue exists
        if (actualQueues < expected) unresolvedQueueing += expected - actualQueues;
      }
      if (
        template.type === "diagnostic" &&
        (template.subtype === "lab" || template.subtype === "imaging")
      ) {
        if (body.ref) testRefsApplied++;
        else unresolvedTestRef++;
      }

      try {
        await api("POST", "/services", body);
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create '${template.name}' (${externalId}): ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  // Per-type breakdown for the summary
  const byType = SERVICE_TEMPLATES.reduce<Record<string, number>>((acc, t) => {
    acc[t.type] = (acc[t.type] ?? 0) + 1;
    return acc;
  }, {});
  const typeBreakdown = Object.entries(byType)
    .map(([t, n]) => `${t}=${n}`)
    .join(", ");

  const diagLabImagingCount =
    SERVICE_TEMPLATES.filter(
      (t) => t.type === "diagnostic" && (t.subtype === "lab" || t.subtype === "imaging"),
    ).length * facilities.length;
  const refSummary =
    `consent on ${consentRefsApplied}/${total}` +
    `, queueing on ${queueingApplied}/${SERVICE_TEMPLATES.filter((t) => t.type === "pe").length * facilities.length}` +
    `, dx-test ref on ${testRefsApplied}/${diagLabImagingCount}` +
    (unresolvedConsent || unresolvedQueueing || unresolvedTestRef
      ? ` (${unresolvedConsent} consent + ${unresolvedQueueing} queueing + ${unresolvedTestRef} dx-test refs unresolved)`
      : "");

  spinner.succeed(
    `Services: ${created} new, ${skipped} skipped — ${total} total target (${typeBreakdown}); ${refSummary}`,
  );
}

// ---------------------------------------------------------------------------
// Org-level config arrays
// ---------------------------------------------------------------------------
// Six "settings" pages (Adjustment Reasons, Stock Rooms, Product Types,
// Payment Methods, Tax Types) are NOT separate entities — they're stored as
// JSON arrays on the parent organization record. The mycure UI just patches
// the org. We mirror that here and merge with whatever's already on the org
// so reruns don't overwrite real data the user added by hand.
//
// Field mapping (verified against packages/sdk/src/{inventory,billing}/composables):
//   - Adjustment reasons → org.wh_stockAdjustmentReasons (string[])
//   - Stock rooms        → org.configInventory.stockRooms  (string[])
//   - Product types      → org.wh_productTypes             (string[])
//   - Payment methods    → org.bl_paymentMethods           ({code,type,name,description}[])
//                          + org.bl_defaultPaymentMethod   (string code)
//   - Tax types          → org.bl_taxTypes                 ({code,name,value,description}[])
//                          + org.configBilling.taxTypes    (mirror of bl_taxTypes)
//                          + org.configBilling.taxTypeServiceSalesDefault (string code)
//                          + org.configBilling.taxTypeProductSalesDefault (string code)

const SEED_ADJUSTMENT_REASONS = [
  "Damaged",
  "Expired",
  "Lost",
  "Stolen",
  "Returned to Supplier",
  "Quality Defect",
  "Inventory Count Adjustment",
];

const SEED_STOCK_ROOMS = [
  "Main Pharmacy",
  "Lab Stock Room",
  "Front Desk Cabinet",
  "Cold Storage",
];

const SEED_PRODUCT_TYPES = [
  "Medicine",
  "Medical Supplies",
  "Lab Reagent",
  "PPE",
  "Office Supply",
  "Equipment",
];

// LIS Specimen Report Recipients — stored as a string array on
// organizations.configLIS.orderTestsReportTargets (verified against
// packages/sdk/src/diagnostics/composables/specimen-report-recipients.ts).
// Same patch-the-org pattern as adjustment reasons / stock rooms.
const SEED_LIS_REPORT_RECIPIENTS = [
  "Patient",
  "Referring Physician",
  "Attending Physician",
  "HMO / Insurance",
  "Company HR / Occupational Health",
  "Insurance Company",
  "School Health Office",
];

interface SeedPaymentMethod {
  code: string;
  type: "cash" | "check" | "card" | "credit" | "others";
  name: string;
  description?: string;
}

const SEED_PAYMENT_METHODS: SeedPaymentMethod[] = [
  // "Cash" is auto-injected by the UI list, but we add an explicit row anyway
  // so the org-level config is self-contained without UI fallbacks.
  { code: "CASH", type: "cash", name: "Cash", description: "Cash payment" },
  { code: "GCASH", type: "others", name: "GCash", description: "GCash mobile wallet" },
  { code: "MAYA", type: "others", name: "Maya", description: "Maya / PayMaya wallet" },
  { code: "BPI", type: "card", name: "BPI Credit Card", description: "BPI Visa / Mastercard" },
  { code: "BDO", type: "card", name: "BDO Credit / Debit", description: "BDO Visa / Mastercard" },
  { code: "CHEQUE", type: "check", name: "Personal Check", description: "Personal / company cheque" },
  { code: "BANKXFER", type: "others", name: "Bank Transfer", description: "Online bank transfer / InstaPay / PESONet" },
];
const SEED_DEFAULT_PAYMENT_METHOD = "CASH";

interface SeedTaxType {
  code: string;
  name: string;
  value: number;        // rate %
  description?: string;
}

const SEED_TAX_TYPES: SeedTaxType[] = [
  { code: "VAT12", name: "Value Added Tax (12%)", value: 12, description: "Standard VAT for goods and services" },
  { code: "VAT0", name: "VAT Exempt (0%)", value: 0, description: "Exempt sales (medical services for some categories)" },
  { code: "PT3", name: "Percentage Tax (3%)", value: 3, description: "Non-VAT registered, gross receipts" },
];
const SEED_DEFAULT_TAX_SERVICE = "VAT0";   // medical services often VAT-exempt
const SEED_DEFAULT_TAX_PRODUCT = "VAT12";  // products taxed at 12%

async function getOrg(orgId: string): Promise<Record<string, unknown>> {
  // Just fetch the whole org — body is small and $select array encoding
  // varies across Feathers/Drizzle versions. The fields we touch are all
  // top-level so we read them directly off the response.
  const res = (await api("GET", `/organizations/${orgId}`)) as Record<string, unknown>;
  return res ?? {};
}

async function patchOrg(orgId: string, body: Record<string, unknown>): Promise<void> {
  await api("PATCH", `/organizations/${orgId}`, body);
}

async function seedOrgConfig(facilities: { id: string; label: string }[]): Promise<void> {
  const spinner = ora("Seeding org config (payment methods, tax types, inventory lists)...").start();

  for (const facility of facilities) {
    spinner.text = `[${facility.label}] reading current org config...`;
    const org = await getOrg(facility.id);

    // Merge: keep anything already present, add only what's missing.
    const existingReasons = (org.wh_stockAdjustmentReasons as string[] | undefined) ?? [];
    const mergedReasons = Array.from(new Set([...existingReasons, ...SEED_ADJUSTMENT_REASONS]));

    const existingProductTypes = (org.wh_productTypes as string[] | undefined) ?? [];
    const mergedProductTypes = Array.from(new Set([...existingProductTypes, ...SEED_PRODUCT_TYPES]));

    const existingConfigInventory =
      (org.configInventory as Record<string, unknown> | undefined) ?? {};
    const existingStockRooms = (existingConfigInventory.stockRooms as string[] | undefined) ?? [];
    const mergedStockRooms = Array.from(new Set([...existingStockRooms, ...SEED_STOCK_ROOMS]));

    const existingPayments =
      (org.bl_paymentMethods as SeedPaymentMethod[] | undefined) ?? [];
    const existingPaymentCodes = new Set(existingPayments.map((p) => p.code));
    const mergedPayments = [
      ...existingPayments,
      ...SEED_PAYMENT_METHODS.filter((p) => !existingPaymentCodes.has(p.code)),
    ];

    const existingTaxes = (org.bl_taxTypes as SeedTaxType[] | undefined) ?? [];
    const existingTaxCodes = new Set(existingTaxes.map((t) => t.code));
    const mergedTaxes = [
      ...existingTaxes,
      ...SEED_TAX_TYPES.filter((t) => !existingTaxCodes.has(t.code)),
    ];

    const existingConfigBilling =
      (org.configBilling as Record<string, unknown> | undefined) ?? {};

    // LIS specimen report recipients — string array nested under configLIS
    const existingConfigLIS =
      (org.configLIS as Record<string, unknown> | undefined) ?? {};
    const existingRecipients =
      (existingConfigLIS.orderTestsReportTargets as string[] | undefined) ?? [];
    const mergedRecipients = Array.from(
      new Set([...existingRecipients, ...SEED_LIS_REPORT_RECIPIENTS]),
    );

    spinner.text = `[${facility.label}] patching org config...`;
    await patchOrg(facility.id, {
      wh_stockAdjustmentReasons: mergedReasons,
      wh_productTypes: mergedProductTypes,
      configInventory: {
        ...existingConfigInventory,
        stockRooms: mergedStockRooms,
      },
      bl_paymentMethods: mergedPayments,
      bl_defaultPaymentMethod:
        org.bl_defaultPaymentMethod ?? SEED_DEFAULT_PAYMENT_METHOD,
      bl_taxTypes: mergedTaxes,
      configBilling: {
        ...existingConfigBilling,
        taxTypes: mergedTaxes,
        taxTypeServiceSalesDefault:
          existingConfigBilling.taxTypeServiceSalesDefault ?? SEED_DEFAULT_TAX_SERVICE,
        taxTypeProductSalesDefault:
          existingConfigBilling.taxTypeProductSalesDefault ?? SEED_DEFAULT_TAX_PRODUCT,
      },
      configLIS: {
        ...existingConfigLIS,
        orderTestsReportTargets: mergedRecipients,
      },
    });
  }

  spinner.succeed(
    `Org config: ${SEED_ADJUSTMENT_REASONS.length} reasons, ${SEED_STOCK_ROOMS.length} stock rooms, ${SEED_PRODUCT_TYPES.length} product types, ${SEED_PAYMENT_METHODS.length} payment methods, ${SEED_TAX_TYPES.length} tax types, ${SEED_LIS_REPORT_RECIPIENTS.length} LIS recipients per facility`,
  );
}

// ---------------------------------------------------------------------------
// Inventory Suppliers (real entity at /inventory-suppliers)
// ---------------------------------------------------------------------------
// Required field per packages/sdk/src/inventory/composables/suppliers.ts:
//   warehouse (org id), name. Plus optional description/email/phone/website
//   /address. We dedup on (warehouse, name) since name is the natural key
//   exposed in the UI.

interface SupplierTemplate {
  name: string;
  description: string;
  email?: string;
  phone?: string;
  website?: string;
  address?: {
    street1?: string;
    city?: string;
    province?: string;
    country?: string;
  };
}

const SEED_SUPPLIERS: SupplierTemplate[] = [
  {
    name: "MedExpress Distributors",
    description: "Pharmaceutical wholesale supplier (Metro Manila branch).",
    email: "orders@medexpress.example.ph",
    phone: "+6328123456",
    website: "https://medexpress.example.ph",
    address: { street1: "12 Mabini St", city: "Manila", province: "Metro Manila", country: "PHL" },
  },
  {
    name: "HealthCare Logistics PH",
    description: "Medical supplies and consumables — nationwide delivery.",
    email: "sales@hclph.example.ph",
    phone: "+6332456789",
    address: { street1: "88 Osmeña Blvd", city: "Cebu City", province: "Cebu", country: "PHL" },
  },
  {
    name: "DiagnoTech Solutions",
    description: "Diagnostic reagents and lab consumables distributor.",
    email: "support@diagnotech.example.ph",
    phone: "+6327654321",
    address: { street1: "45 Commonwealth Ave", city: "Quezon City", province: "Metro Manila", country: "PHL" },
  },
  {
    name: "Mediplus Wholesale Inc.",
    description: "General medical supplies, PPE, and clinic equipment.",
    email: "wholesale@mediplus.example.ph",
    phone: "+6382334567",
    address: { street1: "120 J.P. Laurel Ave", city: "Davao City", province: "Davao del Sur", country: "PHL" },
  },
  {
    name: "LabPharma Inc.",
    description: "Laboratory chemistry reagents and immunoassay kits.",
    email: "info@labpharma.example.ph",
    phone: "+6328765432",
    address: { street1: "23 Shaw Blvd", city: "Pasig", province: "Metro Manila", country: "PHL" },
  },
];

async function findSupplier(warehouse: string, name: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/inventory-suppliers?warehouse=${encodeURIComponent(warehouse)}&name=${encodeURIComponent(name)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedSuppliers(facilities: { id: string; label: string }[]): Promise<void> {
  const total = SEED_SUPPLIERS.length * facilities.length;
  const spinner = ora(`Seeding ${total} inventory suppliers (${SEED_SUPPLIERS.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const tpl of SEED_SUPPLIERS) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.name} (${progress}/${total})`;

      const existing = await findSupplier(facility.id, tpl.name);
      if (existing) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/inventory-suppliers", {
          warehouse: facility.id,
          name: tpl.name,
          description: tpl.description,
          email: tpl.email,
          phone: tpl.phone,
          website: tpl.website,
          address: tpl.address,
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create supplier '${tpl.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`Suppliers: ${created} new, ${skipped} skipped — ${total} total target`);
}

// ---------------------------------------------------------------------------
// Service Providers (real entity at /service-providers)
// ---------------------------------------------------------------------------
// Links a clinician (account uid) to a service with a reader's-fee commission
// (% of the service price). The mycure SDK populates `provider` from accounts
// and `service` from services, so we POST { facility, provider, service,
// commissionsPost }. Dedup on (facility, provider, service).
//
// Body shape verified from
//   packages/sdk/src/services/composables/provider-commission.ts
//   services/hapihub/src/services/service/providers.ts

interface ProviderAssignment {
  /** seed user email — looked up to its account uid at runtime */
  userEmail: string;
  /** SERVICE_TEMPLATES.type — match the first template of this type */
  serviceType: ServiceTemplate["type"];
  /** Match by name (within the type) for deterministic targeting. */
  serviceName: string;
  /** Reader's-fee percentage (0-100). */
  readersFeePercentage: number;
}

const SEED_PROVIDER_ASSIGNMENTS: ProviderAssignment[] = [
  // Internist (Dr. Cruz) — General + Follow-up + Specialist
  { userEmail: "doctor@mycure.test",   serviceName: "General Consultation",         serviceType: "clinical-consultation", readersFeePercentage: 70 },
  { userEmail: "doctor@mycure.test",   serviceName: "Follow-up Consultation",       serviceType: "clinical-consultation", readersFeePercentage: 70 },
  { userEmail: "doctor@mycure.test",   serviceName: "Specialist Consultation",      serviceType: "clinical-consultation", readersFeePercentage: 80 },
  // Pediatrician (Dr. Reyes) — general consults + telemedicine
  { userEmail: "pedia@mycure.test",    serviceName: "General Consultation",         serviceType: "clinical-consultation", readersFeePercentage: 70 },
  { userEmail: "pedia@mycure.test",    serviceName: "Follow-up Consultation",       serviceType: "clinical-consultation", readersFeePercentage: 70 },
  { userEmail: "pedia@mycure.test",    serviceName: "Telemedicine Consultation",    serviceType: "clinical-consultation", readersFeePercentage: 75 },
  // Family medicine (Dr. Santos) — general + telemed + specialist
  { userEmail: "familymd@mycure.test", serviceName: "General Consultation",         serviceType: "clinical-consultation", readersFeePercentage: 70 },
  { userEmail: "familymd@mycure.test", serviceName: "Specialist Consultation",      serviceType: "clinical-consultation", readersFeePercentage: 80 },
  { userEmail: "familymd@mycure.test", serviceName: "Telemedicine Consultation",    serviceType: "clinical-consultation", readersFeePercentage: 75 },
  // Nurse procedures (small commission for procedural support)
  { userEmail: "nurse@mycure.test",    serviceName: "Nebulization",                 serviceType: "clinical-procedure",    readersFeePercentage: 20 },
  { userEmail: "nurse@mycure.test",    serviceName: "IV Insertion / IVF Drip",      serviceType: "clinical-procedure",    readersFeePercentage: 20 },
  // Imaging tech reads X-ray / ECG / UTZ
  { userEmail: "imaging@mycure.test",  serviceName: "Chest X-ray (PA view)",        serviceType: "diagnostic",            readersFeePercentage: 40 },
  { userEmail: "imaging@mycure.test",  serviceName: "Chest X-ray (PA + Lateral)",   serviceType: "diagnostic",            readersFeePercentage: 40 },
  { userEmail: "imaging@mycure.test",  serviceName: "12-lead ECG",                  serviceType: "diagnostic",            readersFeePercentage: 40 },
  { userEmail: "imaging@mycure.test",  serviceName: "Abdominal Ultrasound",         serviceType: "diagnostic",            readersFeePercentage: 50 },
  { userEmail: "imaging@mycure.test",  serviceName: "Obstetric Ultrasound",         serviceType: "diagnostic",            readersFeePercentage: 50 },
];

async function findServiceByName(
  facility: string,
  type: string,
  name: string,
): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/services?facility=${encodeURIComponent(facility)}&type=${encodeURIComponent(type)}&name=${encodeURIComponent(name)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function findServiceProvider(
  facility: string,
  provider: string,
  service: string,
): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/service-providers?facility=${encodeURIComponent(facility)}&provider=${encodeURIComponent(provider)}&service=${encodeURIComponent(service)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedServiceProviders(
  facilities: { id: string; label: string }[],
  userIds: Record<string, string>,
): Promise<void> {
  const total = SEED_PROVIDER_ASSIGNMENTS.length * facilities.length;
  const spinner = ora(`Seeding ${total} service-provider assignments...`).start();
  let created = 0;
  let skipped = 0;
  let missing = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const assignment of SEED_PROVIDER_ASSIGNMENTS) {
      progress++;
      spinner.text =
        `[${facility.label}] ${assignment.userEmail} → ${assignment.serviceName} (${progress}/${total})`;

      const providerUid = userIds[assignment.userEmail];
      if (!providerUid) {
        missing++;
        continue;
      }

      const serviceId = await findServiceByName(
        facility.id,
        assignment.serviceType,
        assignment.serviceName,
      );
      if (!serviceId) {
        missing++;
        continue;
      }

      const existing = await findServiceProvider(facility.id, providerUid, serviceId);
      if (existing) {
        skipped++;
        continue;
      }

      try {
        // Note: hapihub auto-derives `facility` from the service, and the
        // create-side ALLOWED_CREATE_FIELDS list rejects `facility` outright
        // (see services/hapihub/src/services/service/providers.ts:21).
        await api("POST", "/service-providers", {
          provider: providerUid,
          service: serviceId,
          commissionsPost: [
            { type: "readersfee", percentage: assignment.readersFeePercentage },
          ],
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(
          `Failed to assign ${assignment.userEmail} → ${assignment.serviceName}: ${msg.slice(0, 200)}`,
        );
        process.exit(1);
      }
    }
  }

  spinner.succeed(
    `Service providers: ${created} new, ${skipped} skipped, ${missing} unmatched — ${total} target`,
  );
}

// ---------------------------------------------------------------------------
// Withholding Taxes (organization-member field)
// ---------------------------------------------------------------------------
// The "Withholding Taxes" page is a filtered view of organization-members
// where withholdingTax > 0. Patch the doctor + nurse memberships in each org
// with a default rate. Idempotent: PATCH overwrites with the same value.

interface WithholdingTaxAssignment {
  userEmail: string;
  /** percentage 0-100 */
  withholdingTax: number;
}

const SEED_WITHHOLDING_TAXES: WithholdingTaxAssignment[] = [
  { userEmail: "doctor@mycure.test", withholdingTax: 10 },
  { userEmail: "nurse@mycure.test",  withholdingTax: 5 },
];

async function findMembership(uid: string, organization: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/organization-members?uid=${encodeURIComponent(uid)}&organization=${encodeURIComponent(organization)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedWithholdingTaxes(
  facilities: { id: string; label: string }[],
  userIds: Record<string, string>,
): Promise<void> {
  const total = SEED_WITHHOLDING_TAXES.length * facilities.length;
  const spinner = ora(`Setting withholding tax on ${total} member rows...`).start();
  let updated = 0;
  let missing = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const wt of SEED_WITHHOLDING_TAXES) {
      progress++;
      spinner.text =
        `[${facility.label}] ${wt.userEmail} → ${wt.withholdingTax}% (${progress}/${total})`;

      const uid = userIds[wt.userEmail];
      if (!uid) {
        missing++;
        continue;
      }
      const memberId = await findMembership(uid, facility.id);
      if (!memberId) {
        missing++;
        continue;
      }

      try {
        await api("PATCH", `/organization-members/${memberId}`, {
          withholdingTax: wt.withholdingTax,
        });
        updated++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(
          `Failed to set withholdingTax on ${wt.userEmail}: ${msg.slice(0, 200)}`,
        );
        process.exit(1);
      }
    }
  }

  spinner.succeed(
    `Withholding tax: ${updated} memberships updated, ${missing} unmatched — ${total} target`,
  );
}

// ---------------------------------------------------------------------------
// PME Form Templates (real entity at /form-templates, type=ape-report)
// ---------------------------------------------------------------------------
// The mycure UI ships a set of starter PME presets (5 of them) at
//   apps/mycure/src/pages/pme/reportTemplatePresets.ts
// We dynamically import them when the sibling `mycure` repo is checked out
// alongside `mycure-infra` (default workspace layout). When unavailable the
// step is skipped with a warning rather than failing the whole seed.
//
// Body shape verified from apps/mycure/src/pages/pme/FormTemplateDetail.vue
// submit handler:
//   { type: 'ape-report', facility, name, description, template (HTML),
//     items: [...multiplechoice items], config: { hide* flags + records } }

interface PmeReportPreset {
  id: string;
  name: string;
  description: string;
  template: string;
  items?: Array<{ question: string; type: "multiplechoice"; choices: string[] }>;
}

async function loadPmeReportPresets(): Promise<PmeReportPreset[] | null> {
  // Try to find the sibling mycure repo. Default layout:
  //   <ws>/mycure-infra/scripts/seed.ts        ← __dirname
  //   <ws>/mycure/apps/mycure/src/pages/pme/reportTemplatePresets.ts
  const candidates = [
    `${import.meta.dir}/../../mycure/apps/mycure/src/pages/pme/reportTemplatePresets.ts`,
    `${import.meta.dir}/../../../mycure/apps/mycure/src/pages/pme/reportTemplatePresets.ts`,
  ];
  for (const path of candidates) {
    try {
      const file = Bun.file(path);
      if (!(await file.exists())) continue;
      const mod = await import(path);
      if (Array.isArray(mod.PME_REPORT_PRESETS)) {
        return mod.PME_REPORT_PRESETS as PmeReportPreset[];
      }
    } catch {
      // try next candidate
    }
  }
  return null;
}

async function findFormTemplate(
  facility: string,
  type: string,
  name: string,
): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/form-templates?facility=${encodeURIComponent(facility)}&type=${encodeURIComponent(type)}&name=${encodeURIComponent(name)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedPmeFormTemplates(facilities: { id: string; label: string }[]): Promise<void> {
  const presets = await loadPmeReportPresets();
  if (!presets || presets.length === 0) {
    console.log(
      chalk.yellow(
        "⚠  PME Form Templates skipped — could not load PME_REPORT_PRESETS\n" +
        "   from sibling mycure repo. Expected at:\n" +
        "     ../mycure/apps/mycure/src/pages/pme/reportTemplatePresets.ts\n" +
        "   Clone the mycure repo next to mycure-infra to enable this step.",
      ),
    );
    return;
  }

  const total = presets.length * facilities.length;
  const spinner = ora(`Seeding ${total} PME form templates (${presets.length} presets per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const preset of presets) {
      progress++;
      spinner.text = `[${facility.label}] ${preset.name} (${progress}/${total})`;

      const existing = await findFormTemplate(facility.id, "ape-report", preset.name);
      if (existing) {
        skipped++;
        continue;
      }

      const items = (preset.items ?? []).filter((i) => i.type === "multiplechoice");

      try {
        await api("POST", "/form-templates", {
          facility: facility.id,
          type: "ape-report",
          name: preset.name,
          description: preset.description,
          template: preset.template,
          items,
          // The FormTemplates list pages filter by `hide: false` (strict
          // equality, not $ne). New rows without an explicit `hide` get
          // dropped from the UI — must set this on create.
          hide: false,
          config: {
            // Mirrors FormTemplates.vue parseCreate() — all flags default off
            // since the presets render their own headers/footers.
            hideReviewedBy: false,
            disableClinicHeader: false,
            hideFinalizedBy: false,
            hideExaminedBy: false,
            disablePatientHeader: false,
            hideCreatedBy: false,
            disableTemplateNameHeading: false,
            records: {},
          },
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create PME template '${preset.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`PME templates: ${created} new, ${skipped} skipped — ${total} total target`);
}

// ---------------------------------------------------------------------------
// Verbose clinic profiles — layer the contact details / address / socials
// onto each org via PATCH /organizations/:id. Idempotent: same fields just
// get overwritten with the same values on rerun.
// ---------------------------------------------------------------------------

async function seedClinicProfiles(
  facilities: Array<{ id: string; label: string; profile: OrgProfile }>,
): Promise<void> {
  const spinner = ora(`Patching ${facilities.length} clinic profiles...`).start();
  let updated = 0;

  for (const { id, label, profile } of facilities) {
    spinner.text = `[${label}] applying clinic profile...`;
    try {
      // NOTE: do NOT include `types` here. The PatchOrganizationRequest
      // OpenAPI spec restricts `types[]` to the OrganizationType enum
      // (cms, his, facility, pharmacy, etc.) which excludes 'clinic',
      // even though hapihub's runtime stores 'clinic' there. We set
      // types on initial create via createOrganization() — that path
      // accepts any string. Reruns of the seed shouldn't try to mutate
      // types on existing orgs.
      await patchOrg(id, {
        description: profile.description,
        email: profile.email,
        emails: [profile.email],
        phone: profile.phone,
        phones: [profile.phone],
        website: profile.website,
        timezone: profile.timezone,
        address: profile.address,
        socialMediaURLs: profile.socialMediaURLs,
        // NOTE: organizations.tags is reused by the Patient Tags settings
        // page (see useEmrPatientTagListProps). We deliberately don't write
        // demo markers here so they don't pollute the patient-classification
        // tag list — patient tags are seeded by seedPatientTags() instead.
        // Demo provenance lives in `metadata`.
        metadata: {
          seed: true,
          isDemoOrg: true,
          demoMarkers: profile.tags ?? [],
        },
        isPublic: false,
      });
      updated++;
    } catch (err: unknown) {
      const msg = (err as Error).message;
      spinner.fail(`Failed to patch '${label}': ${msg.slice(0, 200)}`);
      process.exit(1);
    }
  }

  spinner.succeed(`Clinic profiles patched (${updated}/${facilities.length})`);
}

// ---------------------------------------------------------------------------
// Verbose user profiles — PATCH /personal-details/{uid} for each user with
// the demographics and (for the doctor) the clinician-only fields. The
// personal_details `id` equals the account `uid` (no separate lookup needed).
// ---------------------------------------------------------------------------

async function seedUserProfiles(userIds: Record<string, string>): Promise<void> {
  const spinner = ora("Patching user personal-details...").start();
  let patched = 0;
  let skipped = 0;
  let progress = 0;
  const total = Object.keys(USER_PROFILES).length;
  // Capture the current session so we can restore it afterwards (the rest
  // of the seed runs as superadmin).
  const superadminCookie = sessionCookie;

  for (const user of USERS) {
    progress++;
    const profile = USER_PROFILES[user.email];
    if (!profile) {
      skipped++;
      continue;
    }
    const uid = userIds[user.email];
    if (!uid) {
      skipped++;
      continue;
    }
    spinner.text = `[${user.email}] (${progress}/${total})`;

    // hapihub's personal-details PATCH requires the requester to be the
    // owner of the row — superadmin gets 403 on other users' records.
    // Sign in as each user before patching their own details.
    sessionCookie = "";
    try {
      await signIn(user.email, PASSWORD);
    } catch (err: unknown) {
      const msg = (err as Error).message;
      console.warn(
        chalk.yellow(`  ⚠  could not sign in as ${user.email}: ${msg.slice(0, 160)}`),
      );
      skipped++;
      continue;
    }

    // The hapihub PATCH handler only normalizes `dateOfBirth` from string
    // to epoch (services/hapihub/src/services/person/details.ts:872) — the
    // doc_* timestamp columns are passed through as-is and rejected by
    // schema validation if they're strings. Convert ISO → epoch ms here.
    const toEpoch = (iso?: string) => (iso ? new Date(iso).getTime() : undefined);

    // Strip undefined values so we don't blow away existing fields with null.
    const body: Record<string, unknown> = {
      mobileNo: profile.mobileNo,
      sex: profile.sex,
      dateOfBirth: profile.dateOfBirth,    // string → epoch handled server-side
      bloodType: profile.bloodType,
      nationality: profile.nationality,
      maritalStatus: profile.maritalStatus,
      address: profile.address,
    };
    if (profile.doc_PRCLicenseNo)    body.doc_PRCLicenseNo = profile.doc_PRCLicenseNo;
    if (profile.doc_PRCLicenseExp)   body.doc_PRCLicenseExp = toEpoch(profile.doc_PRCLicenseExp);
    if (profile.doc_PTRNumber)       body.doc_PTRNumber = profile.doc_PTRNumber;
    if (profile.doc_S2Number)        body.doc_S2Number = profile.doc_S2Number;
    if (profile.doc_philhealthPAN)   body.doc_philhealthPAN = profile.doc_philhealthPAN;
    if (profile.doc_practicingSince) body.doc_practicingSince = toEpoch(profile.doc_practicingSince);
    if (profile.doc_title)           body.doc_title = profile.doc_title;
    if (profile.doc_bio)             body.doc_bio = profile.doc_bio;
    if (profile.doc_specialties)     body.doc_specialties = profile.doc_specialties;
    if (profile.doc_professions)     body.doc_professions = profile.doc_professions;
    if (profile.doc_education)       body.doc_education = profile.doc_education;
    if (profile.doc_affiliations)    body.doc_affiliations = profile.doc_affiliations;

    try {
      await api("PATCH", `/personal-details/${uid}`, body);
      patched++;
    } catch (err: unknown) {
      const msg = (err as Error).message;
      // Known issue: some hapihub builds hit a UNIQUE constraint on
      // personal_details_history.id when the audit-trail row collides
      // with a stale row (the 0010 migration's PK uniqueness check).
      // Non-fatal — the user account itself is fine, just the verbose
      // profile didn't get written. Log and continue so the rest of
      // the seed still completes.
      const trimmed = msg.length > 160 ? `${msg.slice(0, 160)}…` : msg;
      console.warn(
        chalk.yellow(`  ⚠  personal-details patch failed for ${user.email}: ${trimmed}`),
      );
      skipped++;
    }
  }

  // Restore the superadmin session so subsequent seed steps stay authorised.
  sessionCookie = superadminCookie;

  if (skipped > 0) {
    spinner.warn(
      `User profiles: ${patched} patched, ${skipped} skipped (see warnings above)`,
    );
  } else {
    spinner.succeed(`User profiles: ${patched} patched, ${skipped} skipped`);
  }
}

// ---------------------------------------------------------------------------
// Partners: HMOs, Companies, Government — all in /insurance-contracts
// ---------------------------------------------------------------------------
// One table backs three settings pages, discriminated by `type` +
// `insurerSubtype` (see packages/sdk/src/organizations/composables/partners.ts):
//   HMO        → type=insurance-facility           insurerSubtype=hmo
//   Government → type=insurance-facility           insurerSubtype=government
//   Company    → type=corporate-partner-facility   (no subtype)
// All scoped to the active org via `insured`. Custom partners (no link to
// an existing organization) just carry insurerName + insurerDescription.

interface PartnerTemplate {
  kind: "hmo" | "company" | "government";
  insurerName: string;
  insurerDescription: string;
}

const SEED_PARTNERS: PartnerTemplate[] = [
  // HMOs (top private health insurers in PH)
  { kind: "hmo", insurerName: "Maxicare Healthcare Corporation", insurerDescription: "Maxicare HMO — leading private health insurer (PHP plans + accreditation network)." },
  { kind: "hmo", insurerName: "Intellicare", insurerDescription: "Intellicare HMO — corporate health plans, partner to Asalus Corporation." },
  { kind: "hmo", insurerName: "Medicard Philippines", insurerDescription: "Medicard HMO — comprehensive corporate and individual coverage." },
  { kind: "hmo", insurerName: "PhilCare", insurerDescription: "PhilCare HMO (PhilHealth Care, Inc.) — health plans with hospital network." },
  { kind: "hmo", insurerName: "Cocolife Healthcare", insurerDescription: "Cocolife HMO — a subsidiary of United Coconut Planters Life Assurance." },
  { kind: "hmo", insurerName: "Pacific Cross Health Care", insurerDescription: "Pacific Cross HMO — international health and travel insurance." },
  { kind: "hmo", insurerName: "EastWest Healthcare", insurerDescription: "EastWest HMO — wholly-owned by EastWest Bank." },
  { kind: "hmo", insurerName: "Insular Health Care", insurerDescription: "Insular Health Care (InLife) — long-standing PH HMO." },

  // Companies (corporate partners — Filipino household names)
  { kind: "company", insurerName: "ABS-CBN Corporation",          insurerDescription: "Corporate health-care partner — broadcasting & media employees." },
  { kind: "company", insurerName: "Ayala Corporation",             insurerDescription: "Corporate health-care partner — Ayala group of companies." },
  { kind: "company", insurerName: "San Miguel Corporation",        insurerDescription: "Corporate health-care partner — beverages, food, packaging." },
  { kind: "company", insurerName: "Globe Telecom",                 insurerDescription: "Corporate health-care partner — telecom employees." },
  { kind: "company", insurerName: "PLDT Inc.",                     insurerDescription: "Corporate health-care partner — telecom and digital services." },
  { kind: "company", insurerName: "BDO Unibank",                   insurerDescription: "Corporate health-care partner — universal bank." },
  { kind: "company", insurerName: "Jollibee Foods Corporation",    insurerDescription: "Corporate health-care partner — food service group." },
  { kind: "company", insurerName: "SM Investments Corporation",    insurerDescription: "Corporate health-care partner — retail, banking, real estate." },

  // Government partners
  { kind: "government", insurerName: "PhilHealth", insurerDescription: "Philippine Health Insurance Corporation — national health insurance." },
  { kind: "government", insurerName: "GSIS",       insurerDescription: "Government Service Insurance System — for government employees." },
  { kind: "government", insurerName: "SSS",        insurerDescription: "Social Security System — private-sector workers' insurance and sickness benefits." },
  { kind: "government", insurerName: "DOH",        insurerDescription: "Department of Health — public health programs and indigent care." },
  { kind: "government", insurerName: "PCSO",       insurerDescription: "Philippine Charity Sweepstakes Office — medical assistance program." },
];

function buildPartnerBody(insured: string, p: PartnerTemplate): Record<string, unknown> {
  if (p.kind === "company") {
    return {
      insured,
      type: "corporate-partner-facility",
      insurerName: p.insurerName,
      insurerDescription: p.insurerDescription,
    };
  }
  return {
    insured,
    type: "insurance-facility",
    insurerSubtype: p.kind,                  // "hmo" or "government"
    insurerName: p.insurerName,
    insurerDescription: p.insurerDescription,
  };
}

async function findPartner(
  insured: string,
  type: string,
  insurerName: string,
  insurerSubtype?: string,
): Promise<string | undefined> {
  try {
    const sub = insurerSubtype ? `&insurerSubtype=${encodeURIComponent(insurerSubtype)}` : "";
    const res = (await api(
      "GET",
      `/insurance-contracts?insured=${encodeURIComponent(insured)}&type=${encodeURIComponent(type)}${sub}&insurerName=${encodeURIComponent(insurerName)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedPartners(facilities: { id: string; label: string }[]): Promise<void> {
  const total = SEED_PARTNERS.length * facilities.length;
  const spinner = ora(`Seeding ${total} insurance/corporate/government partners...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const tpl of SEED_PARTNERS) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.kind} / ${tpl.insurerName} (${progress}/${total})`;

      const body = buildPartnerBody(facility.id, tpl);
      const existing = await findPartner(
        facility.id,
        body.type as string,
        tpl.insurerName,
        body.insurerSubtype as string | undefined,
      );
      if (existing) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/insurance-contracts", body);
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create partner '${tpl.insurerName}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  const breakdown =
    `${SEED_PARTNERS.filter((p) => p.kind === "hmo").length} HMOs, ` +
    `${SEED_PARTNERS.filter((p) => p.kind === "company").length} companies, ` +
    `${SEED_PARTNERS.filter((p) => p.kind === "government").length} gov`;
  spinner.succeed(`Partners: ${created} new, ${skipped} skipped — ${total} target (${breakdown})`);
}

// ---------------------------------------------------------------------------
// Diagnostic Center partners (organizations with type=diagnostic-center)
// ---------------------------------------------------------------------------
// Per useDiagnosticCenterPartnerListProps: these are full org rows (not
// insurance contracts), with overlords=[seedFacilityId] linking them back
// to the active org. Idempotent dedup on (overlords contains facility, name).

interface DiagnosticCenterTemplate {
  name: string;
  description: string;
}

const SEED_DX_CENTERS: DiagnosticCenterTemplate[] = [
  { name: "Hi-Precision Diagnostics",   description: "Multi-branch laboratory and imaging diagnostic centre — accepts referrals." },
  { name: "Healthway Medical Imaging",  description: "Outpatient imaging partner — CT, MRI, ultrasound, X-ray." },
  { name: "Makati Medical Lab Sendouts", description: "Reference laboratory for chemistry, microbiology, and special tests." },
  { name: "St. Luke's Diagnostic Center", description: "Hospital-grade diagnostic services for outpatient referrals." },
  { name: "Detoxicare Molecular Lab",   description: "Specialty molecular and genomics diagnostic centre." },
];

async function findDiagnosticCenter(facilityId: string, name: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/organizations?type=diagnostic-center&overlords=${encodeURIComponent(facilityId)}&name=${encodeURIComponent(name)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedDiagnosticCenters(facilities: { id: string; label: string }[]): Promise<void> {
  const total = SEED_DX_CENTERS.length * facilities.length;
  const spinner = ora(`Seeding ${total} diagnostic-center partners...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const tpl of SEED_DX_CENTERS) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.name} (${progress}/${total})`;

      const existing = await findDiagnosticCenter(facility.id, tpl.name);
      if (existing) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/organizations", {
          type: "diagnostic-center",
          overlords: [facility.id],
          name: tpl.name,
          description: tpl.description,
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create dx-center '${tpl.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`Diagnostic centers: ${created} new, ${skipped} skipped — ${total} target`);
}

// ---------------------------------------------------------------------------
// Registration: Queues
// ---------------------------------------------------------------------------
// Hapihub auto-creates 8 default queues per facility (Cashier, End Of
// Encounter, Front Desk, Nurse, Doctor, Laboratory, Imaging X-ray, Imaging
// Ultrasound) when an org is created with `types: ['clinic']` — see
// services/hapihub/src/services/organization/organizations.ts:400.
//
// We layer additional queues on top:
//   1. Procedure Room — auto-defaults skip `type: 'procedure'`, so add
//      one for the procedure-type queue used by clinical-procedure flows.
//   2. Per-doctor consult queues — one queue per doctor with that doctor's
//      org-member id in `writers: ["member::<id>"]`. The mycure UI uses
//      `writers` as the doctor↔queue link: when a doctor is selected in
//      a service-provider context, the matching queue auto-selects.
//      See packages/sdk/src/queueing/composables/queues.ts:115-198.

interface DoctorQueueSpec {
  /** Email of the user (must match a USERS entry with `roleIds: ['doctor', ...]`). */
  email: string;
  /** Display name shown on the queue. */
  queueName: string;
  /** Visit time per patient — used for queue ETA calculations. */
  normalTimeMins: number;
  description: string;
}

const SEED_DOCTOR_QUEUES: DoctorQueueSpec[] = [
  {
    email: "doctor@mycure.test",
    queueName: "Dr. Juan Cruz — Internal Medicine",
    normalTimeMins: 30,
    description: "IM / endocrinology consults — Dr. Juan Cruz.",
  },
  {
    email: "pedia@mycure.test",
    queueName: "Dr. Sofia Reyes — Pediatrics",
    normalTimeMins: 25,
    description: "Pediatric consults — Dr. Sofia Reyes.",
  },
  {
    email: "familymd@mycure.test",
    queueName: "Dr. Mateo Santos — Family Medicine",
    normalTimeMins: 20,
    description: "Family medicine / preventive care — Dr. Mateo Santos.",
  },
];

/** Find an org-member row id by (uid, organization) — null if missing. */
async function findMemberId(uid: string, organization: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/organization-members?uid=${encodeURIComponent(uid)}&organization=${encodeURIComponent(organization)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

/** Find an existing queue by (organization, name). */
async function findQueueByName(organization: string, name: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/queues?organization=${encodeURIComponent(organization)}&name=${encodeURIComponent(name)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedExtraQueues(
  facilities: { id: string; label: string }[],
  userIds: Record<string, string>,
): Promise<void> {
  const total = (1 + SEED_DOCTOR_QUEUES.length) * facilities.length;
  const spinner = ora(
    `Seeding ${total} extra queues (procedure + ${SEED_DOCTOR_QUEUES.length} per-doctor) on ${facilities.length} facilities...`,
  ).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;
  let writersAdded = 0;

  for (const facility of facilities) {
    // ── 1. Procedure queue (no auto-default for type=procedure) ──
    progress++;
    const procName = "Procedure Room";
    spinner.text = `[${facility.label}] ${procName} (${progress}/${total})`;
    const existingProc = await findQueueByName(facility.id, procName);
    if (existingProc) {
      skipped++;
    } else {
      try {
        await api("POST", "/queues", {
          organization: facility.id,
          name: procName,
          type: "procedure",
          description: "Minor in-clinic procedures — suturing, IV starts, dressings.",
          normalTime: 25 * 60 * 1000,  // millis
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create procedure queue: ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }

    // ── 2. Per-doctor consult queues with writers ──
    for (const docQ of SEED_DOCTOR_QUEUES) {
      progress++;
      spinner.text = `[${facility.label}] ${docQ.queueName} (${progress}/${total})`;

      const uid = userIds[docQ.email];
      if (!uid) {
        skipped++;
        continue;
      }
      const memberId = await findMemberId(uid, facility.id);
      if (!memberId) {
        skipped++;
        continue;
      }

      const existing = await findQueueByName(facility.id, docQ.queueName);
      if (existing) {
        // Make sure the doctor is in writers even on rerun (in case it
        // was created without). PATCH adds the writer if missing.
        try {
          await api("PATCH", `/queues/${existing}`, {
            $addToSet: { writers: `member::${memberId}` },
          });
          writersAdded++;
        } catch {
          // ignore — best effort, the queue already exists
        }
        skipped++;
        continue;
      }

      try {
        await api("POST", "/queues", {
          organization: facility.id,
          name: docQ.queueName,
          type: "doctor",
          description: docQ.description,
          normalTime: docQ.normalTimeMins * 60 * 1000,
          // writers tags this queue to a specific member. The UI's
          // service-provider selection auto-picks the queue where
          // the chosen doctor is listed (see queues.ts:115-198).
          writers: [`member::${memberId}`],
        });
        created++;
        writersAdded++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(
          `Failed to create doctor queue for ${docQ.email}: ${msg.slice(0, 200)}`,
        );
        process.exit(1);
      }
    }
  }

  spinner.succeed(
    `Extra queues: ${created} new, ${skipped} skipped — ${total} target ` +
    `(${writersAdded} doctor↔queue writers links established)`,
  );
}

// ---------------------------------------------------------------------------
// Registration: Patient Tags (org.tags string array) + Privacy Notices
// (org.mf_kioskMessages object array)
// ---------------------------------------------------------------------------

const SEED_PATIENT_TAGS = [
  "VIP",
  "Senior Citizen",
  "PWD",
  "Pediatric",
  "Pregnant",
  "Diabetic",
  "Hypertensive",
  "Insurance / HMO",
  "Walk-in",
  "Returning Patient",
];

interface PrivacyNoticeTemplate {
  id: string;        // stable id per locale
  language: string;  // ISO 639-1
  title: string;
  acceptButtonText: string;
  text: string;
}

const SEED_PRIVACY_NOTICES: PrivacyNoticeTemplate[] = [
  {
    id: "seed-privacy-en",
    language: "en",
    title: "Patient Privacy Notice",
    acceptButtonText: "I Agree",
    text:
      "MyCure Demo Clinic respects your privacy. By proceeding, you consent " +
      "to the collection, use, and storage of your personal health information " +
      "for the purpose of medical evaluation, treatment, billing, and statutory " +
      "reporting (Republic Act No. 10173 — Data Privacy Act of 2012). Your " +
      "information will be kept confidential and shared only with authorised " +
      "clinic staff, your insurance provider (if applicable), and government " +
      "agencies when required by law.",
  },
  {
    id: "seed-privacy-tl",
    language: "tl",
    title: "Pahatid Tungkol sa Pribasiya",
    acceptButtonText: "Sang-ayon Ako",
    text:
      "Iginagalang ng MyCure Demo Clinic ang inyong privacy. Sa pagpapatuloy, " +
      "pumapayag kayo sa pagkolekta, paggamit, at pag-iimbak ng inyong " +
      "personal na impormasyong pangkalusugan para sa medikal na pagsusuri, " +
      "paggamot, pagsingil, at iniaatas na pag-uulat (Batas Republika Blg. " +
      "10173 — Data Privacy Act of 2012). Ang inyong impormasyon ay mananatiling " +
      "kumpidensyal at ipapaalam lamang sa awtorisadong kawani ng klinika, " +
      "sa inyong insurance provider (kung mayroon), at sa mga ahensya ng " +
      "gobyerno kung iniaatas ng batas.",
  },
];

async function seedPatientTagsAndPrivacy(facilities: { id: string; label: string }[]): Promise<void> {
  const spinner = ora(
    `Seeding patient tags + ${SEED_PRIVACY_NOTICES.length} privacy notices on ${facilities.length} orgs...`,
  ).start();

  for (const facility of facilities) {
    spinner.text = `[${facility.label}] reading current tags + kiosk messages...`;
    const org = await getOrg(facility.id);

    // Patient tags: merge with existing.
    const existingTags = (org.tags as string[] | undefined) ?? [];
    const mergedTags = Array.from(new Set([...existingTags, ...SEED_PATIENT_TAGS]));

    // Privacy notices live in mf_kioskMessages. Dedup by stable seed id;
    // preserve any non-seed kiosk messages that may exist already.
    const existingMessages =
      (org.mf_kioskMessages as Array<{ id?: string }> | undefined) ?? [];
    const seedIds = new Set(SEED_PRIVACY_NOTICES.map((m) => m.id));
    const nonSeedMessages = existingMessages.filter((m) => !m.id || !seedIds.has(m.id));
    const mergedMessages = [...nonSeedMessages, ...SEED_PRIVACY_NOTICES];

    spinner.text = `[${facility.label}] patching tags + kiosk messages...`;
    try {
      await patchOrg(facility.id, {
        tags: mergedTags,
        mf_kioskMessages: mergedMessages,
      });
    } catch (err: unknown) {
      const msg = (err as Error).message;
      spinner.fail(`Failed to patch tags/privacy on '${facility.label}': ${msg.slice(0, 200)}`);
      process.exit(1);
    }
  }

  spinner.succeed(
    `Patient tags (${SEED_PATIENT_TAGS.length}) + privacy notices (${SEED_PRIVACY_NOTICES.length} languages) merged on ${facilities.length} orgs`,
  );
}

// ---------------------------------------------------------------------------
// EMR Form Templates — dynamic-import FORM_TEMPLATE_PRESETS from sibling
// mycure repo (~30 presets across med-certificate, fit-certificate,
// consent-form, waiver, health-history, general, claims). Same idempotency
// strategy as PME templates: lookup-first by (facility, type, name).
// ---------------------------------------------------------------------------

interface EmrFormTemplatePreset {
  id: string;
  type:
    | "med-certificate"
    | "fit-certificate"
    | "consent-form"
    | "waiver"
    | "health-history"
    | "general"
    | "claims";
  name: string;
  description: string;
  template: string;
  items?: Array<{ question: string; type: "multiplechoice"; choices: string[] }>;
}

async function loadEmrFormPresets(): Promise<EmrFormTemplatePreset[] | null> {
  const candidates = [
    `${import.meta.dir}/../../mycure/apps/mycure/src/pages/emr/formTemplatePresets.ts`,
    `${import.meta.dir}/../../../mycure/apps/mycure/src/pages/emr/formTemplatePresets.ts`,
  ];
  for (const path of candidates) {
    try {
      const file = Bun.file(path);
      if (!(await file.exists())) continue;
      const mod = await import(path);
      if (Array.isArray(mod.FORM_TEMPLATE_PRESETS)) {
        return mod.FORM_TEMPLATE_PRESETS as EmrFormTemplatePreset[];
      }
    } catch {
      // try next candidate
    }
  }
  return null;
}

async function seedEmrFormTemplates(facilities: { id: string; label: string }[]): Promise<void> {
  const presets = await loadEmrFormPresets();
  if (!presets || presets.length === 0) {
    console.log(
      chalk.yellow(
        "⚠  EMR Form Templates skipped — could not load FORM_TEMPLATE_PRESETS\n" +
        "   from sibling mycure repo. Expected at:\n" +
        "     ../mycure/apps/mycure/src/pages/emr/formTemplatePresets.ts",
      ),
    );
    return;
  }

  const total = presets.length * facilities.length;
  const spinner = ora(`Seeding ${total} EMR form templates (${presets.length} presets per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const preset of presets) {
      progress++;
      spinner.text = `[${facility.label}] ${preset.type} / ${preset.name} (${progress}/${total})`;

      const existing = await findFormTemplate(facility.id, preset.type, preset.name);
      if (existing) {
        skipped++;
        continue;
      }

      const items = (preset.items ?? []).filter((i) => i.type === "multiplechoice");

      try {
        await api("POST", "/form-templates", {
          facility: facility.id,
          type: preset.type,
          name: preset.name,
          description: preset.description,
          template: preset.template,
          items,
          // FormTemplates UI list filters `hide: false` (strict equality).
          hide: false,
          config: {
            disableClinicHeader: false,
            disablePatientHeader: false,
            disableTemplateNameHeading: false,
            enableLoggedInUserFooter: false,
            records: {},
          },
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create EMR template '${preset.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  // Per-type breakdown for the summary.
  const byType = presets.reduce<Record<string, number>>((acc, p) => {
    acc[p.type] = (acc[p.type] ?? 0) + 1;
    return acc;
  }, {});
  const breakdown = Object.entries(byType).map(([t, n]) => `${t}=${n}`).join(", ");
  spinner.succeed(`EMR templates: ${created} new, ${skipped} skipped — ${total} target (${breakdown})`);
}

// ---------------------------------------------------------------------------
// Medicines + Favorite Medicines (medicine-configurations)
// ---------------------------------------------------------------------------
// Owner=facility (organization=orgId) so they're scoped to the seed clinics.
// Favorites reference an existing medicine — we lookup by (organization,
// genericName) before creating the configuration row.

interface MedicineTemplate {
  genericName: string;
  brandName?: string;
  formulations: string[];   // e.g. ["500mg tablet", "250mg/5mL syrup"]
  /** Optional default favorite-prescription params for this medicine. */
  favorite?: {
    formulation: string;    // pick one of the formulations above
    dispense: string;       // e.g. "21 tablets"
    dosageSig: string;      // e.g. "1 tablet"
    frequency: string;      // e.g. "every 8 hours"
    note?: string;          // e.g. "take with food"
  };
}

const SEED_MEDICINES: MedicineTemplate[] = [
  {
    genericName: "Paracetamol",
    brandName: "Biogesic",
    formulations: ["500mg tablet", "250mg/5mL syrup", "125mg/5mL drops", "1g IV vial"],
    favorite: {
      formulation: "500mg tablet", dispense: "20 tablets",
      dosageSig: "1 tablet", frequency: "every 4–6 hours PRN for fever or pain",
      note: "Max 4g/day. Take with or without food.",
    },
  },
  {
    genericName: "Amoxicillin",
    brandName: "Amoxil",
    formulations: ["500mg capsule", "250mg/5mL suspension", "125mg/5mL pediatric drops"],
    favorite: {
      formulation: "500mg capsule", dispense: "21 capsules",
      dosageSig: "1 capsule", frequency: "every 8 hours for 7 days",
      note: "Complete the full course even if you feel better.",
    },
  },
  {
    genericName: "Amoxicillin + Clavulanic Acid",
    brandName: "Co-Amoxiclav (Augmentin)",
    formulations: ["625mg tablet", "1g tablet", "228mg/5mL suspension"],
    favorite: {
      formulation: "625mg tablet", dispense: "14 tablets",
      dosageSig: "1 tablet", frequency: "every 12 hours for 7 days",
      note: "Take with food to reduce GI upset.",
    },
  },
  {
    genericName: "Cefalexin",
    brandName: "Keflex",
    formulations: ["500mg capsule", "250mg/5mL suspension"],
  },
  {
    genericName: "Azithromycin",
    brandName: "Zithromax",
    formulations: ["500mg tablet", "200mg/5mL suspension"],
    favorite: {
      formulation: "500mg tablet", dispense: "3 tablets",
      dosageSig: "1 tablet", frequency: "once daily for 3 days",
    },
  },
  { genericName: "Ciprofloxacin", brandName: "Cipro",       formulations: ["500mg tablet", "250mg tablet"] },
  { genericName: "Levofloxacin",  brandName: "Levox",       formulations: ["500mg tablet", "750mg tablet"] },
  { genericName: "Metronidazole", brandName: "Flagyl",      formulations: ["500mg tablet", "200mg/5mL suspension"] },
  {
    genericName: "Loratadine",
    brandName: "Claritin",
    formulations: ["10mg tablet", "5mg/5mL syrup"],
    favorite: {
      formulation: "10mg tablet", dispense: "10 tablets",
      dosageSig: "1 tablet", frequency: "once daily PRN for allergies",
    },
  },
  { genericName: "Cetirizine",   brandName: "Virlix",       formulations: ["10mg tablet", "5mg/5mL syrup"] },
  { genericName: "Diphenhydramine", brandName: "Benadryl",  formulations: ["25mg capsule", "12.5mg/5mL syrup"] },
  {
    genericName: "Salbutamol",
    brandName: "Ventolin",
    formulations: ["100mcg/dose MDI inhaler", "1mg/mL nebule", "2mg tablet"],
    favorite: {
      formulation: "1mg/mL nebule", dispense: "10 nebules",
      dosageSig: "1 nebule via nebulizer", frequency: "every 4–6 hours PRN for shortness of breath",
    },
  },
  { genericName: "Ipratropium Bromide", brandName: "Atrovent", formulations: ["500mcg/2.5mL nebule"] },
  { genericName: "Budesonide",          brandName: "Pulmicort", formulations: ["0.5mg/2mL nebule"] },
  {
    genericName: "Omeprazole",
    brandName: "Losec",
    formulations: ["20mg capsule", "40mg capsule", "40mg IV vial"],
    favorite: {
      formulation: "20mg capsule", dispense: "30 capsules",
      dosageSig: "1 capsule", frequency: "once daily, 30 minutes before breakfast",
      note: "Take on an empty stomach.",
    },
  },
  { genericName: "Pantoprazole",       brandName: "Pantoloc",   formulations: ["40mg tablet", "40mg IV vial"] },
  { genericName: "Ranitidine",         brandName: "Zantac",     formulations: ["150mg tablet", "300mg tablet"] },
  {
    genericName: "Metformin",
    brandName: "Glucophage",
    formulations: ["500mg tablet", "850mg tablet", "1g tablet"],
    favorite: {
      formulation: "500mg tablet", dispense: "60 tablets",
      dosageSig: "1 tablet", frequency: "twice daily with meals",
      note: "Take with food to reduce GI side effects.",
    },
  },
  { genericName: "Glimepiride",        brandName: "Amaryl",     formulations: ["1mg tablet", "2mg tablet", "4mg tablet"] },
  {
    genericName: "Losartan",
    brandName: "Cozaar",
    formulations: ["50mg tablet", "100mg tablet"],
    favorite: {
      formulation: "50mg tablet", dispense: "30 tablets",
      dosageSig: "1 tablet", frequency: "once daily",
    },
  },
  { genericName: "Telmisartan",        brandName: "Micardis",   formulations: ["40mg tablet", "80mg tablet"] },
  { genericName: "Amlodipine",         brandName: "Norvasc",    formulations: ["5mg tablet", "10mg tablet"] },
  { genericName: "Atenolol",           brandName: "Tenormin",   formulations: ["25mg tablet", "50mg tablet"] },
  { genericName: "Atorvastatin",       brandName: "Lipitor",    formulations: ["10mg tablet", "20mg tablet", "40mg tablet"] },
  { genericName: "Rosuvastatin",       brandName: "Crestor",    formulations: ["10mg tablet", "20mg tablet"] },
  { genericName: "Simvastatin",        brandName: "Zocor",      formulations: ["10mg tablet", "20mg tablet"] },
  { genericName: "Aspirin (low-dose)", brandName: "Bayer",      formulations: ["80mg tablet", "100mg tablet"] },
  { genericName: "Clopidogrel",        brandName: "Plavix",     formulations: ["75mg tablet"] },
  {
    genericName: "Mefenamic Acid",
    brandName: "Dolfenal",
    formulations: ["500mg capsule", "250mg/5mL suspension"],
    favorite: {
      formulation: "500mg capsule", dispense: "10 capsules",
      dosageSig: "1 capsule", frequency: "every 6 hours PRN for pain",
    },
  },
  { genericName: "Ibuprofen",          brandName: "Advil",      formulations: ["200mg tablet", "400mg tablet", "100mg/5mL suspension"] },
  { genericName: "Celecoxib",          brandName: "Celebrex",   formulations: ["100mg capsule", "200mg capsule"] },
  { genericName: "Diclofenac",         brandName: "Voltaren",   formulations: ["50mg tablet", "75mg IM ampule", "1% topical gel"] },
  {
    genericName: "Tramadol",
    brandName: "Tramal",
    formulations: ["50mg capsule", "100mg/2mL ampule"],
  },
  { genericName: "Hyoscine N-Butylbromide", brandName: "Buscopan", formulations: ["10mg tablet", "20mg/mL ampule"] },
  { genericName: "Domperidone",        brandName: "Motilium",   formulations: ["10mg tablet", "1mg/mL suspension"] },
  { genericName: "Ondansetron",        brandName: "Zofran",     formulations: ["4mg tablet", "8mg tablet", "4mg/2mL ampule"] },
  {
    genericName: "Loperamide",
    brandName: "Imodium",
    formulations: ["2mg capsule"],
    favorite: {
      formulation: "2mg capsule", dispense: "6 capsules",
      dosageSig: "2 capsules initially, then 1 capsule after each loose stool",
      frequency: "as needed", note: "Max 8 capsules per day.",
    },
  },
  { genericName: "Oral Rehydration Salts", brandName: "Hydrite", formulations: ["sachet 20.5g per litre"] },
  { genericName: "Hydroxyzine",        brandName: "Iterax",     formulations: ["10mg tablet", "25mg tablet"] },
  { genericName: "Multivitamins (B-complex)", brandName: "Berocca", formulations: ["effervescent tablet", "film-coated tablet"] },
  { genericName: "Ferrous Sulfate",    brandName: "FeroSul",    formulations: ["325mg tablet", "75mg/5mL syrup"] },
  { genericName: "Folic Acid",         brandName: "Folart",     formulations: ["5mg tablet", "1mg tablet"] },
];

async function findMedicine(facility: string, genericName: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/medicines?organization=${encodeURIComponent(facility)}&genericName=${encodeURIComponent(genericName)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function findMedicineConfig(
  facility: string,
  medicineId: string,
): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/medicine-configurations?organization=${encodeURIComponent(facility)}&medicine=${encodeURIComponent(medicineId)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedMedicines(facilities: { id: string; label: string }[]): Promise<void> {
  const total = SEED_MEDICINES.length * facilities.length;
  const spinner = ora(`Seeding ${total} medicines (${SEED_MEDICINES.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;
  // Track medicine ids per (facility, genericName) for the favorite step.
  const medicineIds: Record<string, Record<string, string>> = {};

  for (const facility of facilities) {
    medicineIds[facility.id] = {};
    for (const tpl of SEED_MEDICINES) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.genericName} (${progress}/${total})`;

      const existing = await findMedicine(facility.id, tpl.genericName);
      if (existing) {
        medicineIds[facility.id][tpl.genericName] = existing;
        skipped++;
        continue;
      }

      try {
        const res = (await api("POST", "/medicines", {
          organization: facility.id,
          genericName: tpl.genericName,
          brandName: tpl.brandName,
          formulations: tpl.formulations.map((f) => ({ formulation: f })),
        })) as { id?: string };
        if (res?.id) medicineIds[facility.id][tpl.genericName] = res.id;
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create medicine '${tpl.genericName}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`Medicines: ${created} new, ${skipped} skipped — ${total} target`);

  // ---- Favorite medicines (medicine-configurations) -----------------------
  const favTemplates = SEED_MEDICINES.filter((m) => !!m.favorite);
  if (favTemplates.length === 0) return;

  const favTotal = favTemplates.length * facilities.length;
  const favSpinner = ora(
    `Seeding ${favTotal} favorite-medicine configurations (${favTemplates.length} per facility)...`,
  ).start();
  let favCreated = 0;
  let favSkipped = 0;
  let favMissing = 0;
  let favProgress = 0;

  for (const facility of facilities) {
    for (const tpl of favTemplates) {
      favProgress++;
      favSpinner.text = `[${facility.label}] favorite: ${tpl.genericName} (${favProgress}/${favTotal})`;

      const medId = medicineIds[facility.id][tpl.genericName];
      if (!medId) {
        favMissing++;
        continue;
      }
      const existing = await findMedicineConfig(facility.id, medId);
      if (existing) {
        favSkipped++;
        continue;
      }

      try {
        await api("POST", "/medicine-configurations", {
          organization: facility.id,
          medicine: medId,
          genericName: tpl.genericName,
          brandName: tpl.brandName,
          formulation: tpl.favorite!.formulation,
          dispense: tpl.favorite!.dispense,
          dosageSig: tpl.favorite!.dosageSig,
          frequency: tpl.favorite!.frequency,
          note: tpl.favorite!.note,
        });
        favCreated++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        favSpinner.fail(`Failed to create favorite for '${tpl.genericName}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  favSpinner.succeed(
    `Favorite medicines: ${favCreated} new, ${favSkipped} skipped, ${favMissing} unmatched — ${favTotal} target`,
  );
}

// ---------------------------------------------------------------------------
// Dental Statuses (fixtures with type=dental-status)
// ---------------------------------------------------------------------------
// Drawn from the DENTAL_STATUS_TYPES enum in the SDK so the values map 1:1
// with the UI dropdown. We only seed a curated subset (the most frequently
// used Filipino-clinic ones) — operators can add more in-app.

interface DentalStatusTemplate {
  category: string;
  statusType:
    | "default" | "icdas" | "surfaces" | "rct" | "implant" | "prosthetic"
    | "extraction" | "periodontal" | "orthodontic" | "anomaly" | "endodontic"
    | "trauma" | "missing-congenital" | "missing-caries" | "missing-other"
    | "extraction-indicated" | "extraction-caries" | "extraction-other"
    | "impacted" | "root-fragment" | "denture" | "supernumerary";
  abbreviation: string;
  colorCoding: string;   // #ef5350 (red) / #42a5f5 (blue) / #000000 (black)
  /**
   * Treatment-stage classification per DENTAL_STAGES in the SDK
   * (packages/sdk/src/emr/composables/dental-statuses.ts:14):
   *   baseline → existing condition observed at the chart visit
   *   order    → indicated / planned treatment
   *   result   → completed treatment outcome
   * Multi-stage statuses (e.g. "Extraction Indicated" can be both
   * ordered and progress to a result) get all applicable values.
   */
  stages: Array<"baseline" | "order" | "result">;
  forAll?: boolean;
  description?: string;
}

const SEED_DENTAL_STATUSES: DentalStatusTemplate[] = [
  // Baseline conditions — what's observed at the chart visit
  { category: "Caries",                 statusType: "default",     abbreviation: "C",   colorCoding: "#ef5350", stages: ["baseline"],          forAll: true, description: "Carious lesion (decay) — general" },
  { category: "Missing (Congenital)",   statusType: "missing-congenital",   abbreviation: "CM", colorCoding: "#000000", stages: ["baseline"],          forAll: true, description: "Tooth never erupted / never formed" },
  { category: "Impacted",               statusType: "impacted",    abbreviation: "Im",  colorCoding: "#000000", stages: ["baseline"],          forAll: true, description: "Impacted tooth (commonly third molars)" },
  { category: "Periodontitis",          statusType: "periodontal", abbreviation: "P",   colorCoding: "#ef5350", stages: ["baseline"],          forAll: true, description: "Periodontal disease — general" },
  { category: "Trauma / Fracture",      statusType: "trauma",      abbreviation: "T",   colorCoding: "#ef5350", stages: ["baseline"],                       description: "Trauma or fracture" },
  { category: "Supernumerary",          statusType: "supernumerary", abbreviation: "Sp", colorCoding: "#000000", stages: ["baseline"],                      description: "Supernumerary (extra) tooth" },
  { category: "Root Fragment",          statusType: "root-fragment", abbreviation: "RF", colorCoding: "#000000", stages: ["baseline"],                      description: "Remaining root fragment" },

  // Order — indicated / planned treatment
  { category: "Extraction Indicated",   statusType: "extraction-indicated", abbreviation: "I",  colorCoding: "#ef5350", stages: ["order"],          forAll: true, description: "Planned for extraction" },
  { category: "Orthodontic Treatment",  statusType: "orthodontic", abbreviation: "O",  colorCoding: "#42a5f5", stages: ["order", "result"],                 description: "Under or completed orthodontic treatment" },

  // Result — completed treatment outcomes
  { category: "Filled Tooth",           statusType: "default",     abbreviation: "F",   colorCoding: "#42a5f5", stages: ["result"],            forAll: true, description: "Previously restored / filled" },
  { category: "Missing (Caries)",       statusType: "missing-caries", abbreviation: "M", colorCoding: "#ef5350", stages: ["result"],           forAll: true, description: "Missing due to dental caries" },
  { category: "Missing (Other)",        statusType: "missing-other", abbreviation: "MO", colorCoding: "#000000", stages: ["result"],           forAll: true, description: "Missing for other reasons (trauma, perio)" },
  { category: "Extracted (Caries)",     statusType: "extraction-caries",    abbreviation: "X",  colorCoding: "#ef5350", stages: ["result"],     forAll: true, description: "Extracted due to caries" },
  { category: "Root Canal Treatment",   statusType: "rct",         abbreviation: "RCT", colorCoding: "#42a5f5", stages: ["result"],                       description: "Root canal therapy completed" },
  { category: "Crown (Porcelain)",      statusType: "prosthetic",  abbreviation: "Cr",  colorCoding: "#42a5f5", stages: ["result"],                       description: "Full porcelain crown" },
  { category: "Bridge Pontic",          statusType: "prosthetic",  abbreviation: "Br",  colorCoding: "#42a5f5", stages: ["result"],                       description: "Pontic of a fixed bridge" },
  { category: "Veneer",                 statusType: "prosthetic",  abbreviation: "V",   colorCoding: "#42a5f5", stages: ["result"],                       description: "Cosmetic facial veneer" },
  { category: "Implant",                statusType: "implant",     abbreviation: "Imp", colorCoding: "#42a5f5", stages: ["result"],                       description: "Dental implant in place" },
  { category: "Denture",                statusType: "denture",     abbreviation: "Rm",  colorCoding: "#000000", stages: ["result"],                       description: "Removable denture" },
];

// /fixtures only honors a fixed includeQueryFields list (verified at
// services/hapihub/src/services/fixture/fixture.ts:137):
//   ['type','subtype','organization','account','status','tags','stages','code']
// `category` is silently dropped server-side, so we can't dedup with a
// per-category lookup — we fetch all dental-statuses for the org once,
// then dedup client-side.

async function listExistingDentalCategories(facility: string): Promise<Set<string>> {
  try {
    const res = (await api(
      "GET",
      `/fixtures?type=dental-status&organization=${encodeURIComponent(facility)}&%24limit=500`,
    )) as { data?: Array<{ category?: string }> } | Array<{ category?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return new Set(list.map((f) => f.category).filter(Boolean) as string[]);
  } catch {
    return new Set();
  }
}

async function seedDentalStatuses(facilities: { id: string; label: string }[]): Promise<void> {
  const total = SEED_DENTAL_STATUSES.length * facilities.length;
  const spinner = ora(`Seeding ${total} dental statuses (${SEED_DENTAL_STATUSES.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    // Fetch existing categories once per facility (single round-trip vs 19).
    spinner.text = `[${facility.label}] reading existing dental statuses...`;
    const existingCategories = await listExistingDentalCategories(facility.id);

    for (const tpl of SEED_DENTAL_STATUSES) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.category} (${progress}/${total})`;

      if (existingCategories.has(tpl.category)) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/fixtures", {
          type: "dental-status",
          organization: facility.id,
          category: tpl.category,
          statusType: tpl.statusType,
          abbreviation: tpl.abbreviation,
          colorCoding: tpl.colorCoding,
          stages: tpl.stages,
          forAll: !!tpl.forAll,
          description: tpl.description,
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create dental status '${tpl.category}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`Dental statuses: ${created} new, ${skipped} skipped — ${total} target`);
}

// ---------------------------------------------------------------------------
// System-level fixtures: countries, PH address components, ICD-10 codes,
// professions, specialties.
// ---------------------------------------------------------------------------
// These are SYSTEM-LEVEL (no `organization`/`account`) — the entire
// installation shares one set. Per the OpenAPI specs at
// apis/hapihub/src/fixture/components/schemas/Create*Request.yaml:
//   address-country        → required: type, name
//   address-region/...     → required: type, name
//   icd10                  → required: type, code, text
//   profession             → required: type, code, text
//   specialty              → required: type, code, text
//
// Idempotency: the /fixtures includeQueryFields whitelist allows `code`
// (for icd10/profession/specialty natural-key lookups). For countries
// and address components without a code field, we pre-fetch by `type`
// and dedup client-side by name — same pattern as dental-statuses.

interface CountryTemplate {
  name: string;
  ioc?: string;          // 3-letter IOC code (e.g., 'PHI')
  alpha2: string;        // ISO 3166-1 alpha-2 (e.g., 'PH')
  alpha3: string;        // ISO 3166-1 alpha-3 (e.g., 'PHL')
  callingCodes?: string[];
  currencies?: string[];
  languages?: string[];
}

// Ten countries — Philippines first (primary), then frequently-seen
// neighbours and major business / OFW destinations. Full list via UI.
const SEED_COUNTRIES: CountryTemplate[] = [
  { name: "Philippines",   ioc: "PHI", alpha2: "PH", alpha3: "PHL", callingCodes: ["63"],     currencies: ["PHP"], languages: ["fil", "eng"] },
  { name: "United States", ioc: "USA", alpha2: "US", alpha3: "USA", callingCodes: ["1"],      currencies: ["USD"], languages: ["eng"] },
  { name: "Japan",         ioc: "JPN", alpha2: "JP", alpha3: "JPN", callingCodes: ["81"],     currencies: ["JPY"], languages: ["jpn"] },
  { name: "China",         ioc: "CHN", alpha2: "CN", alpha3: "CHN", callingCodes: ["86"],     currencies: ["CNY"], languages: ["zho"] },
  { name: "South Korea",   ioc: "KOR", alpha2: "KR", alpha3: "KOR", callingCodes: ["82"],     currencies: ["KRW"], languages: ["kor"] },
  { name: "Singapore",     ioc: "SGP", alpha2: "SG", alpha3: "SGP", callingCodes: ["65"],     currencies: ["SGD"], languages: ["eng", "msa", "zho", "tam"] },
  { name: "Malaysia",      ioc: "MAS", alpha2: "MY", alpha3: "MYS", callingCodes: ["60"],     currencies: ["MYR"], languages: ["msa", "eng"] },
  { name: "Thailand",      ioc: "THA", alpha2: "TH", alpha3: "THA", callingCodes: ["66"],     currencies: ["THB"], languages: ["tha"] },
  { name: "Vietnam",       ioc: "VIE", alpha2: "VN", alpha3: "VNM", callingCodes: ["84"],     currencies: ["VND"], languages: ["vie"] },
  { name: "Indonesia",     ioc: "INA", alpha2: "ID", alpha3: "IDN", callingCodes: ["62"],     currencies: ["IDR"], languages: ["ind"] },
  { name: "Australia",     ioc: "AUS", alpha2: "AU", alpha3: "AUS", callingCodes: ["61"],     currencies: ["AUD"], languages: ["eng"] },
  { name: "Canada",        ioc: "CAN", alpha2: "CA", alpha3: "CAN", callingCodes: ["1"],      currencies: ["CAD"], languages: ["eng", "fra"] },
  { name: "United Kingdom", ioc: "GBR", alpha2: "GB", alpha3: "GBR", callingCodes: ["44"],    currencies: ["GBP"], languages: ["eng"] },
  { name: "Saudi Arabia",  ioc: "KSA", alpha2: "SA", alpha3: "SAU", callingCodes: ["966"],    currencies: ["SAR"], languages: ["ara"] },
  { name: "United Arab Emirates", ioc: "UAE", alpha2: "AE", alpha3: "ARE", callingCodes: ["971"], currencies: ["AED"], languages: ["ara", "eng"] },
];

interface AddressComponentTemplate {
  type: "address-region" | "address-province" | "address-municipality" | "address-barangay";
  name: string;
  designation?: string;   // e.g., "NCR", "Region IV-A"
  country?: string;        // alpha3 of parent country
  region?: string;
  province?: string;
}

// 17 PH regions + a curated subset of common provinces. Municipality /
// barangay levels left out — operators can add via UI when needed.
const SEED_ADDRESS_COMPONENTS: AddressComponentTemplate[] = [
  // Regions (all 17)
  { type: "address-region", name: "National Capital Region",                     designation: "NCR",          country: "PHL" },
  { type: "address-region", name: "Cordillera Administrative Region",            designation: "CAR",          country: "PHL" },
  { type: "address-region", name: "Ilocos Region",                               designation: "Region I",     country: "PHL" },
  { type: "address-region", name: "Cagayan Valley",                              designation: "Region II",    country: "PHL" },
  { type: "address-region", name: "Central Luzon",                               designation: "Region III",   country: "PHL" },
  { type: "address-region", name: "Calabarzon",                                  designation: "Region IV-A",  country: "PHL" },
  { type: "address-region", name: "Mimaropa",                                    designation: "Region IV-B",  country: "PHL" },
  { type: "address-region", name: "Bicol Region",                                designation: "Region V",     country: "PHL" },
  { type: "address-region", name: "Western Visayas",                             designation: "Region VI",    country: "PHL" },
  { type: "address-region", name: "Central Visayas",                             designation: "Region VII",   country: "PHL" },
  { type: "address-region", name: "Eastern Visayas",                             designation: "Region VIII",  country: "PHL" },
  { type: "address-region", name: "Zamboanga Peninsula",                         designation: "Region IX",    country: "PHL" },
  { type: "address-region", name: "Northern Mindanao",                           designation: "Region X",     country: "PHL" },
  { type: "address-region", name: "Davao Region",                                designation: "Region XI",    country: "PHL" },
  { type: "address-region", name: "Soccsksargen",                                designation: "Region XII",   country: "PHL" },
  { type: "address-region", name: "Caraga",                                      designation: "Region XIII",  country: "PHL" },
  { type: "address-region", name: "Bangsamoro Autonomous Region in Muslim Mindanao", designation: "BARMM",     country: "PHL" },

  // Provinces — high-traffic ones
  { type: "address-province", name: "Metro Manila",          country: "PHL", region: "National Capital Region" },
  { type: "address-province", name: "Cebu",                  country: "PHL", region: "Central Visayas" },
  { type: "address-province", name: "Bohol",                 country: "PHL", region: "Central Visayas" },
  { type: "address-province", name: "Negros Oriental",       country: "PHL", region: "Central Visayas" },
  { type: "address-province", name: "Negros Occidental",     country: "PHL", region: "Western Visayas" },
  { type: "address-province", name: "Iloilo",                country: "PHL", region: "Western Visayas" },
  { type: "address-province", name: "Davao del Sur",         country: "PHL", region: "Davao Region" },
  { type: "address-province", name: "Davao del Norte",       country: "PHL", region: "Davao Region" },
  { type: "address-province", name: "Misamis Oriental",      country: "PHL", region: "Northern Mindanao" },
  { type: "address-province", name: "Cavite",                country: "PHL", region: "Calabarzon" },
  { type: "address-province", name: "Laguna",                country: "PHL", region: "Calabarzon" },
  { type: "address-province", name: "Batangas",              country: "PHL", region: "Calabarzon" },
  { type: "address-province", name: "Rizal",                 country: "PHL", region: "Calabarzon" },
  { type: "address-province", name: "Quezon",                country: "PHL", region: "Calabarzon" },
  { type: "address-province", name: "Pampanga",              country: "PHL", region: "Central Luzon" },
  { type: "address-province", name: "Bulacan",               country: "PHL", region: "Central Luzon" },
  { type: "address-province", name: "Pangasinan",            country: "PHL", region: "Ilocos Region" },
  { type: "address-province", name: "Benguet",               country: "PHL", region: "Cordillera Administrative Region" },
  { type: "address-province", name: "Zamboanga del Sur",     country: "PHL", region: "Zamboanga Peninsula" },
  { type: "address-province", name: "Albay",                 country: "PHL", region: "Bicol Region" },
];

interface CodeTextTemplate {
  code: string;
  text: string;
}

// 50 common ICD-10 codes covering primary-care, OPD, and PE clinic use.
// Sourced from WHO ICD-10 + frequent Filipino-clinic billing codes.
const SEED_ICD10_CODES: CodeTextTemplate[] = [
  // Infectious / GI
  { code: "A09",      text: "Other gastroenteritis and colitis of infectious and unspecified origin" },
  { code: "A90",      text: "Dengue fever (classical dengue)" },
  { code: "A91",      text: "Dengue haemorrhagic fever" },
  { code: "B34.9",    text: "Viral infection, unspecified" },
  { code: "B83.9",    text: "Helminthiasis, unspecified" },
  // Respiratory
  { code: "J00",      text: "Acute nasopharyngitis (common cold)" },
  { code: "J02.9",    text: "Acute pharyngitis, unspecified" },
  { code: "J03.9",    text: "Acute tonsillitis, unspecified" },
  { code: "J06.9",    text: "Acute upper respiratory infection, unspecified" },
  { code: "J11.1",    text: "Influenza with other respiratory manifestations, virus not identified" },
  { code: "J18.9",    text: "Pneumonia, unspecified organism" },
  { code: "J20.9",    text: "Acute bronchitis, unspecified" },
  { code: "J45.901",  text: "Asthma, unspecified, with (acute) exacerbation" },
  { code: "J45.909",  text: "Unspecified asthma, uncomplicated" },
  // Cardiovascular / Endocrine
  { code: "I10",      text: "Essential (primary) hypertension" },
  { code: "I25.10",   text: "Atherosclerotic heart disease of native coronary artery without angina pectoris" },
  { code: "I50.9",    text: "Heart failure, unspecified" },
  { code: "I63.9",    text: "Cerebral infarction, unspecified" },
  { code: "E11.9",    text: "Type 2 diabetes mellitus without complications" },
  { code: "E11.65",   text: "Type 2 diabetes mellitus with hyperglycemia" },
  { code: "E78.5",    text: "Hyperlipidemia, unspecified" },
  { code: "E03.9",    text: "Hypothyroidism, unspecified" },
  { code: "E66.9",    text: "Obesity, unspecified" },
  // GI
  { code: "K21.9",    text: "Gastro-oesophageal reflux disease without oesophagitis" },
  { code: "K29.70",   text: "Gastritis, unspecified, without bleeding" },
  { code: "K30",      text: "Functional dyspepsia" },
  { code: "K59.00",   text: "Constipation, unspecified" },
  // Skin
  { code: "L01.0",    text: "Impetigo" },
  { code: "L08.9",    text: "Local infection of the skin and subcutaneous tissue, unspecified" },
  { code: "L20.9",    text: "Atopic dermatitis, unspecified" },
  { code: "L50.9",    text: "Urticaria, unspecified" },
  // GU / women's health
  { code: "N39.0",    text: "Urinary tract infection, site not specified" },
  { code: "N91.2",    text: "Amenorrhoea, unspecified" },
  { code: "N94.6",    text: "Dysmenorrhoea, unspecified" },
  { code: "Z34.90",   text: "Encounter for supervision of normal pregnancy, unspecified, unspecified trimester" },
  // Pediatric / immunization
  { code: "Z23",      text: "Encounter for immunization" },
  { code: "Z00.121",  text: "Encounter for routine child health examination with abnormal findings" },
  { code: "Z00.129",  text: "Encounter for routine child health examination without abnormal findings" },
  // Pre-employment / general check
  { code: "Z00.00",   text: "Encounter for general adult medical examination without abnormal findings" },
  { code: "Z02.1",    text: "Encounter for pre-employment examination" },
  { code: "Z02.5",    text: "Encounter for examination for participation in sport" },
  { code: "Z02.79",   text: "Encounter for issue of other medical certificate" },
  // Mental health
  { code: "F32.9",    text: "Major depressive disorder, single episode, unspecified" },
  { code: "F41.1",    text: "Generalized anxiety disorder" },
  { code: "F51.01",   text: "Primary insomnia" },
  // Musculoskeletal
  { code: "M25.50",   text: "Pain in unspecified joint" },
  { code: "M54.5",    text: "Low back pain" },
  { code: "M79.1",    text: "Myalgia" },
  // Symptoms / signs
  { code: "R05",      text: "Cough" },
  { code: "R10.4",    text: "Other and unspecified abdominal pain" },
  { code: "R50.9",    text: "Fever, unspecified" },
  { code: "R51",      text: "Headache" },
];

// 12 PRC-recognised health professions
const SEED_PROFESSIONS: CodeTextTemplate[] = [
  { code: "MD",       text: "Physician (Medical Doctor)" },
  { code: "DDS",      text: "Dentist (Doctor of Dental Surgery)" },
  { code: "RN",       text: "Registered Nurse" },
  { code: "RM",       text: "Registered Midwife" },
  { code: "RMT",      text: "Registered Medical Technologist" },
  { code: "RRT",      text: "Registered Radiologic Technologist" },
  { code: "RPh",      text: "Registered Pharmacist" },
  { code: "RPT",      text: "Registered Physical Therapist" },
  { code: "ROT",      text: "Registered Occupational Therapist" },
  { code: "RND",      text: "Registered Nutritionist-Dietitian" },
  { code: "RPm",      text: "Registered Psychometrician" },
  { code: "PSY",      text: "Registered Psychologist" },
];

// 20 PSCH-recognised medical specialties (major boards)
const SEED_SPECIALTIES: CodeTextTemplate[] = [
  { code: "IM",       text: "Internal Medicine" },
  { code: "PEDS",     text: "Pediatrics" },
  { code: "OBG",      text: "Obstetrics and Gynecology" },
  { code: "FM",       text: "Family Medicine" },
  { code: "GS",       text: "General Surgery" },
  { code: "ORTHO",    text: "Orthopedics" },
  { code: "OPHTH",    text: "Ophthalmology" },
  { code: "ENT",      text: "Otorhinolaryngology (ENT)" },
  { code: "DERMA",    text: "Dermatology" },
  { code: "PSYCH",    text: "Psychiatry" },
  { code: "RADIO",    text: "Radiology" },
  { code: "PATH",     text: "Pathology" },
  { code: "ANES",     text: "Anesthesiology" },
  { code: "EM",       text: "Emergency Medicine" },
  { code: "CARDIO",   text: "Cardiology" },
  { code: "ENDO",     text: "Endocrinology, Diabetes and Metabolism" },
  { code: "PULMO",    text: "Pulmonology" },
  { code: "GI",       text: "Gastroenterology" },
  { code: "NEPH",     text: "Nephrology" },
  { code: "ONCO",     text: "Oncology (Medical)" },
];

// /fixtures includeQueryFields whitelist accepts `type` and `code` for
// natural-key lookups, but rejects `name` etc. — so we use the same
// upfront-fetch dedup pattern as dental statuses.
async function listExistingFixtureKeys(
  fixtureType: string,
  keyField: "name" | "code",
): Promise<Set<string>> {
  const seen = new Set<string>();
  let skip = 0;
  const limit = 500;
  while (true) {
    try {
      const res = (await api(
        "GET",
        `/fixtures?type=${encodeURIComponent(fixtureType)}&%24limit=${limit}&%24skip=${skip}`,
      )) as { data?: Array<Record<string, string | undefined>> } | Array<Record<string, string | undefined>>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const f of list) {
        const k = f?.[keyField];
        if (k) seen.add(k);
      }
      if (list.length < limit) break;
      skip += limit;
      if (skip >= limit * 5) break;
    } catch {
      break;
    }
  }
  return seen;
}

async function seedSystemFixtures(): Promise<void> {
  // ─── Countries ──────────────────────────────────────────────────────
  {
    const spinner = ora(`Seeding ${SEED_COUNTRIES.length} countries...`).start();
    const existing = await listExistingFixtureKeys("address-country", "name");
    let created = 0;
    let skipped = 0;
    for (const c of SEED_COUNTRIES) {
      if (existing.has(c.name)) {
        skipped++;
        continue;
      }
      try {
        await api("POST", "/fixtures", {
          type: "address-country",
          name: c.name,
          ioc: c.ioc,
          alpha2: c.alpha2,
          alpha3: c.alpha3,
          callingCodes: c.callingCodes,
          currencies: c.currencies,
          languages: c.languages,
          tags: ["seed"],
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create country '${c.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
    spinner.succeed(`Countries: ${created} new, ${skipped} skipped — ${SEED_COUNTRIES.length} target`);
  }

  // ─── Address regions / provinces ────────────────────────────────────
  {
    const total = SEED_ADDRESS_COMPONENTS.length;
    const spinner = ora(`Seeding ${total} PH address components (regions + provinces)...`).start();
    // Fetch existing once per component type.
    const existingByType: Record<string, Set<string>> = {};
    for (const t of new Set(SEED_ADDRESS_COMPONENTS.map((c) => c.type))) {
      existingByType[t] = await listExistingFixtureKeys(t, "name");
    }
    let created = 0;
    let skipped = 0;
    let progress = 0;
    for (const c of SEED_ADDRESS_COMPONENTS) {
      progress++;
      spinner.text = `${c.type} / ${c.name} (${progress}/${total})`;
      if (existingByType[c.type].has(c.name)) {
        skipped++;
        continue;
      }
      try {
        await api("POST", "/fixtures", {
          type: c.type,
          name: c.name,
          designation: c.designation,
          country: c.country,
          region: c.region,
          province: c.province,
          tags: ["seed", "ph"],
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create '${c.type}/${c.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
    spinner.succeed(`Address components: ${created} new, ${skipped} skipped — ${total} target`);
  }

  // ─── ICD-10 codes ───────────────────────────────────────────────────
  {
    const total = SEED_ICD10_CODES.length;
    const spinner = ora(`Seeding ${total} ICD-10 codes...`).start();
    // `code` IS in the includeQueryFields whitelist — but we still pre-fetch
    // for one-round-trip-per-type efficiency vs N codes × N round trips.
    const existing = await listExistingFixtureKeys("icd10", "code");
    let created = 0;
    let skipped = 0;
    let progress = 0;
    for (const c of SEED_ICD10_CODES) {
      progress++;
      spinner.text = `${c.code} / ${c.text.slice(0, 50)} (${progress}/${total})`;
      if (existing.has(c.code)) {
        skipped++;
        continue;
      }
      try {
        await api("POST", "/fixtures", {
          type: "icd10",
          code: c.code,
          text: c.text,
          tags: ["seed"],
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create ICD-10 '${c.code}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
    spinner.succeed(`ICD-10: ${created} new, ${skipped} skipped — ${total} target`);
  }

  // ─── Professions ────────────────────────────────────────────────────
  {
    const total = SEED_PROFESSIONS.length;
    const spinner = ora(`Seeding ${total} professions...`).start();
    const existing = await listExistingFixtureKeys("profession", "code");
    let created = 0;
    let skipped = 0;
    for (const p of SEED_PROFESSIONS) {
      if (existing.has(p.code)) {
        skipped++;
        continue;
      }
      try {
        await api("POST", "/fixtures", {
          type: "profession",
          code: p.code,
          text: p.text,
          tags: ["seed", "ph"],
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create profession '${p.code}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
    spinner.succeed(`Professions: ${created} new, ${skipped} skipped — ${total} target`);
  }

  // ─── Specialties ────────────────────────────────────────────────────
  {
    const total = SEED_SPECIALTIES.length;
    const spinner = ora(`Seeding ${total} medical specialties...`).start();
    const existing = await listExistingFixtureKeys("specialty", "code");
    let created = 0;
    let skipped = 0;
    for (const s of SEED_SPECIALTIES) {
      if (existing.has(s.code)) {
        skipped++;
        continue;
      }
      try {
        await api("POST", "/fixtures", {
          type: "specialty",
          code: s.code,
          text: s.text,
          tags: ["seed"],
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create specialty '${s.code}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
    spinner.succeed(`Specialties: ${created} new, ${skipped} skipped — ${total} target`);
  }
}

// ---------------------------------------------------------------------------
// Diagnostics: LIS (laboratory) + RIS (radiology)
// ---------------------------------------------------------------------------
// LIS and RIS share the same backend tables — only `type` (or `subtype` for
// sections) discriminates. Helpers below take a `kind` of "laboratory" or
// "radiology" and reuse the shared logic for tests, sections, packages, and
// report templates. Analyzers (`/diagnostic-analyzers`) are LIS-only — RIS
// has no settings page for them.
//
// Dependency order within each kind:
//   1. Sections (fixtures of type=diagnostic-section, subtype=kind)
//   2. Tests (diagnostic-tests, references section)
//   3. Packages (diagnostic-packages, references test ids)
//   4. Analyzers (LIS only — independent)
//   5. Form templates (form-templates type=lab-result|imaging-result)

type DiagnosticKind = "laboratory" | "radiology";
const FORM_TEMPLATE_TYPE_FOR: Record<DiagnosticKind, string> = {
  laboratory: "lab-result",
  radiology: "imaging-result",
};

interface DiagnosticSectionTemplate {
  name: string;
  code: string;
}

const SEED_LIS_SECTIONS: DiagnosticSectionTemplate[] = [
  { name: "Hematology",          code: "HEMA" },
  { name: "Clinical Chemistry",  code: "CHEM" },
  { name: "Clinical Microscopy", code: "MICRO" },
  { name: "Immunology / Serology", code: "IMMU" },
  { name: "Microbiology",        code: "BACT" },
];

const SEED_RIS_SECTIONS: DiagnosticSectionTemplate[] = [
  { name: "X-ray",          code: "XRAY" },
  { name: "Ultrasound",     code: "UTZ" },
  { name: "CT Scan",        code: "CT" },
  { name: "MRI",            code: "MRI" },
  { name: "Mammography",    code: "MAMMO" },
  { name: "Cardiology",     code: "CARDIO" },
];

interface DiagnosticTestTemplate {
  name: string;
  /** Section name (must match SEED_*_SECTIONS) — looked up at seed time. */
  section: string;
  hl7Code?: string;
  hl7System?: string;
  disclaimer?: string;
}

const SEED_LIS_TESTS: DiagnosticTestTemplate[] = [
  { name: "Complete Blood Count (CBC)", section: "Hematology",            hl7Code: "58410-2", hl7System: "LOINC" },
  { name: "Hemoglobin",                 section: "Hematology",            hl7Code: "718-7",   hl7System: "LOINC" },
  { name: "Platelet Count",             section: "Hematology",            hl7Code: "777-3",   hl7System: "LOINC" },
  { name: "Blood Typing (ABO/Rh)",      section: "Hematology",            hl7Code: "883-9",   hl7System: "LOINC" },
  { name: "Fasting Blood Sugar (FBS)",  section: "Clinical Chemistry",    hl7Code: "1558-6",  hl7System: "LOINC" },
  { name: "HbA1c",                      section: "Clinical Chemistry",    hl7Code: "4548-4",  hl7System: "LOINC" },
  { name: "Lipid Profile",              section: "Clinical Chemistry",    hl7Code: "57698-3", hl7System: "LOINC" },
  { name: "Creatinine",                 section: "Clinical Chemistry",    hl7Code: "2160-0",  hl7System: "LOINC" },
  { name: "BUN (Blood Urea Nitrogen)",  section: "Clinical Chemistry",    hl7Code: "3094-0",  hl7System: "LOINC" },
  { name: "SGPT/ALT",                   section: "Clinical Chemistry",    hl7Code: "1742-6",  hl7System: "LOINC" },
  { name: "SGOT/AST",                   section: "Clinical Chemistry",    hl7Code: "1920-8",  hl7System: "LOINC" },
  { name: "Urinalysis",                 section: "Clinical Microscopy",   hl7Code: "24356-8", hl7System: "LOINC" },
  { name: "Fecalysis",                  section: "Clinical Microscopy",   hl7Code: "10705-1", hl7System: "LOINC" },
  { name: "HBsAg (Hep B Surface Ag)",   section: "Immunology / Serology", hl7Code: "5196-1",  hl7System: "LOINC" },
  { name: "HIV Screening",              section: "Immunology / Serology", hl7Code: "5018-7",  hl7System: "LOINC" },
  { name: "Pregnancy Test (β-hCG)",     section: "Immunology / Serology", hl7Code: "2118-8",  hl7System: "LOINC" },
  { name: "Urine Culture & Sensitivity", section: "Microbiology",         hl7Code: "630-4",   hl7System: "LOINC" },
  { name: "Sputum Culture",              section: "Microbiology",         hl7Code: "624-7",   hl7System: "LOINC" },
];

// ─── Diagnostic measures (LIS only) ─────────────────────────────────
// Measures are the structured sub-fields of a diagnostic-test result
// (per the OpenAPI spec at apis/hapihub/src/diagnostic/components/
// schemas/CreateDiagnosticMeasureRequest.yaml). For lab tests, this is
// what the UI renders as numeric fields, dropdowns, etc. on the result
// form. Imaging tests use form-template HTML reports instead, so we
// only seed measures for the LIS catalogue.
//
// Connection to billing services: unchanged. service.ref → test.id.
// test.id ← measure.test (separate join). The two are independent — we
// just enrich the test side with measures so result entry forms have
// real fields to fill in.

interface MeasureRange {
  min?: number;
  max?: number;
  sex?: "all" | "male" | "female";
  ageMin?: number;
  ageMax?: number;
}
interface MeasureTemplate {
  name: string;
  type: "numeric" | "posneg" | "text" | "html" | "multiplechoice" | "checklist" | "numeric-breakdown";
  /** Group within the test (e.g., "Hematology"). Optional. */
  set?: string;
  unit?: string;
  siunit?: string;
  unitToSIUnitConversionFactor?: number;
  description?: string;
  choices?: string[];
  referenceRanges?: MeasureRange[];
}
interface TestMeasuresTemplate {
  /** Must match a SEED_LIS_TESTS entry by name. */
  testName: string;
  measures: MeasureTemplate[];
}

const SEED_LIS_MEASURES: TestMeasuresTemplate[] = [
  // Complete Blood Count — RBC indices + 5-part diff
  {
    testName: "Complete Blood Count (CBC)",
    measures: [
      { name: "Hemoglobin",     type: "numeric", set: "RBC indices", unit: "g/dL",        referenceRanges: [{ min: 13.5, max: 17.5, sex: "male" }, { min: 12.0, max: 16.0, sex: "female" }] },
      { name: "Hematocrit",     type: "numeric", set: "RBC indices", unit: "%",            referenceRanges: [{ min: 41.0, max: 53.0, sex: "male" }, { min: 36.0, max: 46.0, sex: "female" }] },
      { name: "RBC Count",       type: "numeric", set: "RBC indices", unit: "x10⁶/µL",      referenceRanges: [{ min: 4.5, max: 5.9, sex: "male" }, { min: 4.0, max: 5.2, sex: "female" }] },
      { name: "MCV",             type: "numeric", set: "RBC indices", unit: "fL",           referenceRanges: [{ min: 80, max: 100, sex: "all" }] },
      { name: "MCH",             type: "numeric", set: "RBC indices", unit: "pg",           referenceRanges: [{ min: 27, max: 33, sex: "all" }] },
      { name: "MCHC",            type: "numeric", set: "RBC indices", unit: "g/dL",         referenceRanges: [{ min: 32, max: 36, sex: "all" }] },
      { name: "WBC Count",       type: "numeric", set: "WBC",        unit: "x10³/µL",      referenceRanges: [{ min: 4.5, max: 11.0, sex: "all" }] },
      { name: "Neutrophils",    type: "numeric", set: "Differential count", unit: "%",     referenceRanges: [{ min: 40, max: 75, sex: "all" }] },
      { name: "Lymphocytes",    type: "numeric", set: "Differential count", unit: "%",     referenceRanges: [{ min: 20, max: 45, sex: "all" }] },
      { name: "Monocytes",      type: "numeric", set: "Differential count", unit: "%",     referenceRanges: [{ min: 2, max: 10, sex: "all" }] },
      { name: "Eosinophils",    type: "numeric", set: "Differential count", unit: "%",     referenceRanges: [{ min: 1, max: 6, sex: "all" }] },
      { name: "Basophils",      type: "numeric", set: "Differential count", unit: "%",     referenceRanges: [{ min: 0, max: 2, sex: "all" }] },
      { name: "Platelet Count", type: "numeric", set: "Platelets",   unit: "x10³/µL",      referenceRanges: [{ min: 150, max: 450, sex: "all" }] },
    ],
  },
  // Standalone single-measure tests
  {
    testName: "Hemoglobin",
    measures: [
      { name: "Hemoglobin", type: "numeric", unit: "g/dL", referenceRanges: [{ min: 13.5, max: 17.5, sex: "male" }, { min: 12.0, max: 16.0, sex: "female" }] },
    ],
  },
  {
    testName: "Platelet Count",
    measures: [
      { name: "Platelet Count", type: "numeric", unit: "x10³/µL", referenceRanges: [{ min: 150, max: 450, sex: "all" }] },
    ],
  },
  // Blood Typing — multiplechoice
  {
    testName: "Blood Typing (ABO/Rh)",
    measures: [
      { name: "ABO Group", type: "multiplechoice", choices: ["A", "B", "AB", "O"] },
      { name: "Rh Type",   type: "multiplechoice", choices: ["Positive", "Negative"] },
    ],
  },
  // Urinalysis — mix of text, posneg, and numeric
  {
    testName: "Urinalysis",
    measures: [
      { name: "Color",            type: "multiplechoice", set: "Macroscopic",  choices: ["Yellow", "Straw", "Amber", "Dark Yellow", "Red", "Brown"] },
      { name: "Clarity",          type: "multiplechoice", set: "Macroscopic",  choices: ["Clear", "Slightly Hazy", "Hazy", "Cloudy", "Turbid"] },
      { name: "pH",               type: "numeric",         set: "Chemical",     referenceRanges: [{ min: 4.5, max: 8.0, sex: "all" }] },
      { name: "Specific Gravity", type: "numeric",         set: "Chemical",     referenceRanges: [{ min: 1.005, max: 1.030, sex: "all" }] },
      { name: "Protein",          type: "posneg",          set: "Chemical" },
      { name: "Glucose",          type: "posneg",          set: "Chemical" },
      { name: "Ketones",          type: "posneg",          set: "Chemical" },
      { name: "Blood",            type: "posneg",          set: "Chemical" },
      { name: "Leukocyte Esterase", type: "posneg",        set: "Chemical" },
      { name: "Nitrite",          type: "posneg",          set: "Chemical" },
      { name: "WBC (per HPF)",    type: "text",            set: "Microscopic", description: "White blood cells per high-power field, e.g. '0-2/HPF'" },
      { name: "RBC (per HPF)",    type: "text",            set: "Microscopic", description: "Red blood cells per high-power field" },
      { name: "Bacteria",         type: "multiplechoice",  set: "Microscopic", choices: ["None", "Few", "Moderate", "Many"] },
      { name: "Epithelial Cells", type: "multiplechoice",  set: "Microscopic", choices: ["None", "Few", "Moderate", "Many"] },
    ],
  },
  // Fecalysis
  {
    testName: "Fecalysis",
    measures: [
      { name: "Color",       type: "multiplechoice", set: "Macroscopic", choices: ["Brown", "Yellow", "Green", "Black", "Red"] },
      { name: "Consistency", type: "multiplechoice", set: "Macroscopic", choices: ["Formed", "Soft", "Loose", "Watery", "Hard"] },
      { name: "Mucus",       type: "posneg",          set: "Macroscopic" },
      { name: "Blood",       type: "posneg",          set: "Macroscopic" },
      { name: "Pus Cells",   type: "text",            set: "Microscopic" },
      { name: "Ova / Cyst",  type: "text",            set: "Parasitology", description: "Specify organism if seen, e.g. 'Ascaris lumbricoides'" },
      { name: "Trophozoite", type: "text",            set: "Parasitology" },
    ],
  },
  // Chemistry singles
  {
    testName: "Fasting Blood Sugar (FBS)",
    measures: [
      { name: "Glucose (fasting)", type: "numeric", unit: "mg/dL", siunit: "mmol/L", unitToSIUnitConversionFactor: 0.0555, referenceRanges: [{ min: 70, max: 99, sex: "all" }] },
    ],
  },
  {
    testName: "HbA1c",
    measures: [
      { name: "HbA1c", type: "numeric", unit: "%",
        description: "Reference: <5.7 normal, 5.7-6.4 prediabetes, ≥6.5 diabetes (ADA)",
        referenceRanges: [{ min: 4.0, max: 5.6, sex: "all" }] },
      { name: "Estimated Average Glucose", type: "numeric", unit: "mg/dL",
        description: "Computed: eAG = 28.7 × HbA1c − 46.7" },
    ],
  },
  {
    testName: "Lipid Profile",
    measures: [
      { name: "Total Cholesterol", type: "numeric", unit: "mg/dL", siunit: "mmol/L", unitToSIUnitConversionFactor: 0.02586,
        description: "Desirable <200, borderline 200-239, high ≥240",
        referenceRanges: [{ max: 200, sex: "all" }] },
      { name: "HDL Cholesterol",   type: "numeric", unit: "mg/dL", siunit: "mmol/L", unitToSIUnitConversionFactor: 0.02586,
        description: "Higher is protective. Low <40 male, <50 female.",
        referenceRanges: [{ min: 40, sex: "male" }, { min: 50, sex: "female" }] },
      { name: "LDL Cholesterol",   type: "numeric", unit: "mg/dL", siunit: "mmol/L", unitToSIUnitConversionFactor: 0.02586,
        description: "Optimal <100, near-optimal 100-129, borderline 130-159, high 160-189, very high ≥190",
        referenceRanges: [{ max: 130, sex: "all" }] },
      { name: "Triglycerides",     type: "numeric", unit: "mg/dL", siunit: "mmol/L", unitToSIUnitConversionFactor: 0.01129,
        description: "Normal <150, borderline 150-199, high 200-499, very high ≥500",
        referenceRanges: [{ max: 150, sex: "all" }] },
      { name: "VLDL",              type: "numeric", unit: "mg/dL",
        description: "Computed: VLDL = Triglycerides / 5",
        referenceRanges: [{ min: 5, max: 40, sex: "all" }] },
      { name: "TC/HDL Ratio",      type: "numeric", description: "Cardiac risk indicator",
        referenceRanges: [{ max: 5.0, sex: "all" }] },
    ],
  },
  {
    testName: "Creatinine",
    measures: [
      { name: "Creatinine", type: "numeric", unit: "mg/dL", siunit: "µmol/L", unitToSIUnitConversionFactor: 88.4,
        referenceRanges: [{ min: 0.6, max: 1.2, sex: "male" }, { min: 0.5, max: 1.0, sex: "female" }] },
    ],
  },
  {
    testName: "BUN (Blood Urea Nitrogen)",
    measures: [
      { name: "BUN", type: "numeric", unit: "mg/dL", siunit: "mmol/L", unitToSIUnitConversionFactor: 0.357,
        referenceRanges: [{ min: 7, max: 20, sex: "all" }] },
    ],
  },
  {
    testName: "SGPT/ALT",
    measures: [
      { name: "SGPT/ALT", type: "numeric", unit: "U/L",
        referenceRanges: [{ min: 7, max: 56, sex: "male" }, { min: 7, max: 35, sex: "female" }] },
    ],
  },
  {
    testName: "SGOT/AST",
    measures: [
      { name: "SGOT/AST", type: "numeric", unit: "U/L",
        referenceRanges: [{ min: 10, max: 40, sex: "male" }, { min: 9, max: 32, sex: "female" }] },
    ],
  },
  // Serology — single posneg
  {
    testName: "HBsAg (Hep B Surface Ag)",
    measures: [
      { name: "HBsAg", type: "posneg", description: "Reactive (positive) suggests Hep B infection." },
    ],
  },
  {
    testName: "HIV Screening",
    measures: [
      { name: "Anti-HIV 1/2", type: "posneg", description: "Reactive screens require confirmatory testing." },
    ],
  },
  {
    testName: "Pregnancy Test (β-hCG)",
    measures: [
      { name: "β-hCG", type: "posneg", description: "Qualitative urine pregnancy test." },
    ],
  },
  // Microbiology — text-heavy
  {
    testName: "Urine Culture & Sensitivity",
    measures: [
      { name: "Organism Isolated", type: "text", description: "Genus + species if identified, e.g. 'Escherichia coli'." },
      { name: "Colony Count",       type: "text", unit: "CFU/mL", description: "≥10⁵ CFU/mL is significant." },
      { name: "Sensitivities",      type: "html", description: "Antibiotic sensitivity panel — paste the analyzer's table." },
    ],
  },
  {
    testName: "Sputum Culture",
    measures: [
      { name: "Gram Stain",       type: "text" },
      { name: "Organism Isolated", type: "text" },
      { name: "Colony Count",      type: "text" },
      { name: "Sensitivities",     type: "html" },
    ],
  },
];

const SEED_RIS_TESTS: DiagnosticTestTemplate[] = [
  { name: "Chest X-ray (PA view)",       section: "X-ray",       hl7Code: "36572-2", hl7System: "LOINC" },
  { name: "Chest X-ray (PA + Lateral)",  section: "X-ray",       hl7Code: "24648-8", hl7System: "LOINC" },
  { name: "Abdominal X-ray (Flat plate)", section: "X-ray",      hl7Code: "30715-3", hl7System: "LOINC" },
  { name: "Abdominal Ultrasound",        section: "Ultrasound",  hl7Code: "30714-6", hl7System: "LOINC" },
  { name: "Pelvic Ultrasound (Female)",  section: "Ultrasound",  hl7Code: "37068-0", hl7System: "LOINC" },
  { name: "Obstetric Ultrasound",        section: "Ultrasound",  hl7Code: "44115-0", hl7System: "LOINC" },
  { name: "Whole Abdomen Ultrasound",    section: "Ultrasound",  hl7Code: "30706-2", hl7System: "LOINC" },
  { name: "CT Scan — Cranial (Plain)",   section: "CT Scan",     hl7Code: "30799-1", hl7System: "LOINC" },
  { name: "CT Scan — Whole Abdomen w/ Contrast", section: "CT Scan", hl7Code: "30727-8", hl7System: "LOINC" },
  { name: "MRI — Brain (Plain + Contrast)", section: "MRI",      hl7Code: "30661-9", hl7System: "LOINC" },
  { name: "MRI — Lumbar Spine",          section: "MRI",         hl7Code: "30667-6", hl7System: "LOINC" },
  { name: "Mammography (Bilateral)",     section: "Mammography", hl7Code: "26346-7", hl7System: "LOINC" },
  // ECG is billed as imaging in SEED_SERVICES (cardiology); the matching
  // test row lets services.ref link the two so testSection auto-populates.
  { name: "12-lead ECG",                 section: "Cardiology",  hl7Code: "11524-6", hl7System: "LOINC" },
];

interface DiagnosticPackageTemplate {
  name: string;
  description: string;
  /** Test names (must exist in SEED_*_TESTS) — looked up at seed time. */
  tests: string[];
}

const SEED_LIS_PACKAGES: DiagnosticPackageTemplate[] = [
  {
    name: "Basic Health Screen",
    description: "CBC + Urinalysis + FBS — common pre-employment / annual baseline.",
    tests: ["Complete Blood Count (CBC)", "Urinalysis", "Fasting Blood Sugar (FBS)"],
  },
  {
    name: "Diabetes Workup",
    description: "Fasting glucose + HbA1c + Lipid Profile — diabetes risk assessment.",
    tests: ["Fasting Blood Sugar (FBS)", "HbA1c", "Lipid Profile"],
  },
  {
    name: "Kidney + Liver Panel",
    description: "Renal (Creatinine + BUN) and hepatic (SGPT, SGOT) function.",
    tests: ["Creatinine", "BUN (Blood Urea Nitrogen)", "SGPT/ALT", "SGOT/AST"],
  },
  {
    name: "STD / Hepatitis Screen",
    description: "HBsAg + HIV — basic infectious-disease panel.",
    tests: ["HBsAg (Hep B Surface Ag)", "HIV Screening"],
  },
];

const SEED_RIS_PACKAGES: DiagnosticPackageTemplate[] = [
  {
    name: "Pre-Employment Imaging",
    description: "Chest X-ray (PA + Lateral) — standard occupational requirement.",
    tests: ["Chest X-ray (PA + Lateral)"],
  },
  {
    name: "Abdominal Workup",
    description: "Abdominal X-ray + Whole Abdomen Ultrasound — generalist workup.",
    tests: ["Abdominal X-ray (Flat plate)", "Whole Abdomen Ultrasound"],
  },
  {
    name: "Prenatal Imaging",
    description: "Pelvic ultrasound + Obstetric ultrasound for prenatal evaluation.",
    tests: ["Pelvic Ultrasound (Female)", "Obstetric Ultrasound"],
  },
];

interface AnalyzerTemplate {
  name: string;
  description: string;
  externalId: string;
  hl7Host?: string;
  hl7Port?: string;
  hl7ReceivingFacility?: string;
  hl7ReceivingApplication?: string;
}

const SEED_LIS_ANALYZERS: AnalyzerTemplate[] = [
  { name: "Sysmex XN-1000",     externalId: "SYSMEXXN1000", description: "5-part differential hematology analyzer.",            hl7Host: "10.0.10.20",  hl7Port: "5000", hl7ReceivingFacility: "LAB", hl7ReceivingApplication: "SYSMEX" },
  { name: "Beckman Coulter AU480", externalId: "BCAU480",   description: "Clinical chemistry analyzer (general chemistries).",   hl7Host: "10.0.10.21",  hl7Port: "5000", hl7ReceivingFacility: "LAB", hl7ReceivingApplication: "AU480" },
  { name: "Roche Cobas e411",   externalId: "COBASE411",    description: "Immunoassay analyzer (hormones, tumor markers).",      hl7Host: "10.0.10.22",  hl7Port: "5000", hl7ReceivingFacility: "LAB", hl7ReceivingApplication: "COBAS" },
  { name: "BD BACTEC FX",       externalId: "BACTECFX",     description: "Blood culture and microbial detection system.",        hl7Host: "10.0.10.23",  hl7Port: "5000", hl7ReceivingFacility: "LAB", hl7ReceivingApplication: "BACTEC" },
  { name: "Sysmex UN-2000",     externalId: "SYSMEXUN2000", description: "Automated urinalysis analyzer (chemistry + sediment).", hl7Host: "10.0.10.24",  hl7Port: "5000", hl7ReceivingFacility: "LAB", hl7ReceivingApplication: "UN2000" },
  { name: "Cepheid GeneXpert",  externalId: "GENEXPERT",    description: "Cartridge-based PCR analyzer (TB, COVID-19, etc.).",   hl7Host: "10.0.10.25",  hl7Port: "5000", hl7ReceivingFacility: "LAB", hl7ReceivingApplication: "GENEXPERT" },
];

// ---- Sections (fixtures with type=diagnostic-section) ----------------------

async function listExistingDiagnosticSectionNames(
  facility: string,
  kind: DiagnosticKind,
): Promise<Set<string>> {
  // /fixtures only honors a fixed includeQueryFields list — `name` isn't on
  // it. Same dedup approach as dental statuses: fetch all org-scoped rows
  // for this kind, dedup by name client-side.
  try {
    const res = (await api(
      "GET",
      `/fixtures?type=diagnostic-section&subtype=${encodeURIComponent(kind)}&organization=${encodeURIComponent(facility)}&%24limit=500`,
    )) as { data?: Array<{ name?: string }> } | Array<{ name?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return new Set(list.map((s) => s.name).filter(Boolean) as string[]);
  } catch {
    return new Set();
  }
}

async function seedDiagnosticSections(
  facilities: { id: string; label: string }[],
  kind: DiagnosticKind,
  templates: DiagnosticSectionTemplate[],
): Promise<void> {
  const total = templates.length * facilities.length;
  const spinner = ora(`Seeding ${total} ${kind} sections (${templates.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    spinner.text = `[${facility.label}] reading existing ${kind} sections...`;
    const existing = await listExistingDiagnosticSectionNames(facility.id, kind);

    for (const tpl of templates) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.name} (${progress}/${total})`;

      if (existing.has(tpl.name)) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/fixtures", {
          type: "diagnostic-section",
          subtype: kind,
          organization: facility.id,
          name: tpl.name,
          code: tpl.code,
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create ${kind} section '${tpl.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`${kind} sections: ${created} new, ${skipped} skipped — ${total} target`);
}

// ---- Tests (diagnostic-tests) ---------------------------------------------

interface SectionRef { id: string; name: string; }

async function listSectionsForFacility(
  facility: string,
  kind: DiagnosticKind,
): Promise<SectionRef[]> {
  try {
    const res = (await api(
      "GET",
      `/fixtures?type=diagnostic-section&subtype=${encodeURIComponent(kind)}&organization=${encodeURIComponent(facility)}&%24limit=500`,
    )) as { data?: Array<{ id: string; name?: string }> } | Array<{ id: string; name?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list
      .filter((s) => !!s.name && !!s.id)
      .map((s) => ({ id: s.id, name: s.name as string }));
  } catch {
    return [];
  }
}

async function findDiagnosticTest(
  facility: string,
  kind: DiagnosticKind,
  name: string,
): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/diagnostic-tests?facility=${encodeURIComponent(facility)}&type=${encodeURIComponent(kind)}&name=${encodeURIComponent(name)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedDiagnosticTests(
  facilities: { id: string; label: string }[],
  kind: DiagnosticKind,
  templates: DiagnosticTestTemplate[],
): Promise<Record<string, Record<string, string>>> {
  const total = templates.length * facilities.length;
  const spinner = ora(`Seeding ${total} ${kind} tests (${templates.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let missingSection = 0;
  let progress = 0;
  // Return value: facilityId → testName → testId, used by package seeding.
  const testIds: Record<string, Record<string, string>> = {};

  for (const facility of facilities) {
    testIds[facility.id] = {};
    const sections = await listSectionsForFacility(facility.id, kind);
    const sectionByName = new Map(sections.map((s) => [s.name, s.id]));

    for (const tpl of templates) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.name} (${progress}/${total})`;

      const sectionId = sectionByName.get(tpl.section);
      if (!sectionId) {
        missingSection++;
        continue;
      }

      const existing = await findDiagnosticTest(facility.id, kind, tpl.name);
      if (existing) {
        testIds[facility.id][tpl.name] = existing;
        skipped++;
        continue;
      }

      try {
        const res = (await api("POST", "/diagnostic-tests", {
          facility: facility.id,
          type: kind,
          name: tpl.name,
          section: sectionId,
          hl7Code: tpl.hl7Code,
          hl7System: tpl.hl7System,
          disclaimer: tpl.disclaimer,
        })) as { id?: string };
        if (res?.id) testIds[facility.id][tpl.name] = res.id;
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create ${kind} test '${tpl.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(
    `${kind} tests: ${created} new, ${skipped} skipped, ${missingSection} unmatched section — ${total} target`,
  );
  return testIds;
}

// ---- Measures (diagnostic-measures) — LIS only ----------------------------
//
// /diagnostic-measures `includeQueryFields = ['facility','test','name','type','isPublic','hl7IdentifierCod','hl7IdentifierSys']`
// (services/hapihub/src/services/diagnostic/measures.ts:120). `test` and
// `name` are both whitelisted, so we can use them for natural-key dedup.
// We pre-fetch the full set per test to avoid N round-trips when a test
// has many measures (CBC has 13).
//
// Connection to billing services is unaffected — service.ref points at
// the diagnostic-test row, and measure.test points at the same test row.
// They form a chain (service → test → measures), independent links.

async function listExistingMeasureNames(facility: string, testId: string): Promise<Set<string>> {
  try {
    const res = (await api(
      "GET",
      `/diagnostic-measures?facility=${encodeURIComponent(facility)}&test=${encodeURIComponent(testId)}&%24limit=200`,
    )) as { data?: Array<{ name?: string }> } | Array<{ name?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return new Set(list.map((m) => m.name).filter(Boolean) as string[]);
  } catch {
    return new Set();
  }
}

async function seedDiagnosticMeasures(
  facilities: { id: string; label: string }[],
  testIdsByFacility: Record<string, Record<string, string>>,
  templates: TestMeasuresTemplate[],
): Promise<void> {
  const measuresPerFacility = templates.reduce((sum, t) => sum + t.measures.length, 0);
  const total = measuresPerFacility * facilities.length;
  const spinner = ora(
    `Seeding ${total} diagnostic measures (${measuresPerFacility} per facility, across ${templates.length} tests)...`,
  ).start();
  let created = 0;
  let skipped = 0;
  let missingTest = 0;
  let progress = 0;

  for (const facility of facilities) {
    const facilityTests = testIdsByFacility[facility.id] ?? {};
    for (const tpl of templates) {
      const testId = facilityTests[tpl.testName];
      if (!testId) {
        missingTest += tpl.measures.length;
        progress += tpl.measures.length;
        continue;
      }
      const existing = await listExistingMeasureNames(facility.id, testId);
      for (const m of tpl.measures) {
        progress++;
        spinner.text = `[${facility.label}] ${tpl.testName} → ${m.name} (${progress}/${total})`;
        if (existing.has(m.name)) {
          skipped++;
          continue;
        }
        try {
          await api("POST", "/diagnostic-measures", {
            facility: facility.id,
            test: testId,
            name: m.name,
            type: m.type,
            ...(m.set ? { set: m.set } : {}),
            ...(m.unit ? { unit: m.unit } : {}),
            ...(m.siunit ? { siunit: m.siunit } : {}),
            ...(m.unitToSIUnitConversionFactor != null
              ? { unitToSIUnitConversionFactor: m.unitToSIUnitConversionFactor }
              : {}),
            ...(m.description ? { description: m.description } : {}),
            ...(m.choices ? { choices: m.choices } : {}),
            ...(m.referenceRanges ? { referenceRanges: m.referenceRanges } : {}),
          });
          created++;
        } catch (err: unknown) {
          const msg = (err as Error).message;
          spinner.fail(
            `Failed to create measure '${tpl.testName}/${m.name}': ${msg.slice(0, 200)}`,
          );
          process.exit(1);
        }
      }
    }
  }

  spinner.succeed(
    `Diagnostic measures: ${created} new, ${skipped} skipped, ${missingTest} test refs unresolved — ${total} target`,
  );
}

// ---- Packages (diagnostic-packages) ---------------------------------------

// /diagnostic-packages includeQueryFields=['facility','type','account'] — `name`
// is silently dropped server-side, mirroring the dental-statuses bug. Fetch
// all packages once per (facility, kind), then dedup by name client-side.
async function listExistingPackageNames(
  facility: string,
  kind: DiagnosticKind,
): Promise<Set<string>> {
  try {
    const res = (await api(
      "GET",
      `/diagnostic-packages?facility=${encodeURIComponent(facility)}&type=${encodeURIComponent(kind)}&%24limit=500`,
    )) as { data?: Array<{ name?: string }> } | Array<{ name?: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return new Set(list.map((p) => p.name).filter(Boolean) as string[]);
  } catch {
    return new Set();
  }
}

async function seedDiagnosticPackages(
  facilities: { id: string; label: string }[],
  kind: DiagnosticKind,
  templates: DiagnosticPackageTemplate[],
  testIds: Record<string, Record<string, string>>,
): Promise<void> {
  const total = templates.length * facilities.length;
  const spinner = ora(`Seeding ${total} ${kind} packages (${templates.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let missingTest = 0;
  let progress = 0;

  for (const facility of facilities) {
    spinner.text = `[${facility.label}] reading existing ${kind} packages...`;
    const existingNames = await listExistingPackageNames(facility.id, kind);

    for (const tpl of templates) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.name} (${progress}/${total})`;

      const facilityTestIds = testIds[facility.id] ?? {};
      const ids = tpl.tests.map((n) => facilityTestIds[n]).filter(Boolean);
      if (ids.length !== tpl.tests.length) {
        // Some referenced tests didn't get created — still build the package
        // with whatever resolved so the rest of the seed proceeds.
        missingTest += tpl.tests.length - ids.length;
      }

      if (existingNames.has(tpl.name)) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/diagnostic-packages", {
          facility: facility.id,
          type: kind,
          name: tpl.name,
          description: tpl.description,
          tests: ids,
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create ${kind} package '${tpl.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(
    `${kind} packages: ${created} new, ${skipped} skipped, ${missingTest} test refs unresolved — ${total} target`,
  );
}

// ---- Analyzers (LIS only) -------------------------------------------------

async function findAnalyzer(facility: string, externalId: string): Promise<string | undefined> {
  try {
    const res = (await api(
      "GET",
      `/diagnostic-analyzers?facility=${encodeURIComponent(facility)}&externalId=${encodeURIComponent(externalId)}&%24limit=1`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function seedAnalyzers(
  facilities: { id: string; label: string }[],
  templates: AnalyzerTemplate[],
): Promise<void> {
  const total = templates.length * facilities.length;
  const spinner = ora(`Seeding ${total} laboratory analyzers (${templates.length} per facility)...`).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const tpl of templates) {
      progress++;
      spinner.text = `[${facility.label}] ${tpl.name} (${progress}/${total})`;

      const existing = await findAnalyzer(facility.id, tpl.externalId);
      if (existing) {
        skipped++;
        continue;
      }

      try {
        await api("POST", "/diagnostic-analyzers", {
          facility: facility.id,
          name: tpl.name,
          description: tpl.description,
          externalId: tpl.externalId,
          hl7Host: tpl.hl7Host,
          hl7Port: tpl.hl7Port,
          hl7ReceivingFacility: tpl.hl7ReceivingFacility,
          hl7ReceivingApplication: tpl.hl7ReceivingApplication,
          hl7Version: "2.3",
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create analyzer '${tpl.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`Analyzers: ${created} new, ${skipped} skipped — ${total} target`);
}

// ---- LIS / RIS report templates (form-templates dynamic-imported) ---------

interface DiagnosticReportPreset {
  id: string;
  name: string;
  description: string;
  template: string;
  items?: Array<{ question: string; type: "multiplechoice"; choices: string[] }>;
}

async function loadDiagnosticReportPresets(
  kind: DiagnosticKind,
): Promise<{ presets: DiagnosticReportPreset[] | null; templateType: string }> {
  const subdir = kind === "laboratory" ? "lis" : "ris";
  const exportName = kind === "laboratory" ? "LIS_FORM_TEMPLATE_PRESETS" : "RIS_REPORT_PRESETS";
  const candidates = [
    `${import.meta.dir}/../../mycure/apps/mycure/src/pages/${subdir}/formTemplatePresets.ts`,
    `${import.meta.dir}/../../../mycure/apps/mycure/src/pages/${subdir}/formTemplatePresets.ts`,
  ];
  for (const path of candidates) {
    try {
      const file = Bun.file(path);
      if (!(await file.exists())) continue;
      const mod = await import(path);
      if (Array.isArray(mod[exportName])) {
        return {
          presets: mod[exportName] as DiagnosticReportPreset[],
          templateType: FORM_TEMPLATE_TYPE_FOR[kind],
        };
      }
    } catch {
      // try next candidate
    }
  }
  return { presets: null, templateType: FORM_TEMPLATE_TYPE_FOR[kind] };
}

async function seedDiagnosticFormTemplates(
  facilities: { id: string; label: string }[],
  kind: DiagnosticKind,
): Promise<void> {
  const { presets, templateType } = await loadDiagnosticReportPresets(kind);
  if (!presets || presets.length === 0) {
    const subdir = kind === "laboratory" ? "lis" : "ris";
    console.log(
      chalk.yellow(
        `⚠  ${kind} Form Templates skipped — could not load presets from\n` +
        `   ../mycure/apps/mycure/src/pages/${subdir}/formTemplatePresets.ts`,
      ),
    );
    return;
  }

  const total = presets.length * facilities.length;
  const spinner = ora(
    `Seeding ${total} ${kind} report templates (${presets.length} presets per facility)...`,
  ).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of facilities) {
    for (const preset of presets) {
      progress++;
      spinner.text = `[${facility.label}] ${preset.name} (${progress}/${total})`;

      const existing = await findFormTemplate(facility.id, templateType, preset.name);
      if (existing) {
        skipped++;
        continue;
      }

      const items = (preset.items ?? []).filter((i) => i.type === "multiplechoice");

      try {
        await api("POST", "/form-templates", {
          facility: facility.id,
          type: templateType,
          name: preset.name,
          description: preset.description,
          template: preset.template,
          items,
          // FormTemplates UI list filters `hide: false` (strict equality).
          hide: false,
          config: {
            disableClinicHeader: false,
            disablePatientHeader: false,
            disableTemplateNameHeading: false,
            enableLoggedInUserFooter: false,
            records: {},
          },
        });
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create ${kind} template '${preset.name}': ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  spinner.succeed(`${kind} report templates: ${created} new, ${skipped} skipped — ${total} target`);
}

// ---------------------------------------------------------------------------
// Inventory Products (real entity at /inventory-variants)
// ---------------------------------------------------------------------------
// POST /inventory-variants accepts `initialStock` + `stockRoom` inline —
// the server auto-creates the inventory-stocks row via createStocksForVariant
// (services/hapihub/src/services/inventory/variants.ts:410). One POST per
// product, no separate stock POST needed.
//
// Required: warehouse, name. Everything else optional. We dedup on
// (warehouse, externalId) — externalId pattern: SEED-INV-<NNN>.

interface ProductTemplate {
  /** Maps to one of SEED_PRODUCT_TYPES. */
  productType: "Medicine" | "Medical Supplies" | "Lab Reagent" | "PPE" | "Office Supply" | "Equipment";
  name: string;
  description: string;
  unit: "piece" | "box" | "bottle" | "vial" | "ampule" | "pack" | "roll" | "set" | "mL" | "grams" | "mg";
  unitCost: number;          // PHP
  unitPrice: number;         // PHP — what the patient pays
  initialStock: number;      // current quantity on hand
  reorderLevel?: number;     // alert threshold
  quantityThreshold?: number;
  /** Optional barcode. */
  barcode?: string;
  manufacturer?: string;
  /** Stock room — must match a SEED_STOCK_ROOMS entry. */
  stockRoom?: string;
  isMedicine?: boolean;
  isMedicineDangerous?: boolean;
  /** Tax-exempt? (standard medicines are VAT-exempt in PH). */
  taxExempt?: boolean;
  tags?: string[];
}

// Curated 200-product Filipino clinic catalogue.
// Realistic wholesale-to-retail markup (~1.3-2.0x) and stock levels
// appropriate for a multi-branch outpatient clinic.
const SEED_PRODUCTS: ProductTemplate[] = [
  // ─── Medicine: Analgesics / Antipyretics ───────────────────────
  { productType: "Medicine", name: "Paracetamol 500mg tablet (Biogesic)",        description: "Acetaminophen 500mg film-coated tablet — fever and mild-moderate pain", unit: "piece",  unitCost: 1.20, unitPrice: 2.50, initialStock: 800, reorderLevel: 200, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["analgesic", "otc"] },
  { productType: "Medicine", name: "Paracetamol 250mg/5mL syrup",                description: "Pediatric paracetamol oral suspension, 60mL bottle",                  unit: "bottle", unitCost: 35.00, unitPrice: 65.00, initialStock: 80, reorderLevel: 20, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["analgesic", "pediatric"] },
  { productType: "Medicine", name: "Paracetamol 125mg/5mL drops",                description: "Infant paracetamol oral drops, 15mL bottle",                          unit: "bottle", unitCost: 28.00, unitPrice: 50.00, initialStock: 50, reorderLevel: 15, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["analgesic", "pediatric"] },
  { productType: "Medicine", name: "Mefenamic Acid 500mg capsule (Dolfenal)",   description: "NSAID 500mg cap — moderate pain, dysmenorrhea",                       unit: "piece",  unitCost: 4.50, unitPrice: 9.00, initialStock: 600, reorderLevel: 150, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["nsaid"] },
  { productType: "Medicine", name: "Ibuprofen 400mg tablet (Advil)",            description: "NSAID 400mg tablet — moderate pain, fever",                            unit: "piece",  unitCost: 3.50, unitPrice: 7.50, initialStock: 500, reorderLevel: 120, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["nsaid"] },
  { productType: "Medicine", name: "Ibuprofen 200mg tablet",                     description: "NSAID 200mg — mild pain",                                              unit: "piece",  unitCost: 2.00, unitPrice: 4.50, initialStock: 600, reorderLevel: 150, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Diclofenac 50mg tablet (Voltaren)",         description: "NSAID 50mg — musculoskeletal pain",                                    unit: "piece",  unitCost: 5.50, unitPrice: 12.00, initialStock: 400, reorderLevel: 100, manufacturer: "Novartis", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Diclofenac 1% topical gel 30g",             description: "NSAID topical gel for joint and muscle pain",                          unit: "piece",  unitCost: 95.00, unitPrice: 175.00, initialStock: 60, reorderLevel: 15, manufacturer: "Novartis", stockRoom: "Main Pharmacy", isMedicine: true },
  { productType: "Medicine", name: "Celecoxib 200mg capsule (Celebrex)",        description: "COX-2 inhibitor — chronic pain, arthritis",                            unit: "piece",  unitCost: 22.00, unitPrice: 45.00, initialStock: 200, reorderLevel: 50, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Tramadol 50mg capsule",                      description: "Opioid analgesic — moderate-severe pain",                              unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, isMedicineDangerous: true, tags: ["controlled"] },
  { productType: "Medicine", name: "Aspirin 80mg tablet (low-dose)",            description: "Antiplatelet 80mg — cardio prophylaxis",                               unit: "piece",  unitCost: 1.50, unitPrice: 3.00, initialStock: 700, reorderLevel: 200, manufacturer: "Bayer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: Antibiotics ─────────────────────────────────────
  { productType: "Medicine", name: "Amoxicillin 500mg capsule (Amoxil)",         description: "Penicillin antibiotic 500mg",                                          unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 700, reorderLevel: 200, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Amoxicillin 250mg/5mL suspension",           description: "Pediatric amoxicillin suspension, 60mL",                               unit: "bottle", unitCost: 95.00, unitPrice: 175.00, initialStock: 80, reorderLevel: 20, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Co-Amoxiclav 625mg tablet (Augmentin)",      description: "Amoxicillin + clavulanic acid 625mg",                                  unit: "piece",  unitCost: 28.00, unitPrice: 55.00, initialStock: 300, reorderLevel: 70, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Co-Amoxiclav 1g tablet",                     description: "Amoxicillin + clavulanic acid 1g",                                     unit: "piece",  unitCost: 45.00, unitPrice: 85.00, initialStock: 200, reorderLevel: 50, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Cefalexin 500mg capsule (Keflex)",          description: "1st-gen cephalosporin",                                                unit: "piece",  unitCost: 12.00, unitPrice: 25.00, initialStock: 400, reorderLevel: 100, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Cefuroxime 500mg tablet (Zinacef)",         description: "2nd-gen cephalosporin",                                                unit: "piece",  unitCost: 32.00, unitPrice: 65.00, initialStock: 200, reorderLevel: 50, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Azithromycin 500mg tablet (Zithromax)",     description: "Macrolide antibiotic, 3-day course typical",                           unit: "piece",  unitCost: 35.00, unitPrice: 75.00, initialStock: 250, reorderLevel: 60, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Ciprofloxacin 500mg tablet",                description: "Fluoroquinolone antibiotic",                                           unit: "piece",  unitCost: 9.00, unitPrice: 20.00, initialStock: 400, reorderLevel: 100, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Levofloxacin 500mg tablet (Levox)",         description: "Fluoroquinolone — RTI, UTI",                                           unit: "piece",  unitCost: 25.00, unitPrice: 50.00, initialStock: 200, reorderLevel: 50, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Metronidazole 500mg tablet (Flagyl)",       description: "Anaerobic and protozoal infections",                                   unit: "piece",  unitCost: 5.00, unitPrice: 11.00, initialStock: 400, reorderLevel: 100, manufacturer: "Sanofi", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Doxycycline 100mg capsule",                  description: "Tetracycline antibiotic",                                              unit: "piece",  unitCost: 6.00, unitPrice: 13.00, initialStock: 300, reorderLevel: 80, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Erythromycin 500mg tablet",                  description: "Macrolide antibiotic",                                                 unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 250, reorderLevel: 60, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Clindamycin 300mg capsule",                  description: "Lincosamide — anaerobic infections, dental",                           unit: "piece",  unitCost: 18.00, unitPrice: 38.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: Antihistamines / Allergy ────────────────────────
  { productType: "Medicine", name: "Loratadine 10mg tablet (Claritin)",         description: "2nd-gen antihistamine, non-sedating",                                  unit: "piece",  unitCost: 3.00, unitPrice: 8.00, initialStock: 600, reorderLevel: 150, manufacturer: "Bayer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Cetirizine 10mg tablet (Virlix)",           description: "Antihistamine for chronic urticaria, rhinitis",                        unit: "piece",  unitCost: 2.50, unitPrice: 6.50, initialStock: 700, reorderLevel: 180, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Cetirizine 5mg/5mL syrup",                   description: "Pediatric cetirizine syrup, 60mL",                                     unit: "bottle", unitCost: 65.00, unitPrice: 125.00, initialStock: 80, reorderLevel: 20, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Diphenhydramine 25mg capsule (Benadryl)",   description: "1st-gen antihistamine, sedating",                                      unit: "piece",  unitCost: 4.00, unitPrice: 9.00, initialStock: 400, reorderLevel: 100, manufacturer: "J&J", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Hydroxyzine 25mg tablet (Iterax)",          description: "Antihistamine for anxiety, pruritus",                                  unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 250, reorderLevel: 60, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: Respiratory ─────────────────────────────────────
  { productType: "Medicine", name: "Salbutamol 100mcg/dose MDI (Ventolin)",     description: "Short-acting bronchodilator inhaler, 200 doses",                       unit: "piece",  unitCost: 280.00, unitPrice: 480.00, initialStock: 50, reorderLevel: 12, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Salbutamol 1mg/mL nebule",                   description: "Single-dose nebulizer solution",                                       unit: "ampule", unitCost: 18.00, unitPrice: 38.00, initialStock: 400, reorderLevel: 100, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Ipratropium 500mcg/2.5mL nebule (Atrovent)", description: "Anticholinergic bronchodilator nebule",                                unit: "ampule", unitCost: 35.00, unitPrice: 70.00, initialStock: 200, reorderLevel: 50, manufacturer: "Boehringer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Budesonide 0.5mg/2mL nebule (Pulmicort)",   description: "Inhaled corticosteroid nebule",                                        unit: "ampule", unitCost: 65.00, unitPrice: 125.00, initialStock: 150, reorderLevel: 40, manufacturer: "AstraZeneca", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Salmeterol/Fluticasone MDI (Seretide)",     description: "Combination LABA + ICS inhaler",                                       unit: "piece",  unitCost: 1450.00, unitPrice: 2400.00, initialStock: 25, reorderLevel: 6, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Montelukast 10mg tablet (Singulair)",       description: "Leukotriene receptor antagonist for asthma/rhinitis",                  unit: "piece",  unitCost: 32.00, unitPrice: 65.00, initialStock: 200, reorderLevel: 50, manufacturer: "MSD", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: GI ──────────────────────────────────────────────
  { productType: "Medicine", name: "Omeprazole 20mg capsule (Losec)",           description: "PPI for GERD, peptic ulcer",                                           unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 500, reorderLevel: 120, manufacturer: "AstraZeneca", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Omeprazole 40mg IV vial",                   description: "Injectable PPI for acute GI bleeding",                                 unit: "vial",   unitCost: 95.00, unitPrice: 165.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Pantoprazole 40mg tablet (Pantoloc)",       description: "PPI for severe GERD",                                                  unit: "piece",  unitCost: 18.00, unitPrice: 38.00, initialStock: 300, reorderLevel: 80, manufacturer: "Takeda", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Ranitidine 150mg tablet (Zantac)",          description: "H2-blocker (legacy use)",                                              unit: "piece",  unitCost: 4.00, unitPrice: 9.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Hyoscine N-Butylbromide 10mg tab (Buscopan)", description: "Antispasmodic for abdominal cramps",                                 unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 400, reorderLevel: 100, manufacturer: "Boehringer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Domperidone 10mg tablet (Motilium)",        description: "Prokinetic for nausea, dyspepsia",                                     unit: "piece",  unitCost: 5.50, unitPrice: 12.00, initialStock: 300, reorderLevel: 80, manufacturer: "Janssen", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Ondansetron 8mg tablet (Zofran)",           description: "5-HT3 antagonist for severe nausea/vomiting",                          unit: "piece",  unitCost: 28.00, unitPrice: 55.00, initialStock: 100, reorderLevel: 25, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Loperamide 2mg capsule (Imodium)",          description: "Antidiarrheal",                                                        unit: "piece",  unitCost: 3.00, unitPrice: 7.00, initialStock: 500, reorderLevel: 120, manufacturer: "J&J", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Oral Rehydration Salts (Hydrite) sachet",   description: "ORS sachet, makes 1L oral rehydration solution",                       unit: "pack",   unitCost: 12.00, unitPrice: 22.00, initialStock: 300, reorderLevel: 80, manufacturer: "Unilab", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Lactulose 60mL syrup (Duphalac)",            description: "Osmotic laxative",                                                     unit: "bottle", unitCost: 145.00, unitPrice: 260.00, initialStock: 60, reorderLevel: 15, manufacturer: "Abbott", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: Cardiovascular ──────────────────────────────────
  { productType: "Medicine", name: "Losartan 50mg tablet (Cozaar)",             description: "ARB — hypertension",                                                   unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 600, reorderLevel: 150, manufacturer: "MSD", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Losartan 100mg tablet",                      description: "Higher-dose ARB",                                                      unit: "piece",  unitCost: 9.00, unitPrice: 20.00, initialStock: 400, reorderLevel: 100, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Telmisartan 40mg tablet (Micardis)",        description: "ARB",                                                                  unit: "piece",  unitCost: 18.00, unitPrice: 38.00, initialStock: 300, reorderLevel: 80, manufacturer: "Boehringer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Amlodipine 5mg tablet (Norvasc)",           description: "Calcium channel blocker",                                              unit: "piece",  unitCost: 4.00, unitPrice: 10.00, initialStock: 700, reorderLevel: 180, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Amlodipine 10mg tablet",                     description: "Higher-dose CCB",                                                      unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 500, reorderLevel: 120, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Atenolol 50mg tablet (Tenormin)",           description: "Beta-blocker",                                                         unit: "piece",  unitCost: 5.00, unitPrice: 12.00, initialStock: 400, reorderLevel: 100, manufacturer: "AstraZeneca", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Bisoprolol 5mg tablet (Concor)",            description: "Cardioselective beta-blocker",                                         unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 300, reorderLevel: 80, manufacturer: "Merck KGaA", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Atorvastatin 20mg tablet (Lipitor)",        description: "Statin — dyslipidemia",                                                unit: "piece",  unitCost: 15.00, unitPrice: 32.00, initialStock: 500, reorderLevel: 120, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Atorvastatin 40mg tablet",                   description: "Higher-dose statin",                                                   unit: "piece",  unitCost: 22.00, unitPrice: 45.00, initialStock: 300, reorderLevel: 80, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Rosuvastatin 10mg tablet (Crestor)",        description: "Statin — high-intensity",                                              unit: "piece",  unitCost: 28.00, unitPrice: 55.00, initialStock: 250, reorderLevel: 60, manufacturer: "AstraZeneca", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Simvastatin 20mg tablet (Zocor)",           description: "Statin",                                                               unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 300, reorderLevel: 80, manufacturer: "MSD", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Clopidogrel 75mg tablet (Plavix)",          description: "Antiplatelet — post-MI/stroke",                                        unit: "piece",  unitCost: 32.00, unitPrice: 65.00, initialStock: 200, reorderLevel: 50, manufacturer: "Sanofi", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Furosemide 40mg tablet (Lasix)",            description: "Loop diuretic",                                                        unit: "piece",  unitCost: 3.00, unitPrice: 7.00, initialStock: 400, reorderLevel: 100, manufacturer: "Sanofi", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Furosemide 20mg/2mL ampule",                description: "Injectable loop diuretic",                                             unit: "ampule", unitCost: 18.00, unitPrice: 38.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Hydrochlorothiazide 25mg tablet",            description: "Thiazide diuretic",                                                    unit: "piece",  unitCost: 2.50, unitPrice: 6.00, initialStock: 300, reorderLevel: 80, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: Diabetes ────────────────────────────────────────
  { productType: "Medicine", name: "Metformin 500mg tablet (Glucophage)",       description: "Biguanide oral hypoglycemic, first-line for T2DM",                     unit: "piece",  unitCost: 4.00, unitPrice: 9.00, initialStock: 800, reorderLevel: 200, manufacturer: "Merck", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Metformin 850mg tablet",                     description: "Biguanide, mid-strength",                                              unit: "piece",  unitCost: 5.00, unitPrice: 11.00, initialStock: 600, reorderLevel: 150, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Glimepiride 2mg tablet (Amaryl)",           description: "Sulfonylurea oral hypoglycemic",                                       unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 300, reorderLevel: 80, manufacturer: "Sanofi", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Gliclazide 80mg tablet (Diamicron)",        description: "Sulfonylurea",                                                         unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 200, reorderLevel: 50, manufacturer: "Servier", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Empagliflozin 10mg tablet (Jardiance)",     description: "SGLT2 inhibitor",                                                      unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 150, reorderLevel: 40, manufacturer: "Boehringer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Insulin Glargine 100U/mL pen (Lantus)",     description: "Long-acting basal insulin, 3mL pen",                                   unit: "piece",  unitCost: 850.00, unitPrice: 1450.00, initialStock: 30, reorderLevel: 8, manufacturer: "Sanofi", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["refrigerated"] },
  { productType: "Medicine", name: "Insulin Aspart 100U/mL pen (NovoRapid)",    description: "Rapid-acting insulin, 3mL pen",                                        unit: "piece",  unitCost: 720.00, unitPrice: 1280.00, initialStock: 25, reorderLevel: 6, manufacturer: "Novo Nordisk", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["refrigerated"] },

  // ─── Medicine: Vitamins / Supplements ──────────────────────────
  { productType: "Medicine", name: "Multivitamins B-Complex tablet (Berocca)",   description: "B-complex effervescent tablet",                                        unit: "piece",  unitCost: 6.00, unitPrice: 14.00, initialStock: 600, reorderLevel: 150, manufacturer: "Bayer", stockRoom: "Main Pharmacy", tags: ["supplement"] },
  { productType: "Medicine", name: "Ferrous Sulfate 325mg tablet (FeroSul)",    description: "Iron supplement",                                                      unit: "piece",  unitCost: 1.50, unitPrice: 4.00, initialStock: 800, reorderLevel: 200, manufacturer: "Unilab", stockRoom: "Main Pharmacy", tags: ["supplement"] },
  { productType: "Medicine", name: "Ferrous Sulfate 75mg/5mL syrup",            description: "Pediatric iron syrup, 60mL",                                           unit: "bottle", unitCost: 75.00, unitPrice: 145.00, initialStock: 80, reorderLevel: 20, manufacturer: "Unilab", stockRoom: "Main Pharmacy" },
  { productType: "Medicine", name: "Folic Acid 5mg tablet",                      description: "Folate supplement — antenatal, anemia",                                unit: "piece",  unitCost: 1.20, unitPrice: 3.00, initialStock: 500, reorderLevel: 120, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["supplement", "antenatal"] },
  { productType: "Medicine", name: "Vitamin C 500mg tablet (Cecon/Poten-Cee)",  description: "Ascorbic acid 500mg",                                                  unit: "piece",  unitCost: 2.00, unitPrice: 4.50, initialStock: 1000, reorderLevel: 250, manufacturer: "Unilab", stockRoom: "Main Pharmacy", tags: ["supplement"] },
  { productType: "Medicine", name: "Vitamin D3 1000IU softgel",                  description: "Cholecalciferol 1000IU softgel",                                       unit: "piece",  unitCost: 4.50, unitPrice: 10.00, initialStock: 400, reorderLevel: 100, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["supplement"] },
  { productType: "Medicine", name: "Calcium Carbonate 500mg + Vit D tablet",     description: "Calcium 500mg + cholecalciferol",                                     unit: "piece",  unitCost: 5.00, unitPrice: 11.00, initialStock: 400, reorderLevel: 100, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["supplement"] },
  { productType: "Medicine", name: "Zinc Sulfate 20mg syrup 60mL",               description: "Zinc supplement for diarrhea per WHO",                                 unit: "bottle", unitCost: 65.00, unitPrice: 125.00, initialStock: 70, reorderLevel: 18, manufacturer: "Unilab", stockRoom: "Main Pharmacy", tags: ["supplement", "pediatric"] },
  { productType: "Medicine", name: "Multivitamins + minerals tablet (Centrum)",  description: "Adult daily multivitamin",                                             unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 400, reorderLevel: 100, manufacturer: "Pfizer", stockRoom: "Main Pharmacy", tags: ["supplement"] },

  // ─── Medicine: Topical / Skin ──────────────────────────────────
  { productType: "Medicine", name: "Mupirocin 2% ointment 5g",                   description: "Topical antibiotic for impetigo",                                      unit: "piece",  unitCost: 95.00, unitPrice: 175.00, initialStock: 80, reorderLevel: 20, manufacturer: "GSK", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Hydrocortisone 1% cream 15g",                description: "Mild topical corticosteroid",                                          unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Betamethasone 0.1% cream 15g",               description: "Mid-potency topical steroid",                                          unit: "piece",  unitCost: 55.00, unitPrice: 110.00, initialStock: 80, reorderLevel: 20, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Clotrimazole 1% cream 15g",                  description: "Topical antifungal for tinea, candidiasis",                            unit: "piece",  unitCost: 75.00, unitPrice: 145.00, initialStock: 80, reorderLevel: 20, manufacturer: "Bayer", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },
  { productType: "Medicine", name: "Povidone-Iodine 10% solution 60mL",          description: "Topical antiseptic",                                                   unit: "bottle", unitCost: 38.00, unitPrice: 75.00, initialStock: 150, reorderLevel: 40, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["antiseptic"] },
  { productType: "Medicine", name: "Hydrogen Peroxide 3% solution 60mL",         description: "Wound cleansing antiseptic",                                           unit: "bottle", unitCost: 25.00, unitPrice: 55.00, initialStock: 120, reorderLevel: 30, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["antiseptic"] },
  { productType: "Medicine", name: "Silver Sulfadiazine 1% cream 50g",          description: "Burn dressing antimicrobial",                                          unit: "piece",  unitCost: 185.00, unitPrice: 325.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true },

  // ─── Medicine: IV Fluids ───────────────────────────────────────
  { productType: "Medicine", name: "Plain NSS 0.9% 1L IV bag",                   description: "Normal saline 1000mL for IV infusion",                                 unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 200, reorderLevel: 50, manufacturer: "Euro-Med", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["iv-fluid"] },
  { productType: "Medicine", name: "Plain LR 1L IV bag",                         description: "Lactated Ringer's 1000mL",                                             unit: "piece",  unitCost: 75.00, unitPrice: 145.00, initialStock: 150, reorderLevel: 40, manufacturer: "Euro-Med", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["iv-fluid"] },
  { productType: "Medicine", name: "D5 0.3 NaCl 1L IV bag",                      description: "5% dextrose in 0.3% saline 1000mL",                                    unit: "piece",  unitCost: 75.00, unitPrice: 145.00, initialStock: 100, reorderLevel: 25, manufacturer: "Euro-Med", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["iv-fluid"] },
  { productType: "Medicine", name: "D5W 1L IV bag",                              description: "5% dextrose in water 1000mL",                                          unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 100, reorderLevel: 25, manufacturer: "Euro-Med", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["iv-fluid"] },
  { productType: "Medicine", name: "Plain NSS 0.9% 250mL IV bag",                description: "Saline 250mL for slow infusions",                                      unit: "piece",  unitCost: 35.00, unitPrice: 75.00, initialStock: 200, reorderLevel: 50, manufacturer: "Euro-Med", stockRoom: "Main Pharmacy", isMedicine: true, taxExempt: true, tags: ["iv-fluid"] },

  // ─── Medicine: Vaccines (Cold Storage) ─────────────────────────
  { productType: "Medicine", name: "Tetanus Toxoid 0.5mL ampule",                description: "TT vaccine for wound prophylaxis / antenatal",                         unit: "ampule", unitCost: 65.00, unitPrice: 135.00, initialStock: 100, reorderLevel: 25, manufacturer: "BioFarma", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["vaccine", "refrigerated"] },
  { productType: "Medicine", name: "Hepatitis B vaccine adult 1mL",              description: "Recombinant HBV vaccine",                                              unit: "ampule", unitCost: 285.00, unitPrice: 525.00, initialStock: 50, reorderLevel: 12, manufacturer: "GSK", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["vaccine", "refrigerated"] },
  { productType: "Medicine", name: "Influenza vaccine 0.5mL syringe",            description: "Quadrivalent flu vaccine, season 2026",                                unit: "piece",  unitCost: 525.00, unitPrice: 850.00, initialStock: 80, reorderLevel: 20, manufacturer: "Sanofi", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["vaccine", "refrigerated"] },
  { productType: "Medicine", name: "PCV13 0.5mL syringe (Prevnar 13)",           description: "Pneumococcal conjugate vaccine",                                       unit: "piece",  unitCost: 1850.00, unitPrice: 2950.00, initialStock: 30, reorderLevel: 8, manufacturer: "Pfizer", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["vaccine", "refrigerated"] },
  { productType: "Medicine", name: "MMR vaccine 0.5mL ampule",                   description: "Measles-Mumps-Rubella live vaccine",                                   unit: "ampule", unitCost: 485.00, unitPrice: 850.00, initialStock: 40, reorderLevel: 10, manufacturer: "MSD", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["vaccine", "refrigerated", "pediatric"] },
  { productType: "Medicine", name: "Anti-Rabies Vaccine 0.5mL (Verorab)",        description: "Cell-culture rabies vaccine for PEP",                                  unit: "ampule", unitCost: 925.00, unitPrice: 1450.00, initialStock: 60, reorderLevel: 15, manufacturer: "Sanofi", stockRoom: "Cold Storage", isMedicine: true, taxExempt: true, tags: ["vaccine", "refrigerated", "rabies"] },

  // ─── Medical Supplies: Wound Care & Dressings ─────────────────
  { productType: "Medical Supplies", name: "Sterile Gauze Pad 4x4 (10s pack)",   description: "Pre-cut sterile cotton gauze 4x4 inches, 10 pieces",                   unit: "pack",   unitCost: 22.00, unitPrice: 45.00, initialStock: 300, reorderLevel: 80, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["wound-care", "sterile"] },
  { productType: "Medical Supplies", name: "Cotton Roll 100g",                    description: "Absorbent surgical cotton roll, 100g",                                 unit: "roll",   unitCost: 35.00, unitPrice: 75.00, initialStock: 150, reorderLevel: 40, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Cotton Balls (large) 100s",          description: "Sterile cotton balls — 100 per pack",                                  unit: "pack",   unitCost: 18.00, unitPrice: 38.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Surgical Tape 1in x 10yd (paper)",   description: "Hypoallergenic paper tape",                                            unit: "roll",   unitCost: 35.00, unitPrice: 75.00, initialStock: 200, reorderLevel: 50, manufacturer: "3M Micropore", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Adhesive Bandage assorted (100s)",   description: "Plastic strip bandages, assorted sizes",                               unit: "pack",   unitCost: 65.00, unitPrice: 125.00, initialStock: 100, reorderLevel: 25, manufacturer: "BAND-AID", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Elastic Bandage 4in x 5yd (Crepe)",  description: "Cotton crepe elastic bandage",                                         unit: "roll",   unitCost: 55.00, unitPrice: 110.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Elastic Bandage 6in x 5yd",          description: "Cotton crepe bandage, wider",                                          unit: "roll",   unitCost: 75.00, unitPrice: 145.00, initialStock: 80, reorderLevel: 20, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Triangular Bandage 36in",            description: "Cotton triangular bandage / sling",                                    unit: "piece",  unitCost: 45.00, unitPrice: 95.00, initialStock: 60, reorderLevel: 15, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Suture Pack (Silk 3-0 with needle)", description: "Pre-packaged silk suture, 3-0, with curved cutting needle",            unit: "piece",  unitCost: 95.00, unitPrice: 185.00, initialStock: 100, reorderLevel: 25, manufacturer: "Ethicon", stockRoom: "Main Pharmacy", tags: ["surgical", "sterile"] },
  { productType: "Medical Supplies", name: "Suture Pack (Vicryl 4-0)",          description: "Absorbable polyglactin suture, 4-0",                                   unit: "piece",  unitCost: 185.00, unitPrice: 325.00, initialStock: 50, reorderLevel: 12, manufacturer: "Ethicon", stockRoom: "Main Pharmacy", tags: ["surgical", "sterile"] },
  { productType: "Medical Supplies", name: "Steri-Strips 1/4in x 3in (10s)",    description: "Wound closure strips, 10 per pack",                                    unit: "pack",   unitCost: 145.00, unitPrice: 265.00, initialStock: 50, reorderLevel: 12, manufacturer: "3M", stockRoom: "Main Pharmacy", tags: ["wound-care"] },
  { productType: "Medical Supplies", name: "Surgical Glove Sterile 7.0 (pair)",  description: "Latex sterile surgical gloves, size 7.0",                              unit: "pack",   unitCost: 22.00, unitPrice: 45.00, initialStock: 300, reorderLevel: 80, manufacturer: "Ansell", stockRoom: "Main Pharmacy", tags: ["sterile", "surgical"] },
  { productType: "Medical Supplies", name: "Surgical Glove Sterile 7.5 (pair)",  description: "Latex sterile surgical gloves, size 7.5",                              unit: "pack",   unitCost: 22.00, unitPrice: 45.00, initialStock: 300, reorderLevel: 80, manufacturer: "Ansell", stockRoom: "Main Pharmacy", tags: ["sterile", "surgical"] },

  // ─── Medical Supplies: Injection / IV ─────────────────────────
  { productType: "Medical Supplies", name: "Disposable Syringe 1mL (BD)",        description: "1mL insulin syringe with needle",                                      unit: "piece",  unitCost: 4.00, unitPrice: 9.00, initialStock: 1000, reorderLevel: 250, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Disposable Syringe 3mL (BD)",        description: "3mL syringe with 23G needle",                                          unit: "piece",  unitCost: 5.00, unitPrice: 11.00, initialStock: 1500, reorderLevel: 350, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Disposable Syringe 5mL",             description: "5mL syringe with needle",                                              unit: "piece",  unitCost: 6.00, unitPrice: 13.00, initialStock: 1000, reorderLevel: 250, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Disposable Syringe 10mL",            description: "10mL syringe with needle",                                             unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 600, reorderLevel: 150, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Disposable Syringe 20mL",            description: "20mL syringe with needle",                                             unit: "piece",  unitCost: 12.00, unitPrice: 25.00, initialStock: 300, reorderLevel: 80, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Hypodermic Needle 23G x 1in (100s)", description: "Disposable needle 23G, 1 inch, 100 per box",                           unit: "box",    unitCost: 195.00, unitPrice: 365.00, initialStock: 50, reorderLevel: 12, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile"] },
  { productType: "Medical Supplies", name: "Hypodermic Needle 25G x 1in (100s)", description: "Disposable needle 25G, 1 inch",                                        unit: "box",    unitCost: 195.00, unitPrice: 365.00, initialStock: 50, reorderLevel: 12, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile"] },
  { productType: "Medical Supplies", name: "IV Cannula 22G (BD Insyte)",         description: "IV catheter 22G, blue",                                                unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 250, reorderLevel: 60, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "iv"] },
  { productType: "Medical Supplies", name: "IV Cannula 24G (BD Insyte)",         description: "IV catheter 24G, yellow (pediatric)",                                  unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 200, reorderLevel: 50, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "iv", "pediatric"] },
  { productType: "Medical Supplies", name: "IV Cannula 20G (BD Insyte)",         description: "IV catheter 20G, pink",                                                unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 250, reorderLevel: 60, manufacturer: "BD", stockRoom: "Main Pharmacy", tags: ["sterile", "iv"] },
  { productType: "Medical Supplies", name: "IV Administration Set (vented)",     description: "Standard IV tubing set with drip chamber",                             unit: "piece",  unitCost: 35.00, unitPrice: 75.00, initialStock: 300, reorderLevel: 80, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "iv"] },
  { productType: "Medical Supplies", name: "Microset / Pedia Drip Set",          description: "Pediatric IV set 60 drops/mL",                                         unit: "piece",  unitCost: 45.00, unitPrice: 95.00, initialStock: 150, reorderLevel: 40, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "iv", "pediatric"] },
  { productType: "Medical Supplies", name: "3-Way Stopcock",                     description: "IV line stopcock for multi-port access",                               unit: "piece",  unitCost: 28.00, unitPrice: 60.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "iv"] },
  { productType: "Medical Supplies", name: "Heparin Lock / Saline Lock",         description: "Capped IV access port",                                                unit: "piece",  unitCost: 18.00, unitPrice: 38.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "iv"] },
  { productType: "Medical Supplies", name: "Tourniquet (latex strap)",            description: "Reusable rubber tourniquet for venipuncture",                          unit: "piece",  unitCost: 28.00, unitPrice: 65.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "Medical Supplies", name: "Alcohol Swab (200s box)",            description: "70% isopropyl alcohol prep pads",                                      unit: "box",    unitCost: 95.00, unitPrice: 175.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["antiseptic"] },
  { productType: "Medical Supplies", name: "Cotton-tipped Applicator (100s)",    description: "Sterile swab sticks, 100 per pack",                                    unit: "pack",   unitCost: 28.00, unitPrice: 60.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy" },

  // ─── Medical Supplies: Tubes / Containers ─────────────────────
  { productType: "Medical Supplies", name: "Specimen Cup with Lid 60mL (50s)",   description: "Polypropylene urine specimen cup",                                     unit: "pack",   unitCost: 145.00, unitPrice: 285.00, initialStock: 50, reorderLevel: 12, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab"] },
  { productType: "Medical Supplies", name: "Stool Specimen Cup w/ scoop (50s)",  description: "Stool collection cup with attached scoop",                             unit: "pack",   unitCost: 165.00, unitPrice: 325.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab"] },
  { productType: "Medical Supplies", name: "Vacutainer Lavender Top (EDTA) 4mL", description: "EDTA tube for CBC",                                                    unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 800, reorderLevel: 200, manufacturer: "BD", stockRoom: "Lab Stock Room", tags: ["lab", "phlebotomy"] },
  { productType: "Medical Supplies", name: "Vacutainer Red Top (Plain) 5mL",     description: "Plain tube for chemistry",                                             unit: "piece",  unitCost: 8.00, unitPrice: 18.00, initialStock: 600, reorderLevel: 150, manufacturer: "BD", stockRoom: "Lab Stock Room", tags: ["lab", "phlebotomy"] },
  { productType: "Medical Supplies", name: "Vacutainer Yellow Top (SST) 4mL",    description: "Serum separator tube",                                                 unit: "piece",  unitCost: 12.00, unitPrice: 25.00, initialStock: 500, reorderLevel: 120, manufacturer: "BD", stockRoom: "Lab Stock Room", tags: ["lab", "phlebotomy"] },
  { productType: "Medical Supplies", name: "Vacutainer Light Blue (Citrate) 3mL", description: "Sodium citrate tube for coagulation",                                  unit: "piece",  unitCost: 14.00, unitPrice: 30.00, initialStock: 300, reorderLevel: 80, manufacturer: "BD", stockRoom: "Lab Stock Room", tags: ["lab", "phlebotomy"] },
  { productType: "Medical Supplies", name: "Microscope Slide (plain) 50s",        description: "Glass microscope slides 25x75mm, 50 per box",                          unit: "box",    unitCost: 95.00, unitPrice: 175.00, initialStock: 50, reorderLevel: 12, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab"] },
  { productType: "Medical Supplies", name: "Cover Slip (22mm) 100s",              description: "Glass coverslip 22mm square",                                          unit: "box",    unitCost: 65.00, unitPrice: 125.00, initialStock: 50, reorderLevel: 12, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab"] },
  { productType: "Medical Supplies", name: "Sharps Container 5L",                description: "Puncture-resistant sharps disposal container",                         unit: "piece",  unitCost: 285.00, unitPrice: 485.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["safety"] },

  // ─── Medical Supplies: Catheters / Misc ───────────────────────
  { productType: "Medical Supplies", name: "Foley Catheter 16Fr (2-way)",        description: "Latex Foley catheter with 10mL balloon",                               unit: "piece",  unitCost: 95.00, unitPrice: 185.00, initialStock: 50, reorderLevel: 12, manufacturer: "Bard", stockRoom: "Main Pharmacy", tags: ["sterile"] },
  { productType: "Medical Supplies", name: "Foley Catheter 14Fr (2-way)",        description: "Latex Foley catheter, smaller bore",                                   unit: "piece",  unitCost: 95.00, unitPrice: 185.00, initialStock: 30, reorderLevel: 8, manufacturer: "Bard", stockRoom: "Main Pharmacy", tags: ["sterile"] },
  { productType: "Medical Supplies", name: "Urine Bag 2L (collection)",          description: "Drainage bag with anti-reflux valve",                                  unit: "piece",  unitCost: 38.00, unitPrice: 85.00, initialStock: 80, reorderLevel: 20, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "Medical Supplies", name: "Nasogastric Tube 16Fr",              description: "PVC NGT for adult",                                                    unit: "piece",  unitCost: 65.00, unitPrice: 135.00, initialStock: 40, reorderLevel: 10, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile"] },
  { productType: "Medical Supplies", name: "Suction Catheter 12Fr",              description: "Sterile single-use suction catheter",                                  unit: "piece",  unitCost: 22.00, unitPrice: 50.00, initialStock: 150, reorderLevel: 40, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Endotracheal Tube 7.5mm (cuffed)",   description: "PVC ET tube with cuff",                                                unit: "piece",  unitCost: 285.00, unitPrice: 485.00, initialStock: 20, reorderLevel: 5, manufacturer: "Mallinckrodt", stockRoom: "Main Pharmacy", tags: ["sterile", "anesthesia"] },
  { productType: "Medical Supplies", name: "Tongue Depressor (100s)",            description: "Wooden tongue depressors",                                             unit: "pack",   unitCost: 45.00, unitPrice: 95.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "Medical Supplies", name: "Penlight (LED disposable)",          description: "Disposable medical penlight",                                          unit: "piece",  unitCost: 28.00, unitPrice: 65.00, initialStock: 80, reorderLevel: 20, manufacturer: "Generic", stockRoom: "Main Pharmacy" },

  // ─── Medical Supplies: Examination ────────────────────────────
  { productType: "Medical Supplies", name: "Examination Glove Latex (M, 100s)",  description: "Latex powdered exam gloves, medium",                                   unit: "box",    unitCost: 285.00, unitPrice: 485.00, initialStock: 80, reorderLevel: 20, manufacturer: "Ansell", stockRoom: "Main Pharmacy", tags: ["non-sterile"] },
  { productType: "Medical Supplies", name: "Examination Glove Nitrile (M, 100s)", description: "Nitrile powder-free exam gloves, medium",                              unit: "box",    unitCost: 385.00, unitPrice: 625.00, initialStock: 80, reorderLevel: 20, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["non-sterile", "latex-free"] },
  { productType: "Medical Supplies", name: "Examination Glove Nitrile (L, 100s)", description: "Nitrile powder-free exam gloves, large",                               unit: "box",    unitCost: 385.00, unitPrice: 625.00, initialStock: 80, reorderLevel: 20, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["non-sterile", "latex-free"] },
  { productType: "Medical Supplies", name: "Vaginal Speculum (medium, plastic)", description: "Disposable plastic speculum",                                          unit: "piece",  unitCost: 65.00, unitPrice: 135.00, initialStock: 50, reorderLevel: 12, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "Anoscope Disposable",                description: "Disposable anoscope",                                                  unit: "piece",  unitCost: 145.00, unitPrice: 285.00, initialStock: 20, reorderLevel: 5, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "single-use"] },
  { productType: "Medical Supplies", name: "ECG Electrodes (50s)",               description: "Disposable adult ECG snap electrodes",                                 unit: "pack",   unitCost: 285.00, unitPrice: 525.00, initialStock: 30, reorderLevel: 8, manufacturer: "3M Red Dot", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "Medical Supplies", name: "Pulse Oximeter Probe (adult finger)", description: "Reusable adult finger probe",                                          unit: "piece",  unitCost: 1450.00, unitPrice: 2400.00, initialStock: 10, reorderLevel: 3, manufacturer: "Nellcor", stockRoom: "Main Pharmacy" },
  { productType: "Medical Supplies", name: "Sphygmomanometer Cuff (adult)",      description: "Replacement BP cuff, adult arm",                                       unit: "piece",  unitCost: 485.00, unitPrice: 850.00, initialStock: 15, reorderLevel: 4, manufacturer: "Welch Allyn", stockRoom: "Main Pharmacy" },

  // ─── Lab Reagent ──────────────────────────────────────────────
  { productType: "Lab Reagent", name: "CBC Reagent Kit (Sysmex compatible)",    description: "Hematology analyzer reagent kit, 5L",                                  unit: "set",    unitCost: 4850.00, unitPrice: 7500.00, initialStock: 8, reorderLevel: 2, manufacturer: "Sysmex", stockRoom: "Lab Stock Room", tags: ["reagent", "hematology"] },
  { productType: "Lab Reagent", name: "Glucose Reagent (chemistry analyzer)",   description: "Glucose oxidase reagent for AU480",                                    unit: "set",    unitCost: 1850.00, unitPrice: 2950.00, initialStock: 12, reorderLevel: 3, manufacturer: "Beckman Coulter", stockRoom: "Lab Stock Room", tags: ["reagent", "chemistry"] },
  { productType: "Lab Reagent", name: "Creatinine Reagent",                      description: "Jaffe-method creatinine reagent",                                      unit: "set",    unitCost: 1450.00, unitPrice: 2350.00, initialStock: 10, reorderLevel: 3, manufacturer: "Beckman Coulter", stockRoom: "Lab Stock Room", tags: ["reagent", "chemistry"] },
  { productType: "Lab Reagent", name: "Cholesterol Reagent (Total)",            description: "Enzymatic total cholesterol reagent",                                  unit: "set",    unitCost: 1650.00, unitPrice: 2650.00, initialStock: 10, reorderLevel: 3, manufacturer: "Beckman Coulter", stockRoom: "Lab Stock Room", tags: ["reagent", "chemistry"] },
  { productType: "Lab Reagent", name: "HDL Reagent",                              description: "Direct HDL cholesterol reagent",                                       unit: "set",    unitCost: 1750.00, unitPrice: 2850.00, initialStock: 8, reorderLevel: 2, manufacturer: "Beckman Coulter", stockRoom: "Lab Stock Room", tags: ["reagent", "chemistry"] },
  { productType: "Lab Reagent", name: "Triglycerides Reagent",                   description: "Enzymatic triglycerides reagent",                                      unit: "set",    unitCost: 1650.00, unitPrice: 2650.00, initialStock: 8, reorderLevel: 2, manufacturer: "Beckman Coulter", stockRoom: "Lab Stock Room", tags: ["reagent", "chemistry"] },
  { productType: "Lab Reagent", name: "AST/ALT Reagent (paired)",                description: "Liver enzyme reagent set",                                             unit: "set",    unitCost: 1850.00, unitPrice: 2950.00, initialStock: 8, reorderLevel: 2, manufacturer: "Beckman Coulter", stockRoom: "Lab Stock Room", tags: ["reagent", "chemistry"] },
  { productType: "Lab Reagent", name: "Urinalysis Strip (10-parameter, 100s)",   description: "Multi-pad urinalysis strip",                                           unit: "box",    unitCost: 285.00, unitPrice: 485.00, initialStock: 80, reorderLevel: 20, manufacturer: "Roche", stockRoom: "Lab Stock Room", tags: ["lab", "strip"] },
  { productType: "Lab Reagent", name: "Pregnancy Test Strip (hCG, 50s)",         description: "Urine hCG dipstick",                                                   unit: "box",    unitCost: 145.00, unitPrice: 285.00, initialStock: 60, reorderLevel: 15, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab", "strip"] },
  { productType: "Lab Reagent", name: "Glucose Test Strip (Accu-Chek, 50s)",     description: "Blood glucose monitor strips",                                         unit: "box",    unitCost: 850.00, unitPrice: 1450.00, initialStock: 50, reorderLevel: 12, manufacturer: "Roche", stockRoom: "Lab Stock Room", tags: ["lab", "strip"] },
  { productType: "Lab Reagent", name: "HbA1c Cartridge (DCA Vantage)",           description: "Single-use HbA1c assay cartridge",                                     unit: "piece",  unitCost: 285.00, unitPrice: 485.00, initialStock: 100, reorderLevel: 25, manufacturer: "Siemens", stockRoom: "Lab Stock Room", tags: ["lab", "cartridge"] },
  { productType: "Lab Reagent", name: "HBsAg Rapid Test Card (50s)",             description: "Hepatitis B surface antigen rapid test",                               unit: "box",    unitCost: 950.00, unitPrice: 1650.00, initialStock: 30, reorderLevel: 8, manufacturer: "SD Biosensor", stockRoom: "Lab Stock Room", tags: ["lab", "rapid-test"] },
  { productType: "Lab Reagent", name: "HIV Rapid Test Kit (Determine)",          description: "Anti-HIV 1/2 rapid test, 100 per kit",                                 unit: "box",    unitCost: 4850.00, unitPrice: 7500.00, initialStock: 8, reorderLevel: 2, manufacturer: "Abbott", stockRoom: "Lab Stock Room", tags: ["lab", "rapid-test"] },
  { productType: "Lab Reagent", name: "ABO Blood Typing Antisera (set)",         description: "Anti-A, Anti-B, Anti-D antisera",                                      unit: "set",    unitCost: 1450.00, unitPrice: 2400.00, initialStock: 8, reorderLevel: 2, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab", "blood-bank"] },
  { productType: "Lab Reagent", name: "Gram Stain Kit",                          description: "Crystal violet, iodine, decolorizer, safranin",                        unit: "set",    unitCost: 1850.00, unitPrice: 2950.00, initialStock: 8, reorderLevel: 2, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab", "microbiology"] },
  { productType: "Lab Reagent", name: "Wright Stain 500mL",                       description: "Wright's stain for blood smears",                                      unit: "bottle", unitCost: 850.00, unitPrice: 1450.00, initialStock: 12, reorderLevel: 3, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab", "stain"] },
  { productType: "Lab Reagent", name: "Distilled Water 1L",                       description: "Pyrogen-free distilled water for reagents",                            unit: "bottle", unitCost: 65.00, unitPrice: 125.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab"] },
  { productType: "Lab Reagent", name: "Buffer Solution pH 7.4",                   description: "Phosphate buffer pH 7.4, 500mL",                                       unit: "bottle", unitCost: 285.00, unitPrice: 485.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab", "buffer"] },
  { productType: "Lab Reagent", name: "Immersion Oil 30mL",                       description: "Microscope immersion oil",                                             unit: "bottle", unitCost: 145.00, unitPrice: 285.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["lab"] },
  { productType: "Lab Reagent", name: "X-ray Film Developer 5L",                  description: "Automatic processor developer concentrate",                            unit: "set",    unitCost: 2850.00, unitPrice: 4500.00, initialStock: 6, reorderLevel: 2, manufacturer: "Carestream", stockRoom: "Lab Stock Room", tags: ["radiology"] },
  { productType: "Lab Reagent", name: "X-ray Film Fixer 5L",                      description: "Automatic processor fixer concentrate",                                unit: "set",    unitCost: 2650.00, unitPrice: 4250.00, initialStock: 6, reorderLevel: 2, manufacturer: "Carestream", stockRoom: "Lab Stock Room", tags: ["radiology"] },
  { productType: "Lab Reagent", name: "X-ray Film 8x10 (100s)",                   description: "Blue-base X-ray film 8x10 inches",                                     unit: "box",    unitCost: 4850.00, unitPrice: 7500.00, initialStock: 5, reorderLevel: 2, manufacturer: "Fuji", stockRoom: "Lab Stock Room", tags: ["radiology"] },
  { productType: "Lab Reagent", name: "X-ray Film 14x17 (100s)",                  description: "Blue-base X-ray film 14x17 inches (chest)",                            unit: "box",    unitCost: 8850.00, unitPrice: 13500.00, initialStock: 4, reorderLevel: 1, manufacturer: "Fuji", stockRoom: "Lab Stock Room", tags: ["radiology"] },
  { productType: "Lab Reagent", name: "Ultrasound Gel 250mL",                     description: "Conductive transmission gel for UTZ",                                  unit: "bottle", unitCost: 145.00, unitPrice: 285.00, initialStock: 60, reorderLevel: 15, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["radiology"] },
  { productType: "Lab Reagent", name: "Ultrasound Gel 5L (refill)",               description: "Bulk transmission gel refill",                                         unit: "bottle", unitCost: 850.00, unitPrice: 1450.00, initialStock: 20, reorderLevel: 5, manufacturer: "Generic", stockRoom: "Lab Stock Room", tags: ["radiology"] },

  // ─── PPE ──────────────────────────────────────────────────────
  { productType: "PPE", name: "Surgical Mask 3-Ply (50s)",                       description: "Disposable 3-ply earloop mask",                                        unit: "box",    unitCost: 95.00, unitPrice: 185.00, initialStock: 200, reorderLevel: 50, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "PPE", name: "N95 Respirator (3M 8210)",                        description: "NIOSH-certified N95 respirator",                                       unit: "piece",  unitCost: 65.00, unitPrice: 125.00, initialStock: 200, reorderLevel: 50, manufacturer: "3M", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "PPE", name: "KN95 Mask (10s pack)",                            description: "KN95 disposable respirator",                                           unit: "pack",   unitCost: 145.00, unitPrice: 285.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "PPE", name: "Face Shield (clear, anti-fog)",                   description: "Reusable face shield with foam padding",                               unit: "piece",  unitCost: 85.00, unitPrice: 165.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "PPE", name: "Surgical Gown (sterile, non-woven)",              description: "Single-use sterile surgical gown",                                     unit: "piece",  unitCost: 285.00, unitPrice: 525.00, initialStock: 50, reorderLevel: 12, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["sterile", "disposable"] },
  { productType: "PPE", name: "Isolation Gown (non-sterile)",                    description: "Disposable yellow isolation gown",                                     unit: "piece",  unitCost: 95.00, unitPrice: 185.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "PPE", name: "Surgical Cap (Bouffant, 100s)",                   description: "Disposable bouffant cap",                                              unit: "pack",   unitCost: 95.00, unitPrice: 185.00, initialStock: 50, reorderLevel: 12, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "PPE", name: "Shoe Cover (100s pack)",                          description: "Non-slip disposable shoe covers",                                      unit: "pack",   unitCost: 145.00, unitPrice: 285.00, initialStock: 40, reorderLevel: 10, manufacturer: "Generic", stockRoom: "Main Pharmacy", tags: ["disposable"] },
  { productType: "PPE", name: "Goggles (anti-splash, reusable)",                 description: "Lab safety goggles, reusable",                                         unit: "piece",  unitCost: 285.00, unitPrice: 525.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "PPE", name: "PPE Set Coverall (Level 3)",                      description: "Full disposable coverall for high-risk procedures",                    unit: "set",    unitCost: 485.00, unitPrice: 850.00, initialStock: 30, reorderLevel: 8, manufacturer: "DuPont", stockRoom: "Main Pharmacy", tags: ["disposable"] },

  // ─── Office Supply ────────────────────────────────────────────
  { productType: "Office Supply", name: "Prescription Pad (50 sheets)",          description: "Pre-printed Rx pad for clinic use",                                    unit: "pack",   unitCost: 45.00, unitPrice: 85.00, initialStock: 100, reorderLevel: 25, manufacturer: "Generic", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Medical Certificate Form (100s)",       description: "Standard MC form, 100 sheets",                                         unit: "pack",   unitCost: 65.00, unitPrice: 125.00, initialStock: 60, reorderLevel: 15, manufacturer: "Generic", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Bond Paper Long (Sub-20, 500s)",        description: "Long bond paper, sub-20",                                              unit: "pack",   unitCost: 285.00, unitPrice: 485.00, initialStock: 40, reorderLevel: 10, manufacturer: "Hard Copy", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Bond Paper Short (Sub-20, 500s)",       description: "Short bond paper",                                                     unit: "pack",   unitCost: 245.00, unitPrice: 425.00, initialStock: 40, reorderLevel: 10, manufacturer: "Hard Copy", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Ballpen (Black, 50s)",                  description: "Bic-style ballpoint pen",                                              unit: "pack",   unitCost: 95.00, unitPrice: 185.00, initialStock: 30, reorderLevel: 8, manufacturer: "Pilot", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Patient ID Wristband (Adult, 100s)",    description: "Adhesive patient identification wristband",                            unit: "pack",   unitCost: 285.00, unitPrice: 485.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Patient ID Wristband (Pediatric)",      description: "Pediatric patient ID wristband",                                       unit: "pack",   unitCost: 245.00, unitPrice: 425.00, initialStock: 20, reorderLevel: 5, manufacturer: "Generic", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Thermal Receipt Roll (3in)",            description: "Thermal printer paper for invoice",                                    unit: "roll",   unitCost: 38.00, unitPrice: 75.00, initialStock: 60, reorderLevel: 15, manufacturer: "Generic", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Folder Long (Manila, 100s)",            description: "Manila folder for charts",                                             unit: "pack",   unitCost: 285.00, unitPrice: 485.00, initialStock: 30, reorderLevel: 8, manufacturer: "Generic", stockRoom: "Front Desk Cabinet" },
  { productType: "Office Supply", name: "Sticker Label (1in x 3in, 1000s)",       description: "Self-adhesive labels for specimens",                                   unit: "pack",   unitCost: 245.00, unitPrice: 425.00, initialStock: 25, reorderLevel: 6, manufacturer: "Avery", stockRoom: "Front Desk Cabinet" },

  // ─── Equipment (small/consumable end) ─────────────────────────
  { productType: "Equipment", name: "Digital Thermometer (oral/axillary)",       description: "Battery-operated digital thermometer",                                 unit: "piece",  unitCost: 145.00, unitPrice: 285.00, initialStock: 30, reorderLevel: 8, manufacturer: "Omron", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Infrared Thermometer (forehead)",           description: "Non-contact infrared thermometer",                                     unit: "piece",  unitCost: 1450.00, unitPrice: 2400.00, initialStock: 12, reorderLevel: 3, manufacturer: "Omron", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Sphygmomanometer (aneroid, adult)",         description: "Manual aneroid BP apparatus",                                          unit: "set",    unitCost: 1850.00, unitPrice: 2950.00, initialStock: 10, reorderLevel: 3, manufacturer: "Welch Allyn", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Sphygmomanometer (digital arm)",            description: "Automatic upper-arm BP monitor",                                       unit: "piece",  unitCost: 2850.00, unitPrice: 4500.00, initialStock: 8, reorderLevel: 2, manufacturer: "Omron", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Stethoscope (Littmann Classic III)",        description: "Dual-head adult/pediatric stethoscope",                                unit: "piece",  unitCost: 4850.00, unitPrice: 7500.00, initialStock: 8, reorderLevel: 2, manufacturer: "3M Littmann", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Otoscope (handheld)",                       description: "Pocket otoscope with batteries and specula",                           unit: "set",    unitCost: 4850.00, unitPrice: 7500.00, initialStock: 5, reorderLevel: 2, manufacturer: "Welch Allyn", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Pulse Oximeter (fingertip)",                description: "Portable SpO2 monitor",                                                unit: "piece",  unitCost: 1450.00, unitPrice: 2400.00, initialStock: 15, reorderLevel: 4, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Glucometer (Accu-Chek Active)",             description: "Blood glucose meter starter kit",                                      unit: "set",    unitCost: 1850.00, unitPrice: 2950.00, initialStock: 12, reorderLevel: 3, manufacturer: "Roche", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Nebulizer (compressor, portable)",          description: "Tabletop compressor nebulizer with mouthpiece",                        unit: "set",    unitCost: 2850.00, unitPrice: 4500.00, initialStock: 8, reorderLevel: 2, manufacturer: "Omron", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Weighing Scale (digital, adult)",           description: "Digital floor scale, capacity 180kg",                                  unit: "piece",  unitCost: 4850.00, unitPrice: 7500.00, initialStock: 4, reorderLevel: 1, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Weighing Scale (Infant, digital)",          description: "Pediatric weighing scale 0-20kg",                                      unit: "piece",  unitCost: 5850.00, unitPrice: 8500.00, initialStock: 3, reorderLevel: 1, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
  { productType: "Equipment", name: "Height Measuring Rod (Stadiometer)",        description: "Wall-mounted height measure",                                          unit: "piece",  unitCost: 2850.00, unitPrice: 4500.00, initialStock: 4, reorderLevel: 1, manufacturer: "Generic", stockRoom: "Main Pharmacy" },
];

// Quick sanity assert (build-time): keep this aligned with stock-room and
// product-type names so the seeded refs don't go missing.
function _assertProductCatalogSanity() {
  const validTypes = new Set(SEED_PRODUCT_TYPES);
  const validRooms = new Set(SEED_STOCK_ROOMS);
  for (const p of SEED_PRODUCTS) {
    if (!validTypes.has(p.productType)) {
      throw new Error(`SEED_PRODUCTS: unknown productType '${p.productType}' for '${p.name}'`);
    }
    if (p.stockRoom && !validRooms.has(p.stockRoom)) {
      throw new Error(`SEED_PRODUCTS: unknown stockRoom '${p.stockRoom}' for '${p.name}'`);
    }
  }
}
_assertProductCatalogSanity();

// /inventory-variants includeQueryFields whitelist does NOT include
// externalId (services/hapihub/src/services/inventory/variants.ts:547)
// — the same query-drop pattern we hit on /diagnostic-packages and
// /fixtures. Fetch all variants for the warehouse once, then dedup by
// externalId client-side. Pages of 500 cover our 200-product catalogue
// twice over.
async function listExistingProductExternalIds(warehouse: string): Promise<Set<string>> {
  const seen = new Set<string>();
  let skip = 0;
  const limit = 500;
  while (true) {
    try {
      const res = (await api(
        "GET",
        `/inventory-variants?warehouse=${encodeURIComponent(warehouse)}&%24limit=${limit}&%24skip=${skip}`,
      )) as { data?: Array<{ externalId?: string }>; total?: number } | Array<{ externalId?: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const v of list) if (v.externalId) seen.add(v.externalId);
      if (list.length < limit) break;
      skip += limit;
      // Safety: bail at 5 pages so a buggy server doesn't infinite-loop us.
      if (skip >= limit * 5) break;
    } catch {
      break;
    }
  }
  return seen;
}

async function seedProducts(
  facilities: Array<{ id: string; label: string; profile: OrgProfile }>,
): Promise<void> {
  // Hapihub validation (services/hapihub/src/services/inventory/products.ts:44):
  //   "Can only create products in the main warehouse" — branch warehouses
  //   are rejected. Branches share the parent's catalogue via the `branches`
  //   field (auto-populated server-side on create). Filter to the parent.
  const parentFacility = facilities.find((f) => !f.profile.parentName);
  if (!parentFacility) {
    console.warn(
      chalk.yellow("⚠  Inventory products skipped — no parent facility in ORG_PROFILES."),
    );
    return;
  }
  const parentFacilities = [parentFacility];

  const total = SEED_PRODUCTS.length * parentFacilities.length;
  const spinner = ora(
    `Seeding ${total} inventory products on parent warehouse '${parentFacility.profile.name}' (across ${SEED_PRODUCT_TYPES.length} types)...`,
  ).start();
  let created = 0;
  let skipped = 0;
  let progress = 0;

  for (const facility of parentFacilities) {
    spinner.text = `[${facility.label}] reading existing inventory...`;
    const existingExternalIds = await listExistingProductExternalIds(facility.id);

    for (let i = 0; i < SEED_PRODUCTS.length; i++) {
      const tpl = SEED_PRODUCTS[i];
      const externalId = `SEEDINV${String(i + 1).padStart(3, "0")}`;
      progress++;
      spinner.text = `[${facility.label}] ${tpl.productType} / ${tpl.name} (${progress}/${total})`;

      if (existingExternalIds.has(externalId)) {
        skipped++;
        continue;
      }

      // Deterministic 12-digit barcode (EAN-style): 200<productIdx 7-digit><check 2-digit>.
      const barcode =
        tpl.barcode ||
        `200${String(i + 1).padStart(7, "0")}${String((i + 1) % 100).padStart(2, "0")}`;

      // POST to /inventory-products (NOT /inventory-variants) so the full
      // variant body propagates through createVariantsAfter — bypassing the
      // dedup-loses-fields footgun that hits when POSTing /inventory-variants
      // directly. See services/hapihub/src/services/inventory/products.ts:84
      // — when `variants[]` is supplied, each entry is forwarded verbatim
      // to createInventoryVariant rather than synthesised from limited fields.
      const variantBody: Record<string, unknown> = {
        // warehouse + product are stamped by createVariantsAfter from the
        // parent product, but include them explicitly so processCreateData
        // skips re-creating the parent product.
        name: tpl.name,
        description: tpl.description,
        externalId,
        barcode,
        productType: tpl.productType,
        unit: tpl.unit,
        unitCost: tpl.unitCost,
        unitPrice: tpl.unitPrice,
        initialPrice: tpl.unitPrice,
        initialCost: tpl.unitCost,
        sellable: true,
        onlineSellable: false,
        taxExempt: !!tpl.taxExempt,
        // initialStock + stockRoom are stripped to extraData server-side
        // and used to create the matching inventory-stocks row.
        initialStock: tpl.initialStock,
        ...(tpl.stockRoom ? { stockRoom: tpl.stockRoom } : {}),
        ...(tpl.reorderLevel != null ? { reorderLevel: tpl.reorderLevel } : {}),
        ...(tpl.quantityThreshold != null ? { quantityThreshold: tpl.quantityThreshold } : {}),
        ...(tpl.isMedicine ? { isMedicine: true } : {}),
        ...(tpl.isMedicineDangerous ? { isMedicineDangerous: true } : {}),
        ...(tpl.manufacturer
          ? { metadata: { manufacturer: tpl.manufacturer, seed: true } }
          : { metadata: { seed: true } }),
        tags: ["seed", "demo", ...(tpl.tags ?? [])],
      };

      const productBody: Record<string, unknown> = {
        warehouse: facility.id,
        name: tpl.name,
        description: tpl.description,
        type: tpl.productType,
        tags: ["seed", "demo", ...(tpl.tags ?? [])],
        variants: [variantBody],
      };

      try {
        await api("POST", "/inventory-products", productBody);
        created++;
      } catch (err: unknown) {
        const msg = (err as Error).message;
        spinner.fail(`Failed to create product '${tpl.name}' (${externalId}): ${msg.slice(0, 200)}`);
        process.exit(1);
      }
    }
  }

  // Per-type breakdown for the summary
  const byType = SEED_PRODUCTS.reduce<Record<string, number>>((acc, p) => {
    acc[p.productType] = (acc[p.productType] ?? 0) + 1;
    return acc;
  }, {});
  const breakdown = Object.entries(byType).map(([t, n]) => `${t}=${n}`).join(", ");
  spinner.succeed(
    `Products: ${created} new, ${skipped} skipped — ${total} target (${breakdown})`,
  );
}

// ---------------------------------------------------------------------------
// Reset: wipe seed data via API (DELETE endpoints exposed by hapihub).
// Order matters because of FK / referential constraints:
//
//   1. Sign in as superadmin to authorize subsequent deletes
//   2. For each seed user, list and delete their org memberships
//   3. Delete the seed orgs (child branch first, then parent)
//   4. Delete the seed user accounts last (superadmin LAST so the session
//      stays valid through the loop)
//
// If the superadmin sign-in fails because the password no longer matches
// what's in the DB, the function exits with a clear error pointing the
// operator to manual DB cleanup. This is by design — without superadmin
// auth we can't authorize the deletes. Local dev fallback: drop the rows
// directly via psql then rerun without --reset.
// ---------------------------------------------------------------------------

// Children first so the parent can be deleted last (no orphan _ch refs).
// Derived from ORG_PROFILES so adding a new branch doesn't drift this list.
// Legacy names from earlier revisions of this script are included so that
// running `--reset` against an env seeded with the older script still
// cleans up cleanly (one-shot upgrade path).
const LEGACY_SEED_ORG_NAMES = ["MyCure Demo Branch"];
const SEED_ORG_NAMES = [
  ...LEGACY_SEED_ORG_NAMES,
  ...ORG_PROFILES.filter((o) => o.parentName).map((o) => o.name),
  ...ORG_PROFILES.filter((o) => !o.parentName).map((o) => o.name),
];

async function listAccountIdByEmail(email: string): Promise<string | undefined> {
  try {
    const res = (await api("GET", `/accounts?email=${encodeURIComponent(email)}`)) as
      { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list[0]?.id;
  } catch {
    return undefined;
  }
}

async function listOrgIdsByName(name: string): Promise<string[]> {
  try {
    const res = (await api("GET", `/organizations?name=${encodeURIComponent(name)}`)) as
      { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list.map((o) => o.id);
  } catch {
    return [];
  }
}

async function listMembershipIdsForUser(uid: string): Promise<string[]> {
  try {
    const res = (await api("GET", `/organization-members?uid=${encodeURIComponent(uid)}`)) as
      { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    return list.map((m) => m.id);
  } catch {
    return [];
  }
}

async function resetSeedData() {
  const spinner = ora("Resetting existing seed data...").start();

  // Step 1: Auth as superadmin. If the user doesn't exist, that's fine —
  // assume nothing to reset and move on.
  sessionCookie = "";
  try {
    await signIn("superadmin@mycure.test", PASSWORD);
  } catch (err: unknown) {
    const msg = (err as Error).message;
    // Treat "user not found" / 404-ish as "nothing to reset"
    if (
      msg.includes("USER_NOT_FOUND") ||
      msg.includes("not found") ||
      msg.includes("404") ||
      msg.includes("INVALID_EMAIL_OR_PASSWORD") ||
      msg.includes("Invalid email") ||
      msg.includes("Invalid credentials")
    ) {
      // Could be either "no superadmin yet" (clean DB) or "superadmin
      // exists but password doesn't match". We can't distinguish these
      // from a single 4xx without inspecting the response shape, so try
      // a probe: if the email exists, exit with a clear error; else move on.
      const probe = await listAccountIdByEmail("superadmin@mycure.test");
      if (probe) {
        spinner.fail(
          chalk.red(
            "Cannot sign in as superadmin@mycure.test for --reset.\n" +
            "The account exists but the password doesn't match.\n" +
            "Either rotate the password manually, or wipe the seed users from the DB:\n" +
            "  DELETE FROM organization_members\n" +
            "    WHERE uid IN (SELECT id FROM accounts WHERE email LIKE '%@mycure.test');\n" +
            "  DELETE FROM accounts WHERE email LIKE '%@mycure.test';\n" +
            "  DELETE FROM organizations WHERE name IN (\n" +
            "    " + SEED_ORG_NAMES.map((n) => `'${n}'`).join(", ") + ");\n" +
            "Then rerun without --reset.",
          ),
        );
        process.exit(1);
      }
      spinner.succeed("No existing seed data found — skipping reset");
      return;
    }
    spinner.fail(`Unexpected error during reset auth: ${msg}`);
    process.exit(1);
  }

  // Step 2: For each seed user, find their account id then delete their
  // org memberships. Stash the uid for the final account delete pass.
  const userIds: Record<string, string> = {};
  for (const user of USERS) {
    const uid = await listAccountIdByEmail(user.email);
    if (!uid) continue;
    userIds[user.email] = uid;
    const memberIds = await listMembershipIdsForUser(uid);
    for (const mid of memberIds) {
      try {
        await api("DELETE", `/organization-members/${mid}`);
      } catch {
        // ignore — best effort
      }
    }
  }

  // Step 3a: Delete seed patients + their encounters/records.
  // Find seed patients first (regex match on externalId), then for each
  // we sweep their encounters and medical-records before deleting the
  // patient row — hapihub doesn't cascade the medical_* tables on
  // patient delete and we'd otherwise orphan the fixed patient's chart.
  let seedPatientIds: string[] = [];
  try {
    const res = (await api(
      "GET",
      `/medical-patients?externalId%5B%24regex%5D=%5ESEED-PATIENT-&%24limit=500`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    seedPatientIds = list.map((p) => p.id).filter(Boolean);
  } catch {
    // ignore
  }

  for (const pid of seedPatientIds) {
    // medical-records (vitals, assessment, medication-order, etc.)
    try {
      const res = (await api(
        "GET",
        `/medical-records?patient=${encodeURIComponent(pid)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const r of list) {
        try { await api("DELETE", `/medical-records/${r.id}`); } catch { /* ignore */ }
      }
    } catch { /* ignore */ }
    // medical-encounters
    try {
      const res = (await api(
        "GET",
        `/medical-encounters?patient=${encodeURIComponent(pid)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const e of list) {
        try { await api("DELETE", `/medical-encounters/${e.id}`); } catch { /* ignore */ }
      }
    } catch { /* ignore */ }
    // patient row itself
    try { await api("DELETE", `/medical-patients/${pid}`); } catch { /* ignore */ }
  }

  // Step 3a-svc: Delete seed services (externalId starts with "SEED-SVC-").
  // Done before org delete so we don't leave dangling rows on a deleted facility.
  try {
    const res = (await api(
      "GET",
      `/services?externalId%5B%24regex%5D=%5ESEED-SVC-&%24limit=500`,
    )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
    const list = Array.isArray(res) ? res : res.data ?? [];
    for (const s of list) {
      try {
        await api("DELETE", `/services/${s.id}`);
      } catch {
        // ignore — best effort
      }
    }
  } catch {
    // ignore — $regex may be rejected in some env configs
  }

  // Step 3a-extras: Delete per-org auxiliary entities scoped by facility.
  // These live as separate tables but reference the seed org. Cleared BEFORE
  // org delete so we don't leave dangling rows once the parent is gone.
  // Org-level config arrays (payment methods, tax types, etc.) and
  // member-level fields (withholdingTax) ride on the org / member rows
  // themselves, so they're cleaned up automatically by the org delete.
  const seedOrgIdsForCleanup: string[] = [];
  for (const name of SEED_ORG_NAMES) {
    seedOrgIdsForCleanup.push(...(await listOrgIdsByName(name)));
  }
  for (const orgId of seedOrgIdsForCleanup) {
    // 3a-extras-1: inventory-suppliers (warehouse=orgId)
    try {
      const res = (await api(
        "GET",
        `/inventory-suppliers?warehouse=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const s of list) {
        try {
          await api("DELETE", `/inventory-suppliers/${s.id}`);
        } catch {
          // ignore — best effort
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-2: service-providers (facility=orgId)
    try {
      const res = (await api(
        "GET",
        `/service-providers?facility=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const sp of list) {
        try {
          await api("DELETE", `/service-providers/${sp.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-3: form-templates (facility=orgId — covers BOTH PME
    // ape-report and the 7 EMR template types in one sweep).
    try {
      const res = (await api(
        "GET",
        `/form-templates?facility=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const t of list) {
        try {
          await api("DELETE", `/form-templates/${t.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-4: insurance-contracts (insured=orgId — covers HMOs,
    // companies, and government partners since they share one table).
    try {
      const res = (await api(
        "GET",
        `/insurance-contracts?insured=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const c of list) {
        try {
          await api("DELETE", `/insurance-contracts/${c.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-5: diagnostic-center orgs (type=diagnostic-center,
    // overlords contains seed orgId). These are full org rows, deleted
    // before the parent org so we don't orphan the overlords pointer.
    try {
      const res = (await api(
        "GET",
        `/organizations?type=diagnostic-center&overlords=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const dx of list) {
        try {
          await api("DELETE", `/organizations/${dx.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-6: queues (organization=orgId)
    try {
      const res = (await api(
        "GET",
        `/queues?organization=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const q of list) {
        try {
          await api("DELETE", `/queues/${q.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-7: medicine-configurations (favorites) — must delete BEFORE
    // medicines since they reference medicine.id.
    try {
      const res = (await api(
        "GET",
        `/medicine-configurations?organization=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const c of list) {
        try {
          await api("DELETE", `/medicine-configurations/${c.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-8: medicines (organization=orgId)
    try {
      const res = (await api(
        "GET",
        `/medicines?organization=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const m of list) {
        try {
          await api("DELETE", `/medicines/${m.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-9: dental statuses (fixtures with type=dental-status)
    try {
      const res = (await api(
        "GET",
        `/fixtures?type=dental-status&organization=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const f of list) {
        try {
          await api("DELETE", `/fixtures/${f.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-10: diagnostic-packages (LIS + RIS) — must delete BEFORE
    // tests since they reference test ids.
    try {
      const res = (await api(
        "GET",
        `/diagnostic-packages?facility=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const p of list) {
        try {
          await api("DELETE", `/diagnostic-packages/${p.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-10b: diagnostic-measures — must run BEFORE diagnostic-tests
    // since measures reference tests via measure.test. Sweep all by
    // facility (LIS-only seeded but cleanup is broader for safety).
    try {
      const res = (await api(
        "GET",
        `/diagnostic-measures?facility=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const m of list) {
        try {
          await api("DELETE", `/diagnostic-measures/${m.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-11: diagnostic-tests (LIS + RIS, both types under one
    // facility filter)
    try {
      const res = (await api(
        "GET",
        `/diagnostic-tests?facility=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const t of list) {
        try {
          await api("DELETE", `/diagnostic-tests/${t.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-12: diagnostic-sections (fixtures with type=diagnostic-section)
    try {
      const res = (await api(
        "GET",
        `/fixtures?type=diagnostic-section&organization=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const s of list) {
        try {
          await api("DELETE", `/fixtures/${s.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-13: diagnostic-analyzers (LIS only)
    try {
      const res = (await api(
        "GET",
        `/diagnostic-analyzers?facility=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const a of list) {
        try {
          await api("DELETE", `/diagnostic-analyzers/${a.id}`);
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-14: inventory-variants (products) and their stock rows.
    // Variants are PATCH-archived rather than hard-deleted by the upstream
    // SDK, but the seed-org delete in step 3b would orphan them — so we
    // archive everything in this warehouse here. The inventory-stocks
    // rows are cleaned up by hapihub via the variant after-archive hook.
    try {
      const res = (await api(
        "GET",
        `/inventory-variants?warehouse=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ sku?: string; id?: string }> } | Array<{ sku?: string; id?: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const v of list) {
        const id = v.sku ?? v.id;
        if (!id) continue;
        try {
          // PATCH archive (soft-delete pattern used by the UI).
          await api("PATCH", `/inventory-variants/${id}`, { archive: true });
        } catch {
          try { await api("DELETE", `/inventory-variants/${id}`); } catch { /* ignore */ }
        }
      }
    } catch {
      // ignore
    }
    // 3a-extras-15: inventory-stocks — best-effort sweep in case the
    // variant-archive hook didn't clean them up (e.g., older hapihub).
    try {
      const res = (await api(
        "GET",
        `/inventory-stocks?warehouse=${encodeURIComponent(orgId)}&%24limit=500`,
      )) as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const s of list) {
        try { await api("DELETE", `/inventory-stocks/${s.id}`); } catch { /* ignore */ }
      }
    } catch {
      // ignore
    }
    // LIS/RIS report templates ride on the existing form-templates sweep
    // above (3a-extras-3) — that delete is unfiltered by type, so it
    // catches lab-result + imaging-result + ape-report + EMR variants in
    // one pass.
    // Patient tags + kiosk privacy notices ride on the org row itself
    // (org.tags, org.mf_kioskMessages) so they die with the org delete.
  }

  // Step 3b: Delete seed orgs (child first to avoid orphan _ch refs on the parent).
  for (const name of SEED_ORG_NAMES) {
    const ids = await listOrgIdsByName(name);
    for (const id of ids) {
      try {
        await api("DELETE", `/organizations/${id}`);
      } catch {
        // ignore — best effort (e.g., if hapihub blocks delete on a parent
        // that still has children it didn't return in our list).
      }
    }
  }

  // Step 4: Delete user accounts. Superadmin LAST so the session stays valid.
  const orderedUsers = [
    ...USERS.filter((u) => !u.superadmin),
    ...USERS.filter((u) => u.superadmin),
  ];
  for (const user of orderedUsers) {
    const uid = userIds[user.email];
    if (!uid) continue;
    try {
      await api("DELETE", `/accounts/${uid}`);
    } catch {
      // ignore — user might already be gone
    }
  }

  // Step 5: System-level fixtures we tagged with `seed` (countries, PH
  // address components, ICD-10, professions, specialties). Filter by tag
  // so any operator-created fixtures are preserved. Done last so other
  // entities that referenced them are already gone.
  const SYSTEM_FIXTURE_TYPES = [
    "address-country",
    "address-region",
    "address-province",
    "address-municipality",
    "address-barangay",
    "icd10",
    "profession",
    "specialty",
  ];
  for (const fixtureType of SYSTEM_FIXTURE_TYPES) {
    try {
      const res = (await api(
        "GET",
        `/fixtures?type=${encodeURIComponent(fixtureType)}&%24limit=500`,
      )) as { data?: Array<{ id: string; tags?: string[] }> } | Array<{ id: string; tags?: string[] }>;
      const list = Array.isArray(res) ? res : res.data ?? [];
      for (const f of list) {
        if (!f.tags?.includes("seed")) continue;
        try {
          await api("DELETE", `/fixtures/${f.id}`);
        } catch {
          // ignore — best effort
        }
      }
    } catch {
      // ignore
    }
  }

  // Clear session — main flow will re-auth fresh.
  sessionCookie = "";
  spinner.succeed("Reset complete — proceeding with fresh seed");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  console.log(`\n${chalk.bold("MyCure Seed Script")}`);
  console.log(`${chalk.gray("API:")} ${API_URL}\n`);

  // Optional pre-step: --reset wipes existing seed data so we re-create
  // everything fresh. Useful when role privileges or other body fields
  // changed and you want existing memberships to pick up the new shape.
  if (args.reset) {
    await resetSeedData();
  }

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

  // Step 3: Find-or-create the parent organization, then the child branch.
  // Hapihub constraint (organizations.ts:262): "Can only make child branches
  // of type 'facility'", so both orgs must be facility-typed.
  //
  // Lookup-first to prevent duplicate orgs on rerun. The organizations
  // schema has no unique constraint on `name`, and we can't trust
  // POST /organizations to reject duplicates, so we always look up by
  // name first and only create when nothing matches.
  async function findOrCreateOrg(
    name: string,
    type: string,
    parent?: string,
    types?: string[],
  ): Promise<string> {
    const existing = await listOrgIdsByName(name);
    if (existing.length > 0) {
      return existing[0];
    }
    try {
      const org = await createOrganization(name, type, parent, types);
      return org.id ?? "";
    } catch (err: unknown) {
      const msg = (err as Error).message;
      console.error(chalk.red(`   Could not create '${name}': ${msg}`));
      process.exit(1);
    }
  }

  // Process orgs in declaration order — the parent (no parentName) must
  // come first so each child can resolve its parent id by lookup.
  const orgIds: Record<string, string> = {};
  const orgsToSeed: Array<{ id: string; label: string; profile: OrgProfile }> = [];

  for (const profile of ORG_PROFILES) {
    const isParent = !profile.parentName;
    const spinner = ora(
      `Creating ${isParent ? "parent" : "branch"} organization '${profile.name}'...`,
    ).start();
    const parentId = profile.parentName ? orgIds[profile.parentName] : undefined;
    if (profile.parentName && !parentId) {
      spinner.fail(`Parent '${profile.parentName}' not found before child '${profile.name}'`);
      process.exit(1);
    }
    const id = await findOrCreateOrg(profile.name, "facility", parentId, profile.types);
    orgIds[profile.name] = id;
    orgsToSeed.push({
      id,
      label: isParent ? `${profile.name} (parent)` : `${profile.name} (child)`,
      profile,
    });
    spinner.succeed(
      isParent
        ? `${profile.name} (${id})`
        : `${profile.name} (${id}) — parent=${parentId}`,
    );
  }

  // Patch each org with its verbose profile (email/phone/website/address/etc.)
  await seedClinicProfiles(orgsToSeed);

  // Step 4: Create organization members for ALL orgs.
  // Each user gets the same role/privileges in every org, satisfying the
  // organization_members_uid_organization_uniq index (one row per
  // (uid, organization) pair — enforces no duplicates on rerun).
  const memberSpinner = ora(`Creating organization members in ${orgsToSeed.length} orgs...`).start();
  for (const user of USERS) {
    const uid = userIds[user.email];
    if (!uid) {
      memberSpinner.warn(`${user.email}: no user ID, skipping`);
      continue;
    }
    for (const org of orgsToSeed) {
      memberSpinner.text = `Adding ${user.email} → ${org.label}…`;
      // createMember now PATCHes existing memberships (e.g., the
      // hapihub-auto-created superadmin row) instead of throwing on
      // 409 — let surface real errors here.
      try {
        await createMember(uid, org.id, user);
      } catch (err: unknown) {
        const msg = (err as Error).message;
        memberSpinner.fail(`${user.email} → ${org.label}: ${msg}`);
        process.exit(1);
      }
    }
  }
  memberSpinner.succeed(
    `All members assigned to all orgs (${USERS.length}×${orgsToSeed.length} = ${USERS.length * orgsToSeed.length} memberships)`,
  );

  // Layer verbose personal-details onto each user (mobile, dob, address,
  // doctor PRC license, specialties, etc.). One PATCH per user.
  await seedUserProfiles(userIds);

  // Step 4b: System-level fixtures (countries, PH address regions /
  // provinces, ICD-10, professions, specialties). No org dependency, but
  // referenced by user profiles (specialties/professions) and PE service
  // suggested-Dx pickers (icd10), so seed before those steps. Idempotent
  // and shared installation-wide — seeded once, all orgs use them.
  await seedSystemFixtures();

  // Step 5: Patch org-level config arrays (payment methods, tax types,
  // adjustment reasons, stock rooms, product types). One PATCH per org;
  // merges with existing values so reruns don't clobber manual edits.
  await seedOrgConfig(orgsToSeed);

  // Steps 6-10: Service dependencies — must run BEFORE services so the
  // service POST body can reference (a) consent-form ids from EMR form
  // templates, (b) queue ids, and (c) lab/imaging diagnostic-package ids
  // for PE service queueing. The lookup is done inside seedServices().

  // Step 6: PME form templates (independent — services don't reference these
  // but they're cheap to seed alongside EMR).
  await seedPmeFormTemplates(orgsToSeed);

  // Step 7: EMR form templates — provides the consent-form rows that
  // services attach via consentForms[]. ~30 presets across med-cert,
  // fit-cert, consent-form, waiver, questionnaire, general, claims.
  await seedEmrFormTemplates(orgsToSeed);

  // Step 8: Queues — hapihub auto-creates 8 defaults per facility from
  // `types: ['clinic']` (Cashier, End Of Encounter, Front Desk, Nurse,
  // Doctor, Laboratory, Imaging X-ray, Imaging Ultrasound). We layer:
  //   (a) Procedure Room queue — auto-defaults skip type=procedure
  //   (b) Per-doctor consult queues with writers=["member::<id>"] for
  //       the UI's doctor↔queue auto-select linkage.
  await seedExtraQueues(orgsToSeed, userIds);

  // Step 9: LIS (laboratory) — sections → tests → packages, then analyzers
  // and report templates. Section ids must exist before tests can reference
  // them; test ids must exist before packages can group them. PE services
  // pick a lab package by name in their queueing[] config.
  await seedDiagnosticSections(orgsToSeed, "laboratory", SEED_LIS_SECTIONS);
  const lisTestIds = await seedDiagnosticTests(orgsToSeed, "laboratory", SEED_LIS_TESTS);
  // Measures depend on test ids (measure.test = test.id). Run after
  // tests, before packages — measures don't affect packages, but the
  // ordering keeps the test+its-measures conceptually grouped.
  await seedDiagnosticMeasures(orgsToSeed, lisTestIds, SEED_LIS_MEASURES);
  await seedDiagnosticPackages(orgsToSeed, "laboratory", SEED_LIS_PACKAGES, lisTestIds);
  await seedAnalyzers(orgsToSeed, SEED_LIS_ANALYZERS);
  await seedDiagnosticFormTemplates(orgsToSeed, "laboratory");

  // Step 10: RIS (radiology) — same flow, no analyzers (no UI route exists).
  // PE services pick a radiology package by name in their queueing[] config.
  await seedDiagnosticSections(orgsToSeed, "radiology", SEED_RIS_SECTIONS);
  const risTestIds = await seedDiagnosticTests(orgsToSeed, "radiology", SEED_RIS_TESTS);
  await seedDiagnosticPackages(orgsToSeed, "radiology", SEED_RIS_PACKAGES, risTestIds);
  await seedDiagnosticFormTemplates(orgsToSeed, "radiology");

  // Step 11: Services — at this point all references (consent forms, queues,
  // lab/imaging packages) exist. seedServices() resolves them per-facility
  // before each POST and attaches consentForms[] + queueing[] (PE only).
  await seedServices(orgsToSeed);

  // Step 12: Service providers — link clinicians to services with a
  // reader's-fee commission. Depends on members + services existing.
  await seedServiceProviders(orgsToSeed, userIds);

  // Step 13: Withholding tax — patch doctor + nurse memberships in each org.
  // Depends on memberships existing.
  await seedWithholdingTaxes(orgsToSeed, userIds);

  // Step 14: Inventory suppliers — independent, just needs the org.
  await seedSuppliers(orgsToSeed);

  // Step 14b: Inventory products — references org.wh_productTypes and
  // org.configInventory.stockRooms (both seeded in step 5). One POST per
  // product to /inventory-variants; the server auto-creates the
  // inventory-stocks row from the inline `initialStock` + `stockRoom`.
  await seedProducts(orgsToSeed);

  // Step 15: Partners — HMOs, companies, government (insurance-contracts).
  await seedPartners(orgsToSeed);

  // Step 16: Diagnostic-center partners (organizations with overlords ref).
  await seedDiagnosticCenters(orgsToSeed);

  // Step 17: Patient classification tags + kiosk privacy notices (org PATCH).
  await seedPatientTagsAndPrivacy(orgsToSeed);

  // Step 18: Medicines + favorite-medicine prescription templates.
  await seedMedicines(orgsToSeed);

  // Step 19: Dental statuses (curated subset of the SDK enum).
  await seedDentalStatuses(orgsToSeed);

  // Step 20 (optional): Seed random patients for each facility.
  await seedPatients(orgsToSeed, PATIENT_COUNT);

  // Step 21: Fixed demo patient (Pedro Demo Lopez) with 2 encounters and
  // 9 medical records. Always-on; gives demo users a known, click-throughable
  // chart to inspect. Idempotent on externalId.
  await seedFixedPatient(orgsToSeed, userIds);

  // Step 22: Patient accounts — Better-Auth accounts for the fixed
  // patient + the first N random patients, linked back via
  // medical-patients.account. Default N=5; --patient-accounts 0 to skip.
  const patientAccounts = await seedPatientAccounts(orgsToSeed, PATIENT_ACCOUNT_COUNT);

  // Per-type service breakdown for the summary
  const svcByType = SERVICE_TEMPLATES.reduce<Record<string, number>>((acc, t) => {
    acc[t.type] = (acc[t.type] ?? 0) + 1;
    return acc;
  }, {});
  const svcBreakdown = Object.entries(svcByType)
    .map(([t, n]) => `${t}=${n}`)
    .join(", ");

  // Summary
  console.log(`\n${"=".repeat(64)}`);
  console.log(chalk.bold("SEED COMPLETE"));
  console.log(`${"=".repeat(64)}`);
  console.log(`\n${chalk.gray("Organizations:")}`);
  for (const o of orgsToSeed) {
    console.log(`  ${chalk.cyan(o.profile.name.padEnd(28))} ${o.id}  ${chalk.gray(o.profile.address.city)}`);
  }
  const partnerHmos = SEED_PARTNERS.filter((p) => p.kind === "hmo").length;
  const partnerCos  = SEED_PARTNERS.filter((p) => p.kind === "company").length;
  const partnerGov  = SEED_PARTNERS.filter((p) => p.kind === "government").length;
  const favCount    = SEED_MEDICINES.filter((m) => !!m.favorite).length;
  const phRegionCount = SEED_ADDRESS_COMPONENTS.filter((c) => c.type === "address-region").length;
  const phProvinceCount = SEED_ADDRESS_COMPONENTS.filter((c) => c.type === "address-province").length;
  console.log(
    `${chalk.gray("Fixtures:")}    ${SEED_COUNTRIES.length} countries, ${phRegionCount} PH regions, ${phProvinceCount} PH provinces, ${SEED_ICD10_CODES.length} ICD-10, ${SEED_PROFESSIONS.length} professions, ${SEED_SPECIALTIES.length} specialties (system-wide)`,
  );
  console.log(`\n${chalk.gray("Services:")}    ${SERVICE_TEMPLATES.length} per facility (${svcBreakdown})`);
  console.log(`${chalk.gray("Suppliers:")}   ${SEED_SUPPLIERS.length} per facility`);
  const prodByType = SEED_PRODUCTS.reduce<Record<string, number>>((acc, p) => {
    acc[p.productType] = (acc[p.productType] ?? 0) + 1;
    return acc;
  }, {});
  const prodBreakdown = Object.entries(prodByType).map(([t, n]) => `${t}=${n}`).join(", ");
  console.log(`${chalk.gray("Products:")}    ${SEED_PRODUCTS.length} on parent warehouse, shared with branches (${prodBreakdown})`);
  console.log(`${chalk.gray("Providers:")}   ${SEED_PROVIDER_ASSIGNMENTS.length} service-provider assignments per facility`);
  console.log(`${chalk.gray("WithTax:")}     ${SEED_WITHHOLDING_TAXES.length} member rows per facility`);
  console.log(
    `${chalk.gray("Org config:")}  ${SEED_PAYMENT_METHODS.length} payment methods, ${SEED_TAX_TYPES.length} tax types, ${SEED_PRODUCT_TYPES.length} product types, ${SEED_STOCK_ROOMS.length} stock rooms, ${SEED_ADJUSTMENT_REASONS.length} adjustment reasons`,
  );
  console.log(
    `${chalk.gray("Partners:")}    ${partnerHmos} HMOs, ${partnerCos} companies, ${partnerGov} gov, ${SEED_DX_CENTERS.length} dx-centers per facility`,
  );
  console.log(
    `${chalk.gray("Registration:")} 8 auto-default queues (hapihub) + 1 procedure + ${SEED_DOCTOR_QUEUES.length} per-doctor queues (with writers), ${SEED_PATIENT_TAGS.length} patient tags, ${SEED_PRIVACY_NOTICES.length} privacy notices per facility`,
  );
  console.log(
    `${chalk.gray("EMR:")}         ${SEED_MEDICINES.length} medicines, ${favCount} favorite Rx, ${SEED_DENTAL_STATUSES.length} dental statuses per facility`,
  );
  console.log(
    `${chalk.gray("LIS:")}         ${SEED_LIS_SECTIONS.length} sections, ${SEED_LIS_TESTS.length} tests, ${SEED_LIS_MEASURES.reduce((s, t) => s + t.measures.length, 0)} measures, ${SEED_LIS_PACKAGES.length} packages, ${SEED_LIS_ANALYZERS.length} analyzers per facility`,
  );
  console.log(
    `${chalk.gray("RIS:")}         ${SEED_RIS_SECTIONS.length} sections, ${SEED_RIS_TESTS.length} tests, ${SEED_RIS_PACKAGES.length} packages per facility`,
  );
  if (PATIENT_COUNT > 0) {
    console.log(
      `${chalk.gray("Patients:")}    ${PATIENT_COUNT} on parent facility, shared with branches via hierarchy — verbose PH demographics, vitals, PhilHealth/HMO insurance cards (externalId SEED-PATIENT-1-NNN)`,
    );
  }
  console.log(
    `${chalk.gray("Demo chart:")}  Pedro Demo Lopez (${FIXED_PATIENT_EXTERNAL_ID}) — 2 encounters, 9 medical records (T2DM + HTN storyline)`,
  );
  console.log(`\n${chalk.gray("Accounts")} (password: ${chalk.yellow(PASSWORD)}):`);
  console.log("-".repeat(64));
  console.log(
    `${"Email".padEnd(32)} ${"Role".padEnd(18)} ${"Privileges"}`,
  );
  console.log("-".repeat(64));
  for (const user of USERS) {
    const primaryRole = user.superadmin ? "superadmin" : user.roleIds[0] ?? "—";
    const roleSummary =
      user.roleIds.length > 1 ? `${primaryRole} +${user.roleIds.length - 1}` : primaryRole;
    // Privilege count = union across all mapped roles (matches the
    // privilege-flag construction in createMember).
    const privSet = new Set<string>();
    if (user.superadmin) {
      privSet.add("superadmin");
      privSet.add("admin");
    }
    for (const r of user.roleIds) {
      for (const p of ROLE_PRIVILEGES[r] ?? []) privSet.add(p);
    }
    const privCount = user.superadmin && privSet.size === 0 ? "ALL" : String(privSet.size);
    console.log(
      `${user.email.padEnd(32)} ${roleSummary.padEnd(18)} ${privCount}`,
    );
  }
  console.log("-".repeat(64));

  // Patient accounts breakdown — separate table since they're a distinct
  // identity tier (PXP self-service tag, not staff).
  if (patientAccounts.length > 0) {
    console.log(`\n${chalk.gray("Patient Accounts")} (password: ${chalk.yellow(PASSWORD)}, tags: pxp/seed/patient):`);
    console.log("-".repeat(72));
    console.log(
      `${"Email".padEnd(48)} ${"Patient externalId".padEnd(22)} ${"Status"}`,
    );
    console.log("-".repeat(72));
    for (const acct of patientAccounts) {
      const tag = acct.isFixed ? chalk.cyan(acct.externalId) : acct.externalId;
      const statusLabel =
        acct.status === "new"
          ? chalk.green("new")
          : acct.status === "existing"
            ? chalk.gray("existing")
            : chalk.red("skipped");
      const emailDisplay = acct.email || chalk.gray("(no email)");
      console.log(
        `${emailDisplay.padEnd(48)} ${tag.padEnd(22)} ${statusLabel}`,
      );
    }
    console.log("-".repeat(72));
  }

  console.log(`\n${chalk.gray("Login at:")} ${CMS_URL}`);
}

main().catch((err) => {
  console.error(chalk.red("\nFatal error:"), err);
  process.exit(1);
});
