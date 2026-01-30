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

	bits	16
; ---------------------------------------------------------------------------
;
; configuration du bios
;
; ---------------------------------------------------------------------------
%define 	DEBUG_PORT	0xe9		; 0x402 ou 0xe9

; initial stack
%define 	STACK_SEG   0x0800		; segment de base

;section		.text
;	bits	16
;
;	db		'EXTRA CODE Section',0
;
;	times 	0xFFFF - ($ - $$) db 0xFF

section     .text
    bits	16

%include	"./common/chartable.asm"
%include	"./common/cursor.asm"

; definition du BDA
%include 	"./bda.asm"

; %include 	"./services/macros.asm"
%include 	"./common/debug_cga.asm"
%include	"./drivers/gfx_cgam.asm"
%include	"./drivers/mouse_ps2.asm"
%include 	"./drivers/keyboard_ps2.asm"
%include 	"./services/generic.asm"
%include	"./services/gui_window.asm"

err_vganok	db	'VGA Not Initialized',0

cpt_txt		db 	'0123456789A123456789B123456789C123456789D123456789E123456789F123456789G123456789',0
helloworld	db 	'Hello World !',0

W_T			db	'1 - TEXT WHITE - TRANSPARENT',0
B_T 		db 	'2 - TEXT BLACK - TRANSPARENT',0
W_B 		db 	'3 - TEXT WHITE - ON BLACK',0
B_W 		db 	'4 - TEXT BLACK - ON WHITE',0

reset:
	cli
	; il n'existe aucun 'stack' par défaut
	mov		ax, STACK_SEG
	mov 	ss, ax
	mov 	sp, 0xFFFE     	; haut du segment (64ko de stack), mot-aligné
	cld

	; installé une table d'interruption "dummy"
	call 	ivt_setup
	call	bda_setup

	; Install IRQ 0 : timer_isr
	mov		ax,cs
	mov		dx,ax
	mov		bx,timer_isr
	mov		ax,i8259_MASTER_INT

	call	ivt_setvector

	; initialisation des PIC 8259A
	call 	pic_init

	; load Roms
	call 	setup_load_rom

	; on vérifie que le BIOS VGA a installé une INT 10h
	call	setup_check_vga

	; enable IRQ 0
	mov     ah,IRQ_ENABLED
	mov     al,0
	call    pic_set_irq_mask

	call	kbd_init
	sti

	; on active le mode graphique
	GFX		INIT
	call	mouse_init
	GFX		MOUSE_MOVE
	GFX		MOUSE_SHOW

	push	cs
	pop		ds

	GUI		WINDOW, 50,50,250,100,helloworld

	; GFX		RECTANGLE_DRAW, 50,50,250,100,0

	;GFX		LINE_VERT, 50, 50, 100, 0
	;GFX		LINE_VERT, 300, 50, 100, 0

	;GFX		LINE_HORIZ, 50, 300, 50, 0
	;GFX		LINE_HORIZ, 50, 300, 100, 0



	mov		ax,BDA_DATA_SEG
	mov		ds,ax
endless:
	GFX		TXT_MODE, GFX_TXT_BLACK
	GFX		GOTOXY, 0, 180

	mov		ax, [BDA_MOUSE + mouse.x]
	call 	print_word_hex

	GFX		PUTCH, ' '

	mov		ax, [BDA_MOUSE + mouse.y]
	call 	print_word_hex

	jmp		endless


; -----------------------------------------------------------
; timer ISR (IRQ -> INT)
; -----------------------------------------------------------
timer_isr:
	push	ax

	push    fs
	mov     ax,BDA_DATA_SEG
	mov		fs,ax
; 		inc		byte [fs:BDA_TIMER]

	mov		al, PIC_EOI            ; EOI master
	out		i8259_MASTER_CMD, al
	pop		fs

	pop		ax
	iret

; ------------------------------------------------------------------
; Padding jusqu'au reset vector
; ------------------------------------------------------------------
times 0xFFF0 - ($ - $$) db 0xFF

; ------------------------------------------------------------------
; RESET VECTOR (exécuté par le CPU)
; ------------------------------------------------------------------
section 	.resetvect
bits 		16
global		reset_vector

reset_vector:
   	; code minimal au reset
	jmp		0xF000:reset

builddate:
	db 		'06/01/2026'
	times 		16-($-$$) db 0   ; le stub tient dans 16 octets (ou moins)


