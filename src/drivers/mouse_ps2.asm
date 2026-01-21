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

; commandes
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
%define I8042_CMD_DIS_KBD		 0xAD
%define I8042_CMD_DIS_MOUSE	 0xA7
%define I8042_CMD_WRITE_AUX  0xD4

%include "./services/cursor.asm"

; ------------------------------------------------------------
; remise a zero des valeurs internes du "drivers"
;
; ------------------------------------------------------------
mouse_reset:
						mov				ax, BDA_DATA_SEG
						mov				fs,ax

						; effacer les variables du drivers
						mov				byte  [fs:BDA_MOUSE + mouse.idx],0
						mov				dword [fs:BDA_MOUSE + mouse.buffer],0
						mov				byte  [fs:BDA_MOUSE + mouse.packetlen],3	; 3 bytes par défaut

						mov				byte [fs:BDA_MOUSE + mouse.status],0
						mov				word [fs:BDA_MOUSE + mouse.x],320					; vous pouvez aussi préciser le centre
						mov				word [fs:BDA_MOUSE + mouse.y],100					; vous pouvez aussi préciser le centre

						; experiemntal
						mov				word [fs:BDA_MOUSE + mouse.wheel],0

						mov			 	byte [fs:BDA_MOUSE + mouse.cur_visible], 1
						mov       word [fs:BDA_MOUSE + mouse.cur_x], 0
						mov       word [fs:BDA_MOUSE + mouse.cur_y], 0

						mov 			ax, cs
						mov 			word [fs:BDA_MOUSE + mouse.cur_seg], ax
						mov 			word [fs:BDA_MOUSE + mouse.cur_ofs], mouse_arrow
						ret

; ------------------------------------------------------------
; initialise le i8042 keyboard and mouse (PS/2)
;
; on envoit les commandes RESET/DEFAULT/STREAM
; ------------------------------------------------------------
mouse_init:
						push			ds
						push			ax

						; reset des valeurs internes
						call			mouse_reset

						cli

						call 			ps2_wait_ready_write
						mov 			al, I8042_CMD_DIS_KBD 		; Disable Keyboard
    				out  			i8042_PS2_CTRL, al

						call			ps2_wait_ready_write
						mov  			al, I8042_CMD_DIS_MOUSE 	; Disable Mouse
						out  			i8042_PS2_CTRL, al

						; Vider tout ce qui traîne
    				call ps2_flush_output

						; Activer le port souris (AUX)
						call 			ps2_wait_ready_write
						mov  			al, I8042_CMD_EN_AUX
						out  			i8042_PS2_CTRL, al

						; Lire command byte
						call 			ps2_wait_ready_write
						mov  			al, I8042_CMD_RD_CBYTE
						out  			i8042_PS2_CTRL, al

						call 			ps2_read						         ; AL = command byte

						; Activer IRQ12 (bit 1)
						or   			al, 02h
						mov  			ah, al

						; Réécrire command byte  (commande 0x60 envoyée à 0x64)
						call 			ps2_wait_ready_write
						mov  			al, I8042_CMD_WR_CBYTE
						out  			i8042_PS2_CTRL, al
						call 			ps2_wait_ready_write
						mov  			al, ah
						out  			i8042_PS2_DATA, al

						call 			ps2_flush_output

						; --- Reset
						; réponse attendue : 0xAA, [ID]
						mov 			bl, MOUSE_CMD_RESET
						call 			mouse_sendcmd
						call 			ps2_read			         ; 0xAA attendu (self-test OK)
						call 			ps2_read			         ; ID (souvent 0x00)

						; --- Default
						mov			 	bl, MOUSE_CMD_DEFAULT
						call 			mouse_sendcmd

						; --- streaming
						mov 			bl, MOUSE_EN_STREAM
						call 			mouse_sendcmd

						; détecter le packet size (3/4 bytes)
						call 			mouse_detect_packet_len

						; installer ISR IRQ12 (INT 74h)

						mov       ax,cs
            mov       dx,ax
            mov       bx, isr_mouse_handler

            mov       ax, i8259_SLAVE_INT	          ; base offset IRQ8
            add       ax,4                          ; IRQ 12

            call      ivt_setvector

            ; enable IRQ 1
            mov       ah,IRQ_ENABLED
            mov       al, 12
            call      pic_set_irq_mask

						sti
						pop				ax
						pop				ds
						ret

; ------------------------------------------------------------
; detect la taille du "payload" de la souris.
;
; On envois les commandes 200/100/
;
; ------------------------------------------------------------
mouse_detect_packet_len:
						mov				ax, BDA_DATA_SEG
						mov				fs,ax

						mov 			byte [fs:BDA_MOUSE + mouse.packetlen], 3

						; SET_RATE + 200
						mov 			bl, MOUSE_SET_RATE
						call 			mouse_sendcmd
						mov 			bl, 200
						call 			mouse_sendcmd

						; SET_RATE + 100
						mov 			bl, MOUSE_SET_RATE
						call 			mouse_sendcmd
						mov 			bl, 100
						call 			mouse_sendcmd

						; SET_RATE + 80
						mov 			bl, MOUSE_SET_RATE
						call 			mouse_sendcmd
						mov 			bl, 80
						call 			mouse_sendcmd

						; Get ID
						mov 			bl, MOUSE_GET_ID
						call 			mouse_sendcmd
						call 			ps2_read					         ; AL = ID

						cmp 			al, 03h
						je  			.is4
						cmp 			al, 04h
						je  			.is4
						ret
