OUTPUT_FORMAT(elf32-i386)
ENTRY(reset_vector)

ROM_SIZE = 0x10000;
ROM_BASE = 0x100000000 - ROM_SIZE;   /* 0xFFFF0000 */

SECTIONS
{
  . = ROM_BASE;

  .text : { *(.text*) *(.rodata*) *(.data*) }

  /* Place le reset vector à 0xFFFFFFF0 (16 octets avant 4GB) */
  .reset 0xFFFFFFF0 : { KEEP(*(.reset)) }

  /DISCARD/ : { *(.eh_frame*) *(.comment*) }
}
