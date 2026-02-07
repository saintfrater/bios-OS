# Memory Map / Cartographie Mémoire

## 🇬🇧 English

### Physical Memory Layout (Real Mode)

The processor starts in Real Mode, addressing 1 MB of memory.

| Physical Start | Physical End | Size | Description | Segment | Source File |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`0x00000`** | **`0x003FF`** | 1 KB | **IVT** (Interrupt Vector Table) | `0x0000` | `memory.asm` |
| **`0x00400`** | **`0x004FF`** | 256 B | **BDA** (BIOS Data Area) Standard | `0x0040` | `memory.asm` |
| **`0x00500`** | **`0x005FF`** | ~256 B | **Custom BDA** (Driver Data) | `0x0050` | `memory.asm` |
| **`0x00600`** | **`0x00AFF`** | 1.25 KB | **GUI RAM** (Widget Allocation) | `0x0060` | `gui/lib.asm` |
| **`0x00B00`** | **`0x07FFF`** | 29 KB | **Free** (Low Memory) | | |
| **`0x08000`** | **`0x17FFF`** | 64 KB | **Stack** (Grows downwards) | `0x0800` | `memory.asm` |
| **`0x18000`** | **`0x9FBFF`** | 543 KB | **Free** (Conventional RAM) | | |
| **`0x9FC00`** | **`0x9FFFF`** | 1 KB | **EBDA** (Extended BIOS Data Area) | `0x9FC0` | `memory.asm` |
| **`0xA0000`** | **`0xAFFFF`** | 64 KB | **VGA RAM** (Graphics Modes) | `0xA000` | `Hardware` |
| **`0xB0000`** | **`0xB7FFF`** | 32 KB | **MDA RAM** (Monochrome Text) | `0xB000` | `Hardware` |
| **`0xB8000`** | **`0xBFFFF`** | 32 KB | **VRAM** (CGA / MCGA) | `0xB800` | `memory.asm` |
| **`0xC0000`** | **`0xDFFFF`** | 128 KB | **Option ROMs** (e.g., VGA BIOS) | `0xC000` | `memory.asm` |
| **`0xE0000`** | **`0xEFFFF`** | 64 KB | **System Reserved** (BIOS Extension) | `0xE000` | `Hardware` |
| **`0xF0000`** | **`0xFFFFF`** | 64 KB | **System BIOS ROM** (Code) | `0xF000` | `memory.asm` |

### Detailed Zones

#### Interrupt Vector Table (IVT)
*   **Location**: `0000:0000`
*   **Usage**: Interrupt pointer table (256 entries of 4 bytes).
*   **Initialization**:
    *   `ivt_setup` fills the table with a default handler (`default_isr`).
    *   `ivt_setvector` installs specific IRQs (e.g., Timer on `INT 08h`).

#### BIOS Data Area (BDA)
The project separates the standard IBM BDA from its own variables to avoid conflicts with the VGA BIOS loaded at `0xC000`.

*   **Standard BDA (`0040:0000`)**: Used mainly by the VGA BIOS (loaded via QEMU) to store video modes (`0x0049`) and column count (`0x004A`).
*   **Custom BDA (`0050:0000`)**: Defined by `BDA_DATA_SEG`. Stores driver states:
    *   **Mouse**: Input buffer, status, coordinates, background buffer (for cursor).
    *   **Gfx**: Text cursor position, attributes.
    *   **GUI RAM**: Segment `0x0060` (Physical `0x00600`).
        *   **Layout**: Located in low memory (`0x0060`) to avoid any collision with the Stack (`0x0800`).

#### Stack
*   **Stack**: Segment `0x0800`, SP `0xFFFE`. Grows downwards from physical address `0x17FFE`.

#### Video RAM (CGA High-Res)
*   **Segment**: `0xB800`
*   **Mode**: 640x200 Monochrome (1 bit per pixel).
*   **Organization**: Interleaved.
    *   **Even Lines (0, 2, 4...)**: Offset `0x0000` - `0x1F3F` (Bank 0).
    *   **Odd Lines (1, 3, 5...)**: Offset `0x2000` - `0x3F3F` (Bank 1).

#### VGA RAM & System Reserved
*   **VGA RAM (`0xA0000`)**: Standard 64 KB memory window for VGA graphics modes. Although this project primarily uses the CGA memory at `0xB8000`, this area is physically present when the VGA hardware is emulated.
*   **System Reserved (`0xE0000`)**: Reserved memory area, typically used for motherboard BIOS extensions or specific hardware mapping.

#### ROM
*   **Option ROMs (`0xC0000`)**: Scanned by `setup_load_rom` to initialize the VGA BIOS.
*   **System ROM (`0xF0000`)**: Contains the compiled binary code. The Reset Vector is at `0xFFFF0`.

---

## 🇫🇷 Français

### Cartographie Mémoire Physique (Mode Réel)

Le processeur démarre en mode réel, adressant 1 Mo de mémoire.

