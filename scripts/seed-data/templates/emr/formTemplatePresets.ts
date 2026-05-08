/**
 * Ready-made starter templates for the EMR Form Template editor.
 *
 * Each preset targets a specific template `type` and provides a reasonable
 * baseline body. Authors can pick one, tweak, and save — much faster than
 * building from scratch.
 *
 * CONVENTIONS:
 * - Body only. Clinic header, patient header, template title, and creator
 *   signature are added automatically by the print/preview wrapper (see the
 *   hide* flags in EMR_FORM_TEMPLATE_FIELDS_CONFIG). Don't duplicate them.
 * - Every token used here MUST exist in DEFAULT_FORM_TEMPLATE_TAGS
 *   (packages/ui/src/components/data/form/constants.ts). If you add a token
 *   that isn't in the registry, it will render blank at runtime.
 * - Tokens are bare (no UUID suffix). The WYSIWYG's migrateLegacyTokens
 *   appends UUIDs on load so repeats can coexist.
 * - For dropdown fields, use `{custom_choices_<name>}` in the body AND add
 *   a matching entry to the preset's `items` array (`{ question: '<name>',
 *   type: 'multiplechoice', choices: [...] }`). `applyPreset` pushes these
 *   into `customFieldItems` so they're persisted with the template.
 * - For free-text fields with auto-derived labels, use `{custom_text_<name>}`.
 *   The label is derived from the underscored name (e.g. `sport_or_physical_activity`
 *   → "Sport Or Physical Activity") — no `items` entry needed.
 */

export type FormTemplatePresetType =
  | 'med-certificate'
  | 'fit-certificate'
  | 'waiver'
  | 'consent-form';

/**
 * Dropdown-item definition persisted alongside the template. Must be
 * stored in the form-template record's `items[]` so `FormInput.getCustomChoices`
 * can resolve the `{custom_choices_<question>}` token to an actual select.
 */
export interface FormTemplatePresetItem {
  /** Matches the `<name>` inside `{custom_choices_<name>}` — no prefix. */
  question: string;
  /** Currently only `multiplechoice` renders as a dropdown. */
  type: 'multiplechoice';
  /** Visible options in the dropdown. Each becomes both label and value. */
  choices: string[];
}

export interface FormTemplatePreset {
  id: string;
  type: FormTemplatePresetType;
  name: string;
  description: string;
  template: string;
  /**
   * Optional dropdown-item definitions for `{custom_choices_*}` tokens used
   * in the template body. Gets persisted on save so the dropdowns keep their
   * options when the template is later rendered.
   */
  items?: FormTemplatePresetItem[];
}

/* ---------- Medical Certificate ---------- */

const medCertClassic = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, was seen and examined on
  <strong>{patient_encounter_created_at}</strong>.
</p>

<p><strong>Chief Complaint:</strong> {patient_complaint}</p>

<p><strong>Impression:</strong> {patient_impression}</p>

<p><strong>Diagnosis:</strong> {patient_diagnosis}</p>

<p><strong>Recommendation:</strong></p>
<p>{patient_care_plan}</p>

<p>
  This certification is issued upon the request of the patient for whatever
  legal purpose it may serve.
</p>
`.trim();

const medCertSickLeave = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, was examined on <strong>{patient_encounter_created_at}</strong>
  and diagnosed with the following condition:
</p>

<p><strong>{patient_diagnosis}</strong></p>

<p>
  The patient is advised to rest and refrain from work/school from
  <strong>{date}</strong> to <strong>{date}</strong>. A follow-up consultation is
  recommended thereafter.
</p>

<p><strong>Prescribed medication(s):</strong></p>
<p>{patient_medication_order}</p>

<p>
  This certificate is issued for the purpose of submission to the employer or
  school as proof of medical leave.
</p>
`.trim();

const medCertQuarantine = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, was examined on <strong>{patient_encounter_created_at}</strong>
  and diagnosed with a communicable/contagious condition requiring home
  isolation or quarantine.
</p>

<p><strong>Diagnosis:</strong> {patient_diagnosis}</p>

<p>
  The patient is advised to remain under strict home isolation from
  <strong>{date}</strong> to <strong>{date}</strong>, to prevent transmission
  to household members and the community.
</p>

<p><strong>Precautions and further instructions:</strong></p>
<p>{patient_care_plan}</p>

<p>
  A follow-up evaluation is recommended at the end of the isolation period
  before the patient resumes normal activities.
</p>
`.trim();

const medCertMaternityLeave = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  is currently pregnant and was seen at our clinic on
  <strong>{patient_encounter_created_at}</strong>.
</p>

<p>
  <strong>Age of Gestation:</strong> {custom_text_age_of_gestation_in_weeks}<br />
  <strong>Expected Date of Delivery:</strong> {custom_text_expected_date_of_delivery}
</p>

<p>
  In the interest of the patient's and the baby's health and well-being,
  she is advised to be on maternity leave from <strong>{date}</strong> to
  <strong>{date}</strong>.
</p>

<p><strong>Clinical impression and recommendations:</strong></p>
<p>{patient_impression}</p>

<p>
  This certification is issued for submission to the employer and any
  agency requiring proof of maternity leave.
</p>
`.trim();

const medCertPregnancyConfirmation = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  was seen and examined on <strong>{patient_encounter_created_at}</strong> and
  is confirmed to be pregnant based on clinical and/or laboratory findings.
</p>

<p>
  <strong>Age of Gestation:</strong> {custom_text_age_of_gestation_in_weeks}<br />
  <strong>Expected Date of Delivery:</strong> {custom_text_expected_date_of_delivery}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vital Signs</p>
<p>
  BP: <strong>{vital_blood_pressure}</strong> ·
  PR: <strong>{vital_pulse_rate}</strong> bpm ·
  Wt: <strong>{vital_weight}</strong>
