@echo off

if not exist build mkdir build 
cd src
echo compiling
"C:\Program Files\NASM\nasm.exe" -f elf32 -g -F dwarf boot.asm -o ..\build\bios.o 
echo LD
ld -m elf_i386 -T link.ld -o build\bios.elf build\bios.o
echo ObjectCopy
objcopy -O binary build\bios.elf build\bios.bin 
cd ..
