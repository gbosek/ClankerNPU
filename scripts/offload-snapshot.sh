#!/bin/sh
# Read-only Airoha/OpenWrt offload snapshot. No credentials or packets.
set -u

printf 'snapshot_utc='; date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'kernel='; uname -r
printf 'compatible='; tr '\000' ',' </proc/device-tree/compatible 2>/dev/null; printf '\n'

printf 'npu_firmware=';
dmesg 2>/dev/null | grep 'NPU fw version:' | tail -n 1

if [ -r /proc/config.gz ]; then
	printf 'flow_stats_config=';
	zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_NET_AIROHA_FLOW_STATS=' || printf 'not_set\n'
else
	printf 'flow_stats_config=unknown (no /proc/config.gz)\n'
fi

for dev in pon0 lan1 lan2 lan3 lan4; do
	[ -d "/sys/class/net/$dev" ] || continue
	carrier=$(cat "/sys/class/net/$dev/carrier" 2>/dev/null || printf '?')
	speed=$(cat "/sys/class/net/$dev/speed" 2>/dev/null || printf '?')
	printf 'link %s carrier=%s speed_Mbps=%s\n' "$dev" "$carrier" "$speed"
done

printf 'bridge_ports:\n'
bridge link show 2>/dev/null | sed -n '1,12p'

printf 'flowtable:\n'
nft list table inet fw4 2>/dev/null | awk '
	/^[[:space:]]*flowtable ft \{/ { active=1 }
	active { print; lines++ }
	active && /^[[:space:]]*\}/ { exit }
	lines >= 12 { exit }
'

if [ -r /sys/kernel/debug/ppe/config ]; then
	printf 'ppe_config:\n'
	grep -E '^(npu_attached|ppe[01]_flow_cfg|fe_wan_port):' /sys/kernel/debug/ppe/config
fi

for table in bind entries; do
	if [ -r "/sys/kernel/debug/ppe/$table" ]; then
		printf 'ppe_%s_lines=' "$table"
		wc -l <"/sys/kernel/debug/ppe/$table"
	fi
done

if [ -r /proc/net/nf_conntrack ]; then
	printf 'conntrack_hw_offload=';
	grep -c '\[HW_OFFLOAD\]' /proc/net/nf_conntrack || :
	printf 'conntrack_sw_offload=';
	grep -c '\[OFFLOAD\]' /proc/net/nf_conntrack || :
fi

for zone in /sys/class/thermal/thermal_zone*; do
	[ -r "$zone/temp" ] || continue
	temp=$(cat "$zone/temp" 2>/dev/null || printf '?')
	printf 'thermal %s millidegC=%s\n' "${zone##*/}" "$temp"
done
