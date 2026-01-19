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

kbc_wait_in_empty:
            in        al, i8042_PS2_CTRL
            test      al, 0x02          ; IBF
            jnz       kbc_wait_in_empty
            ret

kbc_wait_out_full:
            in        al, i8042_PS2_CTRL
            test      al, 0x01          ; OBF
            jz        kbc_wait_out_full
            ret

kbc_flush_output:
            in        al, i8042_PS2_CTRL
            test      al, 0x01          ; OBF ?
            jz        .done
            in        al, i8042_PS2_DATA; jette la donnée
            jmp       kbc_flush_output
.done:
            ret


kbc_read_cmdbyte:
            call        kbc_wait_in_empty
            mov         al, 0x20
            out         i8042_PS2_CTRL, al
            call        kbc_wait_out_full
            in          al, i8042_PS2_DATA
            ret

kbc_write_cmdbyte:
            ; entrée: AL = nouveau command byte
            push        ax
            call        kbc_wait_in_empty
            mov         al, 0x60
            out         i8042_PS2_CTRL, al
            call        kbc_wait_in_empty
            pop         ax
            out         i8042_PS2_DATA, al
            ret
kbd_init:
            push      ds
            push      ax

            ; gestion du buffer clavier
            mov       ax, BDA_SEGMENT
            mov       ds, ax
            mov       byte [BDA_KBD_HEAD], 0
            mov       byte [BDA_KBD_TAIL], 0
            mov       byte [BDA_KBD_FLAGS], 0

            cli

;           call      kbc_wait_in_empty
;           mov       al, 0x20
;           out       i8042_PS2_CTRL, al
;
;           call      kbc_wait_out_full
;           in        al, i8042_PS2_DATA             ; AL = command byte
;
;           or        al, 0x01                      ; bit0: enable IRQ1
;           and       al, 0xEF                      ; bit4: 0 = keyboard enabled
;
;           mov       ah, al                        ; save new cmd byte
;
;           ; write command byte
;           call      kbc_wait_in_empty
;           mov       al, 0x60
;           out       i8042_PS2_CTRL, al
;
;           call      kbc_wait_in_empty
;           mov       al, ah
;           out       i8042_PS2_DATA, al
;
;           ; unmask IRQ1 & IRQ2 (master bit 1 & 2 = 0) bit 1 = IRQ 1
;           in        al, i8259_MASTER_DATA
;           and       al, 0xF9                      ; 11111001b
;           out       i8259_MASTER_DATA, al

            ; setup Interrupt Table
            ; installer IRQ1 : MASTER_OFFSET + 1
            mov       ax, i8259_MASTER_INT          ; base offset IRQ0
            inc       ax                            ; IRQ 1
            shl       ax,2                          ; vect * 4
            mov       si, ax

            xor       ax, ax                        ; segment 0x0000
            mov       ds, ax
            mov       word [ds:si], kbd_isr
            mov       ax, cs
            mov       word [ds:si+2], ax

            mov       si, 0x09*4
            xor       ax, ax
            mov       ds, ax
            mov       word [ds:si], kbd_isr
            mov       ax, cs
            mov       word [ds:si+2], ax

            sti

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

            mov         ax,0x0050
            mov         ds,ax
            inc         byte [0x0000]

            mov         al, PIC_EOI            ; EOI master
            out         i8259_MASTER_CMD, al

            pop         ds
            popa
            iret