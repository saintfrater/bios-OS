@echo off
setlocal enabledelayedexpansion




set "MSYS=C:\msys64"
set "NASM=C:\Program Files\NASM\nasm.exe"

"%MSYS%\usr\bin\bash.exe" -lc ^
"set -e; cd '%~dp0'; \
mkdir -p build; \
echo assembling; \
'%NASM%' -f elf32 -g -F dwarf src/boot.asm -o build/bios.o; \
echo linking; \
/usr/bin/ld -m elf_i386 -T link.ld -o build/bios.elf build/bios.o; \
echo objcopy; \
/usr/bin/objcopy -O binary build/bios.elf build/bios.bin; \
echo done"

pause
exit /b %errorlevel%


























exit 0

rem Outils
set NASM="C:\Program Files\NASM\nasm.exe"
set "LD=C:\msys64\usr\bin\ld.exe"
set "OBJCOPY=C:\msys64\mingw64\bin\objcopy.exe"

rem Se placer dans le dossier du .bat
pushd "%~dp0"

if not exist build mkdir build 
cd src
echo compiling ELF file
%NASM% -f elf32 -g -F dwarf boot.asm -o ..\build\bios-elf.o 
echo compiling ROM file
%NASM% -f bin boot.asm -o ..\build\bios.bin
echo Linking
%LD% -m elf_i386 -T link.ld -o ..\build\bios.elf ..\build\bios-elf.o
echo ObjCopy
%OBJCOPY% -O binary ..\build\bios.elf ..\build\bios-elf.bin 

popd

pause