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

entrycode:
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

	; Init du système GUI
	call    gui_init_system
 	call	build_interface

main_loop:
	call    gui_process_all

 	GUI		OBJ_GET_VAL, 5		; slider

	;GFX		GOTOXY, 5, 20
	;call	print_word_hex

	jmp     main_loop

; --- Callbacks (Fonctions appelées par le moteur) ---
on_click_quit:
	hlt
	jmp     on_click_quit


build_interface:
	; --- CRÉATION DYNAMIQUE DES BOUTONS ---
	; On reste dans CS pour lire les arguments,
	; mais on configure DS=GUI_RAM_SEG pour l'allocation

	; Créer Bouton 1 "QUITTER"
    GUI     OBJ_CREATE, OBJ_TYPE_BUTTON_ROUNDED, 10, 10, 80, 16, str_quit, cs
	; Créer Bouton 2 "HELLO"
    GUI     OBJ_CREATE, OBJ_TYPE_BUTTON_ROUNDED, 100, 50, 80, 16, str_hello, cs
	; Créer checkbox 3 "option 1"
    GUI     OBJ_CREATE, OBJ_TYPE_CHECKBOX, 200, 50, 100, 15, str_option1, cs
    GUI     OBJ_CREATE, OBJ_TYPE_CHECKBOX, 200, 50+16, 100, 15, str_option2, cs
    GUI     OBJ_CREATE, OBJ_TYPE_CHECKBOX, 200, 50+16*2, 100, 15, str_option3, cs

    ; Créer Slider (Drag)
    ; GUI     OBJ_CREATE, OBJ_TYPE_SLIDER,
	call    gui_alloc_widget
	jc      .mem_full
	mov     word [gs:si + widget.x], 10
	mov     word [gs:si + widget.y], 100
	mov     word [gs:si + widget.w], 150
	mov     word [gs:si + widget.h], 12
	mov     byte [gs:si + widget.type],OBJ_TYPE_SLIDER
	mov     byte [gs:si + widget.attr_mode], SLIDER_HORIZONTAL
	mov     word [gs:si + widget.attr_min], 10      ; X Min
	mov     word [gs:si + widget.attr_max], 140     ; X Max (Widget.x + W - ThumbW)
	mov     word [gs:si + widget.attr_val], 10      ; Position initiale
	mov     byte [gs:si + widget.thumb_pct], 15     ; Curseur fait 15% de la largeur
;     mov     word [gs:si + widget.event_drag], on_drag_slider

; Créer Slider (Drag)
	call    gui_alloc_widget
	jc      .mem_full
	mov     word [gs:si + widget.x], 400
	mov     word [gs:si + widget.y], 10
	mov     word [gs:si + widget.w], 16
	mov     word [gs:si + widget.h], 150
	mov     byte [gs:si + widget.type], OBJ_TYPE_SLIDER
	mov     byte [gs:si + widget.attr_mode], SLIDER_VERTICAL
	mov     word [gs:si + widget.attr_min], 10      ; X Min
	mov     word [gs:si + widget.attr_max], 140     ; X Max (Widget.x + W - ThumbW)
	mov     word [gs:si + widget.attr_val], 140      ; Position initiale
	mov     byte [gs:si + widget.thumb_pct], 25     ; Curseur fait 15% de la largeur
;     mov     word [gs:si + widget.event_drag], on_drag_slider

.mem_full:
	ret


; --- Données ROM ---
str_quit  db "Quitter", 0
str_hello db "Hello", 0
str_option1 db "option 1", 0
str_option2 db "option 2", 0
str_option3 db "option 3", 0

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
