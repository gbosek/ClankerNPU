# AN7581 no-WiFi profile

This fork promotes `AN7581 + NOWIFI` to a first-class ClankerNPU build
for **any Airoha AN7581 platform that does not use the NPU WiFi datapath**.

It is deliberately not tied to Gemtek XG2010G. XG2010G is the first
planned validation platform because it provides a useful wired/PON test
case, but the firmware profile itself must remain SoC-wide.

## Build

```sh
make an7581-nowifi
```

Equivalent form:

```sh
make SOC=AN7581 WIFI=NOWIFI
```

Output:

```
build/AN7581_NOWIFI/
  firmware.elf
  firmware.map
  npu_rv32.bin
  npu_data.bin
```

## Design rule: SoC generic, board topology stays on the host

The AN7581 firmware may initialize and service SoC-level NPU, PPE and
NPU-bridge functions, but it must not assume a specific product's port
layout, PON front end, external switch, VLAN plan or WAN selection.

Those are provided by the Linux host driver and by the existing runtime
HWNAT mailbox parameters such as:

- `hwnat_wan_mode`
- `hwnat_wan_xsi`
- `hwnat_ae_wan_sel`
- `hwnat_xpon_hal_api_ng`

This keeps one AN7581 no-WiFi image usable on Ethernet-only gateways,
PON gateways and boards with different XSI/external-switch topology,
provided their host NPU ABI and AN7581 hardware revision are compatible.

## Initial feature set

`HAS_AN7581_NOWIFI` is defined when both `AN7581` and `NOWIFI` are
selected.

The initial variant intentionally:

- boots all eight AN7581 NPU harts;
- disables WiFi-specific NPU datapaths;
- preserves existing AN7581 PPE/HWNAT initialization;
- preserves AN7581 tunnel/NPU-bridge support;
- preserves mailbox ABI expected by the Linux `airoha_npu` host driver;
- does not enable the AN7583 GPON DBA implementation;
- does not hard-code XG2010G, EN7572, switch, XSI or WAN-port values.

## Expected hart map

With `AN7581 + NOWIFI`, all eight harts boot and perform common
initialization/self-test. After dispatch the current upstream behavior is:

| Hart | Current role |
|---:|---|
| 0 | NPU init, mailbox, PPE/HWNAT control, then debug/command loop |
| 1 | debug/command loop |
| 2 | timer interrupt + debug/command loop |
| 3 | package/capability check + debug/command loop |
| 4 | debug/command loop |
| 5 | debug/command loop |
| 6 | debug/command loop |
| 7 | AN7581 tunnel/NPU-bridge loop |

An idle hart is not disabled; it remains alive in the NDBG command loop
and is available for later measured, SoC-wide work.

## Compatibility boundary

A successful build does not by itself prove that every AN7581 product is
compatible. Before using a board, verify:

1. the Linux host uses the Airoha NPU mailbox ABI expected by this firmware;
2. the host loads the RV32 image and data image at the AN7581 locations;
3. the package/revision is accepted by the firmware capability table;
4. board-specific Ethernet/PON configuration is supplied by the host;
5. the first test is done with a recoverable RAM/initramfs path.

PON-specific behavior must not be inferred from the AN7583 DBA code.
For AN7581 products, bearer selection, GEM/T-CONT/LLID metadata and
service mapping belong to the actual host/PON stack for that platform.

## Development plan

### Stage 1 — compatibility

Keep behavior identical to generic upstream `AN7581 + NOWIFI` and
validate:

- all eight hart heartbeats;
- no NPU traps;
- mailbox/PPE initialization;
- ordinary Ethernet PPE hardware flow offload;
- board-specific host datapaths such as PON only after the basic path works.

### Stage 2 — generic telemetry

Add read-only NDBG telemetry for SoC-level state that is valid across
AN7581 boards:

- runtime HWNAT WAN parameters;
- PPE0/PPE1 control/parser/table state;
- QDMA/PPE port-selection state;
- NPU bridge channels/credits;
- hart profiler data.

Do not write board-specific registers in this stage.

### Stage 3 — measured optimization

Only after stock-vs-Clanker measurements identify a bottleneck, test
SoC-wide changes such as:

- PPE bind/ageing behavior;
- parser/ethertype coverage;
- flow-table occupancy/collision behavior;
- NPU-bridge channel worker distribution;
- L4S/tunnel path efficiency.

Ordinary routed/NAT traffic should stay in PPE hardware rather than be
redistributed across RISC-V harts merely to increase hart utilization.

## XG2010G as the first validation board

XG2010G is useful because its Linux 6.18 datapath can expose PPE BND/UNB,
QDMA and PON counters while ClankerNPU exposes the NPU side through
NDBG. It is a test platform, not a compile-time dependency.

Any XG2010G-specific integration, such as EN7572 service mapping or a
particular LuCI layout, should live in the XG2010G firmware/plugin tree,
not in this generic AN7581 no-WiFi firmware profile.
