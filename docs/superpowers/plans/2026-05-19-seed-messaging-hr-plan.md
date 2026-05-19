# Seed Upgrade — Messaging + HR Implementation Plan

> **For agentic workers:** Use this checklist to execute task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship hapihub 11.7.0 with a service-account batch-import path for `clock` plus extend `mycure-infra/scripts/seed.ts` to populate rich messaging + backdated HR data on every `--reset` run.

**Architecture:** Two-PR sequence. PR-1 (hapihub) gates `data.startAt = new Date()` and the membership auto-derivation on `isServiceAccount`, so service-account callers can supply `startAt` + `uid` + `membership` directly. PR-2 (mycure-infra) uses that override to seed ~2 months of weekday HR clock data, plus seeds DMs/GCs/messages via the standard authenticated API.

**Tech Stack:** TypeScript + bun (hapihub, seed), Helm + ArgoCD (preprod deploy), GHCR for image registry.

---

## Reference paths

**hapihub repo:** `/Users/centipede/Documents/workspace/work/mycure-prm-v1/`
- Modify: `services/hapihub/src/services/clock/clock.ts`
- Test: `services/hapihub/tests/e2e/clock/service.test.ts`
- Version: `services/hapihub/package.json`

**mycure-infra repo:** `/Users/centipede/Documents/workspace/work/infra-ai/mycure-infra/`
- Modify: `scripts/seed.ts`
- Values: `values/deployments/mycure-preprod.yaml`

---

## Part A — hapihub PR-1 (service-account override)

### Task A1: Extend clock service to support service-account batch import

**File:** `services/hapihub/src/services/clock/clock.ts`

In `createClock.processData`, gate the unconditional `data.startAt = new Date()` and the per-type membership/uid auto-derivation on `isServiceAccount`. When the caller is a service account AND has supplied `uid` + `membership` (and `parent` for station/break), trust the payload and skip the lookups.

- [ ] **Step 1:** Add test cases to `services/hapihub/tests/e2e/clock/service.test.ts`:

```ts
describe('clock createClock service-account batch import', () => {
  it('clobbers startAt for non-service-account callers', async () => {
    const past = new Date('2026-04-15T08:00:00Z');
    const res = await app.request({
      method: 'POST',
      url: '/clock/clocks',
      headers: { authorization: `Bearer ${regularUserToken}` },
      body: { type: 'attendance', organization: orgId, startAt: past.toISOString() },
    });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(new Date(body.startAt).getTime()).not.toBe(past.getTime());
  });

  it('preserves startAt + uid + membership for service-account callers', async () => {
    const past = new Date('2026-04-15T08:00:00Z');
    const end  = new Date('2026-04-15T17:00:00Z');
    const res = await app.request({
      method: 'POST',
      url: '/clock/clocks',
      headers: { authorization: `Bearer ${serviceAccountToken}` },
      body: {
        type: 'attendance',
        organization: orgId,
        uid: targetUserId,
        membership: targetMembershipId,
        startAt: past.toISOString(),
        endAt:   end.toISOString(),
      },
    });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(new Date(body.startAt).getTime()).toBe(past.getTime());
    expect(body.uid).toBe(targetUserId);
    expect(body.membership).toBe(targetMembershipId);
  });
});
```

- [ ] **Step 2:** Modify `src/services/clock/clock.ts` `createClock.processData`. Change the top of the function (after `const uid = …`) from:

```ts
data.startAt = new Date();
data.startedBy = uid;
```

to:

```ts
const isServiceAccount = ctx.params?.user?.isServiceAccount === true;
const isBatchImport = isServiceAccount && data.uid && data.membership;

if (!isServiceAccount || !data.startAt) {
  data.startAt = new Date();
}
data.startedBy = data.startedBy || uid;
```

