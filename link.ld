/*
 * AN75XX NPU firmware linker script
 *
 * Memory layout:
 *   .text + .rodata  → DRAM at 0x84000000  (becomes npu_rv32.bin)
 *   .data            → NPU SRAM at 0x3E900000  (becomes npu_data.bin)
 *   .bss             → NPU SRAM after .data (zeroed by crt0, not in any file)
 *   stacks           → DRAM after .text (not in any file, 16KB per hart)
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    DRAM (rwx)  : ORIGIN = 0x84000000, LENGTH = 2M
    SRAM (rw)   : ORIGIN = 0x3E900000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text.hot)
        *(.text .text.*)
    } > DRAM

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > DRAM

    __image_end = .;

    .data : ALIGN(4) {
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        __data_end = .;
    } > SRAM

    __global_pointer$ = __data_start + 0x800;

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = . - 4;
    } > SRAM

    /* the debug block sits at a fixed address above the globals */
    ASSERT(__bss_end < __ndbg_base, "globals overlap the debug block")

    .stack (NOLOAD) : ALIGN(16) {
        __stack_base = .;
    } > DRAM

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.*)
    }
}

__STACK_SIZE = 0x4000;
__stack0 = __stack_base + 1 * __STACK_SIZE;
__stack1 = __stack_base + 2 * __STACK_SIZE;
__stack2 = __stack_base + 3 * __STACK_SIZE;
__stack3 = __stack_base + 4 * __STACK_SIZE;
__stack4 = __stack_base + 5 * __STACK_SIZE;
__stack5 = __stack_base + 6 * __STACK_SIZE;
__stack6 = __stack_base + 7 * __STACK_SIZE;
__stack7 = __stack_base + 8 * __STACK_SIZE;

/*
 * FOE flow-stats window published to the Linux host by the
 * FLOW_STATS_SETUP mailbox call (PPE function 4).
 *
 * The host ioremaps this window and both writes it (memset_io on flow
 * commit) and reads it (memcpy_fromio when reporting per-entry counters),
 * so it has to be DRAM the host can map. It sits in the SoC-reserved NPU
 * DRAM window (npu-binary@84000000, 10 MiB) well above .text, .rodata and
 * the eight 16 KB hart stacks, which all live just after 0x84000000.
 *
 * 64 KiB = 8192 entries x 8 bytes, matching the host's
 * PPE_STATS_NUM_ENTRIES (4 K) * num_ppe (2) * sizeof(struct airoha_foe_stats).
 *
 * The firmware reads both values back through NPU_FOE_STATS_ADDR /
 * NPU_FOE_STATS_SIZE in npu_internal.h, so these two symbols are the single
 * source of truth and the ASSERTs below guard them at link time.
 */
__npu_stats_base = 0x84900000;
__npu_stats_size = 0x10000;

ASSERT(__stack_base + 8 * __STACK_SIZE <= __npu_stats_base,
       "firmware image or stacks overlap the FOE stats window")
ASSERT(__npu_stats_base + __npu_stats_size <= 0x84A00000,
       "FOE stats window leaves the reserved NPU DRAM")
