# Proposal: RAID hardening of `hel.niflheim` — on-prem backup mirror

**For:** Management decision  
**Prepared by:** Infrastructure team  
**Date:** May 2026  
**Decision needed by:** _TBD_

---

## TL;DR

`hel.niflheim` is our **last-line backup of production data** (tier-4 of the [4-tier backup strategy](BACKUP_DR.md)). Today it stores everything on a **single consumer-grade HDD** that is also a documented SMR drive — the slowest, least reliable consumer category. If that one drive fails between weekly checks, the entire off-cloud safety net silently disappears until someone notices.

We recommend rebuilding the storage with **4 × WD Red Plus 4 TB drives in ZFS RAIDZ2** (Option C below).

| Item | Number |
|---|---:|
| **Recommended one-time cost (all-in)** | **₱33,000 – ₱36,500** |
| Failure tolerance after change | 2 simultaneous drive failures |
| Silent data corruption (bit-rot) detection | Yes (closes a gap noted in our existing weekly verify runbook) |
| Usable capacity | 8 TB (vs ~300 GB used today → ~5 years runway) |
| Recurring cost | ₱0 (electricity unchanged in any meaningful way) |

Three alternative budget tiers from ₱19,000 to ₱72,000 are presented in §[Decision matrix](#decision-matrix) for management's choice.

---

## The problem we are solving

`hel.niflheim` exists to survive scenarios where the primary cloud backup (DO Spaces `sgp1`) is unreachable or compromised. It pulls a 30-day rolling encrypted mirror of our Velero backup repository every night. Procedures for **restoring production data from this host** are documented in [`RESTORE_FROM_ONPREM.md`](RESTORE_FROM_ONPREM.md).

Two structural weaknesses exist today:

1. **Single point of failure (SPOF)**: all backup data lives on `/dev/sda` — one 2 TB Seagate Barracuda drive. No redundancy. A single mechanical or controller failure wipes the entire tier-4 backup until someone notices days later via Discord alerts.
2. **Wrong drive class for the job**: the existing drive is a Seagate Barracuda *ST2000DM008*, which is publicly documented as **SMR (Shingled Magnetic Recording)** — a consumer technology not designed for sustained writes or RAID rebuild workloads. It is unsuitable for inclusion in any future RAID array.

RAID protects against (1). Choosing the right new drives addresses (2). ZFS (the recommended software RAID stack) additionally catches **silent bit-rot** — the one failure mode our weekly `rclone check` cannot detect, as documented in [`ONPREM_BACKUP_SETUP.md` §Weekly Integrity Verification](ONPREM_BACKUP_SETUP.md#weekly-integrity-verification).

---

## Current state of `hel.niflheim` (verified May 2026)

| Item | Detail |
|---|---|
| Chassis | ASUS PRIME B365M-A — desktop tower |
| CPU | Intel i7-9700, 8 cores |
| RAM | 16 GB DDR4-2666, 1 of 4 DIMM slots used, non-ECC, max 64 GB |
| SATA ports | 6 onboard, 2 occupied, **4 free** |
| OS drive | 120 GB Kingston A400 SSD |
| Data drive (the problem) | 2 TB Seagate Barracuda ST2000DM008 — **SMR, single point of failure** |
| Network | 1 GbE wired NIC currently *down*; running over USB Wi-Fi |
| UPS | None |
| Current backup size | 291 GB (vs 1.8 TB available) |

Free chassis bays and PSU wattage need physical verification on-site before the PO is placed (see [Pre-purchase checklist](#pre-purchase-checklist)). The board can run the recommended setup; nothing in the existing chassis blocks this proposal.

---

## Decision matrix

All prices are PHP from actual Philippine retailers (Benson.ph, PCWorx, PCHub, Thinking Tools, Shopee, Lazada) verified **May 2026**. Drive class is **NAS-grade CMR** only — explicitly excluding WD Blue, WD Red WD20EFAX (SMR), and Seagate Barracuda. Allow ±10% movement for promos and exchange rate.

| Option | Layout | Drives | Usable | Failures tolerated | Bit-rot detection | All-in cost† |
|---|---|---|---:|:---:|:---:|---:|
| **A** — Minimum | RAID 1 mirror | 2 × WD Red Plus 4 TB | 4 TB | 1 | Yes (if ZFS) | **₱19,000 – 22,000** |
| **B** — Balanced RAIDZ2 | ZFS RAIDZ2 | 4 × WD Red Plus 2 TB | 4 TB | **2** | **Yes** | **₱24,500 – 27,500** |
| ⭐ **C** — Recommended | ZFS RAIDZ2 | 4 × WD Red Plus 4 TB | **8 TB** | **2** | **Yes** | **₱33,000 – 36,500** |
| **D** — Long horizon | ZFS RAIDZ2 | 4 × Seagate IronWolf 8 TB | 16 TB | 2 | Yes | **₱67,000 – 72,000** |
| ~~E~~ — Not recommended | RAID 5 / RAIDZ1 | 3 × WD Red Plus 2 TB | 4 TB | 1 | Yes (ZFS) | ₱20,000 – 22,000 |

† Includes drives + UPS (₱2,799) + 16 GB RAM stick (~₱2,200) + cables/brackets/Cat6. Excludes possible ₱1,500 hot-swap cage if chassis lacks bays (verify on-site).

### Cost-per-usable-TB

This is the figure that most clearly shows why **Option C is the value pick**:

| Option | Drive cost (PHP) | Usable TB | ₱ / usable-TB |
|---|---:|---:|---:|
| A | ₱13,800 | 4 | ₱3,450 |
| B | ₱19,000 | 4 | ₱4,750 |
| **C** | **₱27,600** | **8** | **₱3,450** |
| D | ~₱62,000 | 16 | ₱3,875 |

Option C delivers the same ₱/TB as the bare-minimum mirror **while also giving us 2-drive failure tolerance and bit-rot detection**.

### Why not the alternatives?

- **Option A** is the lowest sticker price but only survives one drive dying. The entire premise of having `hel.niflheim` is "what if the cloud fails *and* something else fails?" — accepting 1-drive tolerance on the last line of defense partly defeats that.
- **Option B** uses RAIDZ2 (good) but on small drives where the parity overhead makes capacity worse and ₱/TB worst-in-class. Only attractive if budget can't reach C.
- **Option D** is over-provisioned for current needs but would be the right answer if management wants this host to also hold Mongo / Postgres logical dumps, support additional clients (DentaLemon, etc.), or extend retention to 60–90 days.
- **Option E (RAIDZ1)** saves ~₱4,800 over B for the same capacity but halves failure tolerance. Modern ≥2 TB drive rebuilds carry a real risk of a second failure (URE / second-drive death during the long resync) — not worth the savings on a backup system.

---

## What we are actually buying (Option C bill of materials)

### Drives

| Item | Qty | PHP unit | Subtotal | Source |
|---|---:|---:|---:|---|
| WD Red Plus 4 TB NAS HDD (WD40EFPX) | 4 | ₱6,900 | **₱27,600** | [benson.ph](https://benson.ph/products/western-digital-wd-red-plus-nas-hard-drive-3-5-internal-drives) (alternates: [pcworx.ph](https://pcworx.ph/products/western-digital-wd40efpx-68c6cn0-4tb-red-plus-3-5-sata-hdd), [dynaquestpc.com](https://dynaquestpc.com/products/western-digital-wd-red-plus-4tb-256mb-5400rpm-wd40efpx-hard-drive-for-nas)) |

**Purchasing note**: buy from **two different sellers and request different production batches** (ship dates / serial-number ranges) to reduce the risk of correlated failure. Drives from the same batch sometimes fail close in time. Mixing in 1–2 Seagate IronWolf 4 TB drives (₱8,700 each) instead of all WD is acceptable and arguably safer.

### Supporting items (one-time, independent of RAID choice)

| Item | Qty | PHP | Why |
|---|---:|---:|---|
| APC Back-UPS BX650LI-MS 650VA AVR | 1 | ₱2,799 | Power loss during a sync is the most likely real-world corruption event on a 24/7 consumer-grade desktop. Lets the host shut down cleanly. Source: [asianic.com.ph](https://asianic.com.ph/product/apc-backups-650va-bx650lims-230v-avr) (authorized distributor). |
| Kingston Fury Beast 16 GB DDR4-2666 UDIMM | 1 | ~₱2,200 | Brings RAM from 16 → 32 GB. Improves ZFS cache during the weekly verify and the quarterly drill. |
| SATA III data cables, 0.5 m, with latch (pack of 5) | 1 pack | ~₱300 | Existing chassis ships with only 2 cables. |
| 3.5" drive mounting brackets / rails | up to 4 | ~₱200 ea | Quantity depends on chassis bay style; verify on-site. |
| Cat6 patch cable, 2 m | 1 | ~₱150 | Bring up the wired NIC; current Wi-Fi link is bottlenecking the nightly sync. |

### Conditional purchase

| Item | When needed | PHP |
|---|---|---:|
| 5.25" → 4× 3.5" hot-swap cage (Orico, Sama, etc. via Shopee) | Only if the chassis has fewer than 4 free 3.5" bays | ~₱1,500 |

### Option C grand total

| Best case (≥4 free 3.5" bays already) | **₱33,000 – 34,000** |
| Worst case (need hot-swap cage + extra brackets) | **₱36,500** |

---

## Pre-purchase checklist (on-site at the host)

Before placing the order — these answers tighten the BOM:

1. Open the chassis. **Count free 3.5" drive bays** (photograph).
2. Read the **PSU label** for wattage. Need ≥450 W to comfortably support 4 spinning HDDs plus existing components.
3. Confirm the **BIOS allows AHCI mode** for SATA (currently in Intel "RAID mode"; needs to be flipped before software RAID can be used safely).
4. Check whether **wired Ethernet (`enp3s0`) cabling is physically present** at the host — currently the wired NIC is "DOWN", possibly because of an unplugged cable.

---

## Implementation outline (post-approval, post-purchase)

Detailed commands and runbook live in [Appendix A](#appendix-a-technical-migration-detail). High-level steps:

1. **Receive and burn-in test** every new drive over 24–72 hours per drive. Pull and RMA any that throw bad sectors before going live — far better than discovering it during a real recovery.
2. Switch the BIOS from "Intel RAID mode" to AHCI.
3. Install ZFS, cryptsetup, SMART monitoring tools.
4. Build the encrypted ZFS pool on the four new drives.
5. Re-run the existing setup script ([`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh)) pointed at the new pool — it is idempotent and integrates cleanly.
6. Trigger a full re-sync of the ~291 GB current mirror to the new pool (one-time, runs overnight).
7. Retire the existing SMR drive from the backup role (it can stay in the chassis for other uses).
8. Schedule weekly ZFS scrub (built-in feature, sets itself up).

**Expected downtime to the backup function**: zero. The migration is done in parallel with the old setup. The first scheduled cloud sync after the new pool is live takes one cycle (overnight) to fully populate.

---

## Open follow-ups (separate decisions, not bundled here)

These are worth flagging to management but are *not* part of this proposal:

| Risk | Mitigation (cost) | Recommended next step |
|---|---|---|
| **OS drive is still a SPOF** (single 120 GB SSD; if it fails the host needs reinstall) | Mirror the OS to a second SSD (~₱1,200) | Consider as a small follow-up purchase; impact is "1 day of reinstall work", not data loss |
| **No off-site copy of the on-prem mirror** | A second host at a different physical site, or rotated cold drives in a fireproof safe | Larger conversation — worth doing eventually but RAID is the higher-impact fix today |
| **Board does not support ECC RAM** | A board + CPU swap (~₱15,000–25,000) | Likely not worth it — `hel.niflheim` is a non-authoritative mirror and the weekly verify catches any RAM-induced corruption |

---

## Appendices

### Appendix A: Technical migration detail

For the engineer executing the change:

1. `apt install smartmontools zfsutils-linux cryptsetup`
2. Reboot into BIOS, change SATA mode from "RAID" → "AHCI", verify existing OS still boots cleanly.
3. Burn-in every new drive: `badblocks -wsv -b 4096 /dev/sdX` (8 passes; 24–72 h per drive).
4. Build the encrypted pool:
   ```
   zpool create -o ashift=12 -O compression=lz4 -O atime=off \
     -O encryption=aes-256-gcm -O keyformat=passphrase \
     niflheim raidz2 /dev/disk/by-id/ata-WDC_WD40EFPX-...{a,b,c,d}
   zfs create niflheim/mycure-backup
   zfs set mountpoint=/mnt/niflheim/mycure-backup niflheim/mycure-backup
   ```
   **Use `/dev/disk/by-id/` paths**, not `/dev/sdX`, so the pool survives drive re-enumeration on reboot.
5. Re-run the existing tier-4 setup script:
   ```
   sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
     scripts/onprem-backup-setup.sh \
     --encryption=none \
     --backup-dir=/mnt/niflheim/mycure-backup
   ```
   `--encryption=none` because ZFS native encryption (set in step 4) already covers data-at-rest. The script is idempotent.
6. Trigger first full sync: `sudo systemctl start mycure-backup-mirror.service` and monitor via `journalctl --namespace=mycure-backup -u mycure-backup-mirror.service -f`.
7. Retire `/dev/sda` from the backup role. Existing `/mnt/storage/{Backup,dump,dump-mo,dump-pg,mycure-v4}` content can remain on it or be moved into the pool — orthogonal decision.
8. Enable weekly scrub: `systemctl enable --now zfs-scrub-weekly@niflheim.timer`.

### Appendix B: Verification checklist

| Check | Command | Expected |
|---|---|---|
| Pool healthy | `zpool status niflheim` | `state: ONLINE`, all 4 drives present, 0 errors |
| Capacity sensible | `zfs list niflheim` | `AVAIL` ≈ 8 TB minus ~5% ZFS overhead |
| Bit-rot detection live | `zpool scrub niflheim; zpool status -v` | Completes with `0 errors` |
| Mirror service functional | `sudo systemctl start mycure-backup-mirror.service` then `du -sh /mnt/niflheim/mycure-backup/spaces/` | Approximates upstream size after first run |
| Existing verify path still works | `sudo systemctl start mycure-backup-verify.service` | Exits 0, green Discord embed |
| Quarterly drill works | Execute either path in [`RESTORE_FROM_ONPREM.md`](RESTORE_FROM_ONPREM.md) against the latest snapshot | Postgres restores, row counts within 5% of production |
| Single-drive failure drill | `zpool offline niflheim <one-drive-id>` then re-run mirror + verify | Pool stays online, both services succeed |

### Appendix C: PH retailer source links (verified May 2026)

| Store | URL | Notes |
|---|---|---|
| Benson.ph | <https://benson.ph/products/western-digital-wd-red-plus-nas-hard-drive-3-5-internal-drives> | Lowest WD Red Plus prices observed across capacities |
| PCWorx | <https://pcworx.ph/products/seagate-st2000vn003-2tb-ironwolf-hard-disk-drive> | Stock in Muntinlupa + Pampanga |
| Thinking Tools | <https://shop.tti.com.ph/?s=ironwolf&post_type=product> | IronWolf 8 TB (Cebu) — link is search; specific SKU URLs rotate |
| DynaQuest PC | <https://dynaquestpc.com/products/western-digital-wd-red-plus-4tb-256mb-5400rpm-wd40efpx-hard-drive-for-nas> | Carries WD40EFPX (status varies) |
| Asianic Distributors | <https://asianic.com.ph/product/apc-backups-650va-bx650lims-230v-avr> | APC authorized distributor for the recommended UPS |
| Lazada PH | <https://www.lazada.com.ph/tag/wd-red-plus/> | Spot-buy cables, brackets, RAM, Cat6 cable |
| Shopee PH | <https://shopee.ph/list/apc%20650va%20ups> | Same as Lazada; verify seller rating |

### Appendix D: Related internal documentation

- [`BACKUP_DR.md`](BACKUP_DR.md) — full 4-tier backup strategy and RPO/RTO targets
- [`ONPREM_BACKUP_SETUP.md`](ONPREM_BACKUP_SETUP.md) — how the on-prem mirror is set up (the setup script this proposal preserves)
- [`RESTORE_FROM_ONPREM.md`](RESTORE_FROM_ONPREM.md) — how production data is recovered from this host
- [`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh) — host-side setup automation
- [`scripts/onprem-backup-restore.sh`](../../scripts/onprem-backup-restore.sh) — Path-B restore helper
