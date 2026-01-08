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
%define BDA_SEGMENT          0x0040

%define PS2_PORT_BUFFER      0x60
%define PS2_PORT_CTRL        0x64

%define MOUSE_CMD_RESET      0xFF
%define MOUSE_CMD_DEFAULT    0xF6
%define MOUSE_EN_STREAM      0xF4
%define MOUSE_DIS_STREAM     0xF5
%define MOUSE_GET_ID         0xF2
%define MOUSE_SET_RATE       0xF3

%define MOUSE_ACK            0xFA

%define I8042_CMD_EN_AUX     0xA8
%define I8042_CMD_RD_CBYTE   0x20
%define I8042_CMD_WR_CBYTE   0x60
%define I8042_CMD_WRITE_AUX  0xD4

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

; ------------------------------------------------------------
; initialise le i8042 keyboard and mouse (PS/2)
;
; ------------------------------------------------------------
mouse_init:
						; Activer le port souris
						mov				ax, BDA_SEGMENT
						mov				ds,ax
						
						; effacer les variables du drivers
						mov				[BDA_MOUSE_IDX],0
						mov				dword [BDA_MOUSE_BUFFER],0
						mov				byte [DBA_MOUSE_PACKETLEN],3
						
						call 			ps2_flush_output

						; Activer le port souris (AUX)
						call 			ps2_wait_ready_write
						mov  			al, I8042_CMD_EN_AUX
						out  			PS2_PORT_CTRL, al
						
						; Lire command byte
						call 			ps2_wait_ready_write
						mov  			al, I8042_CMD_RD_CBYTE
						out  			PS2_PORT_CTRL, al
						call 			ps2_read						         ; AL = command byte
						
						; Activer IRQ12 (bit 1)
						or   			al, 02h
						mov  			ah, al

						; Réécrire command byte  (commande 0x60 envoyée à 0x64)
						call 			ps2_wait_ready_write
						mov  			al, I8042_CMD_WR_CBYTE
						out  			PS2_PORT_CTRL, al
						call 			ps2_wait_ready_write
						mov  			al, ah
						out  			PS2_PORT_BUFFER, al

						call 			ps2_flush_output

						; --- RESET souris: FA, AA, ID
						mov 			bl, MOUSE_CMD_RESET
						call 			mouse_sendcmd
						call 			ps2_read			         ; 0xAA attendu (self-test OK)
						call 			ps2_read			         ; ID (souvent 0x00)

						; Defaults: FA
						mov			 	bl, MOUSE_CMD_DEFAULT
						call 			mouse_sendcmd

						; Enable streaming: FA
						mov 			bl, MOUSE_EN_STREAM
						call 			mouse_sendcmd

						; (option) détecter 3/4 bytes via F3 200/100/80 + F2
						; call mouse_detect_packet_len

						; installer ISR IRQ12 (INT 74h)
						; call mouse_install_isr

						
						
						; installer le handler
						ret
						
mouse_detect_packet_len:
						mov byte [DBA_MOUSE_PACKETLEN], 3

						; F3 200
						mov bl, MOUSE_SET_RATE
						call mouse_sendcmd
						mov bl, 200
						call mouse_sendcmd

						; F3 100
						mov bl, MOUSE_SET_RATE
						call mouse_sendcmd
						mov bl, 100
						call mouse_sendcmd

						; F3 80
						mov bl, MOUSE_SET_RATE
						call mouse_sendcmd
						mov bl, 80
						call mouse_sendcmd

						; F2 -> ID
						mov bl, MOUSE_GET_ID
						call mouse_sendcmd
						call ps2_read					         ; AL = ID

						cmp al, 03h
						je  .is4
						cmp al, 04h
						je  .is4
						ret
.is4:
						mov byte [DBA_MOUSE_PACKETLEN], 4
						ret
						
; ------------------------------------------------------------
; fonction de gestion du i8042
;
; ------------------------------------------------------------

; attendre que le 8042 soit pret a recevoir de l'information
ps2_wait_ready_write:
.wait:
						in   			al, PS2_PORT_CTRL
						test 			al, 02h              ; IBF
						jnz  			.wait
						ret			

; attendre que le 8042 soit pret a lire de l'information			
ps2_wait_ready_read:
.wait:			
						in   			al, PS2_PORT_CTRL
						test 			al, 01h              ; OBF
						jz   			.wait
						ret			
			
; lire de l'information depuis le 8042
ps2_read:			
						call 			ps2_wait_ready_read
						in   			al, PS2_PORT_BUFFER
						ret			

; vide le buffer interne du 8042 (information(s) ignorée(s)) 
ps2_flush_output:
.flush:			
						in   			al, PS2_PORT_CTRL
						test 			al, 01h
						jz   			.done
						in   			al, PS2_PORT_BUFFER
						jmp  			.flush
.done:
						ret
						


; ------------------------------------------------------------
; envoye une commande souris
;
; BL = commande souris (ou data après une commande F3)
; 
; renvoi CF=0 si ACK, CF=1 sinon
; ------------------------------------------------------------
mouse_sendcmd:
						call 			ps2_wait_ready_write

						mov  			al, I8042_CMD_WRITE_AUX
						out  			PS2_PORT_CTRL, al
			
						call 			ps2_wait_ready_write
						mov  			al, bl
						out  			PS2_PORT_BUFFER, al
			
						call 			ps2_wait_ready_read        ; AL = réponse
						cmp  			al, MOUSE_ACK
						jne  			.bad
						clc
						ret
.bad:
						stc
						ret
						
; ------------------------------------------------------------
; interrupt handler
; 
; buffer[0] = status
; buffer[1] = déplacement x
; buffer[2] = déplacement y (inversé)
; 
; ------------------------------------------------------------
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