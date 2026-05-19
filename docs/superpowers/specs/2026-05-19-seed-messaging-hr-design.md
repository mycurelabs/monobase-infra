# Seed Upgrade — Messaging + HR Demo Data

**Date:** 2026-05-19
**Repos touched:** `monobase-mycure` (hapihub), `mycure-infra` (seed)
**Target environment:** mycure-preprod
**Status:** approved (verbal — Joff)

## Goal

Make `bun scripts/seed.ts --reset` produce a fully populated demo for the new
Messaging and HR modules so the Reports page and chat UI both have realistic
content the moment the seed completes.

- Chat: rich DM + GC fixtures with refs, mentions, reactions, pins; auto
  Announcement channels per branch.
- HR: realistic Mon–Fri operating-schedule data backdated to the previous and
  current calendar month, per-role shift schedules, breaks, station presence,
  so every Reports tile (KPIs, daily trend, heatmap, anomalies, payroll
  timesheet) has non-trivial content.

## Architecture

Two-PR sequence:

1. **PR-1 (hapihub)** — service-account-only override for clock timestamps
   (`startAt`, `endAt`, `expiresAt`). Three conditional gates in `clock.ts`,
   ships as hapihub `11.7.0`.
2. **PR-2 (mycure-infra)** — extends `scripts/seed.ts` with subscription
   `chat` patch, `seedHrSchedules()`, `seedHrClocks()`, `seedConversations()`.

Sequence: bump preprod hapihub → `11.7.0` first, then re-run the seed. The
seed asserts the override is honored before writing historical clocks and
fails fast if it isn't (so a misordered run can't silently produce all-today
clock data).

The seed remains pure-API — no direct Postgres dependency.

## §1 hapihub change (PR-1)

**File:** `services/hapihub/src/services/clock/clock.ts`

### Behaviour change

The `_create` before-hook currently does `data.startAt = new Date()`
unconditionally (~line 68). Gate that to allow service-account callers to
supply their own value:

```ts
const isServiceAccount = ctx.params?.user?.isServiceAccount === true;
if (!isServiceAccount || !data.startAt) {
  data.startAt = new Date();
}
```

Apply the same pattern to:

- `data.expiresAt = new Date(...)` (default-fill, ~line 101) — keep the
  12-hour default when service-account omits it.
- `data.endAt = new Date()` in the `_patch` before-hook (~line 312) —
  service-account PATCH can supply a historical `endAt`.

The cascade hook that closes child station / break clocks when a parent
attendance ends already reads `updated.endAt` and propagates it through; no
change needed there — backdated parent-close cascades correctly.

### Security

`isServiceAccount` is set by `accessTokenAuthorizer` from the better-auth
session record only when the user row has `isServiceAccount: true` in the
legacy accounts collection. This is exactly the same gate already used by:

- `DELETE /subscription/packages/:id`
- `POST /admin/remove-user`
- The platform-admin write paths for organizations.

No new auth surface is being introduced.

### Tests

Add to `services/hapihub/src/services/clock/clock.test.ts`:

```ts
it('clobbers startAt for non-service-account callers', async () => {
  const past = new Date('2026-04-15T08:00:00Z');
  const res = await create(
    { startAt: past, type: 'attendance', organization: orgId },
    { user: { uid: 'user-1', isServiceAccount: false } },
  );
  expect(res.startAt.getTime()).not.toBe(past.getTime());
  expect(res.startAt.getTime()).toBeCloseTo(Date.now(), -3);
});

it('preserves startAt for service-account callers', async () => {
  const past = new Date('2026-04-15T08:00:00Z');
  const res = await create(
    { startAt: past, type: 'attendance', organization: orgId },
    { user: { uid: 'svc-1', isServiceAccount: true } },
  );
  expect(res.startAt.getTime()).toBe(past.getTime());
});

it('preserves endAt for service-account PATCH', async () => {
  const created = await create(/* ... service-account ... */);
  const past = new Date('2026-04-15T17:00:00Z');
  const patched = await patch(created.id, { endAt: past }, {
    user: { uid: 'svc-1', isServiceAccount: true },
  });
  expect(patched.endAt.getTime()).toBe(past.getTime());
});
```