.is4:
						mov 			byte [fs:BDA_MOUSE + mouse.packetlen], 4
						ret

; ------------------------------------------------------------
; fonction de gestion du i8042
;
; ------------------------------------------------------------

; attendre que le 8042 soit pret a recevoir de l'information
ps2_wait_ready_write:
						push			cx
						mov				cx, 1000
.wait:
						in   			al, i8042_PS2_CTRL
						test 			al, 02h              ; IBF
						jz				.ok
						loop  			.wait
.ok:
						pop				cx
						ret

; attendre que le 8042 soit pret a lire de l'information
ps2_wait_ready_read:
.wait:
						in   			al, i8042_PS2_CTRL
						test 			al, 01h              ; OBF
						jz   			.wait
						ret

; lire de l'information depuis le 8042
ps2_read:
						call 			ps2_wait_ready_read
						in   			al, i8042_PS2_DATA
						ret

; vide le buffer interne du 8042 (information(s) ignorée(s))
ps2_flush_output:
.flush:
						in   			al, i8042_PS2_CTRL
						test 			al, 01h
						jz   			.done
						in   			al, i8042_PS2_DATA
						jmp  			.flush
.done:
						ret

; ------------------------------------------------------------
; envoye une commande souris et attends le ACK
;
; BL = commande souris (ou data après une commande F3)
;
; renvoi CF=0 si ACK, CF=1 sinon
; ------------------------------------------------------------
mouse_sendcmd:
						call 			ps2_wait_ready_write

						mov  			al, I8042_CMD_WRITE_AUX
						out  			i8042_PS2_CTRL, al

						call 			ps2_wait_ready_write
 						mov  			al, bl
						out  			i8042_PS2_DATA, al

						call 			ps2_read        					; AL = réponse
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
; buffer[4] = molette (si PacketLen = 4)
;
; status byte :
;    bit 0 = bouton gauche
;    bit 1 = bouton droit
;    bit 2 = bouton milieu
;    bit 3 = toujours 1
;    bit 4 = X sign
;    bit 5 = Y sign
;    bit 6 = X overflow
;    bit 7 = Y overflow
; ------------------------------------------------------------
isr_mouse_handler:
					; sauvegarder tout les registres
					pusha
					push				ds

					; use BDA segment
					mov					ax,BDA_DATA_SEG
					mov					ds,ax

					; lire un octet depuis le contrôleur et le stocker dans le buffer
					in  				al, i8042_PS2_DATA   					; lire octet souris
					movzx 			bx, byte [BDA_MOUSE + mouse.idx]
					mov 				byte [BDA_MOUSE + mouse.buffer + bx], al
					inc					byte [BDA_MOUSE + mouse.idx]

					; vérifier si le packet est complet
					mov 				al, [BDA_MOUSE + mouse.packetlen]
					cmp 				byte [BDA_MOUSE + mouse.idx], al
					jne 				.done

					; packet complet, on decode les données
					mov 				byte [BDA_MOUSE + mouse.idx], 0
					mov 				al, [BDA_MOUSE + mouse.buffer]					; status
					mov 				[BDA_MOUSE + mouse.status], al

					xor					ax,ax
					mov  				al, byte [BDA_MOUSE + mouse.buffer+1]				; delta X
					cbw
					add					[BDA_MOUSE + mouse.x], ax

					xor					ax,ax
					mov 				al, byte [BDA_MOUSE + mouse.buffer+2]				; delta Y
					cbw
					sub					[BDA_MOUSE + mouse.y], ax

					; si packetlen = 4, gérer la molette; experimental
					movsx				ax, byte [BDA_MOUSE + mouse.buffer+3]				; delta Wheel
					cbw
					add					word [BDA_MOUSE + mouse.wheel], ax

					; clamp X
					cmp 				word [BDA_MOUSE + mouse.x], 0
					jge 				.x_ok_low
					mov 				word [BDA_MOUSE + mouse.x], 0
.x_ok_low:
					cmp 				word [BDA_MOUSE + mouse.x], 639
					jle					.x_ok_high
					mov 				word [BDA_MOUSE + mouse.x], 639
.x_ok_high:

					; clamp Y
					cmp 				word [BDA_MOUSE + mouse.y], 0
					jge 				.y_ok_low
					mov 				word [BDA_MOUSE + mouse.y], 0
.y_ok_low:
					cmp 				word [BDA_MOUSE + mouse.y], 199
					jle 				.y_ok_high
					mov 				word [BDA_MOUSE + mouse.y], 199
.y_ok_high:
					; restaurer l'ancien arrière plan du curseur
					call				gfx_cursor_restorebg

					; sauvegarder le nouvel arrière plan du curseur
					call				gfx_cursor_savebg

					call				gfx_cursor_draw

.done:
					mov 				al, 0x20
					out 				i8259_SLAVE_CMD, al      ; EOI PIC esclave
					out 				i8259_MASTER_CMD, al     ; EOI PIC maître

					; restaurer tous les registres
					pop					ds
					popa
					iret