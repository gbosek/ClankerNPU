#!/bin/sh
# Read-only Airoha/OpenWrt offload snapshot. No credentials or packets.
set -u

flow_peer=${1:-}
flow_port=${2:-}
flow_source_port=${3:-}
flow_source=${4:-}

if [ "$#" -gt 4 ]; then
	echo "usage: $0 [peer_ipv4 peer_port [source_port [source_ipv4]]]" >&2
	exit 2
fi
if [ -n "$flow_peer" ] || [ -n "$flow_port" ] ||
	[ -n "$flow_source_port" ] || [ -n "$flow_source" ]; then
	if [ -z "$flow_peer" ] || [ -z "$flow_port" ]; then
		echo "peer IPv4 and peer port must be supplied together" >&2
		exit 2
	fi
	case "$flow_port" in *[!0-9]*|'') echo "invalid peer port" >&2; exit 2 ;; esac
	case "$flow_source_port" in *[!0-9]*) echo "invalid source port" >&2; exit 2 ;; esac
	if [ -n "$flow_source" ] && [ -z "$flow_source_port" ]; then
		echo "source IPv4 requires a source port" >&2
		exit 2
	fi
fi

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
	grep -E '^(npu_attached|gdm2_fwd_cfg|fe_(wan_port|vip_port_en|ifc_port_en)|ppe[01]_(flow_cfg|table_cfg|gdm2_default_cpu_port)):' \
		/sys/kernel/debug/ppe/config
fi

if [ -r /sys/kernel/debug/ppe/bind ]; then
	printf 'ppe_bind_lines='
	wc -l </sys/kernel/debug/ppe/bind
	if [ -n "$flow_peer" ]; then
		printf 'ppe_test_flow_candidates:\n'
		awk -v peer="$flow_peer" -v port="$flow_port" \
		    -v source_port="$flow_source_port" -v source="$flow_source" '
			index($0, " BND ") && index($0, peer ":" port) {
				if (source != "" && index($0, source ":" source_port) == 0)
					next
				if (source == "" && source_port != "" &&
				    index($0, ":" source_port) == 0)
					next
				line = $0
				gsub(/ packets=[^ ]* bytes=[^ ]*/, " flow_stats=UNVERIFIED", line)
				print line
				found = 1
			}
			END { if (!found) print "not_found" }
		' /sys/kernel/debug/ppe/bind
	fi
fi

if [ -r /sys/kernel/debug/ppe/entries ]; then
	printf 'ppe_entries_lines='
	wc -l </sys/kernel/debug/ppe/entries
fi

if [ -r /proc/net/nf_conntrack ]; then
	printf 'conntrack_hw_offload=';
	grep -c '\[HW_OFFLOAD\]' /proc/net/nf_conntrack || :
	printf 'conntrack_sw_offload=';
	grep -c '\[OFFLOAD\]' /proc/net/nf_conntrack || :
	if [ -n "$flow_peer" ]; then
		printf 'conntrack_test_flow:\n'
		awk -v peer="$flow_peer" -v port="$flow_port" \
		    -v source_port="$flow_source_port" -v source="$flow_source" '
		{
			dst = dport = sport = src = 0
			for (i = 1; i <= NF; i++) {
				if ($i == "dst=" peer) dst = 1
				if ($i == "dport=" port) dport = 1
				if ($i == "sport=" source_port) sport = 1
				if ($i == "src=" source) src = 1
			}
			if (dst && dport &&
			    (source_port == "" || sport) &&
			    (source == "" || src)) {
				print
				found = 1
			}
		}
		END { if (!found) print "not_found" }
		' /proc/net/nf_conntrack
	fi
fi

for zone in /sys/class/thermal/thermal_zone*; do
	[ -r "$zone/temp" ] || continue
	temp=$(cat "$zone/temp" 2>/dev/null || printf '?')
	printf 'thermal %s millidegC=%s\n' "${zone##*/}" "$temp"
done
