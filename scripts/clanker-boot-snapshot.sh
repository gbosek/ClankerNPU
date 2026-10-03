#!/bin/sh
# Read-only first-boot gate for the AN7581 NOWIFI ClankerNPU image.
# It reads the fixed NDBG SRAM block, kernel logs and PPE debugfs state.
set -u

NDBG_BASE=0x1e906800
NDBG_HART_BASE=0x1e906880
EXPECTED_MAGIC=0x4e444247
EXPECTED_HARTS=8
EXPECTED_VERSION_WORDS="0x544c4237 0x2e382e30 0x2e305f76 0x3030332e 0x4e4f5749 0x46492e64 0x61306430 0x64630000"
EXPECTED_RV32_SHA256=23f17dfd65a324e127a0d6c49a690b9214ee1055d3cbcccc63f920278e1e55ff
EXPECTED_DATA_SHA256=a0ca04c5cbec29f05beafc7325d4b981fb001f09bda28c6b18b87dae7989ec6e

failures=0
unknowns=0

lower()
{
	printf '%s' "$1" | tr 'A-F' 'a-f'
}

read32()
{
	devmem "$1" 32 2>/dev/null
}

addr()
{
	printf '0x%08x' "$1"
}

tag_name()
{
	case "$(lower "$1")" in
	0x49444c45) printf 'IDLE' ;;
	0x54554e4c) printf 'TUNL' ;;
	0x45525844) printf 'ERXD' ;;
	0x45545846) printf 'ETXF' ;;
	0x4543334c) printf 'EC3L' ;;
	0x4552464c) printf 'ERFL' ;;
	0x44424135) printf 'DBA5' ;;
	0x00000000) printf 'NONE' ;;
	*) printf 'UNKNOWN' ;;
	esac
}

gate()
{
	name=$1
	state=$2
	detail=$3
	printf '%s=%s %s\n' "$name" "$state" "$detail"
	case "$state" in
	FAIL) failures=$((failures + 1)) ;;
	UNKNOWN) unknowns=$((unknowns + 1)) ;;
	esac
}

printf 'snapshot_utc='; date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'kernel='; uname -r
printf 'compatible='; tr '\000' ',' </proc/device-tree/compatible 2>/dev/null; printf '\n'

if ! command -v devmem >/dev/null 2>&1; then
	gate ndbg_access FAIL 'devmem_not_found'
	printf 'overall=FAIL failures=%d unknowns=%d\n' "$failures" "$unknowns"
	exit 1
fi

npu_line=$(dmesg 2>/dev/null | grep 'NPU fw version:' | tail -n 1)
printf 'npu_firmware_log=%s\n' "${npu_line:-not_found}"
case "$npu_line" in
*'NPU fw version: 7.8'*) gate host_version PASS 'expected=7.8' ;;
*'NPU fw version: 1456.62'*) gate host_version FAIL 'stock_firmware_is_running' ;;
*) gate host_version UNKNOWN 'expected=7.8' ;;
esac

magic=$(lower "$(read32 "$NDBG_BASE")")
if [ "$magic" = "$EXPECTED_MAGIC" ]; then
	gate ndbg_magic PASS "value=$magic"
else
	gate ndbg_magic FAIL "value=${magic:-unreadable} expected=$EXPECTED_MAGIC"
	printf 'critical_npu_log:\n'
	dmesg 2>/dev/null | grep -Ei 'airoha-npu|NPU Version|mailbox function|failed to run npu firmware|probe.*failed' | tail -n 80
	printf 'overall=FAIL failures=%d unknowns=%d\n' "$failures" "$unknowns"
	exit 1
fi

version_words=
off=16
while [ "$off" -lt 48 ]; do
	word=$(lower "$(read32 "$(addr $((NDBG_BASE + off)))")")
	version_words="${version_words}${version_words:+ }$word"
	off=$((off + 4))
done
printf 'ndbg_version_words=%s\n' "$version_words"
if [ "$version_words" = "$EXPECTED_VERSION_WORDS" ]; then
	gate ndbg_build PASS 'TLB7.8.0.0_v003.NOWIFI.da0d0dc'
else
	gate ndbg_build FAIL 'unexpected_build_id'
fi

harts_hex=$(read32 "$(addr $((NDBG_BASE + 12)))")
harts=$((harts_hex))
if [ "$harts" -eq "$EXPECTED_HARTS" ]; then
	gate hart_count PASS "count=$harts"
else
	gate hart_count FAIL "count=$harts expected=$EXPECTED_HARTS"
fi
if [ "$harts" -gt 8 ]; then
	harts=8
fi

i=0
while [ "$i" -lt "$harts" ]; do
	base=$((NDBG_HART_BASE + i * 48))
	loop=$(lower "$(read32 "$(addr "$base")")")
	beat=$(lower "$(read32 "$(addr $((base + 4)))")")
	eval "loop_$i=\$loop"
	eval "beat_$i=\$beat"
	i=$((i + 1))
done

sleep 2

