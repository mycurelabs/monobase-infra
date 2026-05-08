/**
 * Ready-made starter templates for the PME (Pre-Employment Medical
 * Examination) Report Template editor.
 *
 * PME reports use the same template engine as EMR certificates, but the
 * template `type` is always `ape-report` (the backend slot). These presets
 * cover the generic clinic use-cases — industry-specific variants can be
 * saved from any of these as a starting point.
 *
 * LAYOUT PHILOSOPHY:
 * - Table-driven, compact, information-rich — modeled after real industry
 *   PME report layouts (PEME forms, executive check-up summaries, OSH
 *   annual physicals). Inline CSS is used so the rendered HTML is
 *   self-contained for both screen preview and print.
 * - Section bars (dark, uppercase, tight) anchor each block; key/value
 *   tables and grid tables (System | Status | Findings) sit underneath.
 * - Default font-size is 12px to match a clinical letterhead, with 4–6px
 *   cell padding so a full report fits cleanly on A4 / Letter.
 *
 * CONVENTIONS (mirror those in `formTemplatePresets.ts`):
 * - Body only. Clinic header, patient header, template title, and signatory
 *   blocks are added automatically by the print/preview wrapper based on the
 *   `hide*` config flags. Don't duplicate them.
 * - Every bare token MUST exist in DEFAULT_FORM_TEMPLATE_TAGS
 *   (packages/ui/src/components/data/form/constants.ts). No invented tokens.
 * - For dropdowns, use `{custom_choices_<name>}` AND add a matching
 *   `{ question: '<name>', type: 'multiplechoice', choices: [...] }` entry
 *   to the preset's `items` array. The preset picker seeds these into the
 *   `customFieldItems` ref on apply so they persist with the template.
 * - For free-text, use `{custom_text_<name>}` — the label is auto-derived
 *   from the underscored name.
 */

export interface PmeReportPresetItem {
  /** Matches the `<name>` in `{custom_choices_<name>}` — no prefix. */
  question: string;
  /** Only `multiplechoice` renders as a dropdown today. */
  type: 'multiplechoice';
  /** Visible options in the dropdown. */
  choices: string[];
}

export interface PmeReportPreset {
  id: string;
  name: string;
  description: string;
  template: string;
  /** Dropdown-item definitions for `{custom_choices_*}` tokens. */
  items?: PmeReportPresetItem[];
}

/* ---------- Style tokens (kept as constants so every section is consistent) ---------- */

const S = {
  // Section title bar — dark, tight, uppercase. Anchors each major block.
  bar:
    'margin: 14px 0 4px; padding: 4px 8px; background: #0f172a; color: #fff;' +
    ' font-weight: 600; font-size: 10px; letter-spacing: 0.06em;' +
    ' text-transform: uppercase;',
  // Standard data table — full-width, collapsed borders, 12px body type.
  table:
    'width: 100%; border-collapse: collapse; font-size: 12px;' +
    ' margin: 0 0 6px;',
  // Header cell — light slate fill, semibold, left aligned, slate borders.
  th:
    'border: 1px solid #cbd5e1; background: #f1f5f9; padding: 4px 8px;' +
    ' text-align: left; font-weight: 600; font-size: 11px;',
  // Body cell — same border, comfortable padding, top-aligned for wraps.
  td:
    'border: 1px solid #cbd5e1; padding: 4px 8px; vertical-align: top;',
  // Label cell within a key/value pair — narrower, semibold, slate fill.
  tdLabel:
    'border: 1px solid #cbd5e1; padding: 4px 8px; vertical-align: top;' +
    ' background: #f8fafc; font-weight: 600; width: 22%;',
  // Emphasis box — used for fitness classification / final verdict.
  banner:
    'margin: 10px 0 4px; padding: 8px 10px; border: 1px solid #0f172a;' +
    ' background: #f8fafc; font-size: 12px;',
  // Sub-label inside a banner.
  bannerLabel:
    'font-size: 10px; letter-spacing: 0.06em; text-transform: uppercase;' +
    ' color: #475569; font-weight: 600; margin-bottom: 2px;',
};

