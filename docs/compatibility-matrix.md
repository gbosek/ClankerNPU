# AN7581 board compatibility matrix

This matrix separates SoC-family compatibility from board-level and live
firmware validation. A matching `compatible` string or capability-table row
is evidence for selecting a profile; it is not proof that ClankerNPU has booted
or that PPE/PON traffic is accelerated.

## Observed board identity

| Board | Device-tree compatibles | Raw IDs observed | Family/revision decoded by current source | Stock runtime observation | ClankerNPU status |
|---|---|---|---|---|---|
| XG-040G-TF | `nokia,xg-040g-tf-ubi`, `airoha,an7581`, `airoha,en7581` | `0x1FB00064=0x000E0000`; `0x1FB00284=0x0204B006` | Family 14, revision 6 | Linux 6.18.52 loads the vendor NPU firmware; boot log reports 1456.62. TF PON has reached O5. | Source capability-table row exists; ClankerNPU has not been run on the board. |
| XG-040G-MD | `nokia,xg-040g-md-ubi`, `airoha,an7581`, `airoha,en7581` | `0x1FB00064=0x000E0000`; `0x1FB00284=0x0204B006` | Family 14, revision 6 | Linux 6.18.52 loads the vendor NPU firmware; boot log reports 1456.62. | Source capability-table row exists; ClankerNPU has not been run. Recovery for experimental boot/flash is not established. |
| Gemtek XG2010G | `gemtek,xg2010g`, `airoha,an7581`, `airoha,en7581` | `0x1FB00064=0x000E0000`; `0x1FB00284=0x0404B002` | Family 14, revision 2 | Linux 6.18.52 loads vendor firmware 1456.62. One short Telecom PPPoE flow produced `[HW_OFFLOAD]` plus PPE BND/bind evidence; this was not repeatable yet. | Source capability-table row exists; ClankerNPU has not been run on the board. |

The user reports that 040GTF and 040GMD are nearly identical, with USB as the
main product difference. Treat USB and other board peripherals as host/DTS
differences unless testing shows an NPU ABI impact.

## What the source currently establishes

`npu_ppe.c::chip_cap_query()` identifies family 14 revision 2 and revision 6
in the existing table. The corresponding capability bytes are `0x1b` and
`0x03`; do not infer undocumented capability-bit meanings from those values.
The NOWIFI profile is intended to remain SoC-generic and does not encode the
XG2010G WAN/PON port map.

The devices share the `airoha,an7581` / `airoha,en7581` compatibles and the
observed stock firmware version, but they do **not** share one raw revision
value or one board topology. Host DTS, Ethernet/PON drivers, service mapping,
and runtime WAN selection remain board-specific.

## Dual-PPE capability versus live operation

The checked-in ImmortalWrt 6.18.52 patch series provides static evidence that
AN7581 is designed and handled as a two-PPE host platform:

- The EN7581/AN7581 SoC data sets `.num_ppe = 2` in
  `target/linux/airoha/patches-6.18/155-v7.2-net-airoha-Rename-get_src_port_id-callback-in-get_sp.patch`.
- PPE setup iterates over `eth->soc->num_ppe` and programs the per-PPE table
  base, hash seed, and flow configuration in
  `target/linux/airoha/patches-6.18/920-13-net-airoha-Rework-MTU-configuration.patch`.
- The SRAM FOE patches select the second PPE window for hashes at or above
  `PPE_SRAM_NUM_ENTRIES` and clear the calculated total SRAM entries in
  `099-06`, `099-07`, and `099-08`. ClankerNPU's `npu_ppe.c` independently
  contains family-14 PPE1 setup/teardown. Upstream commit `735529c` now sizes
  AN7581's ClankerNPU table to `0x4000` (16,384 total entries), splits at
  `0x2000`, and routes the upper half to PPE1 only when its control bit is
  active. These are source/build findings, not live tests.