</p>

<p><strong>Assessment:</strong></p>
<p>{patient_impression}</p>

<p>
  This certificate is issued at the request of the patient for whatever
  legitimate purpose it may serve.
</p>
`.trim();

const medCertSchoolAbsence = `
<p>Date: <strong>{today}</strong></p>

<p>To the {custom_text_school_or_institution_name},</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, student of <strong>{custom_text_grade_or_year_level}</strong>,
  was seen and examined on <strong>{patient_encounter_created_at}</strong>.
</p>

<p><strong>Diagnosis:</strong> {patient_diagnosis}</p>

<p>
  The student is advised to be excused from school attendance and physical
  activities from <strong>{date}</strong> to <strong>{date}</strong>, to allow
  for rest and recovery.
</p>

<p><strong>Recommendations:</strong></p>
<p>{patient_care_plan}</p>

<p>
  Kindly excuse the above-named student from class attendance for the stated
  period. A follow-up evaluation will be conducted thereafter.
</p>
`.trim();

const medCertDentalCompletion = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, has undergone dental examination and treatment at this clinic
  on <strong>{patient_encounter_created_at}</strong>.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Work Done</p>
<p>{dental_note_result_table}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Post-Treatment Instructions</p>
<p>{patient_care_plan}</p>

<p>
  This certification is issued upon the request of the patient for record
  and reimbursement purposes.
</p>
`.trim();

const medCertReturnToWork = `
<p>Date: <strong>{today}</strong></p>

<p>To Whom It May Concern,</p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, previously diagnosed with <strong>{patient_diagnosis}</strong>,
  has undergone a follow-up examination on
  <strong>{patient_encounter_created_at}</strong>.
</p>

<p>
  Based on this evaluation, the patient has sufficiently recovered and is
  <strong>FIT TO RETURN</strong> to work/school effective
  <strong>{date}</strong>.
</p>

<p><strong>Further recommendations or restrictions, if any:</strong></p>
<p>{patient_care_plan}</p>
`.trim();

/* ---------- Fitness Certificate ---------- */

const fitCertPreEmployment = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, has completed a pre-employment medical examination on
  <strong>{patient_encounter_created_at}</strong>.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vital Signs</p>
<ul>
  <li>Blood Pressure: <strong>{vital_blood_pressure}</strong></li>
  <li>Pulse Rate: <strong>{vital_pulse_rate}</strong> bpm</li>
  <li>Respiration Rate: <strong>{vital_resp_rate}</strong> cpm</li>
  <li>Temperature: <strong>{vital_temperature}</strong> °C</li>
  <li>Height: <strong>{vital_height}</strong> · Weight: <strong>{vital_weight}</strong></li>
  <li>BMI: <strong>{vital_bmi}</strong></li>
</ul>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Physical Examination</p>
<p>{patient_physical_exam}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Impression</p>
<p>{patient_impression}</p>

<p>
  Based on the foregoing findings, the patient is found to be
  <strong>PHYSICALLY AND MENTALLY FIT</strong> for employment.
</p>

<p>This certification is valid for thirty (30) days from the date of issue.</p>
`.trim();

const fitCertTravel = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, born on {patient_dob}, has undergone a medical evaluation on
  <strong>{patient_encounter_created_at}</strong> for purposes of travel.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vital Signs</p>
<p>
  BP: <strong>{vital_blood_pressure}</strong> ·
  PR: <strong>{vital_pulse_rate}</strong> ·
  RR: <strong>{vital_resp_rate}</strong> ·
  Temp: <strong>{vital_temperature}</strong> °C
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Relevant History</p>
<p><strong>Past Medical History:</strong> {patient_pmhx}</p>
<p><strong>Allergies:</strong> {patient_allergies_hx}</p>
<p><strong>Current Medications:</strong></p>
<p>{patient_medication_order}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Clinical Assessment</p>
<p>{patient_impression}</p>

<p>
  The patient is in stable condition and is deemed <strong>FIT TO TRAVEL</strong>
  via any mode of transportation.
</p>

<p>This certification is valid for fourteen (14) days from the date of issue.</p>
`.trim();

const fitCertSports = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, has completed a pre-participation physical evaluation on
  <strong>{patient_encounter_created_at}</strong>.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Cardiovascular & Respiratory</p>
<ul>
  <li>Blood Pressure: <strong>{vital_blood_pressure}</strong></li>
  <li>Heart Rate: <strong>{vital_pulse_rate}</strong> bpm</li>
  <li>Respiration Rate: <strong>{vital_resp_rate}</strong> cpm</li>
  <li>Cardiovascular Exam: <strong>{pe_cardiovascular_status}</strong> — {pe_cardiovascular_text}</li>
  <li>Respiratory Exam: <strong>{pe_respiratory_status}</strong> — {pe_respiratory_text}</li>
</ul>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Musculoskeletal</p>
<p><strong>{pe_musculoskeletal_status}</strong> — {pe_musculoskeletal_text}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Impression</p>
<p>{patient_impression}</p>

<p>
  Based on the above findings, the patient is <strong>CLEARED</strong> for
  participation in <strong>{custom_text_sport_or_physical_activity}</strong>.
</p>

<p>
  Clearance is valid for one (1) year from the date of issue unless superseded
  by subsequent medical findings.
