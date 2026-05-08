/**
 * Ready-made starter templates for the RIS (Radiology/Imaging) Report
 * Template editor.
 *
 * Each preset targets a specific imaging modality and follows the standard
 * radiology report structure: Clinical History / Indication → Technique →
 * Findings → Impression → Recommendations.
 *
 * CONVENTIONS:
 * - Body only. Clinic header, patient header, signature block, and report
 *   dates are rendered by the print/preview wrapper. Presets must NOT
 *   duplicate any of those — in particular, no {patient_*} tokens.
 * - Use simple HTML only: <p>, <table>, <tr>, <td>, <strong>. No inline CSS.
 * - No {custom_choices_*} or {custom_text_*} tokens — the richtexteditor
 *   input does not support those constructs.
 */

export interface RisReportPreset {
  id: string;
  name: string;
  description: string;
  template: string;
}

/* ---------- Shared fragments ---------- */

// NOTE: Patient identifying info (name, age, sex, DOB) and report dates
// are rendered by a separate patient-header component at print time, so
// presets must NOT duplicate those here.

const section = (label: string, body: string) =>
  `<p><strong>${label}</strong></p>\n<p>${body}</p>`;

/* ---------- Chest X-Ray ---------- */

const chestXray = `
${section('CLINICAL HISTORY / INDICATION', 'Chest pain; evaluate cardiopulmonary status.')}

${section('TECHNIQUE', 'Posteroanterior (PA) chest radiograph obtained in full inspiration.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Trachea</strong></td>
    <td>Midline</td>
  </tr>
  <tr>
    <td><strong>Heart</strong></td>
    <td>Normal size and contour; cardiothoracic ratio within normal limits</td>
  </tr>
  <tr>
    <td><strong>Lungs</strong></td>
    <td>Clear lung fields bilaterally; no consolidation, infiltrates, or pleural effusion</td>
  </tr>
  <tr>
    <td><strong>Mediastinum</strong></td>
    <td>Not widened; normal hilum bilaterally</td>
  </tr>
  <tr>
    <td><strong>Hemidiaphragms</strong></td>
    <td>Normal; no costophrenic angle blunting</td>
  </tr>
  <tr>
    <td><strong>Bony structures</strong></td>
    <td>Intact ribs, clavicles, and visualized scapulae</td>
  </tr>
  <tr>
    <td><strong>Soft tissues</strong></td>
    <td>Unremarkable</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal chest radiograph. No acute cardiopulmonary finding.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Follow-up imaging as clinically indicated.')}
`.trim();

/* ---------- Pelvic X-Ray ---------- */

const pelvicXray = `
${section('CLINICAL HISTORY / INDICATION', 'Hip or pelvic pain; evaluate bony pelvis.')}

${section('TECHNIQUE', 'Anteroposterior (AP) radiograph of the pelvis.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Pelvic ring</strong></td>
    <td>Intact; no fracture or dislocation</td>
  </tr>
  <tr>
    <td><strong>Hip joints</strong></td>
    <td>Normal joint spaces bilaterally; congruent articular surfaces</td>
  </tr>
  <tr>
    <td><strong>Femoral heads</strong></td>
    <td>Normal contour and density bilaterally</td>
  </tr>
  <tr>
    <td><strong>Sacroiliac joints</strong></td>
    <td>Normal; no widening or sclerosis</td>
  </tr>
  <tr>
    <td><strong>Pubic symphysis</strong></td>
    <td>Normal width and alignment</td>
  </tr>
  <tr>
    <td><strong>Soft tissues</strong></td>
    <td>Unremarkable</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal anteroposterior radiograph of the pelvis. No acute osseous abnormality.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Further imaging with CT or MRI if symptoms persist.')}
`.trim();

/* ---------- Abdominal Ultrasound ---------- */