| Adresse Physique (Début) | Adresse Physique (Fin) | Taille | Description | Segment | Fichier Source |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`0x00000`** | **`0x003FF`** | 1 Ko | **IVT** (Interrupt Vector Table) | `0x0000` | `memory.asm` |
| **`0x00400`** | **`0x004FF`** | 256 o | **BDA** (BIOS Data Area) Standard | `0x0040` | `memory.asm` |
| **`0x00500`** | **`0x005FF`** | ~256 o | **Custom BDA** (Données Drivers) | `0x0050` | `memory.asm` |
| **`0x00600`** | **`0x00AFF`** | 1.25 Ko | **GUI RAM** (Allocation Widgets) | `0x0060` | `gui/lib.asm` |
| **`0x00B00`** | **`0x07FFF`** | 29 Ko | **Libre** (Mémoire Basse) | | |
| **`0x08000`** | **`0x17FFF`** | 64 Ko | **Pile** (Stack) | `0x0800` | `memory.asm` |
| **`0x18000`** | **`0x9FBFF`** | 543 Ko | **Libre** (RAM Conventionnelle) | | |
| **`0x9FC00`** | **`0x9FFFF`** | 1 Ko | **EBDA** (Extended BIOS Data Area) | `0x9FC0` | `memory.asm` |
| **`0xA0000`** | **`0xAFFFF`** | 64 Ko | **VGA RAM** (Modes Graphiques) | `0xA000` | `Matériel` |
| **`0xB0000`** | **`0xB7FFF`** | 32 Ko | **MDA RAM** (Texte Monochrome) | `0xB000` | `Matériel` |
| **`0xB8000`** | **`0xBFFFF`** | 32 Ko | **VRAM** (CGA / MCGA) | `0xB800` | `memory.asm` |
| **`0xC0000`** | **`0xDFFFF`** | 128 Ko | **Option ROMs** (ex: VGA BIOS) | `0xC000` | `memory.asm` |
| **`0xE0000`** | **`0xEFFFF`** | 64 Ko | **Réservé Système** (Extension BIOS) | `0xE000` | `Matériel` |
| **`0xF0000`** | **`0xFFFFF`** | 64 Ko | **System BIOS ROM** (Code) | `0xF000` | `memory.asm` |

### Détails des Zones

#### Interrupt Vector Table (IVT)
*   **Emplacement** : `0000:0000`
*   **Usage** : Table des pointeurs d'interruption (256 entrées de 4 octets).
*   **Initialisation** :
    *   `ivt_setup` remplit la table avec un handler par défaut (`default_isr`).
    *   `ivt_setvector` installe les IRQ spécifiques (ex: Timer sur `INT 08h`).

#### BIOS Data Area (BDA)
Le projet sépare la BDA standard IBM de ses propres variables pour éviter les conflits avec le BIOS VGA chargé en `0xC000`.

*   **BDA Standard (`0040:0000`)** : Utilisée principalement par le BIOS VGA (chargé via QEMU) pour stocker les modes vidéo (`0x0049`) et le nombre de colonnes (`0x004A`).
*   **Custom BDA (`0050:0000`)** : Définie par `BDA_DATA_SEG`. Stocke l'état des drivers :
    *   **Souris** : Buffer d'entrée, état, coordonnées, buffer de sauvegarde du fond (pour le curseur).
    *   **Gfx** : Position du curseur texte, attributs.
    *   **GUI RAM** : Segment `0x0060`.
        *   **Organisation** : Située en mémoire basse (`0x0060`) pour éviter toute collision avec la Pile (`0x0800`).

#### Stack
*   **Stack** : Segment `0x0800`, SP `0xFFFE`. Grandit vers le bas depuis l'adresse physique `0x17FFE`.


#### Video RAM (CGA High-Res)
*   **Segment** : `0xB800`
*   **Mode** : 640x200 Monochrome (1 bit par pixel).
*   **Organisation** : Entrelacée (Interleaved).
    *   **Lignes Paires (0, 2, 4...)** : Offset `0x0000` à `0x1F3F` (Bank 0).
    *   **Lignes Impaires (1, 3, 5...)** : Offset `0x2000` à `0x3F3F` (Bank 1).

#### VGA RAM & Réservé Système
*   **VGA RAM (`0xA0000`)** : Fenêtre mémoire standard de 64 Ko pour les modes graphiques VGA. Bien que ce projet utilise principalement la mémoire CGA à `0xB8000`, cette zone est physiquement présente lorsque le matériel VGA est émulé.
*   **Réservé Système (`0xE0000`)** : Zone mémoire réservée, typiquement utilisée pour les extensions du BIOS de la carte mère ou le mappage de matériel spécifique.

#### ROM
*   **Option ROMs (`0xC0000`)** : Espace scanné par `setup_load_rom` pour initialiser le BIOS VGA.
*   **System ROM (`0xF0000`)** : Contient le code binaire compilé. Le Vecteur de Reset est situé à `0xFFFF0`.