</p>
`.trim();

const fitCertAnnualPhysicalExam = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, born on {patient_dob}, has undergone an Annual Physical
  Examination on <strong>{patient_encounter_created_at}</strong>.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vital Signs</p>
<ul>
  <li>Blood Pressure: <strong>{vital_blood_pressure}</strong></li>
  <li>Pulse Rate: <strong>{vital_pulse_rate}</strong> bpm</li>
  <li>Respiration Rate: <strong>{vital_resp_rate}</strong> cpm</li>
  <li>Temperature: <strong>{vital_temperature}</strong> °C</li>
  <li>Height: <strong>{vital_height}</strong> · Weight: <strong>{vital_weight}</strong></li>
  <li>BMI: <strong>{vital_bmi}</strong></li>
  <li>Visual Acuity: OD <strong>{vital_visual_acuity_right}</strong> · OS <strong>{vital_visual_acuity_left}</strong></li>
  <li>Color Vision: <strong>{vital_color_vision}</strong></li>
</ul>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Physical Examination Findings</p>
<p>{patient_physical_exam}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Clinical Impression</p>
<p>{patient_impression}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Significant Findings / Diagnosis</p>
<p>{patient_diagnosis}</p>

<p>
  Based on the above findings, the patient is deemed to be in
  <strong>{custom_choices_overall_health_status}</strong> overall health.
</p>

<p>This summary is issued upon the request of the patient.</p>
`.trim();

const fitCertPreSurgical = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, has been evaluated on <strong>{patient_encounter_created_at}</strong>
  in connection with a proposed surgical procedure.
</p>

<p>
  <strong>Proposed Procedure:</strong> {custom_text_proposed_procedure}<br />
  <strong>Tentative Date:</strong> {custom_text_tentative_schedule}<br />
  <strong>ASA Physical Status:</strong> {custom_choices_asa_physical_status}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Relevant History</p>
<p><strong>Past Medical History:</strong> {patient_pmhx}</p>
<p><strong>Allergies:</strong> {patient_allergies_hx}</p>
<p><strong>Current Medications:</strong></p>
<p>{patient_medication_order}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vitals & Exam</p>
<p>
  BP: <strong>{vital_blood_pressure}</strong> ·
  PR: <strong>{vital_pulse_rate}</strong> bpm ·
  RR: <strong>{vital_resp_rate}</strong> cpm ·
  Temp: <strong>{vital_temperature}</strong> °C
</p>
<p>{patient_physical_exam}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Clearance Statement</p>
<p>{patient_impression}</p>

<p>
  Based on the above evaluation, the patient is <strong>CLEARED</strong> for the
  proposed surgical procedure and anesthesia. This clearance is valid for
  thirty (30) days from the date of issue unless superseded by new findings.
</p>
`.trim();

const fitCertDriving = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, has been examined on <strong>{patient_encounter_created_at}</strong>
  for the purpose of securing or renewing a
  <strong>{custom_choices_license_category}</strong> driver's license.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vision Assessment</p>
<ul>
  <li>Right Eye (OD): <strong>{vital_visual_acuity_right}</strong></li>
  <li>Left Eye (OS): <strong>{vital_visual_acuity_left}</strong></li>
  <li>Color Vision: <strong>{vital_color_vision}</strong></li>
</ul>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Cardiovascular & General</p>
<ul>
  <li>Blood Pressure: <strong>{vital_blood_pressure}</strong></li>
  <li>Pulse Rate: <strong>{vital_pulse_rate}</strong> bpm</li>
</ul>

<p><strong>Clinical Impression:</strong> {patient_impression}</p>

<p>
  Based on the findings above, the patient is found to be
  <strong>MEDICALLY FIT</strong> to operate a motor vehicle under the category
  indicated. This certificate is valid for one (1) year from the date of issue.
</p>
`.trim();

const fitCertDiving = `
<p>Date: <strong>{today}</strong></p>

<p>
  This is to certify that <strong>{patient_name}</strong>, {patient_age} years old,
  {patient_sex}, has completed a diving-medicine evaluation on
  <strong>{patient_encounter_created_at}</strong>.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vitals</p>
<p>
  BP: <strong>{vital_blood_pressure}</strong> ·
  PR: <strong>{vital_pulse_rate}</strong> bpm ·
  RR: <strong>{vital_resp_rate}</strong> cpm ·
  Temp: <strong>{vital_temperature}</strong> °C
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Cardiovascular</p>
<p><strong>{pe_cardiovascular_status}</strong> — {pe_cardiovascular_text}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Respiratory</p>
<p><strong>{pe_respiratory_status}</strong> — {pe_respiratory_text}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">ENT / Airway</p>
<p>{patient_ent_note}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Clinical Impression</p>
<p>{patient_impression}</p>

<p>
  Based on the findings above, the patient is <strong>CLEARED</strong> for
  recreational diving activities up to a maximum depth of
  <strong>{custom_text_maximum_depth_in_meters}</strong> meters, under
  <strong>{custom_choices_diving_conditions}</strong> conditions.
</p>

<p>
  This clearance is valid for one (1) year from the date of issue, unless
  superseded by new medical findings or a change in the patient's condition.
</p>
`.trim();

/* ---------- Waiver ---------- */

const signatureTable = (rightLabel: string) => `
<br />
<table style="width: 100%; border-collapse: collapse;">
  <tr>
    <td style="width: 50%; text-align: center; padding: 16px; border-top: 1px solid #000;">
      <p>_______________________________</p>
      <p><strong>Patient / Legal Guardian</strong></p>
      <p>Date: {date}</p>
    </td>
    <td style="width: 50%; text-align: center; padding: 16px; border-top: 1px solid #000;">
      <p>_______________________________</p>
      <p><strong>${rightLabel}</strong></p>
      <p>Date: {date}</p>
    </td>
  </tr>
</table>
`.trim();

const waiverProcedureConsent = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}<br />
  Address: {patient_full_address}<br />
  Contact: {patient_mobile_no}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Acknowledgment and Consent</p>
<p>
  I, <strong>{patient_name}</strong>, hereby acknowledge that the procedure to be
  performed has been thoroughly explained to me. I understand its nature,
  purpose, expected benefits, potential risks, and possible alternatives in a
  language I fully comprehend.
