; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : boot.asm
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

BITS			16
org				0

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



						jmp				reset								; ce jump n'est pas sensé être executer, il est présent uniquement pour le debug

; definition du BDA
%include 		".\bda.asm"

%include 		".\drivers\debug.asm"
%include		".\drivers\gfx_cgam.asm"
%include		".\drivers\mouse_ps2.asm"
%include 		".\services\generic.asm"

err_vganok	db				'VGA Not Initialized',0
err_end			db				'code completed successfully',0

reset:
						cli
						; il n'existe aucun 'stack' par défaut
						mov				ax, STACK_SEG
						mov 			ss, ax
						mov 			sp, STACK_TOP     	; haut du segment, mot-aligné
						
						; detection de la mémoire totale
						call			setup_ram
						; modification du stack en "haut" de la RAM
						mov 			ax, dx
						sub 			ax, 0x0400       ; réserver les 16 dernier KB 
						mov 			ss, ax
						mov 			sp, 0x1000       ; sommet de pile
						
						; installé une table d'interruption "dummy"
						call 			setup_ivt
						sti

						; load other Rom
						call 			setup_load_rom
						
						; on vérifie que le BIOS VGA a installer l'INT 10h
						call			setup_check_vga
						
						call			gfx_init
						
						mov				cx,50
.bcl:				; mov				dx,cx
						mov				bl,0
						push 			cx
						call			gfx_putpixel
						pop				cx
						inc				cx
						cmp				cx,150
						jle				.bcl
						
						call			mouse_init
						
						mov				ax,cs
						mov				ds,ax

						mov				si, err_end
						call			debug_puts
											
endless:		hlt
						jmp				endless

; ------------------------------------------------------------------
; Padding jusqu'au reset vector
; ------------------------------------------------------------------
times 0xFFF0 - ($ - $$) db 0xFF

; ------------------------------------------------------------------
; RESET VECTOR (exécuté par le CPU)
; ------------------------------------------------------------------
reset_vector:
						jmp far 	0xF000:reset
; filling						
builddate 	db 				'06/01/2026',0