### Version + release

- Bump `services/hapihub/package.json` → `11.7.0`.
- Conventional commit: `feat(hapihub/clock): allow service-account timestamp overrides`.

## §2 Subscription `chat` flag + Announcements (PR-2)

### Package update

Add to `SEED_SUBSCRIPTION_PACKAGE.products` in `scripts/seed.ts`:

```ts
chat: { key: 'chat', type: 'feature', base: true },
```

Located alphabetically with the other feature flags (between `chatSupport`
and `lis`).

### Subscription patch

After the existing `seedSubscriptions()` PATCH-to-active, fire one more PATCH
per chain-root subscription:

```ts
await api('PATCH', `/subscriptions/${subId}`, { chat: true });
```

This false → true transition triggers `on-chat-enabled.ts` which:

- Upserts `announcement:<chainRootId>` conversation + `announcement:<branchId>`
  for every direct descendant branch (deterministic ids → idempotent).
- Upserts `reader` membership rows for every active org-member.

### Verification

Poll for up to 1 second (4×250ms) for the chain-root announcement
conversation to exist before declaring the subscription patch successful.

```ts
async function awaitAnnouncementChannel(chainRootId: string) {
  for (let i = 0; i < 4; i++) {
    const found = await api('GET',
      `/messaging/conversations?$limit=1&id=announcement:${chainRootId}`);
    if (found.data?.length) return;
    await sleep(250);
  }
  throw new Error(`announcement channel never materialized for ${chainRootId}`);
}
```

## §3 `seedHrSchedules()` — role-shaped shifts (PR-2)

Runs after `seedMemberships()` (needs membership ids), before clock seeding.

For every (user, branch-membership) pair, walk the role table:

| Role marker | Days (1-Mon … 7-Sun) | startTime | endTime | grace |
|---|---|---|---|---|
| Doctor (`doctor`, `pedia`, `familymd`, `doctor_pme`, `medical_head`) | 1–5 | 09:00 | 18:00 | 15 |
| Nurse (`nurse`, `nurse_head`) | 1–5 | 07:00 | 16:00 | 10 |
| Cashier / billing (`billing`, `cashier`, `frontdesk`) | 1–6 | 08:00 | 17:00 | 10 |
| Lab (`med_tech`, `lab_tech`, `lab_qc`) | 2–6 | 08:00 | 17:00 | 10 |
| Imaging (`radiologic_tech`, `imaging_tech`, `imaging_qc`) | 2–6 | 08:00 | 17:00 | 10 |
| Admin (`admin`, `clinic_manager`) | 1–5 | 08:00 | 17:00 | 15 |

Resolution rule: if a user has multiple role tags spanning rows, take the
**first matching row** in table order (Doctor → Nurse → Cashier → Lab →
Imaging → Admin). The superadmin and `service@mycure.md` accounts are
skipped (`continue`).

### POST shape

```ts
await api('POST', '/hr/schedules', {
  organization: branchOrgId,
  membership: membershipId,
  dayOfWeek,        // 1..6 (skip day 7 unless the role table has 7)
  startTime,        // "09:00"
  endTime,          // "18:00"
  graceMinutes,
  createdBy: serviceAccountId,
});
```

### Idempotency

Before creating, list existing schedules:

```ts
const existing = await api('GET',
  `/hr/schedules?organization=${branchOrgId}&membership=${membershipId}&$limit=100`);
for (const row of existing.data) {
  await api('DELETE', `/hr/schedules/${row.id}`);
}
```

then create the new rows.

## §4 `seedHrClocks()` — backdated Mon–Fri data (PR-2)

Runs after `seedHrSchedules()`. **Requires hapihub ≥ 11.7.0** (asserted; see
§6 Preflight).

### Date range

From the **first day of the previous calendar month** through **today** (in
PHT — `Asia/Manila`, UTC+08). Today's data is partial — current-time clocks
that look like they would be live, not closed shifts; see "today" sub-rule
below.

