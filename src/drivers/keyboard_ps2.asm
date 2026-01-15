; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : keyboard_ps2.asm
;  Author   : frater
;  Created  : 06 jan 2026
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

; -------------------------------
; scancode set 1 -> ASCII
; index = scancode (0..0x7F)
; 0 = non imprimable
; -------------------------------
kbd_map_nomod:
            db        0,
            db        27        ; 01 ESC
            db        '1','2','3','4','5','6','7','8','9','0','-','='
            db        8         ; 0E Backspace
            db        9         ; 0F Tab
            db        'q','w','e','r','t','y','u','i','o','p','[',']'
            db        13        ; 1C Enter
            db        0         ; 1D Ctrl
            db        'a','s','d','f','g','h','j','k','l',';',0x27, 0x60
            db        0         ; 2A LShift
            db        0x5c,'z','x','c','v','b','n','m',',','.','/'
            db        0         ; 36 RShift
            db        '*'       ; 37 keypad *
            db        0         ; 38 Alt
            db        ' '       ; 39 Space
            times (0x80-($-kbd_map_nomod)) db 0

kbd_map_shift:
            db        0
            db        27
            db        '!','@','#','$','%','^','&','*','(',')','_','+'
            db        8
            db        9
            db        'Q','W','E','R','T','Y','U','I','O','P','{','}'
            db        13
            db        0
            db        'A','S','D','F','G','H','J','K','L',':','"','~'
            db        0
            db        '|','Z','X','C','V','B','N','M','<','>','?'
            db        0
            db        '*'
            db        0
            db        ' '
            times     (0x80-($-kbd_map_shift)) db 0

; -----------------------------------------------------------
; Vérifie si une touche est disponible dans le buffer clavier
; Retour: CF=0 si une touche est dispo, CF=1 sinon
; -----------------------------------------------------------
kbd_kbhit:
            push      ds
            mov       ax, BDA_SEGMENT
            mov       ds, ax
            mov       al, [BDA_KBD_HEAD]
            cmp       al, [BDA_KBD_TAIL]
            pop       ds
            je        .empty
            clc
            ret
.empty:
            stc
            ret

; -----------------------------------------------------------
; Lit un caractère du buffer clavier (make+ascii)
; Retour: CF=0 si une touche est dispo, AX=word (scancode<<8 | ascii)
;         CF=1 si aucune touche disponible
; -----------------------------------------------------------
kbd_poll:
            push      ds
            mov       ax, BDA_SEGMENT
            mov       ds, ax
            call      kbd_buf_pop
            pop       ds
            ret

; -----------------------------------------------------------
; Lit un caractère du buffer clavier (make+ascii)
; Bloque jusqu'à ce qu'une touche soit disponible
; Retour: AX=word (scancode<<8 | ascii)
; -----------------------------------------------------------
kbd_getch:
.wait:
            call      kbd_poll
            jc        .wait
            ret

; -----------------------------------------------------------
; Met à jour les modifiers sur make code
; -----------------------------------------------------------
kbd_init:
            push      ds
            push      ax

            mov       ax, BDA_SEGMENT
            mov       ds, ax
            mov       byte [BDA_KBD_HEAD], 0
            mov       byte [BDA_KBD_TAIL], 0
            mov       byte [BDA_KBD_FLAGS], 0

            ; installer INT 09h = IRQ1
            cli
            xor       ax, ax
            mov       ds, ax
            mov       si, 0x09*4
            mov       word [ds:si], kbd_isr
            mov       ax, cs
            mov       word [ds:si+2], ax
            sti

            ; unmask IRQ1 (master bit1 = 0)
            in        al, i8259_MASTER_DATA
            and       al, 0xFD
            out       i8259_MASTER_DATA, al

            pop       ax
            pop       ds
            ret

; -----------------------------------------------------------
; Met à jour les modifiers sur make code
; Entrée: AL = scancode (sans bit7)
; -----------------------------------------------------------
kbd_buf_push:
            ; In: AX = word à pousser
            ; DS = 0x40
            push      bx
            push      di

            mov       bl, [BDA_KBD_HEAD]
            mov       bh, [BDA_KBD_TAIL]

            ; next_head = (head+1) & MASK
            mov       dl, bl
            inc       dl
            and       dl, KBD_BUF_MASK

            ; si next_head == tail => buffer plein => drop
            cmp       dl, bh
            je        .full

            ; écrire à BUF[head]
            ; offset = BDA_KBD_BUF + head*2
            xor       bh, bh
            mov       di, bx
            shl       di, 1
            add       di, BDA_KBD_BUF
            mov       [di], ax

            ; head = next_head
            mov       [BDA_KBD_HEAD], dl
.full:
            pop       di
            pop       bx
            ret

