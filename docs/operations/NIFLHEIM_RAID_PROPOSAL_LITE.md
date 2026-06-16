# Proposal (Budget Variant): Single-drive replacement + soft mirror for `hel.niflheim`

**For:** Management decision
**Prepared by:** Infrastructure team
**Date:** June 2026
**Decision needed by:** _TBD_
**Companion to:** [`NIFLHEIM_RAID_PROPOSAL.md`](NIFLHEIM_RAID_PROPOSAL.md) — full RAID proposal (₱33,000–36,500)

---

## TL;DR

The full RAID proposal is the right long-term answer. This document presents **budget alternatives**, for the case where management wants to extend the life of the existing hardware with a single targeted purchase instead of a 4-drive rebuild.

Three tiers are presented, in increasing order of cost and risk reduction:

| Tier | What it is | Cost | Survives 1 drive failure? | Reusable on RAID upgrade? |
|---|---|---:|:---:|:---:|
| ⚠️ Lite-0 | Bigger consumer SMR drive (same class as today) | **₱5,000 – 9,500** | No | **No (throwaway)** |
| Lite-1 | Single NAS-grade CMR drive | **₱9,700 – 10,500** | No | Yes |
| ⭐ **Lite-2 (recommended)** | NAS-grade CMR + nightly soft mirror | **₱10,000 – 11,000** | **Yes** (≤24 h RPO) | Yes |

The recommendation is **Lite-2** — for an extra ₱500–1,000 over Lite-1 you get real protection against the most likely real-world failure (one drive dying), and an extra ~₱1,000–5,000 over Lite-0 you stop spending money you will have to spend again when we eventually upgrade to RAID.

### Lite-2 (recommended budget option) at a glance

| Item | Number |
|---|---:|
| **One-time cost (all-in)** | **₱9,700 – ₱11,000** |
| Failure tolerance after change | 1 drive failure, with up to **24 h of data lag** on the surviving copy |
| Silent data corruption (bit-rot) detection | **No** (gap remains — same as today) |
| Usable capacity | 4 TB primary, 2 TB mirror (vs ~300 GB used today → multi-year runway) |
| Recurring cost | ₱0 |