For mycure preprod, on 2026-05-19, that's: 2026-04-01 → 2026-05-19, ~34
weekdays.

### Per (user, branch-membership, weekday) — pick from role-shaped pattern

For each weekday in range, for each non-superadmin / non-service-account
membership that has a schedule for that day-of-week:

**1. Attendance clock**

```ts
const sched = scheduleFor(userRole, dayOfWeek);
const baseStart = combineLocal(weekday, sched.startTime, 'Asia/Manila');
const baseEnd   = combineLocal(weekday, sched.endTime,   'Asia/Manila');

// natural variance
const startJitterMin = uniformInt(-15, 30);                  // some early, some on-time, occasional minor late
const endJitterMin   = uniformInt(-15, 30);
let startAt = addMinutes(baseStart, startJitterMin);
let endAt   = addMinutes(baseEnd,   endJitterMin);

// 1-in-15 late arrival (45-90 min late) — feeds anomalies + late-count KPI
if (rng < 1/15) startAt = addMinutes(baseStart, uniformInt(45, 90));

// 1-in-25 unclosed shift — feeds "long shift" anomaly + open-clock-stale
if (rng < 1/25) endAt = null;

await api('POST', '/clock/clocks', {
  type: 'attendance',
  organization: branchOrgId,
  membership: membershipId,
  startAt: startAt.toISOString(),
  endAt:   endAt?.toISOString() ?? null,
});
```