; -----------------------------------------------------------
; pop un word du buffer clavier (circulaire)
; -----------------------------------------------------------
kbd_buf_pop:
            ; Out: CF=1 si vide, sinon AX=word, CF=0
            ; DS=0x40
            push      bx
            push      di

            mov       bl, [BDA_KBD_HEAD]
            mov       bh, [BDA_KBD_TAIL]
            cmp       bl, bh
            je        .empty

            ; lire BUF[tail]
            xor       bh, bh
            mov       di, bx
            shl       di, 1
            add       di, BDA_KBD_BUF
            mov       ax, [di]

            ; tail = (tail+1) & MASK
            inc       bh
            and       bh, KBD_BUF_MASK
            mov [BDA_KBD_TAIL], bh

            clc
            pop       di
            pop       bx
            ret
.empty:
            stc
            pop       di
            pop       bx
            ret

; -----------------------------------------------------------
; Keyboard ISR (INT 09h)
; -----------------------------------------------------------
kbd_isr:
    pusha

    in   al, 0x60            ; consomme scancode (obligatoire)

    mov  dx, 0x00E9          ; debugcon
    mov  al, '*'
    out  dx, al

    mov  al, 0x20            ; EOI master
    out  0x20, al

    popa
    iret


; kbd_isr:
            push      ds
            pusha

            mov       ax, BDA_SEGMENT
            mov       ds, ax

            in        al, PS2_PORT_BUFFER
            cmp       al, 0xE0
            jne       .sc
            or        byte [BDA_KBD_FLAGS], 0x10
            jmp       .eoi

.sc:
            mov       bl, al

            test      bl, 0x80
            jz        .make
            and       bl, 0x7F
            mov       al, bl
            call      kbd_update_modifiers_break
            jmp       .clear_eoi

.make:
            mov       al, bl
            call      kbd_update_modifiers_make

            ; filtrer modifiers (ne push pas)
            cmp       bl, 0x2A
            je        .clear_eoi
            cmp       bl, 0x36
            je        .clear_eoi
            cmp       bl, 0x1D
            je        .clear_eoi
            cmp       bl, 0x38
            je        .clear_eoi
            cmp       bl, 0x3A
            je        .clear_eoi

            ; scancode -> ASCII
            mov       al, bl
            xor       bh, bh
            test      byte [BDA_KBD_FLAGS], 0x01
            jz        .nomod
            mov       si, kbd_map_shift
            jmp       .doxlat
.nomod:
            mov       si, kbd_map_nomod
.doxlat:
            ; XLAT uses DS:BX, so set BX = scancode and DS points to table.
            ; On ne veut pas changer DS=0x40. Donc on ne peut pas XLAT directement ici.
            ; => on fait un accès indexé.
            ; AL = [CS:SI + scancode]
            push      ds
            mov       ax, cs
            mov       ds, ax
            xor       ah, ah
            mov       di, si
            add       di, bx
            mov       al, [di]
            pop       ds

            ; AX = (scancode<<8) | ascii
            mov       ah, bl
            call      kbd_buf_push

.clear_eoi:
            and       byte [BDA_KBD_FLAGS], 0xEF      ; clear ext
.eoi:
            mov       al, i8259_MASTER_CMD
            out       i8259_MASTER_CMD, al
            popa
            pop       ds
            iret

; -----------------------------------------------------------
; Met à jour les modifiers sur make code
; Entrée: AL = scancode (sans bit7)
; -----------------------------------------------------------
kbd_update_modifiers_make:
            ; AL = scancode (make)
            cmp       al, 0x2A
            je        .shift_on
            cmp       al, 0x36
            je        .shift_on
            cmp       al, 0x1D
            je        .ctrl_on
            cmp       al, 0x38
            je        .alt_on
            cmp       al, 0x3A
            je        .caps_toggle
            ret
.shift_on:
            or        byte [BDA_KBD_FLAGS], 0x01
            ret
.ctrl_on:
            or        byte [BDA_KBD_FLAGS], 0x02
            ret
.alt_on:
            or        byte [BDA_KBD_FLAGS], 0x04
            ret
.caps_toggle:
            xor       byte [BDA_KBD_FLAGS], 0x08
            ret

kbd_update_modifiers_break:
            ; AL = scancode (break)
            cmp       al, 0x2A
            je        .shift_off
            cmp       al, 0x36
            je        .shift_off
            cmp       al, 0x1D
            je        .ctrl_off
            cmp       al, 0x38
            je        .alt_off
            ret
.shift_off:
            and       byte [BDA_KBD_FLAGS], 0xFE
            ret
.ctrl_off:
            and       byte [BDA_KBD_FLAGS], 0xFD
            ret
.alt_off:
            and       byte [BDA_KBD_FLAGS], 0xFB
            ret
