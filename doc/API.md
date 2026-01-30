# API

Le système utilise plusieurs macro *GFX*,*GUI*, etc pour appeler les fonctions du driver via une table de saut.

Les arguments sont passés sur la pile (Convention C : dernier argument empilé en premier, nettoyage par l'appelant géré par la macro).

  * [CGA](/doc/CGA.md) controleur graphique


## BDA (Bios Data Area) Custom

Le projet utilise une extension de la BDA standard IBM PC.

    Segment BDA Standard : 0x0040 (comme nous appelons le bios VGA, il faut garder cet espace "libre")

    Segment Données Custom : 0x0050 (Défini par BDA_DATA_SEG).

## Structure des données (BDA 0x0050)

Les structures sont définies dans bda.asm.

    OFFSET 0x0000 (Mouse) : État de la souris, coordonnées (x,y), buffer d'arrière-plan.

    OFFSET 0x0034 (Gfx) : Position courante du curseur texte, modes d'affichage.

## Mapping Mémoire Global :

    0000:0000 : IVT (Interrupt Vector Table)

    0040:0000 : BDA Standard

    0050:0000 : Variables Drivers (Souris, Gfx)

    0800:0000 : Stack (0x8000 - 0x18000 approx) ou Code (selon boot.asm).

    B800:0000 : VRAM CGA.

