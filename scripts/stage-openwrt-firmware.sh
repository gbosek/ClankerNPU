#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	printf 'Usage: %s <PBS05 OpenWrt tree>\n' "$0" >&2
	exit 2
fi

openwrt_tree=$(CDPATH= cd -- "$1" && pwd -P)
if [ ! -d "$openwrt_tree/package/firmware" ] ||
   [ ! -d "$openwrt_tree/target/linux/airoha" ]; then
	printf 'Not an OpenWrt Airoha source tree: %s\n' "$openwrt_tree" >&2
	exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
clanker_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
firmware_dir="$clanker_root/build/AN7581_NOWIFI"
manifest="$firmware_dir/SHA256SUMS"
stage_dir="$openwrt_tree/build_dir/clanker-npu-firmware"

for file in npu_rv32.bin npu_data.bin; do
	if [ ! -s "$firmware_dir/$file" ]; then
		printf 'Missing ClankerNPU build output: %s\n' "$firmware_dir/$file" >&2
		exit 1
	fi
done

if [ ! -s "$manifest" ]; then
	printf 'Missing build manifest: %s\n' "$manifest" >&2
	exit 1
fi

(cd "$clanker_root" && sha256sum --check "$manifest")

rv32_size=$(wc -c < "$firmware_dir/npu_rv32.bin")
data_size=$(wc -c < "$firmware_dir/npu_data.bin")
if [ "$rv32_size" -gt 2097152 ] || [ "$data_size" -gt 65536 ]; then
	printf 'Firmware exceeds host driver limits (RV32=%s bytes, data=%s bytes).\n' \
		"$rv32_size" "$data_size" >&2
	exit 1
fi

mkdir -p "$stage_dir"
install -m 0644 "$firmware_dir/npu_rv32.bin" \
	"$stage_dir/en7581_clanker_npu_rv32.bin"
install -m 0644 "$firmware_dir/npu_data.bin" \
	"$stage_dir/en7581_clanker_npu_data.bin"
(cd "$stage_dir" && sha256sum \
	en7581_clanker_npu_rv32.bin en7581_clanker_npu_data.bin > SHA256SUMS)

printf 'Staged ClankerNPU firmware in %s\n' "$stage_dir"
printf 'RV32: %s bytes; data: %s bytes\n' "$rv32_size" "$data_size"
