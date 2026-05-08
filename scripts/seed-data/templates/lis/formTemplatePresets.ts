/**
 * Ready-made starter templates for the LIS Report Template editor.
 *
 * Content uses simple HTML only: <p>, <table>, <tr>, <td>, <strong>.
 * No custom_choices or custom_text tokens — lab report templates use
 * plain result-entry tables that the technologist fills in after printing.
 *
 * NOTE: Patient identifying info (name, age, sex, DOB) is rendered by a
 * separate patient-header component at print time. Presets must NOT
 * duplicate it here.
 */

export interface LisFormTemplatePreset {
  id: string;
  name: string;
  description: string;
  template: string;
}

/* ---- shared helpers ---- */

const resultTable = (title: string, rows: [string, string, string][]) => {
  const rowHtml = rows
    .map(
      ([param, unit, ref]) => `  <tr>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;">${param}</td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;"></td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;">${unit}</td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;">${ref}</td>
  </tr>`,
    )
    .join('\n');
  return `
<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">${title}</p>
<table style="width: 100%; border-collapse: collapse;">
  <tr style="background-color: #f3f4f6;">
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; width: 35%;">Parameter</th>
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; width: 20%;">Result</th>
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; width: 15%;">Unit</th>
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; width: 30%;">Reference Range</th>
  </tr>
${rowHtml}
</table>`.trim();
};

const impressionBlock = `
<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Impression</p>
<p>&nbsp;</p>`.trim();

/* ---- CBC ---- */

const cbcTemplate = `
${resultTable('Complete Blood Count', [
  ['RBC Count', 'x10⁶/µL', 'M: 4.5–5.9  /  F: 4.0–5.2'],
  ['Hemoglobin', 'g/dL', 'M: 13.5–17.5  /  F: 12.0–15.5'],
  ['Hematocrit', '%', 'M: 41–53  /  F: 36–46'],
  ['WBC Count', 'x10³/µL', '4.5–11.0'],
  ['Platelet Count', 'x10³/µL', '150–400'],
  ['MCV', 'fL', '80–100'],
  ['MCH', 'pg', '27–33'],
  ['MCHC', 'g/dL', '32–36'],
  ['RDW-CV', '%', '11.5–14.5'],
])}

${resultTable('Differential Count', [
  ['Segmenters (Neutrophils)', '%', '50–70'],
  ['Lymphocytes', '%', '20–40'],
  ['Monocytes', '%', '2–8'],
  ['Eosinophils', '%', '1–4'],
  ['Basophils', '%', '0–1'],
  ['Band Forms', '%', '0–5'],
])}

${impressionBlock}
`.trim();

/* ---- Urinalysis ---- */

const urinalysisTemplate = `
${resultTable('Macroscopic Examination', [
  ['Color', '', 'Yellow to Amber'],
  ['Transparency', '', 'Clear to Slightly Hazy'],
  ['pH', '', '5.0–8.0'],
  ['Specific Gravity', '', '1.005–1.030'],
])}

${resultTable('Chemical Examination', [
  ['Albumin / Protein', '', 'Negative'],
  ['Glucose / Sugar', '', 'Negative'],
  ['Ketone', '', 'Negative'],
  ['Blood / Occult Blood', '', 'Negative'],
  ['Bilirubin', '', 'Negative'],
  ['Urobilinogen', 'EU/dL', '0.1–1.0'],
  ['Nitrite', '', 'Negative'],
  ['Leukocyte Esterase', '', 'Negative'],
])}

${resultTable('Microscopic Examination (per High Power Field)', [
  ['WBC / Pus Cells', '/hpf', '0–5'],
  ['RBC', '/hpf', '0–2'],
  ['Epithelial Cells', '/hpf', 'Few'],
  ['Bacteria', '/hpf', 'None to Rare'],
  ['Mucus Threads', '/lpf', 'None to Rare'],
  ['Casts', '/lpf', 'None'],
  ['Crystals', '', 'None'],
])}

${impressionBlock}
`.trim();

/* ---- Fecalysis ---- */

