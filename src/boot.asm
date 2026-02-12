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
%include	"./common/patterns.asm"
%include    "./common/generic.asm"
%include	"./common/string.asm"

; definition du BDA
%include 	"./common/bda.asm"

; drivers
%include	"./drivers/gfx_cgam.asm"
%include	"./drivers/mouse_ps2.asm"
%include 	"./drivers/keyboard_ps2.asm"

%include	"./common/debug_cga.asm"

; GUI
%include	"./gui/lib.asm"
%include	"./gui/draw.asm"

; --- Données texte ---
str_quit  db "Quitter", 0
str_hello db "Hello", 0
str_option1 db "option 1", 0
str_option2 db "option 2", 0
str_option3 db "option 3", 0

entrycode:
	cli
	mov		ax, STACK_SEG	; creation du stack par défaut
	mov 	ss, ax
	mov 	sp, 0xFFFE     	; haut du segment (64ko de stack), mot-aligné
	cld

	call 	ivt_setup		; configuration d'une table d'interruption "dummy"
	call	bda_setup		; initialisation du BDA

	ISADBG	ISA_GREEN, 1

	; Install IRQ 0 : timer_isr
	mov		ax,cs
	mov		dx,ax
	mov		bx,timer_isr
	mov		ax,i8259_MASTER_INT

	call	ivt_setvector

	ISADBG	ISA_GREEN, 2

	; initialisation des PIC 8259A
	call 	pic_init

	ISADBG	ISA_GREEN, 4

	; load Roms
	call 	setup_load_rom

	ISADBG	ISA_GREEN, 8

	; on vérifie que le BIOS VGA a installé une INT 10h
	call	setup_check_vga

	ISADBG	ISA_GREEN, 16

	; enable IRQ 0
	mov     ah,IRQ_ENABLED
	mov     al,0
	call    pic_set_irq_mask

	call	kbd_init
	sti

	DEBUG	0xFADE

	ISADBG	ISA_GREEN, 32

	; on active le mode graphique
	GFX		INIT
	call	mouse_init

	GFX		MOUSE_MOVE
	ISADBG	ISA_RED, 0x80

 	GFX		MOUSE_SHOW

	ISADBG	ISA_RED, 0x81

	.loops:
    call    main_loop
	jmp     .loops

; --- Callbacks (Fonctions appelées par le moteur) ---
on_click_quit:
	hlt
	jmp     on_click_quit
    ret

on_click_hello:
	ret

%define     .oldval     	word [bp-2]
%define     .my_slider     	word [bp-4]
%define		.value			word [bp-6]
main_loop:
    push    bp
    mov     bp, sp
    sub     sp, 6

	push	cs
	pop		ds

	DEBUG	1
	ISADBG	ISA_LEFT, 1

	; Init du système GUI
	call    gui_init_system


	DEBUG	2
	ISADBG	ISA_LEFT, 2

	; --- CRÉATION DYNAMIQUE DES BOUTONS ---

	; Créer Bouton 1 "QUITTER"
    GUI     OBJ_CREATE, OBJ_TYPE_BUTTON_ROUNDED, 10, 10, 80, 16
	GUI     OBJ_SET_TEXT, ax, cs, str_quit
	; Créer Bouton 2 "HELLO"
    GUI     OBJ_CREATE, OBJ_TYPE_BUTTON_ROUNDED, 100, 50, 80, 16
	GUI     OBJ_SET_TEXT, ax, cs, str_hello
	; Créer checkbox 3 "option 1"
    GUI     OBJ_CREATE, OBJ_TYPE_CHECKBOX, 200, 50, 100, 15
	GUI     OBJ_SET_TEXT, ax, cs, str_option1

    GUI     OBJ_CREATE, OBJ_TYPE_CHECKBOX, 200, 50+16, 100, 15
	GUI     OBJ_SET_TEXT, ax, cs, str_option2

    GUI     OBJ_CREATE, OBJ_TYPE_CHECKBOX, 200, 50+16*2, 100, 15
	GUI     OBJ_SET_TEXT, ax, cs, str_option3

	DEBUG	3
	ISADBG	ISA_LEFT, 3

    ; Créer Slider (Drag)
    GUI     OBJ_CREATE, OBJ_TYPE_SLIDER, 10, 100, 150, 12
	GUI		OBJ_SET_MODE, ax, SLIDER_HORIZONTAL
	GUI		OBJ_SLIDER_SET_ATTR, ax, 10, 140, 10, 15

	GUI     OBJ_CREATE, OBJ_TYPE_SLIDER, 400, 10, 16, 150
	mov     .my_slider, ax

	GUI		OBJ_SET_MODE, .my_slider, SLIDER_VERTICAL
	GUI		OBJ_SLIDER_SET_ATTR, .my_slider, 0, 15, 15, 12

    mov     .oldval, 0x1256
	mov		.value, 0xFADE

	DEBUG	4
	ISADBG	ISA_LEFT, 4

    .loop:
		call    gui_process_all
 		GUI		OBJ_GET_VAL, .my_slider
		mov		.value, ax

    	cmp     ax,.oldval
    	je      .loop

		; debug
    	mov     .oldval, ax
    	GFX     RECTANGLE_FILL,0,148,50,166, PATTERN_WHITE
		GFX		GOTOXY, 8, 150

		mov		ax, .value
		call	print_word_hex
		; end debug

		mov		dx, 0x3d9
		mov		ax, .value
		and 	ax, 0x000F
		out		dx, al

	jmp     .loop
	leave
	ret

; -----------------------------------------------------------
; timer ISR (IRQ -> INT)
; -----------------------------------------------------------
timer_isr:
	push	ax

	push    fs
	mov     ax,BDA_DATA_SEG
	mov		fs,ax
; exemple de fonctionnement:
; 	inc		byte [fs:BDA_TIMER]

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
	jmp		0xF000:entrycode

builddate:
	db 		__DATE__
	times 		16-($-$$) db 0   ; le stub tient dans 16 octets (ou moins)
