# BDA (Bios Data Area) Custom

Le projet utilise une extension de la BDA standard IBM PC.

    Segment BDA Standard : 0x0040

    Segment Données Custom : 0x0050 (Défini par BDA_DATA_SEG).

## Mapping Mémoire Global :

    0000:0000 : IVT (Interrupt Vector Table)

    0040:0000 : BDA Standard

    0050:0000 : Variables Drivers (Souris, Gfx)

    0800:0000 : Stack (0x8000 - 0x18000 approx) ou Code (selon boot.asm).

    B800:0000 : VRAM CGA.