Then for each `case` (`attendance`, `opening`, `availability`, `station`, `break`), wrap the existing membership-derivation block in `if (!isBatchImport) { … }`. Service-account batch-import payloads carry their own `uid`/`membership`/`parent` so the lookup + member-of-org check is skipped. Keep the `expiresAt` default-fill in the attendance branch (it's already a `if (!data.expiresAt)` guard).

- [ ] **Step 3:** Run the new tests:

```bash
cd /Users/centipede/Documents/workspace/work/mycure-prm-v1
bun test services/hapihub/tests/e2e/clock/service.test.ts
```

Expected: new test cases pass, existing tests still pass.

- [ ] **Step 4:** Commit:

```bash
cd /Users/centipede/Documents/workspace/work/mycure-prm-v1
git add services/hapihub/src/services/clock/clock.ts services/hapihub/tests/e2e/clock/service.test.ts
git commit -m "feat(hapihub/clock): service-account batch import for backdated clocks"
```

### Task A2: Bump hapihub to 11.7.0

- [ ] **Step 1:** Edit `services/hapihub/package.json` version from `11.6.0` → `11.7.0`. Same for any sibling packages that release in lockstep (apps/mycure, packages/sdk, etc. — match the previous release-bump commit `d101a805`).

- [ ] **Step 2:** Commit + push:

```bash
git add -A
git commit -m "chore(release): bump versions to 11.7.0"
git push origin main
```

- [ ] **Step 3:** Wait for GHCR build of `ghcr.io/mycurelabs/hapihub:11.7.0`. Poll:

```bash
TOKEN=$(gh auth token | base64)
while true; do
  curl -sS -o /dev/null -w "11.7.0 → %{http_code}\n" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    -H "Authorization: Bearer $TOKEN" \
    "https://ghcr.io/v2/mycurelabs/hapihub/manifests/11.7.0"
  sleep 30
done
```

Stop on 200.

---

## Part B — Infra deploy

### Task B1: Bump preprod hapihub → 11.7.0

- [ ] **Step 1:** Edit `mycure-infra/values/deployments/mycure-preprod.yaml`: hapihub `tag: "11.6.0"` → `"11.7.0"`.
- [ ] **Step 2:** Commit + push:

```bash
cd /Users/centipede/Documents/workspace/work/infra-ai/mycure-infra
git add values/deployments/mycure-preprod.yaml
git commit -m "chore: bump hapihub to 11.7.0 for preprod"
git push origin main
```

- [ ] **Step 3:** Hard-refresh root + child:

```bash
CTX=do-sgp1-mycure-doks-main
kubectl --context $CTX -n argocd annotate application mycure-preprod-root argocd.argoproj.io/refresh=hard --overwrite
sleep 18
kubectl --context $CTX -n argocd annotate application mycure-preprod-hapihub argocd.argoproj.io/refresh=hard --overwrite
kubectl --context $CTX -n mycure-preprod rollout status deployment/hapihub --timeout=240s
kubectl --context $CTX -n mycure-preprod get deploy hapihub -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Expected final image: `ghcr.io/mycurelabs/hapihub:11.7.0`.

---

## Part C — seed.ts changes (PR-2)

### Task C1: Add `chat: true` to SEED_SUBSCRIPTION_PACKAGE

**File:** `mycure-infra/scripts/seed.ts`

- [ ] **Step 1:** In `SEED_SUBSCRIPTION_PACKAGE.products`, insert alphabetically near `chatSupport`:

```ts
chat:                    { key: "chat",                    type: "feature", base: true },
```

### Task C2: `patchChatFlag()` + `awaitAnnouncementChannel()` helpers

- [ ] **Step 1:** In `seed.ts`, after `seedSubscriptions()` definition, add:

```ts
async function patchChatFlag(subscriptionId: string): Promise<void> {
  await api("PATCH", `/subscriptions/${subscriptionId}`, { chat: true });
}

async function awaitAnnouncementChannel(chainRootId: string): Promise<void> {
  for (let i = 0; i < 4; i++) {
    const found = await api("GET", `/messaging/conversations?id=announcement:${chainRootId}&$limit=1`);
    if ((found?.data ?? []).length > 0) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  console.warn(`⚠ announcement channel not yet materialized for ${chainRootId} — continuing anyway`);
}
```

- [ ] **Step 2:** In `seedSubscriptions()`, after the existing PATCH-to-active call for each chain-root, fire `patchChatFlag(subId)` then `await awaitAnnouncementChannel(chainRootId)`.

### Task C3: `seedHrSchedules()`

- [ ] **Step 1:** Add helper to map a user's role tags to a shift pattern:

```ts
type ShiftPattern = {
  dayOfWeek: number[];        // 1=Mon..7=Sun
  startTime: string;           // "09:00"
  endTime:   string;           // "18:00"
  graceMinutes: number;
};

function shiftForUser(user: SeedUser): ShiftPattern | null {
  if (isServiceAccount(user) || user.superadmin) return null;
  const r = new Set(user.roleIds);
  if (r.has('doctor') || r.has('doctor_pme') || r.has('pedia') || r.has('familymd') || r.has('medical_head')) {
    return { dayOfWeek: [1,2,3,4,5], startTime: '09:00', endTime: '18:00', graceMinutes: 15 };
  }
  if (r.has('nurse') || r.has('nurse_head')) {
    return { dayOfWeek: [1,2,3,4,5], startTime: '07:00', endTime: '16:00', graceMinutes: 10 };
  }
  if (r.has('billing') || r.has('cashier') || r.has('frontdesk') || r.has('billing_encoder')) {
    return { dayOfWeek: [1,2,3,4,5,6], startTime: '08:00', endTime: '17:00', graceMinutes: 10 };
  }
  if (r.has('med_tech') || r.has('lab_tech') || r.has('lab_qc')) {
    return { dayOfWeek: [2,3,4,5,6], startTime: '08:00', endTime: '17:00', graceMinutes: 10 };
  }
  if (r.has('radiologic_tech') || r.has('imaging_tech') || r.has('imaging_qc')) {
    return { dayOfWeek: [2,3,4,5,6], startTime: '08:00', endTime: '17:00', graceMinutes: 10 };
  }
  if (r.has('admin') || r.has('clinic_manager')) {
    return { dayOfWeek: [1,2,3,4,5], startTime: '08:00', endTime: '17:00', graceMinutes: 15 };
  }
  return null;
}
```

- [ ] **Step 2:** Add `seedHrSchedules()`:

```ts
async function seedHrSchedules(memberships: Memberships): Promise<void> {
  for (const [userEmail, perOrg] of Object.entries(memberships)) {
    const user = USERS.find((u) => u.email === userEmail);
    if (!user) continue;
    const pattern = shiftForUser(user);
    if (!pattern) continue;
    for (const { branchOrgId, membershipId } of perOrg) {
      // Idempotency: wipe existing schedules for this membership first.
      const existing = await api("GET", `/hr/schedules?organization=${branchOrgId}&membership=${membershipId}&$limit=100`);
      for (const row of (existing?.data ?? [])) {
        await api("DELETE", `/hr/schedules/${row.id}`).catch(() => {});
      }
      for (const dow of pattern.dayOfWeek) {
        await api("POST", "/hr/schedules", {
          organization: branchOrgId,
          membership:   membershipId,
          dayOfWeek:    dow,
          startTime:    pattern.startTime,
          endTime:      pattern.endTime,
          graceMinutes: pattern.graceMinutes,
        });
      }
    }
  }
}
```

Note: `Memberships` is the shape returned by `seedMemberships()` — confirm at execution-time and adjust the iteration shape. If memberships are keyed differently, adapt the loop.

### Task C4: `assertServiceAccountTimestampOverride()` preflight

- [ ] **Step 1:** Add:

```ts
async function assertServiceAccountTimestampOverride(probeOrgId: string, probeMembershipId: string, probeUid: string): Promise<void> {
  const past = new Date('2025-01-15T08:00:00Z');
  const probe = await api("POST", "/clock/clocks", {
    type: 'attendance',
    organization: probeOrgId,
    membership:   probeMembershipId,
    uid:          probeUid,
    startAt:      past.toISOString(),
    endAt:        new Date('2025-01-15T17:00:00Z').toISOString(),
  });
  try {
    const got = new Date(probe.startAt).getTime();
    const want = past.getTime();
    if (Math.abs(got - want) > 5000) {
      throw new Error(
        `hapihub does not honor service-account startAt override (got ${probe.startAt}, want ${past.toISOString()}). ` +
        `Bump hapihub to ≥ 11.7.0 in the target environment and retry.`
      );
    }
  } finally {
    await api("DELETE", `/clock/clocks/${probe.id}`).catch(() => {});
  }
}
```

### Task C5: `seedHrClocks()`

- [ ] **Step 1:** Add date-walking helpers:

```ts
const PHT_OFFSET_MIN = -480; // PHT is UTC+8 → -480 minutes WEST of UTC

function startOfPrevMonth(now: Date): Date {
  const d = new Date(now);
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() - 1);
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

function localPhtDateAt(year: number, monthIdx: number, day: number, hh: number, mm: number): Date {
  // Construct a Date whose UTC instant equals the desired PHT wall clock.
  // PHT = UTC + 8, so subtract 8h from the wall clock to get UTC.
  return new Date(Date.UTC(year, monthIdx, day, hh - 8, mm, 0, 0));
}

function* weekdaysBetween(start: Date, endInclusive: Date): Generator<Date> {
  const d = new Date(start);
  d.setUTCHours(0, 0, 0, 0);
  while (d.getTime() <= endInclusive.getTime()) {
    const dow = d.getUTCDay(); // 0=Sun..6=Sat
    // PHT day-of-week: since PHT is UTC+8, a date at UTC midnight is already
    // 08:00 PHT same day — safe to use UTC dow here.
    yield new Date(d);
    d.setUTCDate(d.getUTCDate() + 1);
  }
}

function uniformInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function parseHHMM(s: string): [number, number] {
  const [h, m] = s.split(':').map(Number);
  return [h, m];
}
```

- [ ] **Step 2:** Add the main loop:

```ts
async function seedHrClocks(memberships: Memberships, queues: QueuesByOrg): Promise<void> {
  // Find one (membership, uid, branchOrg) for the preflight probe.
  const anyEmail = USERS.find((u) => !isServiceAccount(u) && !u.superadmin && u.roleIds.includes('doctor'))?.email;
  const probeMembership = memberships[anyEmail!]?.[0];
  if (!probeMembership) throw new Error('No probe membership available for clock override preflight');
  const probeUid = userIdByEmail[anyEmail!];
  await assertServiceAccountTimestampOverride(probeMembership.branchOrgId, probeMembership.membershipId, probeUid);

  const now = new Date();
  const rangeStart = startOfPrevMonth(now);

  for (const [userEmail, perOrg] of Object.entries(memberships)) {
    const user = USERS.find((u) => u.email === userEmail);
    if (!user) continue;
    const pattern = shiftForUser(user);
    if (!pattern) continue;
    const uid = userIdByEmail[userEmail];
    const isDoctor = user.roleIds.some((r) => ['doctor', 'pedia', 'familymd', 'doctor_pme'].includes(r));

    for (const { branchOrgId, membershipId } of perOrg) {
      // Sweep existing clocks in range for idempotency.
      const existing = await api("GET",
        `/clock/clocks?membership=${membershipId}&$limit=500`);
      for (const row of (existing?.data ?? [])) {
        const t = new Date(row.startAt).getTime();
        if (t >= rangeStart.getTime() && t <= now.getTime()) {
          await api("DELETE", `/clock/clocks/${row.id}`).catch(() => {});
        }
      }

      for (const day of weekdaysBetween(rangeStart, now)) {
        const dow = ((day.getUTCDay() + 6) % 7) + 1; // 1=Mon..7=Sun
        if (!pattern.dayOfWeek.includes(dow)) continue;

        const [sh, sm] = parseHHMM(pattern.startTime);
        const [eh, em] = parseHHMM(pattern.endTime);
        const yy = day.getUTCFullYear(), mo = day.getUTCMonth(), dd = day.getUTCDate();
        const baseStart = localPhtDateAt(yy, mo, dd, sh, sm);
        const baseEnd   = localPhtDateAt(yy, mo, dd, eh, em);

        const startJitter = uniformInt(-15, 30);
        let startAt = new Date(baseStart.getTime() + startJitter * 60_000);
        let endAt: Date | null = new Date(baseEnd.getTime() + uniformInt(-15, 30) * 60_000);

        if (Math.random() < 1/15) startAt = new Date(baseStart.getTime() + uniformInt(45, 90) * 60_000);
        if (Math.random() < 1/25) endAt = null;

        // Skip future-of-now weekday entries; today gets an open attendance if the shift would have started already.
        const isToday = (day.getUTCFullYear() === now.getUTCFullYear()
                      && day.getUTCMonth()    === now.getUTCMonth()
                      && day.getUTCDate()     === now.getUTCDate());
        if (isToday) {
          if (startAt.getTime() > now.getTime()) continue; // user hasn't clocked in yet
          endAt = null;                                     // still open
        }

        const attRes = await api("POST", "/clock/clocks", {
          type: 'attendance',
          organization: branchOrgId,
          uid,
          membership: membershipId,
          startAt: startAt.toISOString(),
          endAt:   endAt?.toISOString() ?? null,
        });
        const attendanceId = attRes.id;

        if (endAt) {
          // Lunch break (45 min around 12:00 PHT)
          const brStart = localPhtDateAt(yy, mo, dd, 12, uniformInt(0, 30));
          const brEnd   = new Date(brStart.getTime() + 45 * 60_000);
          if (brStart.getTime() > startAt.getTime() && brEnd.getTime() < endAt.getTime()) {
            await api("POST", "/clock/clocks", {
              type: 'break',
              organization: branchOrgId,
              uid,
              membership: membershipId,
              parent: attendanceId,
              startAt: brStart.toISOString(),
              endAt:   brEnd.toISOString(),
              endReason: 'manual',
            });
          }

          // Stations (doctors only)
          if (isDoctor) {
            const doctorQueueId = queues[branchOrgId]?.byOwnerEmail?.[userEmail];
            if (doctorQueueId) {
              const numStations = uniformInt(2, 4);
              let cursor = new Date(startAt.getTime() + 30 * 60_000);
              const stationEnd = new Date(endAt.getTime() - 30 * 60_000);
              const stationSpan = (stationEnd.getTime() - cursor.getTime()) / numStations;
              for (let i = 0; i < numStations && cursor.getTime() < stationEnd.getTime(); i++) {
                const sStart = new Date(cursor);
                const sEnd   = new Date(cursor.getTime() + stationSpan);
                await api("POST", "/clock/clocks", {
                  type: 'station',
                  organization: branchOrgId,
                  uid,
                  membership: membershipId,
                  parent: attendanceId,
                  queue: doctorQueueId,
                  startAt: sStart.toISOString(),
                  endAt:   sEnd.toISOString(),
                });
                cursor = sEnd;
              }
            }
          }
        }
      }
    }
  }

  // Fire rollup self-heal for each chain-root.
  for (const chainRootId of Object.values(CHAIN_ROOT_BY_NAME)) {
    await api("GET", `/hr/aggregate?organization=${chainRootId}&period=this-month&tzOffsetMinutes=${PHT_OFFSET_MIN}`).catch(() => {});
    await api("GET", `/hr/aggregate?organization=${chainRootId}&period=last-payroll&tzOffsetMinutes=${PHT_OFFSET_MIN}`).catch(() => {});
  }
}
```

Note: `CHAIN_ROOT_BY_NAME`, `userIdByEmail`, and the exact shape of `memberships` / `queues` need to be adapted to the actual structures in `seed.ts`. At execution time, locate the equivalents and rename.

### Task C6: `seedConversations()`

- [ ] **Step 1:** Add the conversation set + canned message pool:

```ts
const CHAT_LINES = [
  'Px in cubicle 2 ready for read',
  "Ms. Reyes' CBC came back, mild anemia",
  'Need a quick consult on the wound dressing in queue 3',
  'Heading to lunch, back at 1:00',
  'Imaging request for chest X-ray sent',
  'Endorsement for the afternoon shift — Bed 4 has pending labs',
  'Has the courier picked up the lab samples?',
  'Found a duplicate chart for px Cruz — merging now',
  'Coming back from break, will pick up queue 2',
  'Lab results uploaded to chart MR-00231',
  'Quick sec — printer in cubicle 1 jammed again',
  'Will need extra hands for the morning rush tomorrow',
  'Px refused phlebotomy — flagged in encounter notes',
  'New PEME batch arrived — 12 walk-ins for the morning',
  'Doctor is running late, please advise patients',
];

const DM_PAIRS: Array<[string, string]> = [
  ['doctor@mycure.test',     'nurse@mycure.test'],
  ['doctor@mycure.test',     'pedia@mycure.test'],
  ['familymd@mycure.test',   'nurse@mycure.test'],
  ['nurse@mycure.test',      'cashier@mycure.test'],
  ['laboratory@mycure.test', 'imaging@mycure.test'],
  ['doctor@mycure.test',     'laboratory@mycure.test'],
];

type GcSpec = { title: string; creator: string; participants: string[] };
const GC_SPECS: GcSpec[] = [
  { title: 'Doctors',       creator: 'doctor@mycure.test', participants: ['doctor@mycure.test', 'pedia@mycure.test', 'familymd@mycure.test', 'admin@mycure.test'] },
  { title: 'Clinic Staff',  creator: 'admin@mycure.test',  participants: ['admin@mycure.test','doctor@mycure.test','pedia@mycure.test','familymd@mycure.test','nurse@mycure.test','cashier@mycure.test','laboratory@mycure.test','imaging@mycure.test'] },
  { title: 'Lab + Imaging', creator: 'laboratory@mycure.test', participants: ['laboratory@mycure.test','imaging@mycure.test','doctor@mycure.test'] },
];
```

- [ ] **Step 2:** Add seeder body:

```ts
async function seedConversations(chainRootId: string, patientIdForRef: string): Promise<void> {
  // Save current session (service account) to restore later.
  const savedSession = sessionCookie;

  try {
    // Sweep existing non-announcement conversations for idempotency.
    const existingConvs = await signInAndCall('admin@mycure.test', PASSWORD, async () => {
      return api("GET", "/messaging/conversations?$limit=100");
    });
    for (const conv of (existingConvs?.data ?? [])) {
      if (conv.type === 'announcement') continue; // hook owns these
      await api("DELETE", `/messaging/conversations/${conv.id}`).catch(() => {});
    }

    // --- DMs ---
    for (const [a, b] of DM_PAIRS) {
      await signIn(a, PASSWORD);
      const aUid = userIdByEmail[a];
      const bUid = userIdByEmail[b];
      const dm = await api("POST", "/messaging/conversations", {
        type: 'dm',
        participants: [aUid, bUid],
      });
      await postMessages(dm.id, [a, b], { withRef: patientIdForRef, withMention: bUid, withReply: true });
    }

    // --- GCs ---
    for (const spec of GC_SPECS) {
      await signIn(spec.creator, PASSWORD);
      const participantUids = spec.participants.map((e) => userIdByEmail[e]);
      const gc = await api("POST", "/messaging/conversations", {
        type: 'gc',
        title: spec.title,
        participants: participantUids.filter((u) => u !== userIdByEmail[spec.creator]),
      });
      const msgIds = await postMessages(gc.id, spec.participants, { withRef: patientIdForRef, withMention: participantUids[1], withReply: true });
      // Reaction
      if (msgIds[0]) {
        await api("POST", `/messaging/messages/${msgIds[0]}/react`, { emoji: '👍' }).catch(() => {});
      }
      // Pin
      if (msgIds[1]) {
        await api("POST", `/messaging/conversations/${gc.id}/pin`, { messageId: msgIds[1] }).catch(() => {});
      }
    }

    // --- Announcement per branch (the hook auto-creates the conv; we just post one welcome). ---
    await signIn('admin@mycure.test', PASSWORD);
    const announcements = await api("GET", "/messaging/conversations?type=announcement&$limit=20");
    for (const ann of (announcements?.data ?? [])) {
      await api("POST", `/messaging/conversations/${ann.id}/messages`, {
        content: [{ type: 'text', value: `Welcome to ${ann.title}. Use this channel for org-wide notices.` }],
      }).catch(() => {});
    }
  } finally {
    sessionCookie = savedSession;
  }
}

async function postMessages(
  conversationId: string,
  participantEmails: string[],
  opts: { withRef?: string; withMention?: string; withReply?: boolean },
): Promise<string[]> {
  const msgIds: string[] = [];
  const count = uniformInt(15, 28);
  let firstMsgId: string | undefined;
  for (let i = 0; i < count; i++) {
    const sender = participantEmails[i % participantEmails.length];
    await signIn(sender, PASSWORD);
    const content: any[] = [{ type: 'text', value: CHAT_LINES[i % CHAT_LINES.length] }];

    // Sprinkles, fixed positions for QA reproducibility.
    let body: any = { content };
    if (i === 0 && opts.withRef) {
      body.content = [
        { type: 'text', value: 'Looking at ' },
        { type: 'ref', kind: 'patient', id: opts.withRef },
        { type: 'text', value: ' — any updates?' },
      ];
    } else if (i === 1 && opts.withMention) {
      body.content = [
        { type: 'mention', id: opts.withMention },
        { type: 'text', value: ' can you take this one?' },
      ];
    } else if (i === 2 && opts.withReply && firstMsgId) {
      body.replyTo = firstMsgId;
    }

    const msg = await api("POST", `/messaging/conversations/${conversationId}/messages`, body);
    if (!firstMsgId) firstMsgId = msg.id;
    msgIds.push(msg.id);
  }
  return msgIds;
}
```

### Task C7: Wire into main flow + augment postFlight

- [ ] **Step 1:** In the main seed flow (the orchestration block after `seedSubscriptions()`), insert:

```ts
console.log("→ seeding HR schedules…");
await seedHrSchedules(memberships);
console.log("→ seeding HR clocks (this month + previous month)…");
await seedHrClocks(memberships, queuesByOrg);
console.log("→ seeding conversations…");
for (const [name, chainRootId] of Object.entries(CHAIN_ROOT_BY_NAME)) {
  const firstPatient = patientsByChainRoot[chainRootId]?.[0];
  await seedConversations(chainRootId, firstPatient);
}
```

- [ ] **Step 2:** Augment `postFlight()` with HR + chat probes (use service-account session for the first, target user for the rest):

```ts
console.log("→ post-flight: HR aggregate…");
const sampleRoot = Object.values(CHAIN_ROOT_BY_NAME)[0];
const agg = await api("GET", `/hr/aggregate?organization=${sampleRoot}&period=this-month&tzOffsetMinutes=${PHT_OFFSET_MIN}`);
const hours = agg?.kpis?.totalHoursWorked ?? 0;
console.log(`   kpis.totalHoursWorked = ${hours}`);
if (hours <= 0) throw new Error("post-flight: HR aggregate returned zero hours worked");

console.log("→ post-flight: messaging convs as doctor@mycure.test…");
await signIn('doctor@mycure.test', PASSWORD);
const convs = await api("GET", "/messaging/conversations?$limit=20");
const types = new Set((convs?.data ?? []).map((c: any) => c.type));
if (!types.has('dm') || !types.has('gc')) {
  throw new Error(`post-flight: doctor@ missing dm or gc convs — got types=${[...types].join(',')}`);
}
```

### Task C8: Commit + push seed

- [ ] **Step 1:** Commit:

```bash
cd /Users/centipede/Documents/workspace/work/infra-ai/mycure-infra
git add scripts/seed.ts
git commit -m "feat(seed): add backdated HR clocks/schedules + messaging fixtures"
git push origin main
```

---

## Part D — Run the seed against preprod

### Task D1: Run seed and verify

- [ ] **Step 1:** Run:

```bash
cd /Users/centipede/Documents/workspace/work/infra-ai/mycure-infra
bun scripts/seed.ts --api-url https://hapihub.preprod.localfirsthealth.com --reset
```

Expected: completes without throwing, post-flight prints non-zero hours and finds DM + GC convs.

- [ ] **Step 2:** Spot-check in the app — sign in as `doctor@mycure.test` / `Mycure123!`, navigate to HR → Reports (this month should be populated), then Chat (DMs + GCs + Announcements visible with content).

---

## Self-Review (writing-plans skill)

**Spec coverage:**
- §1 hapihub change → Task A1 (extended scope: also bypass auto-derivation, not just timestamp clobber — captured in plan).
- §2 chat flag + announcements → C1, C2.
- §3 schedules → C3.
- §4 backdated clocks → C5.
- §5 conversations → C6.
- §6 preflight → C4.
- §7 run order → C7.
- §8 verification → C7 step 2 + D1.
- §9 out of scope → no tasks (intentional).

**Placeholder scan:** the plan calls out two adapt-at-execution-time points (the exact shape of `memberships` / `queues` in seed.ts, and the existence of `userIdByEmail` / `CHAIN_ROOT_BY_NAME`). These are not lazy placeholders — the seed.ts is a ~6800-line file with established conventions and the right move is to mirror them rather than rename. Marked as "Note:" callouts inline.

**Type consistency:** `Memberships`, `QueuesByOrg`, `SeedUser`, `isServiceAccount`, `userIdByEmail`, `CHAIN_ROOT_BY_NAME` reference existing seed.ts symbols. Each new function uses the same patterns the existing code uses.