const abdominalUltrasound = `
${section('CLINICAL HISTORY / INDICATION', 'Abdominal pain; evaluate abdominal organs.')}

${section('TECHNIQUE', 'Gray-scale and color Doppler ultrasonography of the abdomen.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Liver</strong></td>
    <td>Normal size and echogenicity; no focal lesion; smooth margins</td>
  </tr>
  <tr>
    <td><strong>Gallbladder</strong></td>
    <td>Normal wall thickness; no gallstones or sludge</td>
  </tr>
  <tr>
    <td><strong>Common bile duct</strong></td>
    <td>Not dilated</td>
  </tr>
  <tr>
    <td><strong>Pancreas</strong></td>
    <td>Normal size and echotexture; no ductal dilatation</td>
  </tr>
  <tr>
    <td><strong>Spleen</strong></td>
    <td>Normal size and echogenicity</td>
  </tr>
  <tr>
    <td><strong>Right kidney</strong></td>
    <td>Normal size and echogenicity; no hydronephrosis or calculus</td>
  </tr>
  <tr>
    <td><strong>Left kidney</strong></td>
    <td>Normal size and echogenicity; no hydronephrosis or calculus</td>
  </tr>
  <tr>
    <td><strong>Aorta</strong></td>
    <td>Normal caliber; no aneurysmal dilatation</td>
  </tr>
  <tr>
    <td><strong>Free fluid</strong></td>
    <td>None</td>
  </tr>
</table>

${section('IMPRESSION', 'Unremarkable abdominal ultrasound. No significant abnormality detected.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Follow-up imaging as clinically indicated.')}
`.trim();

/* ---------- Pelvic Ultrasound ---------- */

const pelvicUltrasound = `
${section('CLINICAL HISTORY / INDICATION', 'Pelvic pain or gynecologic evaluation.')}

${section('TECHNIQUE', 'Transabdominal pelvic ultrasonography. Transvaginal approach performed if applicable.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Uterus</strong></td>
    <td>Normal size, shape, and position; homogeneous myometrium</td>
  </tr>
  <tr>
    <td><strong>Endometrium</strong></td>
    <td>Normal thickness for phase of cycle</td>
  </tr>
  <tr>
    <td><strong>Right ovary</strong></td>
    <td>Normal size and echogenicity; no cystic or solid lesion</td>
  </tr>
  <tr>
    <td><strong>Left ovary</strong></td>
    <td>Normal size and echogenicity; no cystic or solid lesion</td>
  </tr>
  <tr>
    <td><strong>Adnexa</strong></td>
    <td>No adnexal mass bilaterally</td>
  </tr>
  <tr>
    <td><strong>Cul-de-sac</strong></td>
    <td>No free fluid</td>
  </tr>
  <tr>
    <td><strong>Bladder</strong></td>
    <td>Adequate filling; no wall thickening or intraluminal lesion</td>
  </tr>
</table>

${section('IMPRESSION', 'Unremarkable pelvic ultrasound. No significant pelvic pathology identified.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Follow-up as clinically indicated.')}
`.trim();

/* ---------- Whole-Abdomen Ultrasound ---------- */

const wholeAbdomenUltrasound = `
${section('CLINICAL HISTORY / INDICATION', 'Abdominal and pelvic symptoms; evaluate abdominal and pelvic organs.')}

${section('TECHNIQUE', 'Gray-scale and color Doppler ultrasonography of the whole abdomen including the pelvis.')}

<p><strong>FINDINGS — UPPER ABDOMEN</strong></p>
<table>
  <tr>
    <td><strong>Liver</strong></td>
    <td>Normal size and echogenicity; no focal lesion</td>
  </tr>
  <tr>
    <td><strong>Gallbladder</strong></td>
    <td>Normal wall thickness; no gallstones</td>
  </tr>
  <tr>
    <td><strong>Common bile duct</strong></td>
    <td>Not dilated</td>
  </tr>
  <tr>
    <td><strong>Pancreas</strong></td>
    <td>Normal size and echotexture</td>
  </tr>
  <tr>
    <td><strong>Spleen</strong></td>
    <td>Normal size and echogenicity</td>
  </tr>
  <tr>
    <td><strong>Right kidney</strong></td>
    <td>Normal size and echogenicity; no hydronephrosis or calculus</td>
  </tr>
  <tr>
    <td><strong>Left kidney</strong></td>
    <td>Normal size and echogenicity; no hydronephrosis or calculus</td>
  </tr>
  <tr>
    <td><strong>Aorta</strong></td>
    <td>Normal caliber</td>
  </tr>
</table>

<p><strong>FINDINGS — LOWER ABDOMEN / PELVIS</strong></p>
<table>
  <tr>
    <td><strong>Uterus</strong></td>
    <td>Normal size and position; homogeneous myometrium</td>
  </tr>
  <tr>
    <td><strong>Endometrium</strong></td>
    <td>Normal thickness</td>
  </tr>
  <tr>
    <td><strong>Ovaries</strong></td>
    <td>Normal size and echogenicity bilaterally; no cystic or solid lesion</td>
  </tr>
  <tr>
    <td><strong>Bladder</strong></td>
    <td>Normal wall; no intraluminal lesion</td>
  </tr>
  <tr>
    <td><strong>Free fluid</strong></td>
    <td>None</td>
  </tr>
</table>

${section('IMPRESSION', 'Unremarkable whole-abdomen ultrasound. No significant abnormality detected in the abdominal or pelvic organs.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Follow-up imaging as clinically indicated.')}
`.trim();

