# API Gestionnaire de Mémoire (Heap)

## Description
Ce module fournit un gestionnaire de mémoire dynamique (Heap) simple pour le mode réel x86. Il utilise un algorithme **First-Fit** avec fusion des blocs libres (coalescing) lors de l'allocation pour minimiser la fragmentation.

Le segment de mémoire utilisé est défini par `MEM_HEAP_SEG` (par défaut `0x2000`, soit l'adresse physique `0x20000`).

## Structure des Données
Chaque bloc mémoire est précédé d'un en-tête de 6 octets (aligné sur 16 bits) :

| Offset | Taille | Champ | Description |
| :--- | :--- | :--- | :--- |
| +0 | 1 octet | Status | `0` = Libre, `1` = Alloué |
| +1 | 1 octet | Padding | Réservé pour l'alignement |
| +2 | 2 octets | Size | Taille des données utiles (en octets) |
| +4 | 2 octets | Next | Offset du prochain bloc (0 = Fin de liste) |
| +6 | ... | Data | Données utilisateur |

## Utilisation
L'interaction se fait principalement via la macro `MEM`.

```nasm
%include "./common/memory.asm"

; Initialisation (Obligatoire au démarrage)
MEM MEM_INIT

; Allocation de 100 octets
MEM MEM_ALLOC, 100
; AX contient le handle (offset) ou 0 si erreur

; Utilisation du pointeur
mov bx, ax          ; Sauvegarde du handle
MEM MEM_RESOLVE, bx
; ES:DI pointe maintenant vers les données

; Libération
MEM MEM_FREE, bx
