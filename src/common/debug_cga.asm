; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : cga_debug.asm
;  Author   : frater
;
;  License  : GNU General Public License v3.0 or later (GPL-3.0+)
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.
;
; =============================================================================

; =============================================================================
; Fonction : dump_ram_words
; Description : Lit des mots (16 bits) depuis DS:SI et les affiche en Hexa
; Entrées :
;    DS:SI = Adresse de départ en RAM
;    CX    = Nombre de mots (words) à lire et afficher
; =============================================================================

dump_ram_words:
    jcxz .done              ; Sécurité : si CX=0, on sort

.loop:
    lodsw                   ; Charge [DS:SI] dans AX et incrémente SI de 2
                            ; Note: x86 est Little Endian. Si RAM = 12 34,
                            ; AX vaudra 0x3412.

    push cx                 ; Sauvegarde le compteur de boucle principal
    push si                 ; Sauvegarde le pointeur (si cga_putc le modifie)

    call print_word_hex     ; Affiche AX sous forme "XXXX"

    ; (Optionnel) Ajouter un espace entre chaque mot pour la lisibilité
    mov  al, ' '
    call cga_putc

    pop  si                 ; Restaure SI
    pop  cx                 ; Restaure CX

    loop .loop              ; Décrémente CX et boucle si != 0

.done:
    ret

; =============================================================================
; Fonction : print_word_hex
; Description : Convertit AX en 4 caractères Hexa et les affiche
; Entrée : AX = Valeur 16 bits (ex: 0x1A2B)
; Sortie : Affiche "1A2B" via cga_putc
; =============================================================================
print_word_hex:
    push    ax                 ; Sauvegarde AX car on va le modifier (rotation)
    push    cx
    push    bx

    mov     cx, 4               ; 4 caractères hex dans un mot de 16 bits

.next_digit:
    ; On veut afficher les bits 12-15 d'abord.
    ; L'astuce est de faire une rotation à gauche de 4 bits.
    ; Le quartet de poids fort se retrouve en bas (bits 0-3).
    rol     ax, 4

    mov     bx, ax              ; Copie temporaire
    and     bl, 0x0F            ; On isole les 4 derniers bits (0 à 15)

    mov     al, bl              ; AL contient la valeur numérique (0-15)
    call    nibble_to_ascii    ; Convertit AL en caractère ASCII

    call    cga_putc           ; Affiche le caractère

    loop    .next_digit        ; Répète 4 fois

    pop     bx
    pop     cx
    pop     ax                  ; Restaure l'état original de AX
    ret

; =============================================================================
; Fonction : nibble_to_ascii
; Description : Convertit les 4 bits de poids faible de AL en ASCII Hex
; Entrée : AL (valeur 0-15)
; Sortie : AL (caractère '0'-'9' ou 'A'-'F')
; =============================================================================
nibble_to_ascii:
    cmp     al, 9
    ja      .letter             ; Si > 9, c'est une lettre (A-F)

    add     al, '0'             ; Sinon c'est un chiffre : 0x0 -> '0'
    ret

.letter:
    add     al, 'A' - 10        ; Convertit 10 -> 'A', 11 -> 'B', etc.
    ret