### Build & Run

#### Compilation

From the project root:

```bash
cd src
nasm -f bin boot.asm -o ..\build\bios.bin
```

This produces a raw BIOS ROM image (bios.bin) suitable for direct execution by QEMU.

#### QEMU Execution

The QEMU VGA BIOS must be copied into a local rom/ directory.

Default locations of `vgabios.bin`:

Windows
`C:\Program Files\qemu\share\vgabios.bin`

Linux
`/usr/share/qemu/vgabios.bin`

You can use an video bios from the 86box's project:

https://github.com/86Box/roms

Copy it to: `roms/vgabios.bin`

Then run QEMU with:

```bash
qemu-system-i386 \
  -bios build/bios.bin \
  -device loader,file=roms/vgabios.bin,addr=0xC0000,force-raw=on \
  -device isa-debugcon,chardev=myconsole \
  -chardev stdio,id=myconsole \
  -k be \
  -display sdl
```

This command:

- Loads the custom BIOS as the system ROM
- Injects the VGA BIOS at 0xC0000
- Redirects debug output to the console
- Displays graphics using SDL

#### 86Box Execution

This is a bit tricky since 86box doesn't allow to pick custom BIOS file. You'll have to choose an existing computer and replace the original BIOS file with the compliled one.

create a new configuration:
![86Box Config - Machine](/doc/assets/86box-machine.png)

![86Box Config - video](/doc/assets/86box-video.png)

- save the configuration
- go to the 86Box's `roms\machines\vli486sv2g\` folder
- rename the `0402.001` file (it's the original machine's BIOS);
- copy the `build\bios.bin` into the 86Bos's `roms\machines\vli486sv2g\` folder and rename as `0402.001`