This is **not equivalent** to the full RAID proposal. The gaps are deliberate and listed in [What this proposal does *not* fix](#what-this-proposal-does-not-fix).

---

## Why a budget variant exists

`hel.niflheim` currently stores everything on a **single consumer-grade SMR HDD** (Seagate Barracuda ST2000DM008). The full RAID proposal addresses three problems:

1. The drive is a single point of failure (SPOF)
2. It is SMR-class — wrong drive technology for sustained writes
3. Silent bit-rot is undetectable today

The full proposal solves all three for ₱33–36k. This budget variant solves **#1 and #2** for roughly ₱10k by relaxing the redundancy model from "atomic real-time RAID" to "nightly rsync mirror". The capacity question is moot in either proposal — current usage is **291 GB of 2 TB (~15%)**, so we have multi-year runway under any option.

If budget allows the full proposal, **the full proposal is still the recommendation.** This document exists to give management a defensible cheaper path, not to argue against the original.

---

## The three budget options

### ⚠️ Lite-0 — Rock-bottom: same drive class, larger capacity (NOT recommended, presented for completeness)

Buy the **same consumer SMR-class drive as today**, just bigger. Replace the existing 2 TB Seagate Barracuda with a 4 TB Seagate Barracuda (ST4000DM004) or equivalent consumer HDD. No UPS, no NAS-grade drive, no mirror.

| Item | Detail |
|---|---|
| What changes | Existing 2 TB consumer SMR replaced by a 4 TB consumer SMR (same drive family) |
| Failure model after change | **Same as today** — SPOF on a consumer SMR drive |
| What improves | Capacity only — 2 TB → 4 TB |
| Capacity after change | 4 TB |
| Cost all-in | **₱5,000 – ₱9,500** (drive only; street price varies wildly Shopee → Lazada) |
| Reusable in future RAID upgrade? | **No** — SMR drives are explicitly disqualified from any RAID array we would build. **This spend is throwaway** the moment we go to Lite-2 or the full proposal. |

**Why this is included:** if budget is rock-bottom and the only goal is "more storage now, defer everything else", this is the floor. We do not endorse it — the existing drive being SMR is one of the two structural problems the full proposal aims to fix, and Lite-0 keeps that problem in place. But it is the cheapest possible action that touches the host at all.

**When this would be considered:** absolutely cannot spend more than ~₱5–10k right now, AND the team accepts that we will pay this again later when we upgrade to a proper solution.

### Lite-1 — Single-drive replacement (CMR upgrade, no mirror)

Swap the existing SMR drive for one NAS-grade CMR drive. Keep the same single-disk architecture as today.

| Item | Detail |
|---|---|
| What changes | New 4 TB WD Red Plus replaces the 2 TB SMR Barracuda as the only data drive |
| Failure model after change | **Same as today**: one drive, one failure = all backups gone until manual restore from cloud |
| What improves | Drive is now NAS-grade CMR — much higher MTBF, designed for 24/7 sustained writes |
| Capacity after change | 4 TB (vs 2 TB today) |
| Cost all-in | **₱9,700 – ₱10,500** |

This is the absolute cheapest improvement that is actually worth doing. It still leaves the SPOF intact.

### ⭐ Lite-2 — Asymmetric soft-mirror (recommended budget option)

Add one NAS-grade CMR drive **alongside** the existing drive. The new drive becomes the primary backup target; the existing SMR drive becomes a nightly rsync mirror.

| Item | Detail |
|---|---|
| What changes | New 4 TB WD Red Plus becomes primary; existing 2 TB SMR becomes nightly rsync target |
| Failure model after change | Primary fails → 24 h-old mirror still readable. Mirror fails → primary unaffected. |
| What improves | SMR moved off the hot write path. SPOF replaced by "soft SPOF with 24 h RPO between copies". |
| Capacity after change | 4 TB primary (mirror capped at 2 TB — current usage 291 GB so this is fine for years) |
| Cost all-in | **₱10,000 – ₱11,000** |

The ₱500–₱1,000 delta over Lite-1 buys real protection against a single-drive failure, which is the most likely real-world incident.

---

## Decision matrix (lite variants vs. full proposal)

| Option | Layout | Drives | Usable | Failures tolerated | Bit-rot detection | Data lag on surviving copy | Reusable on RAID upgrade? | All-in cost |
|---|---|---|---:|:---:|:---:|:---:|:---:|---:|
| ⚠️ Lite-0 | Single consumer SMR replace | 1 × Seagate Barracuda 4 TB (SMR) | 4 TB | 0 | No | n/a (no mirror) | **No (throwaway)** | **₱5,000 – 9,500** |
| Lite-1 | Single CMR replace | 1 × WD Red Plus 4 TB | 4 TB | 0 | No | n/a (no mirror) | Yes (becomes a RAID drive) | **₱9,700 – 10,500** |
| ⭐ **Lite-2** | **Single + nightly rsync mirror** | **1 × WD Red Plus 4 TB + existing 2 TB** | **4 TB** | **1** | **No** | **up to 24 h** | **Yes (CMR drive becomes a RAID drive)** | **₱10,000 – 11,000** |
| Full **A** | RAID 1 mirror | 2 × WD Red Plus 4 TB | 4 TB | 1 | Yes (ZFS) | 0 (synchronous) | n/a (already RAID) | ₱19,000 – 22,000 |
| Full **C** (recommended in [full proposal](NIFLHEIM_RAID_PROPOSAL.md)) | ZFS RAIDZ2 | 4 × WD Red Plus 4 TB | 8 TB | **2** | **Yes** | 0 (synchronous) | n/a (already RAID) | ₱33,000 – 36,500 |

### How to read the "data lag" column

In Lite-2, the mirror is updated by a nightly cron job. If the primary drive fails at noon, the mirror contains last night's copy — so up to ~24 hours of mirror data is older than the primary at the moment of failure. In practice this matters very little for `hel.niflheim`:

- The host itself only receives **one cloud sync per day** anyway. The "data lag" is at most one missed daily sync.
- During a real-world recovery, the workflow falls back to the cloud copy (Tier-3) first; this on-prem host is the survivor-of-survivors scenario.

In Lite-1, there is no mirror — the column is "n/a" because the only protection is the cloud copy upstream.

In Full-A and Full-C, the mirror is updated synchronously by ZFS / mdadm — there is no lag.

---

## What this proposal does *not* fix

Honest disclosure for the decision-maker — relative to the full proposal:

| Gap | Practical impact | Mitigation if budget reaches the full proposal later |
|---|---|---|
| **No bit-rot detection** | Silent corruption on the primary drive over months/years could go undetected until a restore test fails. The existing weekly `rclone check` against the cloud bucket detects *most* of these but not all. | Full proposal uses ZFS, which scrubs and detects bit-rot automatically. |
| **24 h RPO between copies (not synchronous)** | If primary fails between mirror runs, mirror is up to one day stale. Acceptable for a tier-4 backup; not acceptable as a primary store. | Full proposal uses atomic RAID — both copies are always identical. |
| **Old SMR drive remains in service** | The mirror role is less write-intensive (rsync diffs) so SMR is acceptable here, but the drive itself is still aging consumer hardware. | Full proposal retires it entirely from the backup path. |
| **Survives only 1 drive failure, not 2** | Two simultaneous failures = total data loss on host (cloud copy still exists upstream). | Full proposal (Option C) survives 2 simultaneous failures via RAIDZ2. |
| **No ECC / no extra RAM** | RAM-induced corruption on the rsync host is possible but rare. | Full proposal includes a RAM upgrade. |

If management chooses Lite-2 today and the full proposal later, **the new 4 TB WD Red Plus from this proposal becomes one of the 4 drives in the full RAID build** — the spend is not wasted.

---

## Bill of materials (Lite-2 — recommended budget option)

| Item | Qty | PHP unit | Subtotal | Source |
|---|---:|---:|---:|---|
| WD Red Plus 4 TB NAS HDD (WD40EFPX) | 1 | ₱6,900 | ₱6,900 | [benson.ph](https://benson.ph/products/western-digital-wd-red-plus-nas-hard-drive-3-5-internal-drives), [pcworx.ph](https://pcworx.ph/products/western-digital-wd40efpx-68c6cn0-4tb-red-plus-3-5-sata-hdd), [dynaquestpc.com](https://dynaquestpc.com/products/western-digital-wd-red-plus-4tb-256mb-5400rpm-wd40efpx-hard-drive-for-nas) |
| APC Back-UPS BX650LI-MS 650VA AVR | 1 | ₱2,799 | ₱2,799 | [asianic.com.ph](https://asianic.com.ph/product/apc-backups-650va-bx650lims-230v-avr) |
| SATA III data cable, 0.5 m (with latch) | 1 | ~₱150 | ~₱150 | Shopee/Lazada |
| 3.5" mounting bracket | 1 | ~₱200 | ~₱200 | Shopee/Lazada |
| Cat6 patch cable, 2 m | 1 | ~₱150 | ~₱150 | Shopee/Lazada |
| **Lite-2 grand total** | | | **₱10,200 (typical) / ₱11,000 (worst case)** | |

The UPS is included because power-loss during a write is the most common real-world corruption event on a consumer desktop. It is not optional even on the budget variant.

### If choosing Lite-1 instead

Drop the existing drive entirely from the BOM and use only the new 4 TB drive. Cost: same minus ~₱200 in mounting hardware ≈ **₱9,700 – ₱10,500**.

### If choosing ⚠️ Lite-0 (rock-bottom) instead

| Item | Qty | PHP | Source |
|---|---:|---:|---|
| Seagate Barracuda 4 TB (ST4000DM004) — consumer SMR | 1 | ₱5,000 – 9,500 | [Shopee (search)](https://shopee.ph/list/seagate%20barracuda%204tb) · [Lazada (search)](https://www.lazada.com.ph/catalog/?q=seagate+barracuda+4tb) |

That is the entire BOM. No UPS, no mirror, no NAS-grade drive. Street price on Shopee resellers is typically ₱5,000–6,500; Lazada authorized retailers run ₱8,000–9,500. **This drive must be retired at the next RAID build** — it is not eligible for inclusion in either ZFS or mdadm arrays.

---

## Pre-purchase checklist

1. Open the chassis. **Confirm one free 3.5" drive bay** for the new drive (Lite-2 only).
2. Read the **PSU label** for wattage. Need ≥350 W to comfortably support 2 spinning HDDs plus existing components — almost certainly fine on any modern desktop PSU.
3. Confirm the **BIOS allows AHCI mode** for SATA (currently set to Intel "RAID mode"; switch to AHCI before the install).
4. Check whether **wired Ethernet (`enp3s0`) cabling is physically present** at the host — the nightly mirror runs faster over wired GbE than the current USB Wi-Fi.

---

## Implementation outline (Lite-2)

The existing setup script ([`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh)) handles the primary drive role unchanged. Only one new piece is added: a systemd timer that runs `rsync` from primary → mirror every night.

1. Receive the new drive and **burn-in test** (24–72 h) with `badblocks -wsv -b 4096 /dev/sdX`. RMA if it throws errors before going live.
2. Switch BIOS SATA mode "Intel RAID" → "AHCI".
3. Install the new drive, format as ext4 / XFS, mount at `/mnt/storage` (primary).
4. Remount the existing SMR drive at `/mnt/storage-mirror` (mirror).
5. Re-run the existing setup script pointed at the new primary:
   ```sh
   sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
     scripts/onprem-backup-setup.sh \
     --encryption=luks-partition --luks-device=/dev/disk/by-id/ata-WDC_WD40EFPX-... \
     --yes-wipe-device
   ```
6. Drop a small `/etc/systemd/system/mycure-backup-mirror-local.{service,timer}` pair that runs:
   ```sh
   rsync -aAX --delete /mnt/storage/ /mnt/storage-mirror/
   ```
   on a nightly schedule (after the cloud sync completes — chained off `mycure-backup-mirror.service`).
7. Run the first sync manually; verify the mirror is populated.
8. Optional but recommended: add a weekly Discord alert if the mirror's last successful run is more than 36 h old.

**Expected downtime to the backup function**: zero (the new drive is added alongside; the existing drive's role is changed but no data is removed). The full first cloud sync to the new primary takes one overnight cycle.

---

## Verification checklist

| Check | Command | Expected |
|---|---|---|
| New drive healthy after burn-in | `sudo smartctl -a /dev/sdX \| grep -i reallocated` | `0` reallocated sectors |
| Primary mounted and writable | `df -h /mnt/storage` | New 4 TB drive shown |
| Mirror mounted and writable | `df -h /mnt/storage-mirror` | Existing 2 TB drive shown |
| Cloud sync to primary works | `sudo systemctl start mycure-backup-mirror.service` then `du -sh /mnt/storage/spaces/` | Approximates upstream size |
| Local rsync to mirror works | `sudo systemctl start mycure-backup-mirror-local.service` then `du -sh /mnt/storage-mirror/spaces/` | Matches primary within last hour |
| Existing verify path still works | `sudo systemctl start mycure-backup-verify.service` | Exits 0, green Discord embed |
| Quarterly drill works | Execute either path in [`RESTORE_FROM_ONPREM.md`](RESTORE_FROM_ONPREM.md) against the latest snapshot | Postgres restores, row counts within 5% of production |
| Primary-failure drill | Unmount `/mnt/storage`, point restore at `/mnt/storage-mirror` instead | Restore succeeds from mirror copy |

---

## When the full proposal is the right choice anyway

Pick the full proposal over this one if any of these are true:

- The host will also store **Mongo or Postgres logical dumps** in addition to Velero mirror (capacity question changes).
- The host will be expanded to back up **additional clients** (DentaLemon, etc.) on top of mycure.
- Management wants **two-drive failure tolerance** explicitly (this proposal only survives one).
- Management wants **bit-rot detection** as a hard requirement.
- A formal **compliance or audit** asks for "RAID" by name.

---

## Related internal documentation

- [`NIFLHEIM_RAID_PROPOSAL.md`](NIFLHEIM_RAID_PROPOSAL.md) — full proposal (recommended; this document's companion)
- [`BACKUP_DR.md`](BACKUP_DR.md) — full 4-tier backup strategy and RPO/RTO targets
- [`ONPREM_BACKUP_SETUP.md`](ONPREM_BACKUP_SETUP.md) — how the on-prem mirror is set up
- [`RESTORE_FROM_ONPREM.md`](RESTORE_FROM_ONPREM.md) — how production data is recovered from this host
- [`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh) — host-side setup automation
