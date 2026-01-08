; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : textmode.asm
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

;
; text mod functions
; 
;

vid_seg			dw				VIDEO_SEG
cursor_ofs 	dw 				0
txt_attr		db				VIDEO_ATTR


; -----------------------------------------------------------------------------
; cls : efface l'écran en remplissant txtmode_CELLS cellules par " " + ATTR
; -----------------------------------------------------------------------------
txtmode_clear:
						mov   		ax,0xB800						; select video segment
						mov   		es,ax
						xor   		ax,ax								; 0
						; mov				[cursor_ofs],ax			; reset 'virtual' cursor
						mov   		di,ax
						; default attr + space
						mov   		ah, [txt_attr]
						mov				al, ' '
						;
						mov   		cx,2000							; 25x80
						rep  	 		stosw								; attr + char
						ret

; -----------------------------------------------------------------------------
; puts : imprime une chaîne ASCIIZ (DS:SI) en VRAM (ES:cursor_ofs)
; - gère '\n' (LF=10) comme nouvelle ligne
; - ignore '\r' (CR=13)
; -----------------------------------------------------------------------------
txtmode_puts:
.next:
						lodsb                    	; AL = *SI++
						test 			al, al
						jz   			.done

						cmp  			al, 10               ; '\n'
						je   			.lf
						cmp  			al, 13               ; '\r'
						je   			.next

						call 			txtmode_putc
						jmp  			.next

.lf:
						call 			txtmode_newline
						jmp  			.next
.done:
						ret

; -----------------------------------------------------------------------------
; putc : imprime le caractère AL à la position du curseur logiciel
; -----------------------------------------------------------------------------
txtmode_putc:
						push 			ax
						push 			bx
						push 			di

						mov 			di, [cursor_ofs]
						; écrire char + attr
						mov 			ah, txt_attr
						stosw                           ; écrit AX à ES:DI, puis DI += 2

						; mettre à jour cursor_ofs
						mov 			[cursor_ofs], di

						; si fin d'écran, on “reboucle” au début (simple)
						; (vous pouvez remplacer par un scroll si besoin)
						mov 			bx, 4000										; 80x25x2
						cmp 			di, bx
						jb  			.ok
						mov 			word [cursor_ofs], 0
.ok:
						pop 			di
						pop 			bx
						pop 			ax
						ret

; -----------------------------------------------------------------------------
; newline : avance le curseur au début de la ligne suivante (80 colonnes)
; -----------------------------------------------------------------------------
txtmode_newline:
						push 			ax
						push 			dx

						mov 			ax, [cursor_ofs]            ; offset en octets
						xor				dx, dx
						mov 			cx, 160								      ; taille d'une ligne en octets = 160
						div 			cx                          ; AX = ligne, DX = reste (offset dans la ligne)

						inc 			ax                          ; ligne suivante
						cmp 			ax, 25
						jb  			.set
						xor 			ax, ax                      ; si dépasse, revient en haut (simple)
.set:
						
						mov 			cx, 160											; cursor_ofs = ligne * 160
						mul 			cx                          ; DX:AX = AX*CX ; ici AX suffit
						mov 			[cursor_ofs], ax
			
						pop 			dx
						pop 			ax
						ret

