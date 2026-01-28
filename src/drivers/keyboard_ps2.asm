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

kbd_flush:
    in        al, 0x64              ; Lire le Status Register
    test      al, 1                 ; Est-ce qu'il y a une donnée (Output Buffer Full) ?
    jz        .done
    in        al, 0x60              ; Lire et ignorer la donnée
    jmp       kbd_flush
.done:
    ret

kbd_init:
    push      ds
    push      ax
    call      kbd_flush
    ; gestion du buffer clavier

    mov       ax,cs                     ; get current CS
    mov       dx,ax
    mov       bx,kbd_isr                ; Event handler
    mov       ax, i8259_MASTER_INT      ; base offset IRQ 0
    inc       ax                        ; IRQ 1
    call      ivt_setvector

    ; enable IRQ 1
    mov       ah,IRQ_ENABLED
    mov       al,1
    call      pic_set_irq_mask
    pop       ax
    pop       ds
    ret

; -----------------------------------------------------------
; Keyboard ISR (IRQ -> INT)
; -----------------------------------------------------------
kbd_isr:
    pusha
    push        ds

    in          al, 0x60               ; consomme scancode (obligatoire)

    mov         al, PIC_EOI            ; EOI master
    out         i8259_MASTER_CMD, al

    pop         ds
    popa
    iret