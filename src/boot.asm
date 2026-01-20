; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : boot.asm
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

bits			16
; ---------------------------------------------------------------------------
;
; configuration du bios
;
; ---------------------------------------------------------------------------
%define DEBUG_PORT		0xe9								; 0x402 ou 0xe9

; initial stack
%define STACK_SEG   	0x1000							; segment de base

section 		.text
bits				16

; definition du BDA
%include 		"./bda.asm"

; %include 		"./services/macros.asm"
%include 		"./drivers/debug.asm"
%include		"./drivers/gfx_cgam.asm"
%include		"./drivers/mouse_ps2.asm"
%include 		"./drivers/keyboard_ps2.asm"
%include 		"./services/generic.asm"

err_vganok	db				'VGA Not Initialized',0
;err_end			db				'code completed successfully',0

reset:
						cli
						cld

						; il n'existe aucun 'stack' par défaut
						mov				ax, STACK_SEG
						mov 			ss, ax
						mov 			sp, 0xFFFE     	; haut du segment (64ko de stack), mot-aligné

						; installé une table d'interruption "dummy"
						call 			ivt_setup

						call			bda_setup

						; test IRQ 0
						mov				ax,cs
						mov				dx,ax
						mov				bx,test_isr
						mov				ax,i8259_MASTER_INT

						call			ivt_setvector

						; initialisation des PIC 8259A
						call 			pic_init

						; load Roms
						call 			setup_load_rom

						; on vérifie que le BIOS VGA a installé une INT 10h
						call			setup_check_vga

						; on initialise le mode texte 80x25 par défaut DEBUG
						;mov				ax, 0x0003
						;int				10h

						; enable IRQ 0
            mov       ah,IRQ_ENABLED
            mov       al,0
            call      pic_set_irq_mask

						call 			kbd_init
						sti

						; on active le mode graphique
						call			gfx_init

						;call 			mouse_reset
						call			mouse_init
endless:
						mov				ax,BDA_DATA_SEG
						mov				ds,ax

						mov				dx,0
						call			scr_gotoxy

						mov				ax,0					; adresse début dump
						mov				si,ax
						mov				cx, 0x20
.dump:
						test 			cx,0x000F
						jnz				.sameline
						inc				dh
						xor				dl,dl
						call			scr_gotoxy
.sameline:
						mov				al,[ds:si]
						inc				si

						push			ds
						push			si

						call			scr_puthex8
						mov				al,' '
						call			scr_putc

						pop				si
						pop				ds

						loop			.dump

						jmp				endless


; -----------------------------------------------------------
; Keyboard ISR (IRQ -> INT)
; -----------------------------------------------------------
test_isr:
            push			  ax

            ; push        fs
            ;mov         ax,BDA_DATA_SEG
            ;mov         fs,ax
						;inc         byte [fs:0x0005]

            mov         al, PIC_EOI            ; EOI master
            out         i8259_MASTER_CMD, al
            ; pop         fs

            pop					ax
            iret

; ------------------------------------------------------------------
; Padding jusqu'au reset vector
; ------------------------------------------------------------------
times 0xFFF0 - ($ - $$) db 0xFF

; ------------------------------------------------------------------
; RESET VECTOR (exécuté par le CPU)
; ------------------------------------------------------------------
section 		.resetvect
bits 				16
global			reset_vector

reset_vector:
    				; code minimal au reset
				    jmp 			0xF000:reset
builddate 	db 				'06/01/2026'
						times 		16-($-$$) db 0   ; le stub tient dans 16 octets (ou moins)


