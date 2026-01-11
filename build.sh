#!/usr/bin/env bash
set -euo pipefail

mkdir -p build

cd src
nasm -f elf32 -g -F dwarf boot.asm -o ../build/bios.o
cd ..
ld -m elf_i386 -T link.ld -o build/bios.elf build/bios.o
objcopy -O binary build/bios.elf build/bios.bin