/* ---------- Shared fragments ---------- */

const sectionBar = (label: string) =>
  `<p style="${S.bar}">${label}</p>`;

// Verdict banner — single-cell table (not a <div>) so TipTap preserves it
// through `setContent`. Inner content uses <p> (a real TipTap node) so the
// style attribute survives the editor's schema round-trip.
const banner = (label: string, body: string) => `
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.banner}">
        <p style="${S.bannerLabel}">${label}</p>
        <p style="margin: 0;">${body}</p>
      </td>
    </tr>
  </tbody>
</table>`.trim();

/** Compact two-column key/value grid (label | value | label | value). */
const kvGrid = (
  rows: Array<Array<{ label: string; value: string }>>,
) => `
<table style="${S.table}">
  <tbody>
    ${rows
      .map(
        cols => `
    <tr>
      ${cols
        .map(
          c => `
      <td style="${S.tdLabel}">${c.label}</td>
      <td style="${S.td}">${c.value}</td>`,
        )
        .join('')}
    </tr>`,
      )
      .join('')}
  </tbody>
</table>`.trim();

const vitalsBlock = `
${sectionBar('Vital Signs & Anthropometrics')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}">BP</th>
      <th style="${S.th}">PR</th>
      <th style="${S.th}">RR</th>
      <th style="${S.th}">Temp</th>
      <th style="${S.th}">Height</th>
      <th style="${S.th}">Weight</th>
      <th style="${S.th}">BMI</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="${S.td}">{vital_blood_pressure}</td>
      <td style="${S.td}">{vital_pulse_rate} bpm</td>
      <td style="${S.td}">{vital_resp_rate} cpm</td>
      <td style="${S.td}">{vital_temperature} °C</td>
      <td style="${S.td}">{vital_height}</td>
      <td style="${S.td}">{vital_weight}</td>
      <td style="${S.td}">{vital_bmi}</td>
    </tr>
  </tbody>
</table>`.trim();

const visionBlock = `
${sectionBar('Vision Screening')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}">VA — Right (OD)</th>
      <th style="${S.th}">VA — Left (OS)</th>
      <th style="${S.th}">Color Vision</th>
      <th style="${S.th}">Remarks</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="${S.td}">{vital_visual_acuity_right}</td>
      <td style="${S.td}">{vital_visual_acuity_left}</td>
      <td style="${S.td}">{vital_color_vision}</td>
      <td style="${S.td}">{vital_visual_remarks}</td>
    </tr>
  </tbody>
</table>`.trim();

/** Generic 3-column "system | status | findings" body. Used for both
 *  Review of Systems and Physical Examination, since clinically they
 *  follow the same shape. */
const systemRows = (
  rows: Array<{ system: string; statusToken: string; textToken: string }>,
) =>
  rows
    .map(
      r => `
    <tr>
      <td style="${S.tdLabel}">${r.system}</td>
      <td style="${S.td}; width: 18%;">${r.statusToken}</td>
      <td style="${S.td}">${r.textToken}</td>
    </tr>`,
    )
    .join('');

