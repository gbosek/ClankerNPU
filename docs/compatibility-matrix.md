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

## Validation levels

| Level | Evidence | Current result |
|---|---|---|
| Device identity | Device-tree compatibles and raw SoC ID reads | Collected on all three boards in the field record. |
| Stock host/firmware integration | Linux NPU driver probes and reports 1456.62 | Observed on all three boards. |
| Static Clanker capability match | Family/revision is represented in `chip_cap_query()` | Yes for revision 2 and revision 6. |
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