const fecalysisTemplate = `
${resultTable('Macroscopic Examination', [
  ['Color', '', 'Brown'],
  ['Consistency', '', 'Formed'],
  ['Odor', '', 'Characteristic'],
  ['Mucus', '', 'None'],
  ['Blood', '', 'None'],
])}

${resultTable('Microscopic Examination (per High Power Field)', [
  ['WBC / Pus Cells', '/hpf', 'None to rare'],
  ['RBC', '/hpf', 'None to rare'],
  ['Bacteria', '', 'Few'],
  ['Fat Globules', '', 'None to rare'],
  ['Undigested Food Particles', '', 'None to few'],
])}

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Parasitology</p>
<table style="width: 100%; border-collapse: collapse;">
  <tr style="background-color: #f3f4f6;">
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left;">Organism</th>
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left;">Stage</th>
    <th style="border: 1px solid #d1d5db; padding: 6px 8px; text-align: left;">Findings</th>
  </tr>
  <tr>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;">Ova / Cysts</td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;"></td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;"></td>
  </tr>
  <tr>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;">Trophozoites</td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;"></td>
    <td style="border: 1px solid #d1d5db; padding: 6px 8px;"></td>
  </tr>
</table>

${impressionBlock}
`.trim();

/* ---- Clinical Chemistry ---- */

const clinicalChemistryTemplate = `
${resultTable('Kidney Function', [
  ['Blood Urea Nitrogen (BUN)', 'mg/dL', '7–20'],
  ['Creatinine', 'mg/dL', 'M: 0.7–1.3  /  F: 0.6–1.1'],
  ['BUN / Creatinine Ratio', '', '10–20'],
  ['Uric Acid', 'mg/dL', 'M: 3.5–7.2  /  F: 2.6–6.0'],
])}

${resultTable('Liver Function', [
  ['SGOT / AST', 'U/L', 'M: 10–40  /  F: 10–32'],
  ['SGPT / ALT', 'U/L', 'M: 10–55  /  F: 7–36'],
  ['Alkaline Phosphatase (ALP)', 'U/L', '44–147'],
  ['Total Bilirubin', 'mg/dL', '0.2–1.2'],
  ['Direct Bilirubin', 'mg/dL', '0.0–0.3'],
  ['Indirect Bilirubin', 'mg/dL', '0.2–0.9'],
  ['Total Protein', 'g/dL', '6.0–8.3'],
  ['Albumin', 'g/dL', '3.5–5.0'],
  ['Globulin', 'g/dL', '2.0–3.5'],
  ['LDH', 'U/L', '135–225'],
  ['GGT', 'U/L', 'M: 10–71  /  F: 6–42'],
])}

${impressionBlock}
`.trim();

/* ---- Lipid Profile ---- */

const lipidProfileTemplate = `
<p><strong>Specimen:</strong> Serum &nbsp; <strong>Fasting:</strong> Yes / No</p>

${resultTable('Lipid Panel', [
  ['Total Cholesterol', 'mg/dL', 'Desirable: < 200  /  Borderline: 200–239  /  High: ≥ 240'],
  ['Triglycerides', 'mg/dL', 'Normal: < 150  /  Borderline: 150–199  /  High: 200–499'],
  ['HDL Cholesterol', 'mg/dL', 'M: ≥ 40  /  F: ≥ 50  /  Optimal: ≥ 60'],
  ['LDL Cholesterol (calculated)', 'mg/dL', 'Optimal: < 100  /  Near optimal: 100–129  /  High: ≥ 160'],
  ['VLDL Cholesterol', 'mg/dL', '2–30'],
  ['Total Cholesterol / HDL Ratio', '', 'Desirable: < 5.0'],
  ['Non-HDL Cholesterol', 'mg/dL', '< 130 (optimal)'],
])}

${impressionBlock}
`.trim();

/* ---- FBS / HbA1c ---- */

const fbsHba1cTemplate = `
<p><strong>Specimen:</strong> Serum / Whole Blood &nbsp; <strong>Fasting:</strong> ≥ 8 hours</p>

${resultTable('Blood Glucose & Glycemic Control', [
  ['Fasting Blood Sugar (FBS)', 'mg/dL', 'Normal: 70–99  /  Pre-DM: 100–125  /  DM: ≥ 126'],
  ['2-Hour Post-Prandial Blood Sugar', 'mg/dL', 'Normal: < 140  /  Pre-DM: 140–199  /  DM: ≥ 200'],
  ['Random Blood Sugar (RBS)', 'mg/dL', 'Normal: < 140  /  DM: ≥ 200 with symptoms'],
  ['HbA1c (Glycated Hemoglobin)', '%', 'Normal: < 5.7  /  Pre-DM: 5.7–6.4  /  DM: ≥ 6.5'],
  ['Estimated Average Glucose (eAG)', 'mg/dL', 'Calculated from HbA1c'],
])}

${impressionBlock}
`.trim();