/* ---------- CT Scan — Head ---------- */

const ctScanHead = `
${section('CLINICAL HISTORY / INDICATION', 'Headache or neurologic symptoms; evaluate intracranial structures.')}

${section('TECHNIQUE', 'Axial CT images of the brain acquired without intravenous contrast at standard slice thickness.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Brain parenchyma</strong></td>
    <td>No focal hypodense or hyperdense lesion; gray-white matter differentiation preserved</td>
  </tr>
  <tr>
    <td><strong>Ventricles</strong></td>
    <td>Normal size and configuration; no hydrocephalus</td>
  </tr>
  <tr>
    <td><strong>Midline</strong></td>
    <td>No midline shift</td>
  </tr>
  <tr>
    <td><strong>Basal cisterns</strong></td>
    <td>Patent; no effacement</td>
  </tr>
  <tr>
    <td><strong>Sulci / gyri</strong></td>
    <td>Normal for age; no cortical atrophy</td>
  </tr>
  <tr>
    <td><strong>Extra-axial spaces</strong></td>
    <td>No subdural or epidural collection</td>
  </tr>
  <tr>
    <td><strong>Calvarium</strong></td>
    <td>Intact; no fracture</td>
  </tr>
  <tr>
    <td><strong>Visualized paranasal sinuses</strong></td>
    <td>Clear</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal non-contrast CT scan of the brain. No acute intracranial abnormality.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. MRI may provide additional characterization if clinically indicated.')}
`.trim();

/* ---------- CT Scan — Abdomen ---------- */

const ctScanAbdomen = `
${section('CLINICAL HISTORY / INDICATION', 'Abdominal pain or palpable mass; evaluate abdominal and pelvic organs.')}

${section('TECHNIQUE', 'Axial, coronal, and sagittal CT images of the abdomen and pelvis acquired with intravenous contrast during portal venous phase.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Liver</strong></td>
    <td>Normal size and attenuation; no focal lesion; homogeneous enhancement</td>
  </tr>
  <tr>
    <td><strong>Gallbladder</strong></td>
    <td>Normal wall thickness; no calculi or pericholecystic fluid</td>
  </tr>
  <tr>
    <td><strong>Bile ducts</strong></td>
    <td>Not dilated</td>
  </tr>
  <tr>
    <td><strong>Pancreas</strong></td>
    <td>Normal size and attenuation; normal pancreatic duct</td>
  </tr>
  <tr>
    <td><strong>Spleen</strong></td>
    <td>Normal size and attenuation</td>
  </tr>
  <tr>
    <td><strong>Adrenal glands</strong></td>
    <td>Normal bilaterally</td>
  </tr>
  <tr>
    <td><strong>Kidneys</strong></td>
    <td>Normal size, contour, and enhancement bilaterally; no hydronephrosis or calculus</td>
  </tr>
  <tr>
    <td><strong>Bowel</strong></td>
    <td>No wall thickening, dilatation, or obstruction</td>
  </tr>
  <tr>
    <td><strong>Mesentery / lymph nodes</strong></td>
    <td>No enlarged lymph nodes</td>
  </tr>
  <tr>
    <td><strong>Vascular structures</strong></td>
    <td>Aorta and major vessels patent; no aneurysm</td>
  </tr>
  <tr>
    <td><strong>Pelvis</strong></td>
    <td>Pelvic organs unremarkable; no free fluid or pelvic mass</td>
  </tr>
  <tr>
    <td><strong>Bony structures</strong></td>
    <td>No lytic or sclerotic lesion</td>
  </tr>
</table>

${section('IMPRESSION', 'Unremarkable contrast-enhanced CT scan of the abdomen and pelvis. No significant intra-abdominal pathology identified.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Follow-up imaging or laboratory correlation as clinically indicated.')}
`.trim();