alive_fail=0
trap_fail=0
i=0
while [ "$i" -lt "$harts" ]; do
	base=$((NDBG_HART_BASE + i * 48))
	eval "loop=\${loop_$i}"
	eval "before=\${beat_$i}"
	after=$(lower "$(read32 "$(addr $((base + 4)))")")
	mails=$(lower "$(read32 "$(addr $((base + 16)))")")
	last_mail=$(lower "$(read32 "$(addr $((base + 20)))")")
	traps=$(lower "$(read32 "$(addr $((base + 24)))")")
	cause=$(lower "$(read32 "$(addr $((base + 28)))")")
	epc=$(lower "$(read32 "$(addr $((base + 32)))")")
	if [ "$loop" != 0x00000000 ] && [ "$after" != "$before" ]; then
		alive=PASS
	else
		alive=FAIL
		alive_fail=1
	fi
	if [ "$traps" != 0x00000000 ]; then
		trap_fail=1
	fi
	printf 'hart%d loop=%s(%s) beat_before=%s beat_after=%s alive=%s mails=%s last_mail=%s traps=%s cause=%s epc=%s\n' \
		"$i" "$(tag_name "$loop")" "$loop" "$before" "$after" "$alive" \
		"$mails" "$last_mail" "$traps" "$cause" "$epc"
	i=$((i + 1))
done
if [ "$alive_fail" -eq 0 ] && [ "$harts" -eq "$EXPECTED_HARTS" ]; then
	gate hart_liveness PASS 'all_8_heartbeats_moved_over_2s'
else
	gate hart_liveness FAIL 'one_or_more_harts_not_live'
fi
if [ "$trap_fail" -eq 0 ]; then
	gate hart_traps PASS 'all_trap_counts_zero'
else
	gate hart_traps FAIL 'one_or_more_traps_recorded'
fi

critical=$(dmesg 2>/dev/null | grep -Eic 'mailbox function [0-9]+ timed out|failed to run npu firmware|airoha-npu.*probe.*failed')
if [ "$critical" -eq 0 ]; then
	gate mailbox_timeout PASS 'no_host_timeout_or_probe_failure'
else
	gate mailbox_timeout FAIL "critical_log_lines=$critical"
fi

if [ -r /sys/kernel/debug/ppe/config ]; then
	printf 'ppe_config:\n'
	grep -E '^(npu_attached|ppe[01]_(enabled|flow_cfg|table_cfg|gdm2_default_cpu_port)):' /sys/kernel/debug/ppe/config
	ppe0=$(awk -F': *' '/^ppe0_enabled:/{print $2}' /sys/kernel/debug/ppe/config)
	ppe1=$(awk -F': *' '/^ppe1_enabled:/{print $2}' /sys/kernel/debug/ppe/config)
	[ "$ppe0" = 1 ] && gate ppe0_enable PASS 'enabled=1' || gate ppe0_enable FAIL "enabled=${ppe0:-missing}"
	[ "$ppe1" = 1 ] && gate ppe1_enable PASS 'enabled=1' || gate ppe1_enable FAIL "enabled=${ppe1:-missing}"
else
	gate ppe0_enable UNKNOWN 'debugfs_config_unavailable'
	gate ppe1_enable UNKNOWN 'debugfs_config_unavailable'
fi

if command -v sha256sum >/dev/null 2>&1; then
	rv32=/lib/firmware/airoha/en7581_clanker_npu_rv32.bin
	data=/lib/firmware/airoha/en7581_clanker_npu_data.bin
	if [ -r "$rv32" ]; then
		rv32_hash=$(sha256sum "$rv32" | awk '{print $1}')
		[ "$rv32_hash" = "$EXPECTED_RV32_SHA256" ] && gate rv32_file PASS "sha256=$rv32_hash" || gate rv32_file FAIL "sha256=$rv32_hash"
	else
		gate rv32_file FAIL 'file_missing'
	fi
	if [ -r "$data" ]; then
		data_hash=$(sha256sum "$data" | awk '{print $1}')
		[ "$data_hash" = "$EXPECTED_DATA_SHA256" ] && gate data_file PASS "sha256=$data_hash" || gate data_file FAIL "sha256=$data_hash"
	else
		gate data_file FAIL 'file_missing'
	fi
else
	gate firmware_file_hash UNKNOWN 'sha256sum_unavailable'
fi

if [ -r /proc/config.gz ]; then
	printf 'flow_stats_config='; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_NET_AIROHA_FLOW_STATS=' || printf 'not_set\n'
else
	printf 'flow_stats_config=unknown (no /proc/config.gz)\n'
fi

printf 'critical_npu_log:\n'
dmesg 2>/dev/null | grep -Ei 'airoha-npu|NPU Version|mailbox function|failed to run npu firmware|probe.*failed|trap' | tail -n 80

if [ "$failures" -gt 0 ]; then
	printf 'overall=FAIL failures=%d unknowns=%d\n' "$failures" "$unknowns"
	exit 1
elif [ "$unknowns" -gt 0 ]; then
	printf 'overall=INCOMPLETE failures=0 unknowns=%d\n' "$unknowns"
	exit 2
else
	printf 'overall=PASS failures=0 unknowns=0\n'
fi
