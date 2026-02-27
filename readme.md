# Custom BIOS / ROM Project

---

## 🇬🇧 English

### Overview

This project aims to design and implement a **PC-compatible BIOS/ROM from scratch**, primarily targeted for **QEMU emulation**, with a strong focus on **low-level PC architecture** and **x86 real-mode assembly programming**.

Rather than booting an operating system from disk, the PC starts **directly from the ROM** into a **minimalist graphical interface**, using **CGA High-Resolution Monochrome (640×200)** mode.

![Screenshot 86Box](/doc/assets/Capture-86Box.png)

Screenshot from a CGA Hi res test on 86Box.

![Screenshot QEMU VGA](/doc/assets/Screenshot-VGA.png)

Screenshot from a VGA Hi res test on QEMU with "italic Font".

You may want to get a look at the [Older screenshots](/doc/assets/screenshot.md)

The project is intentionally educational, experimental, and minimalist.

---

### Objectives

- **Write a PC-compatible BIOS from scratch**
  - No reuse of existing BIOS code
  - Minimal but functional implementation
  - Compatible with QEMU & 86Box
  - Target architecture: **i386+**

- **Boot directly from ROM**
  - No DOS, no bootloader, no disk dependency
  - Execution starts at reset vector (F000:FFF0)
  - ROM is responsible for full system initialization

- **Provide a minimalist graphical interface**
  - Graphics mode: **CGA High-Resolution Monochrome (640×200)** and **VGA High-Resolution 16 colors (640×480)**
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

- **VGA Text Font**
  You may want to use "custom" font; you can pick any "F08" (8 bytes per character) font from this repo:

  https://github.com/viler-int10h/vga-text-mode-fonts


---

### API

Get a look at the [API](/doc/API.md) for more information.

---

### Build and Run

[read detailed step to compile an run](/doc/build.md)

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


![Screenshot 86Box](/doc/assets/Capture-86Box.png)

Screenshot d'un EcranCGA Hi res test sur 86Box.

![Screenshot QEMU VGA](/doc/assets/Screenshot-VGA.png)

screenshot d'un ecran VGA Hi res test avec police Italique sur QEMU.

You may want to get a look at the [Older screenshots](/doc/assets/screenshot.md)

---

### Objectifs

- **Écrire un BIOS PC depuis zéro**
  - Aucun code BIOS existant réutilisé
  - Implémentation minimale mais fonctionnelle
  - Compatible avec QEMU & 86Box
  - Architecture ciblée : **i386+**

- **Démarrer directement depuis la ROM**
  - Sans DOS, sans bootloader, sans disque
  - Exécution depuis le vecteur de reset (F000:FFF0)
  - La ROM initialise entièrement la machine

- **Fournir une interface graphique minimaliste**
  - Mode graphique : **CGA Hi-Res Monochrome (640×200)** et **VGA Hi-Res 16 couleurs (640×480)**
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

- **VGA Text Font**
  Vous pouvez utiliser des polices de caractères personnalisées. Vous pouvez choisir n'importe quelle police 'F08' (8 octets par caractère) de ce référentiel:

  https://github.com/viler-int10h/vga-text-mode-fonts


----

### API

Consultez la documentation de l'[API](/doc/API.md) pour plus d'informations.

---


### Compilation et exécution

[read detailed step to compile an run](/doc/build.md)

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

---
