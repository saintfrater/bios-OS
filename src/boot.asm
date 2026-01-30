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

setup_gui:
    ; Initialiser le segment de données correct pour le texte du bouton
    mov     ax, cs  ; ou DS selon où sont tes chaines
    mov     [btn_quit + widget.text_seg], ax

	; GUI		WINDOW, 50,50,250,100,helloworld

	; GFX		RECTANGLE_DRAW, 50,50,250,100,0

	;GFX		LINE_VERT, 50, 50, 100, 0
	;GFX		LINE_VERT, 300, 50, 100, 0

	;GFX		LINE_HORIZ, 50, 300, 50, 0
	;GFX		LINE_HORIZ, 50, 300, 100, 0



	mov		ax,BDA_DATA_SEG
	mov		ds,ax
endless:

	; 1. Récupérer souris
    mov     ax, [BDA_MOUSE + mouse.x]
    mov     cx, ax                      ; CX = Souris X
    mov     ax, [BDA_MOUSE + mouse.y]
    mov     dx, ax                      ; DX = Souris Y
    mov     bl, [BDA_MOUSE + mouse.status] ; BL = Boutons

    ; 2. Gérer le bouton
    mov     si, btn_quit                ; SI pointe sur l'objet
    call    gui_update_button           ; Met à jour l'état et redessine si besoin

    ; 3. Vérifier si cliqué (AL = 1)
    cmp     al, 1
    je      action_quitter

    ; 4. Afficher le curseur souris (Important : après avoir dessiné le bouton)
	;    GFX     MOUSE_MOVE

	GFX		TXT_MODE, GFX_TXT_BLACK
	GFX		GOTOXY, 0, 180

	mov		ax, [BDA_MOUSE + mouse.x]
	call 	print_word_hex

	GFX		PUTCH, ' '

	mov		ax, [BDA_MOUSE + mouse.y]
	call 	print_word_hex

	jmp		endless

action_quitter:
	hlt
	jmp		action_quitter


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

; Déclaration d'un bouton "Quitter"
btn_quit:
    istruc widget
        at widget.x,        dw 10
        at widget.y,        dw 10
        at widget.w,        dw 80
        at widget.h,        dw 20
        at widget.state,    db GUI_STATE_NORMAL
        at widget.text_ofs, dw str_quit
        at widget.text_seg, dw 0 ; Sera rempli au runtime (CS ou DS)
        at widget.id,       db 1
    iend

str_quit db "QUITTER", 0

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


