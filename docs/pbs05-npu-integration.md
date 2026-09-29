# PBS05 firmware and NPU integration notes

Status: source/build audit, 2026-09-29. The pre-existing dirty PBS05 checkout
was preserved untouched; test integration is isolated in the separate
`ponwrt-pbs05-latest` tree. No router was flashed or booted during this audit.

## Host firmware loading on AN7581

The checked-out ImmortalWrt AN7581 target enables the NPU node through
`an758x-nokia_xg-040g-common.dtsi`. The XG2010G DTS includes that common board
file. These boards do not override `firmware-name`, so the Linux Airoha NPU
driver uses its built-in EN7581 defaults:

```text
/lib/firmware/airoha/en7581_npu_rv32.bin
/lib/firmware/airoha/en7581_npu_data.bin
```

The AN7581 target's `DEFAULT_PACKAGES` includes
`airoha-en7581-npu-firmware`; the XG2010G device-specific package list does
not need to repeat it. The firmware-name kernel patch permits a board DTS to
select another pair, and the direct-load patch requests those files from the
mounted firmware filesystem. This explains why absence from the device's
`/lib/firmware` listing alone was not enough to conclude how its running
1456.62 image was delivered: the running field image may use a different
image/driver integration than this source checkout.

## Safe Clanker test-image design

Keep the production device profile and stock firmware package unchanged.
For a test image, use a separate device profile/DTS and a separate firmware
package that installs unique paths, for example:

```text
/lib/firmware/airoha/en7581_clanker_npu_rv32.bin
/lib/firmware/airoha/en7581_clanker_npu_data.bin
```

The test DTS should set its two-entry `firmware-name` property to those paths.
The existing stock files can then remain installed as the known rollback
baseline without a filename collision. Start with the spare 040GMD on a
recoverable RAM/initramfs path; do not replace a production image or flash
NAND until firmware loading, mailbox/telemetry, PPE initialization, forwarding,
and recovery have all been demonstrated.

The test DTS selects those exact paths; the stock names and package remain
available as the rollback baseline. GitHub Actions run
[36559144364](https://github.com/gbosek/ClankerNPU/actions/runs/36559144364)
built commit `da0d0dc7fdd0bf5f83110f7258aecfcaba2fb69f` successfully after the
complete `npu_ppe.c` was restored. Its artifact contains a 30,672-byte RV32
binary and a 128-byte data binary with version string
`TLB7.8.0.0_v003.NOWIFI.da0d0dc`.

The PBS05 test package pins the two CI artifact hashes and fails its build if
they differ. The package and the 040GMD-only initramfs profile were rebuilt,
then the two Clanker files were extracted from the kernel-bundled
`initramfs_data.cpio`; their hashes matched the CI artifact exactly:

```text
npu_rv32.bin: 23f17dfd65a324e127a0d6c49a690b9214ee1055d3cbcccc63f920278e1e55ff
npu_data.bin: a0ca04c5cbec29f05beafc7325d4b981fb001f09bda28c6b18b87dae7989ec6e
ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-clanker-test-initramfs.itb
SHA-256: 64b998dddff182b5048163f2c3aebd00af7baee25d16d78ac20ca549e33068a7
Kernel: Linux 6.18.52; FIT includes the test DTS and kernel-bundled initramfs
```

The profile metadata and SHA-256 manifest validate, and the generated DTB
contains the two ClankerNPU firmware paths above. This establishes
build/package/image integration only, not mailbox ABI compatibility, a
successful device boot, or a recovery path. The profile intentionally emits
no sysupgrade/NAND image. No router has been flashed or booted with it.

## Dual-PPE finding

The Linux EN7581 host driver advertises two PPE instances (`.num_ppe = 2`)
and initializes per-instance registers. ClankerNPU now includes upstream
commit [`735529c`](https://github.com/ClankerConstruction/ClankerNPU/commit/735529c10d5120e10f7e4a6ddf97fb384fce9903): on AN7581, the FOE table is
16,384 entries total, split at index `0x2000`; the upper half is written and
cleared through the PPE1 register window when PPE1's control bit is already
active. That gives 8,192 entries per PPE when both are enabled. The size and
table-mode register fields follow the stock image's arrangement; the patch
does not itself enable PPE1. Other SoC builds retain their existing table
size. The upstream change was applied locally and the AN7581 NOWIFI firmware
compiled, but engine-specific runtime counters and flow ownership still need
to be measured before claiming both PPEs handle traffic.

## PBS05 update audit

The latest fetched `pbs05/ponwrt` `master` was `c3b518ba` on 2026-09-29.
Relevant changes:

- [`e4d0908` (merged by PR #14)](https://github.com/pbs05/ponwrt/commit/e4d0908bb0)
  adds the native Airoha L2B FOE-entry layout
  fix. The local worktree's untracked `930-net-airoha-fix-native-l2b-entry-layout.patch`
  has the same Git blob hash as the file now tracked by PBS05, so do not add a
  duplicate copy when moving to the updated source.
- [`c3b518b`](https://github.com/pbs05/ponwrt/commit/c3b518baec8ed0cc5a353327fa154f38bde1e6c0)
  updates the firewall4 bridge-flowtable patch to discover Linux
  bridge member ports and resolve VLAN bridge ports to lower devices. This
  may make more transparent L2 traffic eligible for a bridge flowtable, but
  it still depends on kernel/PPE support and does not prove hardware offload.
- The local PBS05 checkout is a shallow tree at `18d7b410` with numerous
  modified and untracked files. Its current working tree has the bridge
  flowtable patch removed from the active patch directory and retained under
  `patches-disabled`; it must not be silently re-enabled. The refreshed remote
  also contains a large official-source history merge, so its reported 76001
  commit gap is not a sensible direct-pull plan. Keep this checkout intact;
  use a clean updated source tree and port only reviewed local customizations
  when building against the latest PBS05 base.

The bridge-flowtable update is relevant to the requested L2 bridge testing;
the native L2B patch is relevant to LAN-to-LAN forwarding. Neither changes
the stock 1456.62 NPU firmware, enables both PPEs by itself, nor implements
PON/IPTV multicast replication.

## PPE-enable diagnostic rebuild (2026-09-29)

The isolated PBS05 build tree adds `ppe0_enabled` and `ppe1_enabled` to
`/sys/kernel/debug/ppe/config`, using the driver's existing
`airoha_ppe_is_enabled(eth, i)` helper (the per-engine `PPE_GLO_CFG` enable
bit). The read-only `scripts/offload-snapshot.sh` collector now records both
fields. Linux 6.18.52 `target/linux/compile` and `target/linux/install`
completed, and the MD-only initramfs FIT was rebuilt and structurally checked:

```text
ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-clanker-test-initramfs.itb
SHA-256: 64b998dddff182b5048163f2c3aebd00af7baee25d16d78ac20ca549e33068a7
```

The current artifact is in the local
`artifacts/pbs05-an7581-clanker-test-2026-09-29-da0d0dc-ppe-diag/`
directory. Its resolved kernel configuration has
`# CONFIG_NET_AIROHA_FLOW_STATS is not set`, so this image does not exercise
the function-4 flow-statistics handshake. The enable flags also prove only
engine enablement, not flow ownership or traffic handling. The FIT has not
been booted; no router was modified, and the existing stock 1456.62 image
remains the baseline.