They do **not** establish that PPE1 is enabled on a particular boot, receives
flows, or shares traffic with PPE0. The kernel has runtime PPE-enable checks,
and the actual engine/flow ownership must be observed. In the existing
XG2010G stock-firmware test, one short flow produced `[HW_OFFLOAD]` and two
PPE `BND` lines, but those lines were not attributed to PPE0 or PPE1; their
count cannot prove dual-engine use.

| Claim | Evidence available | Status |
|---|---|---|
| AN7581 host driver supports two PPE instances | `.num_ppe = 2` and per-instance setup loop in the source patch series | Source-confirmed |
| ClankerNPU AN7581 FOE sizing and PPE1 window routing | Commit `735529c`; local AN7581 NOWIFI build succeeds | Source/build-confirmed; not boot-tested |
| PPE0 and PPE1 were both enabled on the stock 1456.62 XG2010G boot | No engine-specific register/debugfs snapshot retained | Unknown |
| A live test flow used each PPE, or both handled traffic concurrently | BND lines lack recorded engine attribution/counter deltas | Not proven |

The PBS05 debugfs source now exposes `ppe0_enabled` / `ppe1_enabled` using the
same `airoha_ppe_is_enabled()` check the host datapath uses for
`PPE_GLO_CFG(i) & PPE_GLO_CFG_EN_MASK`. This change compiled into the new
040GMD-only initramfs FIT (SHA-256
`DB217444339B593FC075326A2AE21C66A40911B57FD65E860A7EFD721E4D6538`), but
that FIT has not been booted. The read-only `scripts/offload-snapshot.sh`
collector captures these flags together with the raw per-engine flow/table
configuration, GDM2 CPU-port selection, and global forwarding selectors.
Capture them at idle and during a uniquely identified test flow. An enabled
bit proves engine enablement only; actual flow use still requires
engine-attributed FOE ownership or distinct per-engine hit/packet counters.
Do not treat two BND rows as proof of two active engines.

The 8192 + 8192 table layout is a **capacity/table-routing** property, not a
throughput multiplier and not an enable switch. For runtime acceptance, collect
the driver's per-engine enable/config state and either an engine-attributed
FOE index or distinct PPE0/PPE1 hit/packet counters before and during uniquely
identified flows. Then repeat with concurrent flows and, separately, each
mwan3-selected WAN. Do not infer engine ownership from the number of `BND`
lines or from total table capacity.

## Validation levels

| Level | Evidence | Current result |
|---|---|---|
| Device identity | Device-tree compatibles and raw SoC ID reads | Collected on all three boards in the field record. |
| Stock host/firmware integration | Linux NPU driver probes and reports 1456.62 | Observed on all three boards. |
| Static Clanker capability match | Family/revision is represented in `chip_cap_query()` | Yes for revision 2 and revision 6. |
| ClankerNPU firmware/PBS05 test image | AN7581 NOWIFI compile, package hash match, isolated 040GMD initramfs FIT, FIT/profile/checksum validation | Build/package/image verified; not boot-tested and no sysupgrade image. |
| ClankerNPU boot/ABI | Live test with ClankerNPU and host-driver logs | Not yet demonstrated on any of the three boards. |
| PPE routed offload | Exact live flow correlates with hardware bind/counters and measured forwarding | One transient stock-firmware XG2010G flow observed; stable coverage not established. |
| Native bridge / IPTV multicast | Per-path live counters and traffic across the actual interfaces | Not accepted yet; see the deployment validation record. |

## Memory-window note

The field record reports a common reserved NPU firmware DRAM area at
`0x84000000..0x849fffff`. The ClankerNPU `FLOW_STATS_SETUP` implementation
currently advertises `0x84900000` as a 64 KiB window within that range. This
is source/build evidence only: runtime mapping, ownership, cache behavior and
counter updates still require on-board validation. Do not use these values as
permission to write memory from a shell or another host component.

For board roles, optical state, port mapping and current test evidence, see
[AN7581 deployment validation](an7581-deployment-validation.md).
Firmware loading and the PBS05/L2B update audit are recorded in
[PBS05 firmware and NPU integration notes](pbs05-npu-integration.md).