const systemsReviewBlock = `
${sectionBar('Review of Systems')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}">System</th>
      <th style="${S.th}">Status</th>
      <th style="${S.th}">Findings / Notes</th>
    </tr>
  </thead>
  <tbody>
    ${systemRows([
      { system: 'General', statusToken: '{ros_status_general}', textToken: '{ros_general}' },
      { system: 'Eyes', statusToken: '{ros_status_eyes}', textToken: '{ros_eyes}' },
      { system: 'HEENT', statusToken: '{ros_status_ent}', textToken: '{ros_ent}' },
      { system: 'Respiratory / Lungs', statusToken: '{ros_status_respiratory}', textToken: '{ros_respiratory}' },
      { system: 'Cardiovascular', statusToken: '{ros_status_cardiovascular}', textToken: '{ros_cardiovascular}' },
      { system: 'Gastrointestinal', statusToken: '{ros_status_gastrointestinal}', textToken: '{ros_gastrointestinal}' },
      { system: 'Genitourinary', statusToken: '{ros_status_genitourinary}', textToken: '{ros_genitourinary}' },
      { system: 'Musculoskeletal', statusToken: '{ros_status_musculoskeletal}', textToken: '{ros_musculoskeletal}' },
      { system: 'Neurologic', statusToken: '{ros_status_neurologic}', textToken: '{ros_neurologic}' },
      { system: 'Skin', statusToken: '{ros_status_skin}', textToken: '{ros_skin}' },
    ])}
  </tbody>
</table>`.trim();

const physicalExamBlock = `
${sectionBar('Physical Examination')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}">Region</th>
      <th style="${S.th}">Status</th>
      <th style="${S.th}">Findings / Notes</th>
    </tr>
  </thead>
  <tbody>
    ${systemRows([
      { system: 'General', statusToken: '{pe_general_status}', textToken: '{pe_general_text}' },
      { system: 'Head', statusToken: '{pe_head_status}', textToken: '{pe_head_text}' },
      { system: 'Eyes', statusToken: '{pe_eyes_status}', textToken: '{pe_eyes_text}' },
      { system: 'Ears', statusToken: '{pe_ears_status}', textToken: '{pe_ears_text}' },
      { system: 'Nose', statusToken: '{pe_nose_status}', textToken: '{pe_nose_text}' },
      { system: 'Throat', statusToken: '{pe_throat_status}', textToken: '{pe_throat_text}' },
      { system: 'Neck', statusToken: '{pe_neck_status}', textToken: '{pe_neck_text}' },
      { system: 'Chest', statusToken: '{pe_chest_status}', textToken: '{pe_chest_text}' },
      { system: 'Respiratory', statusToken: '{pe_respiratory_status}', textToken: '{pe_respiratory_text}' },
      { system: 'Cardiovascular', statusToken: '{pe_cardiovascular_status}', textToken: '{pe_cardiovascular_text}' },
      { system: 'Abdomen', statusToken: '{pe_abdomen_status}', textToken: '{pe_abdomen_text}' },
      { system: 'Musculoskeletal', statusToken: '{pe_musculoskeletal_status}', textToken: '{pe_musculoskeletal_text}' },
      { system: 'Skin', statusToken: '{pe_skin_status}', textToken: '{pe_skin_text}' },
      { system: 'Extremities', statusToken: '{pe_extermities_status}', textToken: '{pe_extermities_text}' },
      { system: 'Neurologic', statusToken: '{pe_neurologic_status}', textToken: '{pe_neurologic_text}' },
    ])}
    <tr>
      <td style="${S.tdLabel}">Narrative Summary</td>
      <td colspan="2" style="${S.td}">{patient_physical_exam}</td>
    </tr>
  </tbody>
</table>`.trim();

const historyBlock = `
${sectionBar('Relevant History')}
${kvGrid([
  [
    { label: 'Past Medical Hx', value: '{patient_pmhx}' },
    { label: 'Family Hx', value: '{patient_fhx}' },
  ],
  [
    { label: 'Social Hx', value: '{patient_shx}' },
    { label: 'Allergies', value: '{patient_allergies_hx}' },
  ],
  [
    { label: 'Surgical Hx', value: '{patient_surgical_hx}' },
    { label: 'Hospitalizations', value: '{patient_hospitalization_hx}' },
  ],
])}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Current Medications</td>
      <td style="${S.td}">{patient_medication_order}</td>
    </tr>
  </tbody>
</table>`.trim();