/* ---------- MRI — Brain ---------- */

const mriBrain = `
${section('CLINICAL HISTORY / INDICATION', 'Headache or neurologic deficit; MRI brain for characterization.')}

${section('TECHNIQUE', 'Multiplanar MRI of the brain: axial T1-weighted, T2-weighted, FLAIR, and diffusion-weighted imaging (DWI/ADC). Gadolinium contrast administered.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Brain parenchyma</strong></td>
    <td>No abnormal T1 or T2/FLAIR signal intensity; no restricted diffusion on DWI</td>
  </tr>
  <tr>
    <td><strong>Enhancement</strong></td>
    <td>No abnormal enhancement following contrast administration</td>
  </tr>
  <tr>
    <td><strong>Ventricles</strong></td>
    <td>Normal size and morphology; no hydrocephalus</td>
  </tr>
  <tr>
    <td><strong>Midline</strong></td>
    <td>No midline shift; corpus callosum intact</td>
  </tr>
  <tr>
    <td><strong>Cerebellum</strong></td>
    <td>Normal signal and morphology</td>
  </tr>
  <tr>
    <td><strong>Brainstem</strong></td>
    <td>Normal signal intensity throughout</td>
  </tr>
  <tr>
    <td><strong>Extra-axial spaces</strong></td>
    <td>No subdural or epidural collection; no subarachnoid hemorrhage</td>
  </tr>
  <tr>
    <td><strong>Intracranial vessels (MRA, if included)</strong></td>
    <td>Normal flow voids; no aneurysm or significant stenosis</td>
  </tr>
  <tr>
    <td><strong>Calvarium and skull base</strong></td>
    <td>Intact; normal marrow signal</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal MRI of the brain with and without contrast. No acute intracranial abnormality.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Follow-up MRI or additional sequences as clinically indicated.')}
`.trim();

/* ---------- MRI — Spine ---------- */

const mriSpine = `
${section('CLINICAL HISTORY / INDICATION', 'Back or neck pain with or without radiculopathy; MRI spine for evaluation.')}

${section('TECHNIQUE', 'Multiplanar MRI of the lumbar spine: sagittal T1-weighted and T2-weighted, axial T2-weighted sequences. No contrast administered.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Vertebral alignment</strong></td>
    <td>Normal lordotic/kyphotic curvature; no anterolisthesis or retrolisthesis</td>
  </tr>
  <tr>
    <td><strong>Vertebral bodies</strong></td>
    <td>Normal height and signal intensity; no compression fracture or marrow edema</td>
  </tr>
  <tr>
    <td><strong>Disc spaces</strong></td>
    <td>Maintained disc heights and signal intensity at all levels visualized</td>
  </tr>
  <tr>
    <td><strong>Disc herniations</strong></td>
    <td>No disc protrusion, extrusion, or sequestration</td>
  </tr>
  <tr>
    <td><strong>Spinal canal</strong></td>
    <td>Adequate caliber throughout; no significant central canal stenosis</td>
  </tr>
  <tr>
    <td><strong>Spinal cord / conus</strong></td>
    <td>Normal position and signal intensity; conus terminates at normal level</td>
  </tr>
  <tr>
    <td><strong>Neural foramina</strong></td>
    <td>Patent bilaterally at all levels; no foraminal stenosis</td>
  </tr>
  <tr>
    <td><strong>Facet joints</strong></td>
    <td>No significant facet hypertrophy or effusion</td>
  </tr>
  <tr>
    <td><strong>Paraspinal soft tissues</strong></td>
    <td>Unremarkable</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal MRI of the lumbar spine. No disc herniation, significant stenosis, or nerve root compression identified.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Physical therapy and conservative management may be considered. Follow-up imaging if symptoms persist or worsen.')}
`.trim();