</p>

<p>
  I have had the opportunity to ask questions, and all my concerns have been
  satisfactorily addressed. I voluntarily give my informed consent to proceed.
</p>

<p>
  I hereby release and waive any claim against the attending physician, staff,
  and facility for any untoward incident arising from the procedure, provided
  that due care and accepted medical standards were observed.
</p>

${signatureTable('Witness')}
`.trim();

const waiverAMA = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Age: {patient_age} · Sex: {patient_sex}<br />
  Date of Birth: {patient_dob}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Declaration</p>
<p>
  I, <strong>{patient_name}</strong>, acknowledge that I have been advised by my
  attending physician regarding the recommended course of treatment for the
  following condition:
</p>

<p><strong>{patient_diagnosis}</strong></p>

<p>
  The nature of my condition, the recommended treatment, and the potential
  consequences of refusing such treatment — including but not limited to
  worsening of my condition, complications, or death — have been explained to
  me in a language I fully understand.
</p>

<p>
  Despite this advice, I am choosing to <strong>REFUSE</strong> the recommended
  treatment <strong>AGAINST MEDICAL ADVICE (AMA)</strong>, of my own free will
  and without coercion.
</p>

<p>
  I hereby release the attending physician, the staff, and the facility from
  any liability that may arise from my refusal of the recommended treatment.
</p>

${signatureTable('Witness')}
`.trim();

const waiverPhotography = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Age: {patient_age} · Sex: {patient_sex}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Authorization</p>
<p>
  I, <strong>{patient_name}</strong>, authorize the attending physician and the
  facility to photograph, video-record, or otherwise document my condition,
  treatment, or procedure for any of the following purposes:
</p>

<ul>
  <li>Inclusion in my medical record</li>
  <li>Professional education and training</li>
  <li>Publication in medical journals or academic presentations (de-identified)</li>
</ul>

<p>
  I understand that all identifiable information will be kept confidential and
  that published material will protect my identity unless I explicitly consent
  otherwise.
</p>

<p>
  I may withdraw this authorization at any time by submitting a written request
  to the facility. Withdrawal will not affect any uses already made prior to
  the withdrawal.
</p>

${signatureTable('Attending Physician')}
`.trim();

const waiverAnesthesia = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}<br />
  Address: {patient_full_address}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Procedure and Anesthesia</p>
<p>
  <strong>Proposed Procedure:</strong> {custom_text_proposed_procedure}<br />
  <strong>Type of Anesthesia:</strong> {custom_choices_anesthesia_type}<br />
  <strong>Diagnosis:</strong> {patient_diagnosis}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Acknowledgment of Risks</p>
<p>
  I, <strong>{patient_name}</strong>, acknowledge that the anesthesiologist has
  explained to me, in language that I fully understand, the nature of the
  proposed anesthesia and the associated risks, including but not limited to:
  allergic reaction, respiratory or cardiac events, nerve injury, post-operative
  nausea or sore throat, and in rare cases serious complications up to and
  including death.
</p>

<p>
  I have had the opportunity to ask questions and all my concerns have been
  satisfactorily addressed. I voluntarily consent to the administration of
  anesthesia, to any necessary adjustments during the procedure, and to any
  additional emergency measures required for my safety.
</p>

<p>
  I hereby release and hold harmless the attending anesthesiologist, the
  surgical team, and the facility from any liability arising from the
  anesthetic management, provided that due care and accepted medical
  standards were observed.
</p>

${signatureTable('Attending Anesthesiologist')}
`.trim();

const waiverBloodTransfusion = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}<br />
  Address: {patient_full_address}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Transfusion Details</p>
<p>
  <strong>Diagnosis:</strong> {patient_diagnosis}<br />
  <strong>Indication:</strong> {custom_text_indication_for_transfusion}<br />
  <strong>Blood Product:</strong> {custom_choices_blood_product}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Acknowledgment</p>
<p>
  I, <strong>{patient_name}</strong>, acknowledge that the attending physician
  has explained to me, in a language I fully understand, the clinical
  reason for transfusing the above blood product, the expected benefits, the
  alternatives (including no transfusion), and the possible risks such as
  febrile reaction, allergic reaction, circulatory overload, and — though rare
  — transmission of infection and transfusion-related acute lung injury.
</p>

<p>
  I have had the opportunity to ask questions, and all my concerns have been
  satisfactorily addressed. I voluntarily give my informed consent to receive
  the above blood product and any additional units clinically required during
  the course of treatment.
</p>

<p>
  I hereby release the attending physician, the blood bank, and the facility
  from any liability arising from the transfusion, provided that due care and
  accepted medical and transfusion standards were observed.
</p>

${signatureTable('Attending Physician')}
`.trim();

const waiverMinor = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Minor Patient</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Parent / Legal Guardian</p>
<p>
  Name: <strong>{custom_text_parent_or_guardian_full_name}</strong><br />
  Relationship to Patient: <strong>{custom_choices_relationship_to_patient}</strong><br />
  Contact Number: {custom_text_guardian_contact_number}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent and Waiver</p>
<p>
  I, <strong>{custom_text_parent_or_guardian_full_name}</strong>, being the
  undersigned parent/legal guardian of the above-named minor, hereby consent
  to the medical examination, diagnostic testing, and treatment deemed
  necessary by the attending physician and authorized staff of this facility.
</p>

<p>
  I confirm that I have been given the opportunity to ask questions regarding
  the minor's condition and the proposed course of care, and that all my
  concerns have been satisfactorily addressed.
</p>

<p>
  I hereby release and hold harmless the attending physician, staff, and the
  facility from any liability arising from the treatment of the minor,
  provided that due care and accepted medical standards were observed.
</p>

${signatureTable('Witness')}
`.trim();