const diagnosticsBlock = `
${sectionBar('Ancillary / Diagnostic Tests')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}; width: 22%;">Modality</th>
      <th style="${S.th}">Findings / Order</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Laboratory</td>
      <td style="${S.td}">{patient_lab_order}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Imaging (e.g. Chest X-Ray)</td>
      <td style="${S.td}">{patient_imaging_order}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Other Procedures</td>
      <td style="${S.td}">{patient_medical_procedure_orders}</td>
    </tr>
  </tbody>
</table>`.trim();

const assessmentBlock = `
${sectionBar('Assessment')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Clinical Impression</td>
      <td style="${S.td}">{patient_impression}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Significant Findings / Diagnosis</td>
      <td style="${S.td}">{patient_diagnosis}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">ICD-10 Code</td>
      <td style="${S.td}">{diagnosis_icd10}</td>
    </tr>
  </tbody>
</table>`.trim();

const reportMetaBlock = `
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Date of Examination</td>
      <td style="${S.td}">{patient_encounter_created_at}</td>
      <td style="${S.tdLabel}">Report Date</td>
      <td style="${S.td}">{today}</td>
    </tr>
  </tbody>
</table>`.trim();

/* ---------- Presets ---------- */

const pmeStandardPreEmployment = `
${reportMetaBlock}

${sectionBar('Applicant Information')}
${kvGrid([
  [
    { label: 'Name', value: '<strong>{patient_name}</strong>' },
    { label: 'Date of Birth', value: '{patient_dob}' },
  ],
  [
    { label: 'Age / Sex', value: '{patient_age} · {patient_sex}' },
    { label: 'Civil Status', value: '{patient_marital_status}' },
  ],
  [
    { label: 'Address', value: '{patient_full_address}' },
    { label: 'Contact', value: '{patient_mobile_no} · {patient_email}' },
  ],
])}

${sectionBar('Position Applied For')}
${kvGrid([
  [
    { label: 'Position', value: '{custom_text_position_applied_for}' },
    { label: 'Company / Employer', value: '{custom_text_company_or_employer}' },
  ],
  [
    { label: 'Nature of Work', value: '{custom_choices_nature_of_work}' },
    { label: 'Examined On', value: '{patient_encounter_created_at}' },
  ],
])}

${historyBlock}

${vitalsBlock}

${visionBlock}

${physicalExamBlock}

${diagnosticsBlock}

${assessmentBlock}

${sectionBar('Recommendations')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_care_plan}</td>
    </tr>
  </tbody>
</table>

${banner(
  'Fitness Classification',
  'The applicant is classified as <strong>{custom_choices_fitness_classification}</strong>.',
)}
`.trim();

const pmeAnnualPhysicalExam = `
${reportMetaBlock}

${sectionBar('Employee Information')}
${kvGrid([
  [
    { label: 'Name', value: '<strong>{patient_name}</strong>' },
    { label: 'Date of Birth', value: '{patient_dob}' },
  ],
  [
    { label: 'Age / Sex', value: '{patient_age} · {patient_sex}' },
    { label: 'Civil Status', value: '{patient_marital_status}' },
  ],
  [
    { label: 'Address', value: '{patient_full_address}' },
    { label: 'Contact', value: '{patient_mobile_no} · {patient_email}' },
  ],
  [
    { label: 'Employer / Company', value: '{patient_companies}' },
    { label: 'Employee / Account No.', value: '{patient_company_accountno}' },
  ],
])}

${sectionBar('Interval Since Last APE')}
${kvGrid([
  [
    { label: 'Last Annual Exam', value: '{custom_text_date_of_last_ape}' },
    { label: 'New Concerns Since', value: '{custom_text_interval_concerns}' },
  ],
])}

${historyBlock}

${sectionBar('Immunization Status')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_vaccination_hx}</td>
    </tr>
  </tbody>
</table>

${vitalsBlock}

${visionBlock}

${systemsReviewBlock}

${physicalExamBlock}

${diagnosticsBlock}

${assessmentBlock}

${sectionBar('Health Maintenance & Preventive Recommendations')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_care_plan}</td>
    </tr>
  </tbody>
</table>

${banner(
  'Overall Health Status',
  'The employee is assessed to be in <strong>{custom_choices_overall_health_status}</strong> overall health.',
)}
`.trim();

