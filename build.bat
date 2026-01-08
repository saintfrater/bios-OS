@echo off

cd src
"c:\program files\NASM\nasm" -f bin boot.asm -o ..\build\bios.bin
cd ..

qemu-system-x86_64 -bios build/bios.bin -device loader,file=build/vgabios.bin,addr=0xC0000,force-raw=on -device isa-debugcon,chardev=myconsole -chardev stdio,id=myconsole -k be -display sdl