/* ---------- ECG ---------- */

const ecg = `
${section('CLINICAL HISTORY / INDICATION', 'Chest pain, palpitations, or pre-operative cardiac evaluation.')}

${section('TECHNIQUE', 'Standard 12-lead electrocardiogram (ECG) recorded at 25 mm/s and 10 mm/mV calibration.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>Rate</strong></td>
    <td>Within normal range (60–100 bpm)</td>
  </tr>
  <tr>
    <td><strong>Rhythm</strong></td>
    <td>Regular sinus rhythm</td>
  </tr>
  <tr>
    <td><strong>Electrical axis</strong></td>
    <td>Normal axis</td>
  </tr>
  <tr>
    <td><strong>P waves</strong></td>
    <td>Normal morphology and duration; upright in leads I, II, aVF</td>
  </tr>
  <tr>
    <td><strong>PR interval</strong></td>
    <td>Normal (120–200 ms)</td>
  </tr>
  <tr>
    <td><strong>QRS complex</strong></td>
    <td>Normal duration (&lt;120 ms); no bundle branch block; no delta wave</td>
  </tr>
  <tr>
    <td><strong>ST segment</strong></td>
    <td>Isoelectric in all leads; no ST elevation or depression</td>
  </tr>
  <tr>
    <td><strong>T waves</strong></td>
    <td>Upright and concordant; no T-wave inversion</td>
  </tr>
  <tr>
    <td><strong>QTc interval</strong></td>
    <td>Normal (&lt;440 ms in men; &lt;460 ms in women)</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal sinus rhythm. No acute ischemic changes or conduction abnormality.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Repeat ECG or further cardiac workup (e.g., 2D echo, Holter monitor) as clinically indicated.')}
`.trim();

/* ---------- 2D Echocardiogram ---------- */

const echo2d = `
${section('CLINICAL HISTORY / INDICATION', 'Cardiac evaluation; assess ventricular function and valvular anatomy.')}

${section('TECHNIQUE', '2D and M-mode echocardiography with color flow Doppler and pulsed/continuous-wave Doppler analysis.')}

<p><strong>FINDINGS</strong></p>
<table>
  <tr>
    <td><strong>LV size and systolic function</strong></td>
    <td>Normal; estimated ejection fraction (EF) ≥55%</td>
  </tr>
  <tr>
    <td><strong>LV diastolic function</strong></td>
    <td>Normal diastolic relaxation; no evidence of diastolic dysfunction</td>
  </tr>
  <tr>
    <td><strong>Wall motion</strong></td>
    <td>Normal; no regional wall motion abnormality</td>
  </tr>
  <tr>
    <td><strong>Left atrium (LA)</strong></td>
    <td>Normal size</td>
  </tr>
  <tr>
    <td><strong>Right ventricle (RV)</strong></td>
    <td>Normal size and systolic function; TAPSE within normal limits</td>
  </tr>
  <tr>
    <td><strong>Right atrium (RA)</strong></td>
    <td>Normal size</td>
  </tr>
  <tr>
    <td><strong>Mitral valve</strong></td>
    <td>Trileaflet; no significant stenosis or regurgitation</td>
  </tr>
  <tr>
    <td><strong>Aortic valve</strong></td>
    <td>Trileaflet; no stenosis or regurgitation</td>
  </tr>
  <tr>
    <td><strong>Tricuspid valve</strong></td>
    <td>Normal; trivial regurgitation within physiologic range</td>
  </tr>
  <tr>
    <td><strong>Pulmonary valve</strong></td>
    <td>Normal; estimated RVSP within normal limits</td>
  </tr>
  <tr>
    <td><strong>Aorta / aortic root</strong></td>
    <td>Normal caliber; no dilatation</td>
  </tr>
  <tr>
    <td><strong>Pericardium</strong></td>
    <td>No pericardial effusion</td>
  </tr>
  <tr>
    <td><strong>Interatrial / interventricular septum</strong></td>
    <td>Intact; no shunt flow on color Doppler</td>
  </tr>
</table>

${section('IMPRESSION', 'Normal 2D echocardiogram. Preserved left ventricular systolic function. No significant valvular or structural abnormality.')}

${section('RECOMMENDATIONS', 'Clinical correlation is advised. Repeat echocardiography or additional cardiac evaluation as clinically indicated.')}
`.trim();