const pmeExecutiveCheckup = `
${reportMetaBlock}

${sectionBar('Executive Information')}
${kvGrid([
  [
    { label: 'Name', value: '<strong>{patient_name}</strong>' },
    { label: 'Date of Birth', value: '{patient_dob}' },
  ],
  [
    { label: 'Age / Sex', value: '{patient_age} · {patient_sex}' },
    { label: 'Civil Status', value: '{patient_marital_status}' },
  ],
  [
    { label: 'Blood Type', value: '{patient_blood_type}' },
    { label: 'Contact', value: '{patient_mobile_no} · {patient_email}' },
  ],
  [
    { label: 'Address', value: '{patient_full_address}' },
    { label: 'Company', value: '{patient_companies}' },
  ],
  [
    { label: 'Position', value: '{custom_text_position_or_title}' },
    { label: 'Examined On', value: '{patient_encounter_created_at}' },
  ],
])}

${sectionBar('Chief Concern(s) for This Check-up')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Chief Complaint</td>
      <td style="${S.td}">{patient_complaint}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">History of Present Illness</td>
      <td style="${S.td}">{patient_hpi}</td>
    </tr>
  </tbody>
</table>

${historyBlock}

${sectionBar('Immunization & Preventive History')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_vaccination_hx}</td>
    </tr>
  </tbody>
</table>

${vitalsBlock}

${visionBlock}

${systemsReviewBlock}

${physicalExamBlock}

${sectionBar('Comprehensive Diagnostic Work-up')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}; width: 22%;">Modality</th>
      <th style="${S.th}">Findings / Order</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Laboratory Panel</td>
      <td style="${S.td}">{patient_lab_order}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Imaging Studies</td>
      <td style="${S.td}">{patient_imaging_order}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Cardiac / Other (ECG, 2D-Echo, Stress)</td>
      <td style="${S.td}">{patient_medical_procedure_orders}</td>
    </tr>
  </tbody>
</table>

${assessmentBlock}

${sectionBar('Care Plan & Lifestyle Recommendations')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_care_plan}</td>
    </tr>
  </tbody>
</table>

${banner(
  'Recommended Follow-up',
  '<strong>{custom_choices_follow_up_interval}</strong>',
)}
`.trim();

const pmeReturnToWork = `
${reportMetaBlock}

${sectionBar('Employee Information')}
${kvGrid([
  [
    { label: 'Name', value: '<strong>{patient_name}</strong>' },
    { label: 'Date of Birth', value: '{patient_dob}' },
  ],
  [
    { label: 'Age / Sex', value: '{patient_age} · {patient_sex}' },
    { label: 'Position', value: '{custom_text_position_or_title}' },
  ],
  [
    { label: 'Employer / Company', value: '{patient_companies}' },
    { label: 'Examined On', value: '{patient_encounter_created_at}' },
  ],
])}

${sectionBar('Reason for Absence')}
${kvGrid([
  [
    { label: 'Reason for Leave', value: '{custom_choices_reason_for_leave}' },
    { label: 'Start of Leave', value: '{custom_text_start_of_leave}' },
  ],
  [
    { label: 'Duration of Absence', value: '{custom_text_duration_of_absence}' },
    { label: 'Prior Diagnosis', value: '{patient_diagnosis}' },
  ],
])}

${sectionBar('Current Status')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Current Symptoms / Concerns</td>
      <td style="${S.td}">{patient_complaint}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">History of Present Condition</td>
      <td style="${S.td}">{patient_hpi}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Current Medications</td>
      <td style="${S.td}">{patient_medication_order}</td>
    </tr>
  </tbody>
</table>

${vitalsBlock}

${physicalExamBlock}

${diagnosticsBlock}

${sectionBar('Clinical Impression')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_impression}</td>
    </tr>
  </tbody>
</table>

${sectionBar('Restrictions or Accommodations')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_care_plan}</td>
    </tr>
  </tbody>
</table>

${kvGrid([
  [
    { label: 'Expected Return to Full Duty', value: '{custom_text_expected_return_to_full_duty}' },
    { label: 'Re-evaluation On', value: '{date}' },
  ],
])}

${banner(
  'Fit-to-Work Assessment',
  'Based on the above evaluation, the employee is deemed <strong>{custom_choices_work_fitness_status}</strong>.',
)}
`.trim();

