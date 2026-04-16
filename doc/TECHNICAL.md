# Documentation Technique — ProjectX BIOS/ROM

> **Projet** : Custom BIOS/ROM x86  
> **Auteur** : frater  
> **Licence** : GNU GPL v3.0+  
> **Assembleur** : NASM (x86 Real Mode, 16 bits)  
> **Cibles** : QEMU, 86Box

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture générale](#2-architecture-générale)
3. [Structure des sources](#3-structure-des-sources)
4. [Séquence de démarrage](#4-séquence-de-démarrage)
5. [Cartographie mémoire](#5-cartographie-mémoire)
6. [Drivers graphiques](#6-drivers-graphiques)
7. [Drivers d'entrée](#7-drivers-dentrée)
8. [Système GUI](#8-système-gui)
9. [Gestionnaire de mémoire](#9-gestionnaire-de-mémoire)
10. [API Reference](#10-api-reference)
11. [Système de build](#11-système-de-build)
12. [Configuration](#12-configuration)
13. [Interruptions](#13-interruptions)

---

## 1. Vue d'ensemble

ProjectX est un BIOS/ROM x86 écrit entièrement en assembleur NASM. Il s'exécute directement sur du matériel émulé (QEMU, 86Box) **sans système d'exploitation**, **sans chargeur de démarrage** et **sans accès disque**.

Le projet démarre depuis le vecteur de reset (`0xFFFF0`), initialise le matériel, charge un BIOS VGA externe via option ROM, puis lance une interface graphique interactive dotée d'un système de widgets (boutons, sliders, cases à cocher, labels, fenêtres).

**Capacités actuelles :**
- Démarrage depuis ROM (vecteur de reset standard)
- Mode graphique VGA 640×480 16 couleurs ou CGA 640×200 monochrome
- Entrées clavier PS/2 et souris PS/2 (3 ou 4 octets de paquets)
- Framework GUI avec 5 types de widgets et gestionnaire de fenêtres
- Allocateur de mémoire dynamique (heap first-fit, 32 Ko)

---

## 2. Architecture générale

```
┌─────────────────────────────────────────────────────────────────┐
│                         boot.asm                                │
│              Point d'entrée & boucle principale                 │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │  Drivers GFX │  │ Drivers Input│  │  GUI Framework     │   │
│  │  gfx_vga.asm │  │keyboard_ps2  │  │  lib-api.asm       │   │
│  │  gfx_cgam.asm│  │mouse_ps2.asm │  │  lib-logic.asm     │   │
│  └──────┬───────┘  └──────┬───────┘  │  lib-draw.asm      │   │
│         │                 │          │  lib-wm.asm         │   │
│  ┌──────▼─────────────────▼──────────▼────────────────┐   │   │
│  │              Couche commune (common/)               │   │   │
│  │  bda.asm  memory.asm  chartable.asm  string.asm     │   │   │
│  └─────────────────────────────────────────────────────┘   │   │
└─────────────────────────────────────────────────────────────────┘
         │ INT 10h
┌────────▼──────────┐
│  VGA BIOS optionnel│  (chargé à 0xC0000 via option ROM)
│  vgabios.bin      │
└───────────────────┘
```

**Conventions d'appel :**  
Tous les appels de fonctions internes utilisent la convention C :
- Les arguments sont empilés **de droite à gauche** (dernier argument en premier).
- Le nettoyage de la pile est effectué par **l'appelant** (via les macros).
- Les valeurs de retour sont dans `AX`.

---

## 3. Structure des sources

```
ProjectX/
├── src/
│   ├── boot.asm                 # Entrée ROM, init système, boucle principale
│   ├── common/
│   │   ├── bda.asm              # BIOS Data Area — structures et segments
│   │   ├── memory.asm           # Allocateur heap (first-fit)
│   │   ├── chartable.asm        # Table de caractères (bitmap 8×8)
│   │   ├── char_bold.asm        # Police grasse
│   │   ├── char_light.asm       # Police fine
│   │   ├── cursor.asm           # Gestion curseur texte
│   │   ├── patterns.asm         # Motifs de remplissage (damier, gris…)
│   │   ├── string.asm           # Utilitaires chaînes de caractères
│   │   ├── generic.asm          # Constantes hardware, macro de debug
│   │   ├── debug_gfx.asm        # Outils debug graphique
│   │   └── debug_txt.asm        # Outils debug texte
│   ├── drivers/
│   │   ├── gfx_vga.asm          # Driver VGA 640×480×16
│   │   ├── gfx_cgam.asm         # Driver CGA 640×200 monochrome
│   │   ├── keyboard_ps2.asm     # Driver clavier PS/2
│   │   ├── mouse_ps2.asm        # Driver souris PS/2
│   │   └── textmode.asm         # Utilitaires mode texte
│   ├── gui/
│   │   ├── lib-api.asm          # API widgets + structures + allocation
│   │   ├── lib-draw.asm         # Rendu des widgets
│   │   ├── lib-logic.asm        # Traitement événements, hit-test, callbacks
│   │   ├── lib-wm.asm           # Gestionnaire de fenêtres
│   │   └── lib-wm-draw.asm      # Dessin des fenêtres
│   └── assets/
│       └── *.F08                # Polices binaires (format 8 octets/caractère)
├── build/
│   ├── bios.bin                 # Image ROM compilée (64 Ko)
│   └── bios.lst                 # Listing d'assemblage (debug)
├── doc/                         # Documentation
├── roms/
│   └── vgabios.bin              # BIOS VGA QEMU (option ROM externe)
└── tools/
    ├── build.bat / build.sh     # Scripts de compilation
    └── run.bat                  # Lancement QEMU
```

---

## 4. Séquence de démarrage

### 4.1 Vecteur de reset

Le CPU démarre systématiquement à l'adresse physique `0xFFFF0`. Le code en fin de ROM effectue un saut lointain vers le code d'initialisation :

```asm
; Situé à 0xF000:FFF0
reset_vector:
    jmp 0xF000:entrycode
```

### 4.2 Initialisation (`entrycode` — boot.asm)

```
1. cli                      — Désactiver les interruptions
2. SS = 0x0800, SP = 0xFFFE — Initialiser la pile (64 Ko)
3. ivt_setup()              — Remplir l'IVT avec un handler par défaut
4. bda_setup()              — Initialiser la BIOS Data Area (custom)
5. ivt_setvector(IRQ0)      — Installer le handler Timer (INT 08h)
6. pic_init()               — Initialiser les PIC 8259A (maître/esclave)
7. setup_load_rom()         — Scanner et charger les option ROMs (VGA BIOS)
8. setup_check_vga()        — Vérifier que INT 10h est bien installé
9. pic_set_irq_mask(IRQ0)   — Activer IRQ 0 (timer)
10. kbd_init()              — Initialiser le clavier PS/2 + activer IRQ 1
11. sti                     — Réactiver les interruptions
12. GFX INIT                — Initialiser le mode graphique (VGA ou CGA)
13. mouse_init()            — Initialiser la souris PS/2
14. main_loop()             — Entrer dans la boucle principale
```

### 4.3 Boucle principale (`main_loop` — boot.asm)

```
1. gui_init_system()        — Effacer le pool de widgets
2. Créer les widgets démo   — Boutons, checkboxes, sliders
3. Boucle infinie :
   ├── gui_process_all()    — Traiter les événements et redessiner
   └── HLT                  — Attendre la prochaine interruption
```

---

## 5. Cartographie mémoire

| Adresse physique | Fin | Taille | Contenu | Segment |
|---|---|---|---|---|
| `0x00000` | `0x003FF` | 1 Ko | IVT (256 vecteurs × 4 octets) | `0x0000` |
| `0x00400` | `0x004FF` | 256 o | BDA standard IBM | `0x0040` |
| `0x00500` | `0x006FF` | ~512 o | BDA custom (drivers) | `0x0050` |
| `0x00700` | `0x00A6F` | ~1792 o | GUI RAM (pool de widgets) | `0x0070` |
| `0x00A70` | `0x07FFF` | ~29 Ko | Mémoire basse libre | — |
| `0x08000` | `0x17FFF` | 64 Ko | **Pile** (croît vers le bas) | `0x0800` |
| `0x18000` | `0x1FFFF` | 32 Ko | Libre | — |
| `0x20000` | `0x2FFFF` | 64 Ko | **Heap** (allocation dynamique) | `0x2000` |
| `0x30000` | `0x9FFFF` | 448 Ko | RAM conventionnelle libre | — |
| `0xA0000` | `0xAFFFF` | 64 Ko | VGA RAM (modes graphiques) | `0xA000` |
| `0xB0000` | `0xB7FFF` | 32 Ko | MDA RAM (texte monochrome) | `0xB000` |
| `0xB8000` | `0xBFFFF` | 32 Ko | VRAM CGA/MCGA | `0xB800` |
| `0xC0000` | `0xDFFFF` | 128 Ko | Option ROMs (VGA BIOS) | `0xC000` |
| `0xE0000` | `0xEFFFF` | 64 Ko | Réservé système | `0xE000` |
| `0xF0000` | `0xFFFFF` | 64 Ko | **System BIOS ROM** (code) | `0xF000` |

### 5.1 BDA Custom (`0x0050:0000`)

Défini dans `bda.asm`, ce segment stocke l'état des drivers :

**Structure souris** (`mouse_size` octets) :

| Champ | Taille | Description |
|---|---|---|
| `.buffer[4]` | 4 o | Buffer d'entrée I8042 |
| `.idx` | 1 o | Index courant dans le buffer |
| `.packetlen` | 1 o | Taille du paquet (3 ou 4 octets) |
| `.status` | 1 o | État des boutons |
| `.x` / `.y` | 2+2 o | Coordonnées absolues |
| `.cur_x` / `.cur_y` | 2+2 o | Position du curseur graphique |
| `.cur_counter` | 1 o | Compteur show/hide (récursif) |
| `.bkg_buffer[64]` | 64 o | Sauvegarde du fond sous le curseur |

**Structure GFX** (`gfx_size` octets) :

| Champ | Taille | Description |
|---|---|---|
| `.cur_x` / `.cur_y` | 2+2 o | Position curseur texte (pixels) |
| `.cur_mode` | 1 o | Mode d'écriture texte |
| `.cur_offset` | 2 o | Offset calculé pour le prochain caractère |
| `.cur_shift` | 1 o | x modulo 8 (alignement pixel) |

---

## 6. Drivers graphiques

Le driver actif est sélectionné à la compilation via la constante `GFX_DRIVERS` dans `boot.asm` :

```nasm
%define GFX_DRIVERS 'VGA'   ; ou 'CGA'
```

### 6.1 Driver VGA (`gfx_vga.asm`)

| Propriété | Valeur |
|---|---|
| Mode BIOS | `0x12` |
| Résolution | 640×480 |
| Profondeur | 4 bpp (16 couleurs) |
| Segment VRAM | `0xA000` |
| Accès | Bitplanes VGA |

### 6.2 Driver CGA (`gfx_cgam.asm`)

| Propriété | Valeur |
|---|---|
| Mode BIOS | `0x06` |
| Résolution | 640×200 |
| Profondeur | 1 bpp (2 couleurs) |
| Segment VRAM | `0xB800` |
| Organisation | **Entrelacée** |

Organisation entrelacée CGA :
- Lignes paires (0, 2, 4…) : offsets `0x0000`–`0x1F3F` (Bank 0)
- Lignes impaires (1, 3, 5…) : offsets `0x2000`–`0x3F3F` (Bank 1)

### 6.3 Macro GFX

```nasm
GFX <COMMANDE> [, arg1, arg2, ...]
```

Les arguments sont empilés de droite à gauche. La macro appelle la fonction via la table de sauts `graph_driver`.

#### Fonctions GFX disponibles

| Index | Nom | Arguments | Description |
|---|---|---|---|
| 0 | `INIT` | — | Initialise le mode vidéo, efface l'écran |
| 1 | `PUTPIXEL` | x, y, color | Dessine un pixel |
| 2 | `GETPIXEL` | x, y | Lit la couleur d'un pixel (→ AL) |
| 3 | `GOTOXY` | x, y | Positionne le curseur texte interne |
| 4 | `TXT_MODE` | mode | Définit le mode d'écriture texte |
| 5 | `PUTCH` | char | Affiche un caractère ASCII |
| 6 | `WRITE` | seg, offset | Affiche une chaîne ASCIIZ |
| 7 | `LINE` | x1, y1, x2, y2, color | Ligne (Bresenham) |
| 8 | `RECTANGLE` | x1, y1, x2, y2, color | Contour de rectangle |
| 9 | `RECTANGLE_FILL` | x1, y1, x2, y2, pattern, color, bg | Rectangle plein |
| 10 | `RECTANGLE_ROUND` | x1, y1, x2, y2, color | Rectangle arrondi |
| 11 | `MOUSE_HIDE` | — | Cache le curseur souris |
| 12 | `MOUSE_SHOW` | — | Affiche le curseur souris |
| 13 | `MOUSE_MOVE` | — | Rafraîchit la position du curseur |

**Constantes `TXT_MODE` :**

| Constante | Valeur | Effet |
|---|---|---|
| `GFX_TXT_WHITE_TRANSPARENT` | 0 | Texte blanc, fond inchangé |
| `GFX_TXT_BLACK_TRANSPARENT` | 1 | Texte noir, fond inchangé |
| `GFX_TXT_WHITE` | 2 | Texte blanc sur fond noir |
| `GFX_TXT_BLACK` | 3 | Texte noir sur fond blanc |

---

## 7. Drivers d'entrée

### 7.1 Clavier PS/2 (`keyboard_ps2.asm`)

| Propriété | Valeur |
|---|---|
| Port données | `0x60` |
| Port statut/commande | `0x64` |
| Interruption | IRQ 1 → INT `0x09` |

**Fonctions exposées :**
- `kbd_init()` — Active le clavier et installe l'ISR
- `kbd_flush()` — Vide le buffer d'entrée
- `kbd_isr()` — Handler d'interruption (lit le scancode, envoie EOI)

### 7.2 Souris PS/2 (`mouse_ps2.asm`)

| Propriété | Valeur |
|---|---|
| Contrôleur | I8042 (port PS/2 souris) |
| Interruption | IRQ 12 → INT `0x74` |
| Protocole | Paquets 3 ou 4 octets |

**Fonctions exposées :**
- `mouse_init()` — Initialise le contrôleur souris
- `mouse_reset()` — Réinitialise l'état souris
- `mouse_sendcmd(cmd)` — Envoie une commande au contrôleur
- `mouse_detect_packet_len()` — Détecte si les paquets font 3 ou 4 octets
- `isr_mouse_handler()` — Handler d'interruption IRQ 12

**Flux de traitement d'un paquet souris :**
```
IRQ 12 déclenché
  → Lire octet depuis I8042
  → Accumuler dans mouse.buffer[idx]
  → Si idx == packetlen :
      Mettre à jour mouse.x, mouse.y, mouse.status
      Cacher le curseur graphique
      Recalculer la position
      Afficher le curseur graphique
```

---

## 8. Système GUI

Le framework GUI est entièrement implémenté en assembleur et ne dépend d'aucun OS. Il gère le cycle complet : création, rendu, interaction, callbacks.

### 8.1 Types de widgets

| Constante | Valeur | Description |
|---|---|---|
| `OBJ_TYPE_LABEL` | 0 | Texte statique |
| `OBJ_TYPE_BUTTON` | 1 | Bouton cliquable |
| `OBJ_TYPE_SLIDER` | 2 | Curseur (horizontal ou vertical) |
| `OBJ_TYPE_BUTTON_ROUNDED` | 3 | Bouton avec coins arrondis |
| `OBJ_TYPE_CHECKBOX` | 4 | Case à cocher (toggle) |

### 8.2 États des widgets

```
GUI_STATE_FREE     (0) — Slot mémoire libre
GUI_STATE_NORMAL   (1) — Affiché, au repos
GUI_STATE_HOVER    (2) — Survolé par la souris
GUI_STATE_PRESSED  (3) — Clic en cours
GUI_STATE_DISABLED (4) — Grisé, inactif
```

### 8.3 Structure widget (34 octets)

```nasm
struc widget
    .state       resb 1   ; État (FREE / NORMAL / HOVER / PRESSED / DISABLED)
    .type        resb 1   ; Type de widget
    .oldstate    resb 1   ; Ancienne valeur d'état (détection de changement)
    .user_id     resb 1   ; ID utilisateur
    .win_id      resb 1   ; ID de la fenêtre propriétaire
    .x           resw 1   ; Position X (pixels)
    .y           resw 1   ; Position Y (pixels)
    .w           resw 1   ; Largeur (pixels)
    .h           resw 1   ; Hauteur (pixels)
    .text_ofs    resw 1   ; Offset du texte (pointeur seg:ofs)
    .text_seg    resw 1   ; Segment du texte
    .attr_mode   resb 1   ; Mode : SLIDER_HORIZONTAL(1) / SLIDER_VERTICAL(2)
    .attr_free   resb 1   ; Réservé
    .attr_min    resw 1   ; Valeur minimale
    .attr_max    resw 1   ; Valeur maximale
    .attr_val    resw 1   ; Valeur courante
    .x2          resw 1   ; X2 calculé (x + w)
    .y2          resw 1   ; Y2 calculé (y + h)
    .thumb_pos   resw 1   ; Position curseur slider (pixels)
    .thumb_pct   resb 1   ; Taille curseur slider (% de la piste, 1–100)
    .attr_anchor resw 1   ; Ancre interne pour le drag
    .event_click resw 1   ; Pointeur vers la fonction callback "on click"
endstruc
```

### 8.4 Pool de widgets

- Capacité maximale : **32 widgets simultanés** (`GUI_MAX_WIDGETS`)
- Zone mémoire : segment `SEG_GUI` (physique `0x00700`)
- Allocation : `gui_alloc_widget()` — recherche linéaire du premier slot libre
- Libération : `gui_free_widget()` — remise à zéro du slot

### 8.5 Macro GUI

```nasm
GUI <ACTION> [, arg1, arg2, ...]
```

Appel via la table de sauts `gui_api_table`.

#### Actions GUI disponibles

| Index | Constante | Arguments | Retour | Description |
|---|---|---|---|---|
| 0 | `OBJ_CREATE` | type, x, y, w, h | AX = ID ou -1 | Crée un widget |
| 1 | `OBJ_DESTROY` | id | AX = 0 ou -1 | Détruit un widget |
| 2 | `OBJ_GET_STATE` | id | AX = state | Lit l'état du widget |
| 3 | `OBJ_GET_TYPE` | id | AX = type | Lit le type du widget |
| 4 | `OBJ_GET_VAL` | id | AX = val | Lit la valeur (slider) |
| 5 | `OBJ_SET_VAL` | id, val | — | Définit la valeur (slider) |
| 6 | `OBJ_SET_MODE` | id, mode | — | Définit le mode (direction slider) |
| 7 | `OBJ_SET_TEXT` | id, seg, offset | — | Associe un texte au widget |
| 8 | `OBJ_GET_PTR` | id | GS:SI = ptr | Obtient le pointeur brut |
| 9 | `OBJ_SLIDER_SET_ATTR` | id, min, max, val, pct | — | Configure les attributs slider |

#### Exemple d'utilisation

```nasm
; Créer un bouton à (10, 20), taille 80×20
GUI OBJ_CREATE, OBJ_TYPE_BUTTON, 10, 20, 80, 20
mov [btn_id], ax               ; Sauvegarder l'ID retourné

; Lui associer un texte
GUI OBJ_SET_TEXT, [btn_id], cs, str_label

; Associer un callback (adresse de la fonction)
GUI OBJ_GET_PTR, [btn_id]
mov word [gs:si + widget.event_click], my_callback

; Créer un slider horizontal, valeur 0–100, curseur 20%
GUI OBJ_CREATE, OBJ_TYPE_SLIDER, 10, 50, 200, 16
GUI OBJ_SET_MODE, ax, SLIDER_HORIZONTAL
GUI OBJ_SLIDER_SET_ATTR, ax, 0, 100, 50, 20

; Lire la valeur courante d'un slider
GUI OBJ_GET_VAL, [slider_id]   ; → AX = valeur
```

### 8.6 Traitement des événements (`lib-logic.asm`)

Appelé par `gui_process_all()` à chaque itération de la boucle :

```
Pour chaque widget actif :
  1. Hit-test : la souris est-elle dans le rectangle du widget ?
  2. Mise à jour de l'état (NORMAL → HOVER → PRESSED)
  3. Détection de transition (PRESSED → NORMAL = "click released")
  4. Appel du callback event_click si défini
  5. Marquage "dirty" si l'état a changé → sera redessiné
```

### 8.7 Gestionnaire de fenêtres (`lib-wm.asm`)

| Propriété | Valeur |
|---|---|
| Fenêtres max simultanées | 8 |
| États | FREE, INACTIVE, ACTIVE, HIDDEN |
| Gestion du focus | ID de la fenêtre active stocké dans le BDA |
| Rendu | `lib-wm-draw.asm` |

---

## 9. Gestionnaire de mémoire

Défini dans `common/memory.asm`.

### 9.1 Caractéristiques

| Propriété | Valeur |
|---|---|
| Algorithme | First-fit avec coalescence |
| Segment | `0x2000` (physique `0x20000`) |
| Taille | 32 Ko |
| En-tête de bloc | 6 octets |

### 9.2 Structure d'un bloc

| Offset | Taille | Champ | Valeur |
|---|---|---|---|
| +0 | 1 o | Status | `0` = libre, `1` = alloué |
| +1 | 1 o | Padding | Alignement |
| +2 | 2 o | Size | Taille des données (octets) |
| +4 | 2 o | Next | Offset du bloc suivant (`0` = fin) |
| +6 | … | Data | Données utilisateur |

### 9.3 Macro MEM

```nasm
MEM <FONCTION> [, arg1, arg2]
```

| Constante | Description | Retour |
|---|---|---|
| `MEM_INIT` | Initialise le heap | — |
| `MEM_ALLOC, size` | Alloue `size` octets | AX = handle (offset) ou 0 |
| `MEM_FREE, handle` | Libère le bloc | — |
| `MEM_GET_SIZE, handle` | Taille des données du bloc | AX = size |
| `MEM_RESOLVE, handle` | Convertit le handle en pointeur | ES:DI = données |

#### Exemple

```nasm
MEM MEM_INIT               ; À appeler une fois au démarrage

MEM MEM_ALLOC, 256         ; Allouer 256 octets
mov bx, ax                 ; Conserver le handle

MEM MEM_RESOLVE, bx        ; ES:DI pointe sur les données
mov byte [es:di], 0x42     ; Écriture

MEM MEM_FREE, bx           ; Libérer
```

---

## 10. API Reference

### Récapitulatif des macros

| Macro | Fichier | Usage |
|---|---|---|
| `GFX cmd, ...` | `drivers/gfx_vga.asm` ou `gfx_cgam.asm` | Opérations graphiques |
| `GUI cmd, ...` | `gui/lib-api.asm` | Gestion des widgets |
| `MEM cmd, ...` | `common/memory.asm` | Allocation mémoire |
| `ISADBG msg` | `common/generic.asm` | Debug port ISA (86Box) |

### Segments définis

| Constante | Adresse | Usage |
|---|---|---|
| `SEG_IVT` | `0x0000` | Table des vecteurs d'interruption |
| `SEG_BDA` | `0x0040` | BDA standard IBM |
| `SEG_BDA_CUSTOM` | `0x0050` | BDA custom (drivers) |
| `SEG_GUI` | `0x0070` | Pool de widgets GUI |
| `STACK_SEG` | `0x0800` | Base de la pile |
| `MEM_HEAP_SEG` | `0x2000` | Heap dynamique |
| `SEG_VGA` | `0xA000` | VRAM VGA |
| `SEG_VRAM` | `0xB800` | VRAM CGA/texte |
| `SEG_ROM_VGA` | `0xC000` | BIOS VGA option ROM |
| `SEG_ROM` | `0xF000` | BIOS système (ROM) |

---

## 11. Système de build

### 11.1 Compilation (Windows)

```bat
cd src
nasm -f bin boot.asm -o ..\build\bios.bin
```

Pour générer aussi le listing d'assemblage :

```bat
nasm -f bin boot.asm -o ..\build\bios.bin -l ..\build\bios.lst
```

### 11.2 Compilation (Linux)

```bash
mkdir -p build && cd src
nasm -f elf32 -g -F dwarf boot.asm -o ../build/bios.o
ld -m elf_i386 -T link.ld -o build/bios.elf build/bios.o
objcopy -O binary build/bios.elf build/bios.bin
```

### 11.3 Exécution QEMU

```bash
qemu-system-i386 \
  -bios build/bios.bin \
  -device loader,file=roms/vgabios.bin,addr=0xC0000,force-raw=on \
  -device isa-debugcon,chardev=myconsole \
  -chardev stdio,id=myconsole \
  -k be \
  -display sdl
```

**Prérequis :** Copier `vgabios.bin` dans `roms/` :
- Windows : `C:\Program Files\qemu\share\vgabios.bin`
- Linux : `/usr/share/qemu/vgabios.bin`
- Ou depuis [86Box/roms](https://github.com/86Box/roms)

### 11.4 Exécution 86Box

1. Créer une nouvelle machine virtuelle 86Box.
2. Aller dans `roms\machines\vli486sv2g\`.
3. Renommer le fichier `0402.001` (BIOS d'origine).
4. Copier `build\bios.bin` dans ce dossier et le renommer `0402.001`.

### 11.5 Image ROM

| Fichier | Taille | Format |
|---|---|---|
| `build/bios.bin` | 65 536 octets (64 Ko) | Binaire brut |
| `build/bios.lst` | ~450 Ko | Listing NASM texte |

---

## 12. Configuration

Tous les paramètres de configuration sont définis dans `boot.asm` :

```nasm
; Segment de pile
%define STACK_SEG   0x0800

; Driver graphique : 'VGA' ou 'CGA'
%define GFX_DRIVERS 'VGA'

; Activer la sortie de debug (port ISA 0x7A pour 86Box)
%define DEBUGER_ENABLED
```

**Effets de `GFX_DRIVERS` :**
- `'VGA'` → inclut `drivers/gfx_vga.asm`, mode 640×480×16 couleurs
- `'CGA'` → inclut `drivers/gfx_cgam.asm`, mode 640×200 monochrome, désactive `COLOR_GUI`

**Debug port ISA :**  
La macro `ISADBG` (définie dans `generic.asm`) envoie un caractère au port `0x7A`, visible dans la console 86Box lorsque `DEBUGER_ENABLED` est défini. Désactiver ce symbole supprime toute sortie de debug.

---

## 13. Interruptions

### Table des vecteurs installés

| INT | IRQ | Handler | Fichier source |
|---|---|---|---|
| `0x08` | 0 | `timer_isr` | `boot.asm` |
| `0x09` | 1 | `kbd_isr` | `keyboard_ps2.asm` |
| `0x10` | — | (VGA BIOS via option ROM) | `vgabios.bin` |
| `0x74` | 12 | `isr_mouse_handler` | `mouse_ps2.asm` |

Tous les autres vecteurs (0–255) sont initialisés par `ivt_setup()` avec le handler `default_isr` (retour immédiat avec EOI).

### Initialisation des PIC 8259A

Réalisée par `pic_init()` en mode cascade (maître + esclave) :
- PIC maître : IRQ 0–7 → INT `0x08`–`0x0F`
- PIC esclave : IRQ 8–15 → INT `0x70`–`0x77`

L'activation individuelle des IRQ se fait via `pic_set_irq_mask(irq, state)`.