/* ---- Thyroid Panel ---- */

const thyroidTemplate = `
${resultTable('Thyroid Function Tests', [
  ['TSH (Thyroid-Stimulating Hormone)', 'µIU/mL', '0.27–4.20'],
  ['Free T4 (FT4)', 'ng/dL', '0.93–1.70'],
  ['Free T3 (FT3)', 'pg/mL', '2.0–4.4'],
  ['Total T4', 'µg/dL', '4.5–12.5'],
  ['Total T3', 'ng/dL', '80–200'],
  ['Anti-TPO (Thyroid Peroxidase Ab)', 'IU/mL', '< 35'],
  ['Anti-Tg (Thyroglobulin Ab)', 'IU/mL', '< 115'],
])}

${impressionBlock}
`.trim();

/* ---- Electrolytes ---- */

const electrolytesTemplate = `
${resultTable('Serum Electrolytes', [
  ['Sodium (Na⁺)', 'mEq/L', '136–145'],
  ['Potassium (K⁺)', 'mEq/L', '3.5–5.1'],
  ['Chloride (Cl⁻)', 'mEq/L', '98–107'],
  ['Bicarbonate / CO₂ (HCO₃⁻)', 'mEq/L', '22–29'],
  ['Anion Gap', 'mEq/L', '8–16'],
  ['Calcium (Ca²⁺)', 'mg/dL', '8.5–10.5'],
  ['Ionized Calcium', 'mmol/L', '1.15–1.30'],
  ['Magnesium (Mg²⁺)', 'mg/dL', '1.7–2.2'],
  ['Phosphorus (PO₄³⁻)', 'mg/dL', '2.5–4.5'],
])}

${impressionBlock}
`.trim();

/* ---- Registry ---- */

export const LIS_FORM_TEMPLATE_PRESETS: LisFormTemplatePreset[] = [
  {
    id: 'lis-cbc',
    name: 'Complete Blood Count (CBC)',
    description:
      'Full CBC with red cell indices and five-part differential count. Patient header and Impression section included.',
    template: cbcTemplate,
  },
  {
    id: 'lis-urinalysis',
    name: 'Urinalysis (UA)',
    description:
      'Macroscopic, chemical (dipstick), and microscopic examination of urine. Covers color, pH, albumin, glucose, cells, casts, and bacteria.',
    template: urinalysisTemplate,
  },
  {
    id: 'lis-fecalysis',
    name: 'Fecalysis (Stool Analysis)',
    description:
      'Macroscopic and microscopic stool examination with parasitology section for ova, cysts, and trophozoites.',
    template: fecalysisTemplate,
  },
  {
    id: 'lis-clinical-chemistry',
    name: 'Clinical Chemistry (Kidney & Liver)',
    description:
      'Kidney function panel (BUN, creatinine, uric acid) plus liver function panel (AST, ALT, ALP, bilirubin, protein, albumin, LDH, GGT).',
    template: clinicalChemistryTemplate,
  },
  {
    id: 'lis-lipid-profile',
    name: 'Lipid Profile',
    description:
      'Comprehensive lipid panel including total cholesterol, triglycerides, HDL, LDL (calculated), VLDL, and TC/HDL ratio with risk categorization.',
    template: lipidProfileTemplate,
  },
  {
    id: 'lis-fbs-hba1c',
    name: 'Blood Sugar / HbA1c',
    description:
      'Glycemic panel covering fasting blood sugar, 2-hour PPBS, random blood sugar, HbA1c, and estimated average glucose with ADA diagnostic thresholds.',
    template: fbsHba1cTemplate,
  },
  {
    id: 'lis-thyroid',
    name: 'Thyroid Function Panel',
    description:
      'Complete thyroid profile: TSH, Free T4, Free T3, Total T4, Total T3, Anti-TPO, and Anti-Tg antibodies.',
    template: thyroidTemplate,
  },
  {
    id: 'lis-electrolytes',
    name: 'Serum Electrolytes',
    description:
      'Basic metabolic panel covering sodium, potassium, chloride, bicarbonate, anion gap, calcium (total and ionized), magnesium, and phosphorus.',
    template: electrolytesTemplate,
  },
];
