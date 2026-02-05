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

; definition du BDA
%include 	"./common/bda.asm"

%include 	"./common/debug_cga.asm"
%include	"./drivers/gfx_cgam.asm"
%include	"./services/gui_lib.asm"
%include	"./drivers/mouse_ps2.asm"
%include 	"./drivers/keyboard_ps2.asm"
%include 	"./services/generic.asm"
; %include	"./services/gui_window.asm"

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

    ; Init du système GUI
    call    gui_init_system
 	call	build_interface

main_loop:
    ; 2. Moteur GUI (Gère tout : Loop, HitTest, Draw, Callbacks)
    ; DS pointe déjà sur GUI_RAM_SEG
    call    gui_process_all

    ; 3. Afficher souris
    ; GFX     MOUSE_MOVE

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
    call    gui_alloc_widget        ; Retourne SI = Pointeur nouveau slot
    jc     .mem_full

    ; Remplir les propriétés
    mov     word [gs:si +  widget.x], 10
    mov     word [gs:si +  widget.y], 10
    mov     word [gs:si +  widget.w], 80
    mov     word [gs:si +  widget.h], 20
    mov     word [gs:si +  widget.text_ofs], str_quit
    ; mov     byte [gs:si +  widget.user_id], 1         ; Style "Bouton par défaut" (OK)
    mov     word [gs:si +  widget.text_seg], cs        ; Texte est dans la ROM
    mov     word [gs:si +  widget.event_click], on_click_quit ; Fonction à appeler
    mov     byte [gs:si +  widget.type], WIDGET_TYPE_ROUND_BUTTON

    ; Créer Bouton 2 "HELLO"
    call    gui_alloc_widget
    jc      .mem_full

    mov     word [gs:si +  widget.x], 100
    mov     word [gs:si +  widget.y], 50
    mov     word [gs:si +  widget.w], 80
    mov     word [gs:si +  widget.h], 20
    mov     word [gs:si +  widget.text_ofs], str_hello
    mov     word [gs:si +  widget.text_seg], cs
    mov     byte [gs:si +  widget.type], WIDGET_TYPE_ROUND_BUTTON

    ; Créer Bouton 2 "HELLO"
    call    gui_alloc_widget
    jc      .mem_full

    mov     word [gs:si +  widget.x], 100
    mov     word [gs:si +  widget.y], 150
    mov     word [gs:si +  widget.w], 80
    mov     word [gs:si +  widget.h], 20
    mov     word [gs:si +  widget.text_ofs], str_hello
    mov     word [gs:si +  widget.text_seg], cs
    mov     byte [gs:si +  widget.type], WIDGET_TYPE_ROUND_BUTTON
    ; Pas de callback

    ; Créer Slider (Drag)
    call    gui_alloc_widget
    jc      .mem_full
    mov     word [gs:si + widget.x], 10
    mov     word [gs:si + widget.y], 100
    mov     word [gs:si + widget.w], 150
    mov     word [gs:si + widget.h], 20
    mov     word [gs:si + widget.text_ofs], str_drag
    mov     word [gs:si + widget.text_seg], cs
    mov     byte [gs:si + widget.type], WIDGET_TYPE_SLIDER
    mov     byte [gs:si + widget.attr_mode], 1      ; Horizontal
    mov     word [gs:si + widget.attr_min], 10      ; X Min
    mov     word [gs:si + widget.attr_max], 140     ; X Max (Widget.x + W - ThumbW)
    mov     word [gs:si + widget.attr_val], 10      ; Position initiale
    mov     byte [gs:si + widget.thumb_pct], 15     ; Curseur fait 15% de la largeur
;     mov     word [gs:si + widget.event_drag], on_drag_slider

.mem_full:
	ret


; --- Données ROM ---
str_quit  db "QUITTER", 0
str_hello db "HELLO", 0
str_drag  db "->", 0

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
	jmp		0xF000:reset

builddate:
	db 		__DATE__
	times 		16-($-$$) db 0   ; le stub tient dans 16 octets (ou moins)