const waiverRecordsRelease = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob}<br />
  Address: {patient_full_address}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Authorized Recipient</p>
<p>
  Name / Organization: <strong>{custom_text_recipient_name_or_organization}</strong><br />
  Address: {custom_text_recipient_address}<br />
  Purpose of Release: {custom_text_purpose_of_release}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Scope of Records Released</p>
<p><strong>{custom_choices_scope_of_records}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Authorization</p>
<p>
  I, <strong>{patient_name}</strong>, hereby authorize the clinic to release a
  copy of my medical records, as described above, to the recipient indicated,
  for the stated purpose only.
</p>

<p>
  I understand that my medical records contain sensitive personal and health
  information protected under the Data Privacy Act of 2012 (Republic Act No.
  10173) and that once released to the named recipient, the clinic is no
  longer responsible for how the information is subsequently handled.
</p>

<p>
  I may revoke this authorization at any time by submitting a written notice
  to the clinic, except to the extent that action has already been taken in
  reliance on it.
</p>

${signatureTable('Witness')}
`.trim();

/* ---------- Consent Form ---------- */

const consentDataPrivacy = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}<br />
  Address: {patient_full_address}<br />
  Contact: {patient_mobile_no} · {patient_email}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent for Collection and Processing of Personal Data</p>
<p>
  In compliance with the <strong>Data Privacy Act of 2012 (Republic Act No. 10173)</strong>
  and its implementing rules and regulations, I, <strong>{patient_name}</strong>, give
  my free and informed consent to the clinic to collect, store, access, process,
  and, where necessary, share my personal and sensitive personal information
  for the following purposes:
</p>

<ul>
  <li>Medical assessment, diagnosis, treatment, and continuity of care</li>
  <li>Billing, claims processing, and insurance / HMO reimbursement</li>
  <li>Coordination with other licensed healthcare providers involved in my care</li>
  <li>Compliance with legal, regulatory, and public-health reporting obligations</li>
  <li>Internal clinical audits and quality improvement activities (de-identified)</li>
</ul>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Scope of Information</p>
<p>
  I understand that the information covered by this consent includes, but is not
  limited to, my demographic details, contact information, medical history,
  diagnoses, laboratory and imaging results, prescriptions, and billing records.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">My Rights as a Data Subject</p>
<p>
  I acknowledge that I have been informed of my rights under the Data Privacy
  Act, including the right to be informed, the right to access, the right to
  rectification, the right to erasure or blocking, the right to object, the
  right to data portability, and the right to file a complaint with the
  National Privacy Commission.
</p>

<p>
  I may withdraw this consent at any time by submitting a written request to
  the clinic's Data Protection Officer. Withdrawal will not affect the
  lawfulness of processing performed prior to the withdrawal, nor will it
  prevent the clinic from retaining records required by law.
</p>

<p>
  By affixing my signature below, I confirm that I have read and understood
  the above, and I voluntarily give my consent.
</p>

${signatureTable('Witness')}
`.trim();

const consentGeneralTreatment = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent for Medical Treatment</p>
<p>
  I, <strong>{patient_name}</strong>, voluntarily consent to the medical
  examination, diagnostic procedures, and treatment deemed necessary and
  appropriate by the attending physician and authorized staff of this facility.
</p>

<p>
  I understand that medicine is not an exact science and that no guarantees
  have been made to me regarding the outcome of my care. I have been given the
  opportunity to ask questions regarding my condition and the proposed course
  of treatment, and such questions have been answered to my satisfaction.
</p>

<p>
  I authorize the facility to administer routine diagnostic tests, medications,
  and emergency interventions as required for my safety and well-being.
</p>

${signatureTable('Witness')}
`.trim();

const consentTelehealth = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Age: {patient_age} · Sex: {patient_sex}<br />
  Contact: {patient_mobile_no} · {patient_email}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent for Telehealth Consultation</p>
<p>
  I, <strong>{patient_name}</strong>, understand and consent to receiving
  medical consultation through telehealth — the use of electronic
  communications, including video, audio, and messaging — as an alternative
  to an in-person visit.
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Acknowledgments</p>
<ul>
  <li>
    I understand that telehealth consultations have inherent limitations,
    including the inability to perform a full physical examination, and that
    the attending physician may require an in-person visit at any time.
  </li>
  <li>
    I understand that reasonable measures are taken to protect the privacy and
    security of the consultation, but that no electronic communication channel
    is entirely risk-free.
  </li>
  <li>
    I understand that clinical notes, prescriptions, and other documentation
    produced during the telehealth consultation will form part of my medical
    record.
  </li>
  <li>
    I may decline to proceed with the telehealth consultation at any time and
    request an in-person visit instead.
  </li>
</ul>

<p>
  I voluntarily give my informed consent to proceed with a telehealth
  consultation under the terms above.
</p>

${signatureTable('Attending Physician')}
`.trim();

const consentVaccination = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Vaccine Details</p>
<p>
  <strong>Vaccine:</strong> {custom_choices_vaccine}<br />
  <strong>Dose Number:</strong> {custom_choices_dose_number}<br />
  <strong>Manufacturer / Lot Number:</strong> {custom_text_manufacturer_and_lot_number}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Relevant History</p>
<p><strong>Known Allergies:</strong> {patient_allergies_hx}</p>
<p><strong>Past Vaccinations:</strong> {patient_vaccination_hx}</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent</p>
<p>
  I, <strong>{patient_name}</strong>, acknowledge that the purpose, benefits,
  and potential side effects of the above vaccine have been explained to me,
  including common reactions (soreness, mild fever, fatigue) and rare but
  serious reactions (allergic reaction or anaphylaxis). I have been given
  the opportunity to ask questions, and all my concerns have been answered.
</p>

