; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : mouse_ps2.asm
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
; controleur de souris via le i8042 (PC Classique)
;

%define	PS2_PORT_BUFFER		0x60
%define	PS2_PORT_CTRL			0x64

%define	MOUSE_CMD_RESET		0xff
%define	MOUSE_CMD_DEFAULT	0xf6
%define MOUSE_EN_STREAM		0xf4
%define MOUSE_DIS_STREAM	0xf5

mouse_arrow:
						dw 1001111111111111b    ; 0x9FFF
						dw 1000111111111111b    ; 0x8FFF
						dw 1000011111111111b    ; 0x87FF
						dw 1000001111111111b    ; 0x83FF
						dw 1000000111111111b    ; 0x81FF
						dw 1000000011111111b    ; 0x80FF
						dw 1000000001111111b    ; 0x807F
						dw 1000000000111111b    ; 0x803F
						dw 1000000000011111b    ; 0x801F
						dw 1000000000001111b    ; 0x800F
						dw 1000000011111111b    ; 0x80FF
						dw 1000100001111111b    ; 0x887F
						dw 1001100001111111b    ; 0x987F
						dw 1111110000111111b    ; 0xFC3F
						dw 1111110000111111b    ; 0xFC3F
						dw 1111111000111111b    ; 0xFE3F
						dw 0000000000000000b    ; 0x0000
						dw 0010000000000000b    ; 0x2000
						dw 0011000000000000b    ; 0x3000
						dw 0011100000000000b    ; 0x3800
						dw 0011110000000000b    ; 0x3C00
						dw 0011111000000000b    ; 0x3E00
						dw 0011111100000000b    ; 0x3F00
						dw 0011111110000000b    ; 0x3F80
						dw 0011111111000000b    ; 0x3FC0
						dw 0011111000000000b    ; 0x3E00
						dw 0011011000000000b    ; 0x3600
						dw 0010001100000000b    ; 0x2300
						dw 0000001100000000b    ; 0x0300
						dw 0000000110000000b    ; 0x0180
						dw 0000000110000000b    ; 0x0180
						dw 0000000000000000b    ; 0x0000

mouse_init:
						; Activer le port souris
						mov				ax, BDA_SEGMENT
						mov				ds,ax
						
						; effacer les variables du drivers
						mov				[BDA_MOUSE_IDX],0
						mov				dword [BDA_MOUSE_BUFFER],0
						
						mov 			al, 0xA8
						out 			PS2_PORT_CTRL, al

						; Lire le command byte
						mov 			al, 0x20
						out 			PS2_PORT_CTRL, al
						in  			al, PS2_PORT_BUFFER

						; Activer IRQ12 (bit 1)
						or  			al, 0x02

						; Réécrire le command byte
						mov 			ah, al
						mov 			al, PS2_PORT_BUFFER
						out 			PS2_PORT_CTRL, al
						mov 			al, ah
						out 			PS2_PORT_BUFFER, al
						ret

; envoyer une commande souris						
mouse_sendcmd:
.wait:
						in  			al, PS2_PORT_CTRL
						test 			al, 2
						jnz 			.wait
						mov 			al, 0xD4
						out 			PS2_PORT_CTRL, al

.wait2:
						in  			al, PS2_PORT_CTRL
						test 			al, 2
						jnz 			.wait2
						mov 			al, bl        ; BL = commande souris
						out 			PS2_PORT_BUFFER, al
						ret

mouse_handler:
					push 				ax
					push 				bx
					
					; use BDA segment
					push				ds
					mov					ax,BDA_SEGMENT
					mov					ds,ax
					xor					bx,bx

					in  				al, PS2_PORT_BUFFER   ; lire octet souris
					mov 				[BDA_MOUSE_BUFFER + BDA_MOUSE_IDX], al
					inc					[BDA_MOUSE_IDX]
					
					cmp 				[BDA_MOUSE_IDX], 3
					jne 				.done

					mov 				[BDA_MOUSE_IDX], 0
					; decode buffer
					mov					al, [BDA_MOUSE_BUFFER+1]
					cbw
					add					[BDA_MOUSE_X], ax
					
					mov					al, [BDA_MOUSE_BUFFER+2]
					cbw
					sub					[BDA_MOUSE_Y], ax

.done:
					mov 				al, 0x20
					out 				0xA0, al          ; EOI PIC esclave
					out 				0x20, al          ; EOI PIC maître
					
					pop					ds
					pop 				bx
					pop 				ax
					iret