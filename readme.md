# Custom BIOS / ROM Project  
## Projet BIOS / ROM personnalisé

---

## 🇬🇧 English

### Overview

This project aims to design and implement a **PC-compatible BIOS/ROM from scratch**, primarily targeted for **QEMU emulation**, with a strong focus on **low-level PC architecture** and **x86 real-mode assembly programming**.

Rather than booting an operating system from disk, the PC starts **directly from the ROM** into a **minimalist graphical interface**, using **CGA High-Resolution Monochrome (640×200)** mode.

The project is intentionally educational, experimental, and minimalist.

---

### Objectives

- **Write a PC-compatible BIOS from scratch**
  - No reuse of existing BIOS code
  - Minimal but functional implementation
  - Compatible with QEMU
  - Target architecture: **8086 → 80486**

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
  - Real-mode x86 assembly (8086-compatible)
  - Performance-oriented routines
  - Hardware-near programming
  - Clear separation between hardware-specific drivers and core logic

---

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

---

### Objectifs

- **Écrire un BIOS PC depuis zéro**
  - Aucun code BIOS existant réutilisé
  - Implémentation minimale mais fonctionnelle
  - Compatible avec QEMU
  - Architecture ciblée : **8086 jusqu’au 486**

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
  - Assembleur x86 en mode réel (compatible 8086)
  - Routines optimisées pour la performance
  - Programmation proche du matériel
  - Séparation claire entre cœur du BIOS et drivers matériels

---

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