/* ---------- Registry ---------- */

export const RIS_REPORT_PRESETS: RisReportPreset[] = [
  {
    id: 'ris-chest-xray',
    name: 'Chest X-Ray (PA)',
    description:
      'Standard posteroanterior chest radiograph report. Covers heart, lungs, mediastinum, bony thorax, and soft tissues.',
    template: chestXray,
  },
  {
    id: 'ris-pelvic-xray',
    name: 'Pelvic X-Ray (AP)',
    description:
      'Anteroposterior pelvis radiograph report. Covers pelvic ring, hip joints, femoral heads, sacroiliac joints, and pubic symphysis.',
    template: pelvicXray,
  },
  {
    id: 'ris-abdominal-ultrasound',
    name: 'Abdominal Ultrasound',
    description:
      'Gray-scale and Doppler upper abdominal ultrasound report. Covers liver, gallbladder, bile ducts, pancreas, spleen, kidneys, and aorta.',
    template: abdominalUltrasound,
  },
  {
    id: 'ris-pelvic-ultrasound',
    name: 'Pelvic Ultrasound',
    description:
      'Transabdominal (and transvaginal) pelvic ultrasound report. Covers uterus, endometrium, ovaries, adnexa, and cul-de-sac.',
    template: pelvicUltrasound,
  },
  {
    id: 'ris-whole-abdomen-ultrasound',
    name: 'Whole-Abdomen Ultrasound',
    description:
      'Combined upper abdominal and pelvic ultrasound report. Covers all abdominal and pelvic organs in a single study.',
    template: wholeAbdomenUltrasound,
  },
  {
    id: 'ris-ct-scan-head',
    name: 'CT Scan — Head (Non-contrast)',
    description:
      'Non-contrast axial CT brain report. Covers parenchyma, ventricles, midline, basal cisterns, extra-axial spaces, and calvarium.',
    template: ctScanHead,
  },
  {
    id: 'ris-ct-scan-abdomen',
    name: 'CT Scan — Abdomen and Pelvis (with contrast)',
    description:
      'Contrast-enhanced CT abdomen and pelvis report. Covers all major abdominal organs, bowel, lymph nodes, vasculature, and pelvis.',
    template: ctScanAbdomen,
  },
  {
    id: 'ris-mri-brain',
    name: 'MRI — Brain (with contrast)',
    description:
      'Multiplanar MRI brain with gadolinium report. Covers parenchyma, DWI, enhancement, ventricles, cerebellum, brainstem, and calvarium.',
    template: mriBrain,
  },
  {
    id: 'ris-mri-spine',
    name: 'MRI — Spine (Lumbar)',
    description:
      'Lumbar spine MRI report. Covers alignment, vertebral bodies, disc spaces, canal, cord/conus, neural foramina, and facet joints.',
    template: mriSpine,
  },
  {
    id: 'ris-ecg',
    name: 'ECG (12-lead)',
    description:
      'Standard 12-lead ECG report. Covers rate, rhythm, axis, P waves, PR interval, QRS, ST segment, T waves, and QTc.',
    template: ecg,
  },
  {
    id: 'ris-2d-echo',
    name: '2D Echocardiogram',
    description:
      'Comprehensive 2D echo with Doppler report. Covers LV/RV function, EF, wall motion, all four valves, pericardium, and septal integrity.',
    template: echo2d,
  },
];