<p>
  I voluntarily consent to receive the above vaccine and to any observation
  period immediately after administration. I understand I may decline at any
  time before the vaccine is given.
</p>

${signatureTable('Administering Staff')}
`.trim();

const consentPediatricTreatment = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Minor Patient</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Parent / Legal Guardian</p>
<p>
  Name: <strong>{custom_text_parent_or_guardian_full_name}</strong><br />
  Relationship to Patient: <strong>{custom_choices_relationship_to_patient}</strong><br />
  Contact Number: {custom_text_guardian_contact_number}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent for Pediatric Care</p>
<p>
  I, <strong>{custom_text_parent_or_guardian_full_name}</strong>, confirm that
  I am the parent or legal guardian of the above-named minor and I consent to
  the medical examination, diagnostic procedures, and treatment deemed
  necessary and appropriate by the attending pediatrician and authorized
  staff of this clinic.
</p>

<p>
  I understand that this consent includes routine diagnostic tests,
  age-appropriate medications, and emergency interventions required for the
  safety and well-being of the minor patient.
</p>

<p>
  I have been given the opportunity to ask questions regarding the proposed
  course of treatment and all my concerns have been addressed to my
  satisfaction.
</p>

${signatureTable('Witness')}
`.trim();

const consentHmoAssignment = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Age: {patient_age} · Sex: {patient_sex}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">HMO / Insurance Details</p>
<p>
  HMO / Insurer: <strong>{patient_hmos}</strong><br />
  Member / Account Number: <strong>{patient_hmo_accountno}</strong><br />
  Validity: {patient_hmo_validity} · Expiry: {patient_hmo_expiry}<br />
  Membership Status: {patient_hmo_status}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Assignment of Benefits</p>
<p>
  I, <strong>{patient_name}</strong>, hereby assign directly to the clinic all
  medical benefits, if any, otherwise payable to me for services rendered by
  the clinic in connection with my current care. I understand that I remain
  financially responsible for any amount not covered by my HMO or insurer,
  including but not limited to co-payments, deductibles, non-covered
  services, and amounts exceeding policy limits.
</p>

<p>
  I authorize the clinic to release to my HMO, insurer, or its authorized
  representatives any information required to process, approve, and pay for
  my claim, including portions of my medical record, billing statements, and
  supporting documents.
</p>

<p>
  This authorization remains valid for the duration of my treatment and for
  as long as claims arising from this treatment may be pending with my HMO
  or insurer.
</p>

${signatureTable('Witness')}
`.trim();

const consentFinancialResponsibility = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob} · Address: {patient_full_address}<br />
  Contact: {patient_mobile_no}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Acknowledgment of Financial Responsibility</p>
<p>
  I, <strong>{patient_name}</strong>, acknowledge and agree to be financially
  responsible for all charges incurred for services rendered by the clinic,
  including professional fees, diagnostic tests, procedures, supplies, and
  any other related items.
</p>

<p>
  I understand that:
</p>
<ul>
  <li>
    Payment is due at the time services are rendered, unless other
    arrangements have been approved in writing by the clinic.
  </li>
  <li>
    If I have HMO or insurance coverage, I remain responsible for any
    portion not covered or not approved by my plan — including co-payments,
    excluded services, and amounts exceeding policy limits.
  </li>
  <li>
    The clinic may forward unpaid balances to an authorized collection
    agency after reasonable efforts to collect directly, and I may be held
    liable for associated collection costs.
  </li>
</ul>

<p>
  I acknowledge that I have read and understood the above and voluntarily
  accept financial responsibility for my care.
</p>

${signatureTable('Witness')}
`.trim();

const consentReleaseToThirdParty = `
<p>Date: <strong>{today}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Patient Information</p>
<p>
  Name: <strong>{patient_name}</strong><br />
  Date of Birth: {patient_dob}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Third-Party Recipient</p>
<p>
  Name / Organization: <strong>{custom_text_recipient_name_or_organization}</strong><br />
  Purpose: {custom_text_purpose_of_disclosure}
</p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Information to be Disclosed</p>
<p><strong>{custom_choices_information_to_disclose}</strong></p>

<p style="margin-top: 1rem; margin-bottom: 0.25rem; font-weight: 600;">Consent</p>
<p>
  I, <strong>{patient_name}</strong>, voluntarily consent to the release of
  the above-described information, pertaining to my care at this clinic, to
  the named third-party recipient for the purpose stated above.
</p>

<p>
  I understand that the information covered by this consent is protected
  under the Data Privacy Act of 2012 (Republic Act No. 10173) and that, once
  released, the clinic is no longer responsible for how the recipient uses or
  further discloses the information.
</p>

<p>
  I may revoke this consent at any time by submitting a written notice to
  the clinic's Data Protection Officer, except to the extent that action has
  already been taken in reliance on it.
</p>

${signatureTable('Witness')}
`.trim();

/* ---------- Registry ---------- */

