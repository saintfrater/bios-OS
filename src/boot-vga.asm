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
%define		GFX_DRIVERS	'VGA'

%define		DEBUGER_ENABLED

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
%if GFX_DRIVERS == 'VGA'
	%include	"./drivers/gfx_vga.asm"
%else
	; default drivers
	%include	"./drivers/gfx_cgam.asm"
%endif

%include	"./drivers/mouse_ps2.asm"
%include 	"./drivers/keyboard_ps2.asm"

%include	"./common/debug_gfx.asm"
%include 	"./common/debug_txt.asm"

; GUI
; %include	"./gui/lib-api.asm"

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
 	GFX		MOUSE_SHOW

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

main_loop:
    push    bp
    mov     bp, sp
	%define .oldval     	word [bp-2]
	%define .my_slider     	word [bp-4]
	%define	.value			word [bp-6]
    sub     sp, 6

	push	cs
	pop		ds

	GFX		TXT_MODE, GFX_TXT_WHITE
	GFX		GOTOXY, 10,50
	GFX		WRITE, cs, str_hello


	; Init du système GUI
; 	call    gui_init_system

	.loop:
;		call    gui_process_all

;		mov		dh, 1
;		mov		dl, 10
;		call 	scr_gotoxy
;
;		mov		ax, SEG_BDA_CUSTOM
;		mov		fs, ax
;		mov		ax, word [fs:PTR_MOUSE + mouse.x]
;		call	scr_puthex16
;
;		mov		al, ' '
;		call	scr_putc
;
;		mov		ax, word [fs:PTR_MOUSE + mouse.y]
;		call	scr_puthex16

		nop
	jmp     .loop
	leave
	ret

; -----------------------------------------------------------
; timer ISR (IRQ -> INT)
; -----------------------------------------------------------
timer_isr:
	push	ax

	push    fs
	mov     ax,SEG_BDA_CUSTOM
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