const pmePreDeployment = `
${reportMetaBlock}

${sectionBar('Applicant Information')}
${kvGrid([
  [
    { label: 'Name', value: '<strong>{patient_name}</strong>' },
    { label: 'Date of Birth', value: '{patient_dob}' },
  ],
  [
    { label: 'Age / Sex', value: '{patient_age} · {patient_sex}' },
    { label: 'Civil Status', value: '{patient_marital_status}' },
  ],
  [
    { label: 'Blood Type', value: '{patient_blood_type}' },
    { label: 'Contact', value: '{patient_mobile_no} · {patient_email}' },
  ],
  [
    { label: 'Address', value: '{patient_full_address}' },
    { label: 'Examined On', value: '{patient_encounter_created_at}' },
  ],
])}

${sectionBar('Deployment Details')}
${kvGrid([
  [
    { label: 'Position Applied For', value: '{custom_text_position_applied_for}' },
    { label: 'Destination Country / Region', value: '{custom_text_destination_country}' },
  ],
  [
    { label: 'Nature of Work', value: '{custom_choices_nature_of_work}' },
    { label: 'Deployment Duration', value: '{custom_text_deployment_duration}' },
  ],
])}

${historyBlock}

${sectionBar('Immunization Status')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_vaccination_hx}</td>
    </tr>
  </tbody>
</table>

${vitalsBlock}

${visionBlock}

${systemsReviewBlock}

${physicalExamBlock}

${sectionBar('Destination-Required Screening')}
<table style="${S.table}">
  <thead>
    <tr>
      <th style="${S.th}; width: 22%;">Modality</th>
      <th style="${S.th}">Findings / Order</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="${S.tdLabel}">Laboratory</td>
      <td style="${S.td}">{patient_lab_order}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Imaging (e.g. Chest X-Ray)</td>
      <td style="${S.td}">{patient_imaging_order}</td>
    </tr>
    <tr>
      <td style="${S.tdLabel}">Other Procedures (ECG, Audiometry, Drug Test)</td>
      <td style="${S.td}">{patient_medical_procedure_orders}</td>
    </tr>
  </tbody>
</table>

${assessmentBlock}

${sectionBar('Recommendations Prior to Deployment')}
<table style="${S.table}">
  <tbody>
    <tr>
      <td style="${S.td}">{patient_care_plan}</td>
    </tr>
  </tbody>
</table>

${banner(
  'Fitness for Deployment',
  'The applicant is classified as <strong>{custom_choices_deployment_fitness}</strong> for the proposed deployment.',
)}
`.trim();

/* ---------- Registry ---------- */

const FITNESS_CLASSIFICATION_CHOICES = [
  'Class A — Fit for employment (no findings)',
  'Class B — Fit for employment (minor findings, no work restrictions)',
  'Class C — Fit for employment, pending further evaluation / interventions',
  'Class D — Temporarily Unfit — requires treatment before re-evaluation',
  'Class E — Unfit for employment',
];

const NATURE_OF_WORK_CHOICES = [
  'Office / Administrative (Sedentary)',
  'Light Manual / Retail',
  'Moderate Physical / Field Work',
  'Heavy Manual / Construction',
  'Food Handling',
  'Healthcare / Medical',
  'Transportation / Driving',
  'Security / Law Enforcement',
  'Education / Training',
  'Hazardous / Chemical Environment',
  'Offshore / Maritime',
  'Aviation / Flight Crew',
];