For today (the current weekday), the rule is:
- If `now` ≥ `baseStart`, create the attendance with `startAt = baseStart`
  and `endAt = null` (it's still open — realistic).
- Otherwise skip — the user hasn't clocked in yet.

**2. Break clock** — only when attendance has a non-null `endAt`:

```ts
const breakStart = combineLocal(weekday, '12:00', 'Asia/Manila');
const breakEnd   = addMinutes(breakStart, 45);

await api('POST', '/clock/clocks', {
  type: 'break',
  organization: branchOrgId,
  membership: membershipId,
  parent: attendanceId,
  startAt: breakStart.toISOString(),
  endAt:   breakEnd.toISOString(),
  endReason: 'manual',
});
```

**3. Station clocks** — doctors only (`doctor`, `pedia`, `familymd`), 2–4
per shift:

Each doctor has a primary queue id (already seeded by the existing
`seedQueues()` step — reused). For 2–4 sequential station-presence rows
between `startAt + 30min` and `endAt − 30min`:

```ts
for (const slot of stationSlots) {
  await api('POST', '/clock/clocks', {
    type: 'station',
    organization: branchOrgId,
    membership: membershipId,
    parent: attendanceId,           // attendance clock id
    queue:  doctorQueueId,          // queue id from seedQueues
    startAt: slot.startAt.toISOString(),
    endAt:   slot.endAt.toISOString(),
  });
}
```

The transfer cascade in the create handler will close any previous open
station for the same membership when a new one opens — by passing explicit
`endAt`, the seed sidesteps that path entirely.

### Volume estimate

- 8 non-service-account users (skip superadmin + service)
- × ~3 branch memberships on average (parent + 2 branches)
- × ~34 weekdays
- × ~3 clocks/day (attendance + break + 0–2 stations averaged)

≈ **~2,400 clock rows**. At ~30 inserts/sec with the existing seed throttle
that's ~80 seconds — acceptable.

### Rollup trigger

After the writes, hit aggregate once per chain-root to fire `self-heal.ts`:

```ts
await api('GET',
  `/hr/aggregate?organization=${chainRootId}&period=this-month&tzOffsetMinutes=-480`);
await api('GET',
  `/hr/aggregate?organization=${chainRootId}&period=last-payroll&tzOffsetMinutes=-480`);
```

`self-heal` rebuilds `hr_daily_staff_summary` rows for past days as a
side-effect.

### Idempotency

Before any insert for a (membership, weekday), delete existing clocks:

```ts
const existing = await api('GET',
  `/clock/clocks?membership=${membershipId}&startAt[$gte]=${rangeStart}&startAt[$lt]=${rangeEnd}&$limit=200`);
for (const row of existing.data) {
  await api('DELETE', `/clock/clocks/${row.id}`);
}
```

(Sweeping the entire `[firstOfPrevMonth, today]` once per membership at the
top of the function is sufficient — no need to delete per-weekday.)

## §5 `seedConversations()` — rich chat fixtures (PR-2)

Runs after `seedSubscriptions()` (subscription must be `chat:true` first,
otherwise messaging endpoints 403). Runs per chain-root.

### Conversation set (per chain-root)

**6 DMs** — created by signing in as participant A, then POST
`/messaging/conversations { type: 'dm', participants: [A, B] }`. DM creation
is idempotent on the pair.

| A | B |
|---|---|
| `doctor@` | `nurse@` |
| `doctor@` | `pedia@` |
| `familymd@` | `nurse@` |
| `nurse@` | `cashier@` |
| `laboratory@` | `imaging@` |
| `doctor@` | `laboratory@` |

**3 GCs** — POST `/messaging/conversations { type: 'gc', title, participants }`.

| Title | Creator | Participants |
|---|---|---|
| "Doctors" | `doctor@` | doctor, pedia, familymd, admin |
| "Clinic Staff" | `admin@` | all 8 non-service-account users |
| "Lab + Imaging" | `laboratory@` | laboratory, imaging, doctor |

**Announcements** — auto-provisioned by the `on-chat-enabled` hook. The seed
just posts content to each branch's `announcement:<branchOrgId>` channel.

### Message content per conversation

15–30 messages per DM / GC, alternating senders. Drawn from a small canned
pool of clinical chat lines, e.g.:

```ts
const CHAT_LINES = [
  'Px in cubicle 2 ready for read',
  "Ms. Reyes' CBC came back, mild anemia",
  'Need a quick consult on the wound dressing in queue 3',
  'Heading to lunch, back at 1:00',
  'Imaging request for chest X-ray sent',
  'Endorsement for the afternoon shift — Bed 4 has pending labs',
  'Has the courier picked up the lab samples?',
  /* ~30 lines, no patient names that conflict with real demo patients */
];
```

Plus sprinkles (added once per conversation in fixed order so they're easy
to find for QA):

- **1 ref message** — pick the first seeded patient for the chain-root and
  send `content: [{ type: 'text', value: 'Looking at ' }, { type: 'ref',
  kind: 'patient', id: patientId }, { type: 'text', value: ' — any updates?' }]`.
- **1 mention** — `content: [{ type: 'mention', id: otherUserAccountId },
  { type: 'text', value: ' can you take this one?' }]`.
- **1 reply** — second message references the first via `replyTo`.
- **1 reaction (GCs only)** — POST `/messaging/messages/:id/react { emoji: '👍' }`
  after the first message lands.
- **1 pin (GCs only)** — POST `/messaging/conversations/:id/pin
  { messageId }` against the second message.

### Announcement content

One message per branch's announcement channel, posted by `admin@`:

```
"Welcome to <Branch Name>! Use this channel for org-wide notices."
```

### Idempotency

Re-runs should produce the same result. Approach:

1. List existing conversations for the chain-root by type:
   `GET /messaging/conversations?$limit=100`.
2. For each non-announcement conversation, list its messages and
   `DELETE /messaging/messages/:id` each one. Then `DELETE /messaging/conversations/:id`.
3. (Don't delete announcement convs — the hook owns those. Re-running the
   subscription patch is a no-op since `chat` is already `true`. To
   reset announcements: PATCH `chat: false` then `chat: true`. The seed
   will do this every run for cleanliness.)
4. Re-create DMs / GCs / messages as above.

### Sign-in shuffling

Existing seed plumbing has `signIn(email, password)` which sets
`sessionCookie`. Saving/restoring the service-account cookie around chat
seeding is straightforward (same pattern as the subscription-package
delete in `ensureSeedSubscriptionPackage()`).

## §6 Preflight & failure modes (PR-2)

Before running any historical clock writes:

```ts
async function assertServiceAccountTimestampOverride() {
  const probeStart = new Date('2025-01-15T08:00:00Z');
  const probe = await api('POST', '/clock/clocks', {
    type: 'attendance',
    organization: chainRootId,
    membership: anyMembershipId,
    startAt: probeStart.toISOString(),
  });
  await api('DELETE', `/clock/clocks/${probe.id}`);  // cleanup

  const got = new Date(probe.startAt).getTime();
  const want = probeStart.getTime();
  if (Math.abs(got - want) > 5000) {  // 5s tolerance for serialization
    throw new Error(
      `hapihub does not honor service-account startAt override. ` +
      `Bump hapihub to ≥ 11.7.0 in the target environment and retry.`
    );
  }
}
```

Call once at the top of `seedHrClocks()`. If the assertion trips, the seed
fails immediately with a clear message — no silent corruption.

## §7 Run order in `seed.ts`

Insert new steps at clearly-named call sites:

```
resetSeedData()                              [unchanged]
ensureSeedSubscriptionPackage()              [unchanged]
signUp/signIn all users                      [unchanged]
seedOrganizations()                          [unchanged]
seedMemberships()                            [unchanged]
seedQueues()                                 [unchanged]
seedPatients()                               [unchanged]
seedProductsAndServices()                    [unchanged]
seedSubscriptions()                          [unchanged: per-branch PATCH active]
  └── NEW: patchChatFlag(chainRootId)
  └── NEW: awaitAnnouncementChannel(chainRootId)
seedEncountersAndCharts()                    [unchanged]
NEW: seedHrSchedules()
NEW: seedHrClocks()
  └── assertServiceAccountTimestampOverride() FIRST
NEW: seedConversations()
postFlight()                                 [extend with HR aggregate probe + chat sign-in probe]
```

## §8 Verification (post-seed)

Augmented `postFlight()`:

1. Sign in as `service@mycure.md` → GET `/hr/aggregate?period=this-month&organization=<chainRoot>&tzOffsetMinutes=-480`.
   Assert: `kpis.totalHoursWorked > 0`; `timesheet.length >= 8` (one row per
   non-skipped user; chain-scoped report may show more if it expands per
   membership); heatmap has at least 5 non-zero cells.

2. Sign in as `doctor@mycure.test` → GET `/messaging/conversations`.
   Assert: returns at least 2 DMs, 2 GCs, 1 announcement per branch user
   is in.

3. Sign in as `admin@mycure.test` → GET `/messaging/conversations/{firstGcId}/messages`.
   Assert: pinned message present in response metadata; at least one
   reaction visible.

Failures here exit non-zero with a clear summary of what's missing.

## §9 Out of scope

- Backdated message timestamps (chat is intentionally today-fresh).
- HR settings page configuration (`config_hr` JSONB) — defaults are fine.
- philcare port — follow-up after mycure lands cleanly.
- HR Slice-3 features that aren't in 11.6.0 yet.

## Decisions log

| Decision | Why |
|---|---|
| Two-PR (hapihub + seed) over direct PG writes | Keeps the seed pure-API; matches existing seed plumbing. |
| Service-account-gated override (not unconditional) | Smallest API contract change; can't leak to clients. |
| Calendar-aligned date range (not rolling 60d) | Matches the `this-month` / `last-payroll` Reports filters exactly. |
| Backdated clocks via API (not direct PG) | One less ingredient in `scripts/seed.ts`. |
| Today's data: open attendance only | More realistic than fabricating a finished day before it's done. |
| Chat: 6 DMs + 3 GCs + auto-announcements | Exercises every conversation type. |
| Refs / mentions / reactions / pins one each | Covers UI affordances without bloating message volume. |
| Patching `chat: false → true` every reset | Cleanest re-run idempotency for Announcements. |
| Mycure first, philcare follow-up | Smaller blast radius, validate on one tenant first. |