export const FORM_TEMPLATE_PRESETS: FormTemplatePreset[] = [
  {
    id: 'med-cert-classic',
    type: 'med-certificate',
    name: 'Classic Medical Certificate',
    description:
      'General-purpose "to whom it may concern" certificate with chief complaint, impression, diagnosis, and recommendation.',
    template: medCertClassic,
  },
  {
    id: 'med-cert-sick-leave',
    type: 'med-certificate',
    name: 'Sickness / Medical Leave',
    description:
      'Certificate for work or school absence. Includes rest-period dates and prescribed medications.',
    template: medCertSickLeave,
  },
  {
    id: 'med-cert-return-to-work',
    type: 'med-certificate',
    name: 'Return to Work / School Clearance',
    description:
      'Fit-to-return certificate for patients who have recovered from a prior diagnosis.',
    template: medCertReturnToWork,
  },
  {
    id: 'med-cert-quarantine',
    type: 'med-certificate',
    name: 'Quarantine / Isolation Certificate',
    description:
      'Home-isolation certificate for a patient with a communicable condition. Includes diagnosis, isolation period, and precautions.',
    template: medCertQuarantine,
  },
  {
    id: 'med-cert-maternity-leave',
    type: 'med-certificate',
    name: 'Maternity Leave Certificate',
    description:
      'Maternity leave certification for expectant mothers. Includes age of gestation, expected delivery date, and leave period.',
    template: medCertMaternityLeave,
  },
  {
    id: 'med-cert-pregnancy-confirmation',
    type: 'med-certificate',
    name: 'Pregnancy Confirmation',
    description:
      'Clinical confirmation of pregnancy with current vitals, age of gestation, and expected delivery date.',
    template: medCertPregnancyConfirmation,
  },
  {
    id: 'med-cert-school-absence',
    type: 'med-certificate',
    name: 'School Absence Certificate',
    description:
      'Certificate for students who need to be excused from classes. Includes grade level, diagnosis, and absence period.',
    template: medCertSchoolAbsence,
  },
  {
    id: 'med-cert-dental-completion',
    type: 'med-certificate',
    name: 'Dental Procedure Completion',
    description:
      'After-visit certification for dental work. Includes the work-done table (teeth, surfaces, diagnoses) and post-treatment instructions.',
    template: medCertDentalCompletion,
  },
  {
    id: 'fit-cert-pre-employment',
    type: 'fit-certificate',
    name: 'Pre-Employment Fitness',
    description:
      'Pre-employment medical examination summary with vitals, physical exam, and fitness statement. Valid 30 days.',
    template: fitCertPreEmployment,
  },
  {
    id: 'fit-cert-travel',
    type: 'fit-certificate',
    name: 'Travel Fitness',
    description:
      'Fit-to-travel certificate including relevant history and current medications. Valid 14 days.',
    template: fitCertTravel,
  },
  {
    id: 'fit-cert-sports',
    type: 'fit-certificate',
    name: 'Sports / Physical Activity Clearance',
    description:
      'Pre-participation evaluation with cardiovascular, respiratory, and musculoskeletal assessment. Valid 1 year.',
    template: fitCertSports,
  },
  {
    id: 'fit-cert-annual-physical-exam',
    type: 'fit-certificate',
    name: 'Annual Physical Exam (APE) Summary',
    description:
      'Complete annual-physical summary including vitals, vision, physical-exam findings, impression, and overall health classification.',
    template: fitCertAnnualPhysicalExam,
    items: [
      {
        question: 'overall_health_status',
        type: 'multiplechoice',
        choices: ['Excellent', 'Good', 'Fair', 'Needs Follow-up'],
      },
    ],
  },
  {
    id: 'fit-cert-pre-surgical',
    type: 'fit-certificate',
    name: 'Pre-Surgical / Anesthesia Clearance',
    description:
      'Medical clearance for surgery — relevant history, medications, vitals, ASA physical status, and a pass/hold statement. Valid 30 days.',
    template: fitCertPreSurgical,
    items: [
      {
        question: 'asa_physical_status',
        type: 'multiplechoice',
        choices: [
          'ASA I — Normal healthy patient',
          'ASA II — Mild systemic disease',
          'ASA III — Severe systemic disease',
          'ASA IV — Severe disease that is a constant threat to life',
          'ASA V — Moribund, not expected to survive without the operation',
        ],
      },
    ],
  },
  {
    id: 'fit-cert-driving',
    type: 'fit-certificate',
    name: "Driver's License Fitness",
    description:
      'Medical fitness for a new or renewing driver. Includes visual acuity, color vision, blood pressure, and license category.',
    template: fitCertDriving,
    items: [
      {
        question: 'license_category',
        type: 'multiplechoice',
        choices: [
          'Non-Professional (Private)',
          'Professional',
          'Student Permit',
          'Motorcycle',
          'Light Vehicle',
          'Heavy Vehicle / Trucks',
          'Public Utility Vehicle',
        ],
      },
    ],
  },
  {
    id: 'fit-cert-diving',
    type: 'fit-certificate',
    name: 'Diving / Scuba Fitness',
    description:
      'Diving-medicine clearance with cardiovascular, respiratory, and ENT evaluation. Specifies maximum depth and diving conditions.',
    template: fitCertDiving,
    items: [
      {
        question: 'diving_conditions',
        type: 'multiplechoice',
        choices: [
          'Open water — recreational',
          'Confined water / training only',
          'Deep diving (advanced)',
          'Technical / rebreather',
          'Professional / commercial',
        ],
      },
    ],
  },
  {
    id: 'waiver-procedure-consent',
    type: 'waiver',
    name: 'Procedure Consent & Waiver',
    description:
      'Informed consent for a medical procedure with acknowledgment of risks and waiver of liability.',
    template: waiverProcedureConsent,
  },
  {
    id: 'waiver-ama',
    type: 'waiver',
    name: 'Refusal of Treatment (AMA)',
    description:
      'Against Medical Advice (AMA) waiver. Patient refuses recommended treatment despite being informed of consequences.',
    template: waiverAMA,
  },
  {
    id: 'waiver-photography',
    type: 'waiver',
    name: 'Photography & Media Consent',
    description:
      'Authorization to photograph or video-record the patient for medical record, education, or publication purposes.',
    template: waiverPhotography,
  },
  {
    id: 'waiver-anesthesia',
    type: 'waiver',
    name: 'Anesthesia Consent & Waiver',
    description:
      'Consent for anesthesia with explicit acknowledgment of risks. Covers general, regional, local, and sedation.',
    template: waiverAnesthesia,
    items: [
      {
        question: 'anesthesia_type',
        type: 'multiplechoice',
        choices: [
          'General',
          'Regional — Spinal',
          'Regional — Epidural',
          'Peripheral Nerve Block',
          'Monitored Anesthesia Care (Sedation)',
          'Local Anesthesia',
        ],
      },
    ],
  },
  {
    id: 'waiver-blood-transfusion',
    type: 'waiver',
    name: 'Blood Transfusion Consent',
    description:
      'Consent to receive blood products with acknowledgment of indications, alternatives, and transfusion-related risks.',
    template: waiverBloodTransfusion,
    items: [
      {
        question: 'blood_product',
        type: 'multiplechoice',
        choices: [
          'Whole Blood',
          'Packed Red Blood Cells',
          'Fresh Frozen Plasma',
          'Platelet Concentrate',
          'Cryoprecipitate',
          'Albumin',
        ],
      },
    ],
  },
  {
    id: 'waiver-minor',
    type: 'waiver',
    name: 'Minor Patient Consent (Parent / Guardian)',
    description:
      'Waiver signed by a parent or legal guardian for a minor patient. Captures the guardian\u2019s name, relationship, and contact.',
    template: waiverMinor,
    items: [
      {
        question: 'relationship_to_patient',
        type: 'multiplechoice',
        choices: [
          'Father',
          'Mother',
          'Legal Guardian',
          'Grandparent',
          'Older Sibling',
          'Other Relative',
        ],
      },
    ],
  },
  {
    id: 'waiver-records-release',
    type: 'waiver',
    name: 'Release of Medical Records',
    description:
      'Authorization to release records to a named recipient. Covers scope of records, purpose, and Data Privacy Act acknowledgment.',
    template: waiverRecordsRelease,
    items: [
      {
        question: 'scope_of_records',
        type: 'multiplechoice',
        choices: [
          'All medical records',
          'Specific encounter only',
          'Laboratory results only',
          'Imaging results only',
          'Discharge summary / Clinical abstract',
          'Prescriptions only',
        ],
      },
    ],
  },
  {
    id: 'consent-data-privacy',
    type: 'consent-form',
    name: 'Data Privacy Consent (RA 10173)',
    description:
      'Patient consent to collect and process personal and medical information under the Data Privacy Act. Covers treatment, billing, insurance, and care coordination; lists data-subject rights.',
    template: consentDataPrivacy,
  },
  {
    id: 'consent-general-treatment',
    type: 'consent-form',
    name: 'General Consent for Treatment',
    description:
      'General-purpose consent to medical examination, routine diagnostics, and emergency interventions performed by clinic staff.',
    template: consentGeneralTreatment,
  },
  {
    id: 'consent-telehealth',
    type: 'consent-form',
    name: 'Telehealth Consultation Consent',
    description:
      'Consent for remote consultation via video, audio, or messaging. Covers limitations, privacy, documentation, and right to decline.',
    template: consentTelehealth,
  },
  {
    id: 'consent-vaccination',
    type: 'consent-form',
    name: 'Vaccination / Immunization Consent',
    description:
      'Pre-shot consent with vaccine selector, dose number, manufacturer/lot, allergy review, and prior-vaccination history.',
    template: consentVaccination,
    items: [
      {
        question: 'vaccine',
        type: 'multiplechoice',
        choices: [
          'COVID-19',
          'Influenza (Flu)',
          'Hepatitis B',
          'Hepatitis A',
          'HPV',
          'Measles, Mumps, Rubella (MMR)',
          'Tdap (Tetanus, Diphtheria, Pertussis)',
          'Pneumococcal (PCV)',
          'Varicella',
          'Japanese Encephalitis',
          'Rabies',
          'Meningococcal',
          'Other',
        ],
      },
      {
        question: 'dose_number',
        type: 'multiplechoice',
        choices: ['1st dose', '2nd dose', '3rd dose', 'Booster'],
      },
    ],
  },
  {
    id: 'consent-pediatric-treatment',
    type: 'consent-form',
    name: 'Pediatric Treatment Consent',
    description:
      'Consent by a parent or legal guardian for the medical treatment of a minor patient at the clinic.',
    template: consentPediatricTreatment,
    items: [
      {
        question: 'relationship_to_patient',
        type: 'multiplechoice',
        choices: [
          'Father',
          'Mother',
          'Legal Guardian',
          'Grandparent',
          'Older Sibling',
          'Other Relative',
        ],
      },
    ],
  },
  {
    id: 'consent-hmo-assignment',
    type: 'consent-form',
    name: 'HMO / Insurance Assignment of Benefits',
    description:
      'Patient assigns insurance benefits to the clinic and authorizes the clinic to release documents to the insurer for claim processing.',
    template: consentHmoAssignment,
  },
  {
    id: 'consent-financial-responsibility',
    type: 'consent-form',
    name: 'Financial Responsibility Acknowledgment',
    description:
      'Patient acknowledges responsibility for all charges not covered by insurance, including co-payments, exclusions, and collection costs.',
    template: consentFinancialResponsibility,
  },
  {
    id: 'consent-release-third-party',
    type: 'consent-form',
    name: 'Release of Information to Third Party',
    description:
      'One-time release of specified health information to a named third party (e.g., employer, school, insurer) for a stated purpose.',
    template: consentReleaseToThirdParty,
    items: [
      {
        question: 'information_to_disclose',
        type: 'multiplechoice',
        choices: [
          'Diagnosis and treatment summary',
          'Laboratory and imaging results',
          'Prescription history',
          'Immunization record',
          'Fit-to-work / Fit-to-study certificate only',
          'Full medical summary',
        ],
      },
    ],
  },
];

export function getPresetsForType(type: string | undefined): FormTemplatePreset[] {
  if (!type) return [];
  return FORM_TEMPLATE_PRESETS.filter(p => p.type === type);
}