export const PME_REPORT_PRESETS: PmeReportPreset[] = [
  {
    id: 'pme-standard-peme',
    name: 'Standard Pre-Employment Medical Exam (PEME)',
    description:
      'General-purpose pre-employment evaluation: history, vitals, vision, physical exam by system, ancillary tests, assessment, and a fitness classification with signatories.',
    template: pmeStandardPreEmployment,
    items: [
      {
        question: 'nature_of_work',
        type: 'multiplechoice',
        choices: NATURE_OF_WORK_CHOICES,
      },
      {
        question: 'fitness_classification',
        type: 'multiplechoice',
        choices: FITNESS_CLASSIFICATION_CHOICES,
      },
    ],
  },
  {
    id: 'pme-annual-physical-exam',
    name: 'Annual Physical Exam (APE)',
    description:
      'Yearly wellness evaluation for existing employees. Includes review of systems, immunization status, lifestyle review, and an overall health status rating.',
    template: pmeAnnualPhysicalExam,
    items: [
      {
        question: 'overall_health_status',
        type: 'multiplechoice',
        choices: [
          'Excellent — no findings',
          'Good — minor findings, routine follow-up',
          'Fair — findings requiring management',
          'Needs follow-up / further evaluation',
        ],
      },
    ],
  },
  {
    id: 'pme-executive-checkup',
    name: 'Executive Check-up',
    description:
      'Comprehensive executive health screening — detailed history, full panel of labs/imaging/cardiac work-up, lifestyle plan, and a follow-up interval.',
    template: pmeExecutiveCheckup,
    items: [
      {
        question: 'follow_up_interval',
        type: 'multiplechoice',
        choices: [
          '3 months',
          '6 months',
          '12 months (annual)',
          'As clinically indicated',
        ],
      },
    ],
  },
  {
    id: 'pme-return-to-work',
    name: 'Return-to-Work Medical Evaluation',
    description:
      'Fit-for-duty evaluation for employees returning after prolonged medical leave. Captures reason, duration, current status, and any restrictions or accommodations.',
    template: pmeReturnToWork,
    items: [
      {
        question: 'reason_for_leave',
        type: 'multiplechoice',
        choices: [
          'Medical illness',
          'Surgical procedure',
          'Work-related injury',
          'Non-work-related injury',
          'Mental health / stress-related',
          'Maternity',
          'Paternity',
          'Other',
        ],
      },
      {
        question: 'work_fitness_status',
        type: 'multiplechoice',
        choices: [
          'Fit to return to full duty',
          'Fit to return with restrictions / light duty',
          'Fit to return with reasonable accommodations',
          'Not yet fit — continued leave required',
        ],
      },
    ],
  },
  {
    id: 'pme-pre-deployment',
    name: 'Pre-Deployment / Overseas Medical Exam',
    description:
      'Generic medical evaluation for workers being deployed overseas or to remote assignments. Captures destination, deployment duration, required screening, and deployment fitness.',
    template: pmePreDeployment,
    items: [
      {
        question: 'nature_of_work',
        type: 'multiplechoice',
        choices: NATURE_OF_WORK_CHOICES,
      },
      {
        question: 'deployment_fitness',
        type: 'multiplechoice',
        choices: [
          'Fit for deployment — no conditions',
          'Fit for deployment — with conditions',
          'Unfit for deployment — temporarily',
          'Unfit for deployment',
        ],
      },
    ],
  },
];

/**
 * Helper mirroring `getPresetsForType` in formTemplatePresets.ts. Kept as a
 * function rather than exporting the array directly so the PME dialog can
 * future-proof a "Basic" vs "Executive" split without API changes.
 */
export function getPmeReportPresets(): PmeReportPreset[] {
  return PME_REPORT_PRESETS;
}
