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
%define STACK_SEG   	0x0030							; compatible avec le BMM (Bios Memory Maps)
%define STACK_TOP    	0x0100        			; choix commun en RAM basse (pile descendante)

%define MEM_SEG_DEB		0x0800 						  ; 0x0800:0000 = 0x8000 (32KB) évite IVT/BDA + stack 7C00
%define MEM_SEG_END   0xA000    					; 0xA000:0000 = 0xA0000 (début zone vidéo)
%define MEM_SEG_STEP  0x0040    					; 1KB = 0x400 bytes = 0x40 paragraphs


section 		.text
bits				16
						jmp				reset								; ce jump n'est pas sensé être executer, il est présent uniquement pour le debug

; definition du BDA
%include 		"./bda.asm"

%include 		"./services/macros.asm"
%include 		"./drivers/debug.asm"
%include		"./drivers/gfx_cgam.asm"
;%include		"./drivers/mouse_ps2.asm"
;%include 		"./drivers/keyboard_ps2.asm"
%include 		"./services/generic.asm"

err_vganok	db				'VGA Not Initialized',0
;err_end			db				'code completed successfully',0

reset:
						cli
						; il n'existe aucun 'stack' par défaut
						mov				ax, STACK_SEG
						mov 			ss, ax
						mov 			sp, STACK_TOP     	; haut du segment, mot-aligné

						; detection de la mémoire totale
						call			ram_setup
						sti

						; modification du stack en "haut" de la RAM
						mov 			ax, dx
						sub 			ax, 0x0400       ; réserver les 16 dernier KB
						mov 			ss, ax
						mov 			sp, 0x1000       ; sommet de pile

						; initialisation du BDA
						call			bda_setup

						; installé une table d'interruption "dummy"
						call 			ivt_setup

						; load Roms
						call 			setup_load_rom

						; on vérifie que le BIOS VGA a installé une INT 10h
						call			setup_check_vga

						; on initialise le mode texte 80x25 par défaut DEBUG
						mov				ax, 0x0003
						int				10h

						cli
						; initialisation des PIC 8259A
						call 			pic_init
;						call 			kbd_init

						; test IRQ 0
						mov				ax,cs
						mov				dx,ax
						mov				bx,test_isr
						mov				ax,i8259_MASTER_INT

						call			ivt_setvector

						sti

						; on active le mode graphique
						; call			gfx_init

						;call 			mouse_reset
						;call			mouse_init
endless:
						mov				ax,0x0050
						mov				ds,ax

;						in  			al, 0x64
;						test 			al, 1          				; OBF
;						jz  			.no
;						in  			al, 0x60        			; scancode dans AL
;						mov				byte [0x0001],al
;.no:

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
            pusha
            push        ds

            mov         ax,0x0050
            mov         ds,ax
            inc         byte [0x0005]

            mov         al, PIC_EOI            ; EOI master
            out         i8259_MASTER_CMD, al

            pop         ds
            popa
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
times 16-($-$$) db 0   ; le stub tient dans 16 octets (ou moins)


