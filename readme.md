# Custom BIOS / ROM Project

---

## 🇬🇧 English

### Overview

This project aims to design and implement a **PC-compatible BIOS/ROM from scratch**, primarily targeted for **QEMU emulation**, with a strong focus on **low-level PC architecture** and **x86 real-mode assembly programming**.

Rather than booting an operating system from disk, the PC starts **directly from the ROM** into a **minimalist graphical interface**, using **CGA High-Resolution Monochrome (640×200)** mode.

The project is intentionally educational, experimental, and minimalist.

![Screenshot of the boot + text test](/doc/assets/Capture-2026-01-29-210122.png)
Screenshot of early boot version + Text functions

![Screenshot WIP - Buttons & Sliders](/doc/assets/Capture-2026-02-03-213148.png)
Screenshot of early buttons & sliders

![Screenshot WIP - Rounded Buttons & Checkboxes ](/doc/assets/Capture-2026-01-29-210122.png)
Screenshot of rounded buttons & checkboxes

---

### Objectives

- **Write a PC-compatible BIOS from scratch**
  - No reuse of existing BIOS code
  - Minimal but functional implementation
  - Compatible with QEMU
  - Target architecture: **i386+**

- **Boot directly from ROM**
  - No DOS, no bootloader, no disk dependency
  - Execution starts at reset vector (F000:FFF0)
  - ROM is responsible for full system initialization

- **Provide a minimalist graphical interface**
  - Graphics mode: **CGA High-Resolution Monochrome (640×200)**
  - Direct video memory access
  - Custom cursor and basic UI primitives

- **Deep understanding of PC architecture**
  - CPU reset behavior
  - Memory map (RAM, ROM, EBDA, IVT, BDA)
  - Interrupt Vector Table
  - Hardware initialization (PIC, PIT, keyboard, video)
  - Real-mode execution constraints

- **Improve mastery of x86 assembly**
  - Real-mode x86 assembly (i386+ compatible)
  - Performance-oriented routines
  - Hardware-near programming
  - Clear separation between hardware-specific drivers and core logic

---

### Requirements

To build and run this project, the following tools and components are required:

- **NASM (Netwide Assembler)**
  Used to assemble x86 real-mode assembly source files into a raw binary ROM image.

- **QEMU**
  Used as the primary PC emulator for testing and debugging the custom BIOS.

- **QEMU VGA BIOS**
  The standard QEMU VGA BIOS (`vgabios.bin`) is required to initialize the VGA hardware, allowing the custom BIOS to rely on a known and stable VGA implementation while focusing on its own core logic.

---

### Build and Run

#### Compilation

From the project root:

```bash
cd src
nasm -f bin boot.asm -o ..\build\bios.bin
```

This produces a raw BIOS ROM image (bios.bin) suitable for direct execution by QEMU.

#### Execution

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

### Non-Goals

- Full IBM BIOS compatibility
- Protected mode or modern CPUs
- Advanced OS services
- DOS or legacy OS support

This is a **learning and exploration project**, not a drop-in BIOS replacement.

---

## 🇫🇷 Français

### Présentation

Ce projet consiste à concevoir et développer un **BIOS/ROM PC compatible entièrement écrit “from scratch”**, destiné principalement à l’émulation **QEMU**, avec pour objectif principal l’**apprentissage approfondi de l’architecture PC** et de la **programmation assembleur x86 en mode réel**.

Au lieu de charger un système d’exploitation depuis un disque, le PC **démarre directement depuis la ROM** vers une **interface graphique minimaliste**, utilisant le mode **CGA Haute Résolution Monochrome (640×200)**.

Le projet est volontairement **éducatif, expérimental et minimaliste**.

![Screenshot of the boot + text test](/doc/assets/Capture-2026-01-29-210122.png)
Screenshot of early boot version + Text functions

![Screenshot WIP - Buttons & Sliders](/doc/assets/Capture-2026-02-03-213148.png)
Screenshot of early buttons & sliders

![Screenshot WIP - Rounded Buttons & Checkboxes ](/doc/assets/Capture-2026-01-29-210122.png)
Screenshot of rounded buttons & checkboxes

---

### Objectifs

- **Écrire un BIOS PC depuis zéro**
  - Aucun code BIOS existant réutilisé
  - Implémentation minimale mais fonctionnelle
  - Compatible avec QEMU
  - Architecture ciblée : **i386+**

- **Démarrer directement depuis la ROM**
  - Sans DOS, sans bootloader, sans disque
  - Exécution depuis le vecteur de reset (F000:FFF0)
  - La ROM initialise entièrement la machine

- **Fournir une interface graphique minimaliste**
  - Mode graphique : **CGA Hi-Res Monochrome (640×200)**
  - Accès direct à la mémoire vidéo
  - Curseur personnalisé et primitives graphiques simples

- **Approfondir la compréhension de l’architecture PC**
  - Séquence de reset CPU
  - Cartographie mémoire (RAM, ROM, EBDA, IVT, BDA)
  - Table des vecteurs d’interruptions
  - Initialisation matérielle (PIC, PIT, clavier, vidéo)
  - Contraintes du mode réel

- **Perfectionner la maîtrise de l’assembleur**
  - Assembleur x86 en mode réel (i386+ compatible)
  - Routines optimisées pour la performance
  - Programmation proche du matériel
  - Séparation claire entre cœur du BIOS et drivers matériels

---

### Pré-requis

Pour compiler et exécuter ce projet, les outils suivants sont nécessaires :

- **NASM (Netwide Assembler)**
Utilisé pour assembler le code x86 en mode réel et générer une image ROM binaire brute.

- **QEMU**
Utilisé comme émulateur PC principal pour tester et déboguer le BIOS personnalisé.

- **BIOS VGA de QEMU**
Le BIOS VGA standard de QEMU (vgabios.bin) est utilisé pour initialiser le matériel vidéo, ce qui permet au projet de se concentrer sur le développement du BIOS sans réimplémenter la logique VGA complète.

### Compilation et exécution

#### Compilation

Depuis la racine du projet :

```bash
cd src
nasm -f bin boot.asm -o ..\build\bios.bin
```

Cette commande génère une image BIOS brute (`bios.bin`) directement exécutable par QEMU.

#### Exécution

Le BIOS VGA de QEMU doit être copié dans un dossier local `rom/`.

Emplacements par défaut de `vgabios.bin` :

Windows
`C:\Program Files\qemu\share\vgabios.bin`

Linux
`/usr/share/qemu/vgabios.bin`

Vous pouvez aussi utiliser un bios video du projet de 86box

https://github.com/86Box/roms

À copier vers : `roms/vgabios.bin`

Puis lancer QEMU avec la commande suivante :

```bash
qemu-system-i386 \
  -bios build/bios.bin \
  -device loader,file=roms/vgabios.bin,addr=0xC0000,force-raw=on \
  -device isa-debugcon,chardev=myconsole \
  -chardev stdio,id=myconsole \
  -k be \
  -display sdl
```

Cette commande :

- Charge le BIOS personnalisé comme ROM système
- Injecte le BIOS VGA à l’adresse 0xC0000
- Redirige les messages de debug vers la console
- Affiche l’interface graphique via SDL

### Hors périmètre

- Compatibilité BIOS IBM complète
- Mode protégé ou CPU modernes
- Services système avancés
- Support DOS ou OS legacy

Ce projet est avant tout un **laboratoire d’apprentissage et d’exploration**, et non un BIOS de production.

---

### Status

🚧 **Work in progress**
Designed for experimentation, learning, and documentation.

parcourez l'[API](/doc/API.md) pour plus d'informations

---
