; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gui/lib.asm
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

; --- Configuration ---
%define GUI_MAX_WIDGETS     32          ; Nombre max de widgets simultanés

; Dimensions
%define GUI_CHECKBOX_SIZE 	10			;

; --- Drapeaux & États ---
%define GUI_STATE_FREE      0           ; Le slot est vide (mémoire dispo)
%define GUI_STATE_NORMAL    1           ; Affiché, repos
%define GUI_STATE_HOVER     2           ; Souris dessus
%define GUI_STATE_PRESSED   3           ; Clic enfoncé
%define GUI_STATE_DISABLED  4           ; Grisé

; --- Types de Widgets ---
%define OBJ_TYPE_LABEL           0
%define OBJ_TYPE_BUTTON          1
%define OBJ_TYPE_SLIDER          2
%define OBJ_TYPE_BUTTON_ROUNDED  3
%define OBJ_TYPE_CHECKBOX        4

; --- Widgets attributs ---
%define BUTTON_DEFAULT              0
%define BUTTON_OK                   1

%define SLIDER_HORIZONTAL			1
%define SLIDER_VERTICAL				2

; =============================================================================
;  SECTION : API ACTIONS
; =============================================================================

%define OBJ_CREATE      			0
%define OBJ_DESTROY     			1
%define OBJ_GET_STATE   			2
%define OBJ_GET_TYPE    			3
%define OBJ_GET_VAL     			4
%define	OBJ_SET_VAL					5

%define	OBJ_SET_MODE				6
%define	OBJ_SET_TEXT				7

%define OBJ_GET_PTR					8

%define OBJ_SLIDER_SET_ATTR			9


gui_api_table:
	dw gui_api_create
	dw gui_api_destroy
	dw gui_api_get_state
	dw gui_api_get_type
	dw gui_api_get_val
	dw gui_api_set_val
	dw gui_api_set_mode
	dw gui_api_set_text
	dw gui_get_widget_ptr
	dw gui_api_slider_attr


; --- Structure d'un OBJET (Bouton, etc) ---
struc widget
	.state      resb 1      		; État (0=libre, >0=utilisé)
	.type       resb 1      		; Type (0=Button, 1=Slider...)
	.oldstate   resb 1      		; widget a-t-il été modifié ?
	.user_id    resb 1      		; ID unique utilisateur
	.x          resw 1      		; Position X
	.y          resw 1      		; Position Y
	.x2         resw 1      		; Position X2 calculée
	.y2         resw 1      		; Position Y2 calculée
	.w          resw 1      		; Largeur
	.h          resw 1      		; Hauteur
	.text_ofs   resw 1      		; Offset du texte
	.text_seg   resw 1      		; Segment du texte
	.event_click    resw 1      	; adresse de la fonction "on click"
	.event_drag     resw 1      	; adresse de la fonction "on drag"

	.attr_mode      resb 1      	; 0=None, 1=Horiz, 2=Vert
	.attr_min       resw 1      	; Valeur/Position Min
	.attr_max       resw 1      	; Valeur/Position Max
	.attr_val    	resw 1 			; Valeur/Position Actuelle

	.thumb_pos      resw 1      	; Valeur/Position Actuelle en pixel pour le dessin.
	.thumb_pct      resb 1      	; Taille du curseur en % (1-100)

	.attr_anchor    resw 1      	; interne Offset pour le drag
	alignb      2           		; Alignement mémoire pour performance
endstruc
; actuellement 34 octets

%macro GUI 1-*
	%rep %0 - 1
		%rotate -1
		push %1
	%endrep
	%rotate -1
	call word [cs:gui_api_table + ((%1)*2)]
	add sp, (%0 - 1) * 2
%endmacro

; -----------------------------------------------------------------------------
; gui_api_slider_attr
; -----------------------------------------------------------------------------
%define     .id      word [bp+4]
%define     .min	 word [bp+6]
%define     .max	 word [bp+8]
%define     .val	 word [bp+10]
%define     .pct     word [bp+12]
gui_api_slider_attr:
	push    bp
	mov     bp, sp
	push	ax

	push	.id         ; ID
	call    gui_get_widget_ptr
	jc      .err

	mov		ax, .min
	mov		word [gs:si + widget.attr_min], ax
	mov		ax, .max
	mov		word [gs:si + widget.attr_max], ax
	mov		ax, .val
	mov		word [gs:si + widget.attr_val], ax
	mov		ax, .pct
	mov		byte [gs:si + widget.thumb_pct], al

	call	gui_slider_update_pixels

	.err:
	pop		ax
	leave
	ret
%undef     .id
%undef     .mode

; -----------------------------------------------------------------------------
; gui_api_set_mode
; -----------------------------------------------------------------------------
%define     .id       word [bp+4]
%define     .mode     word [bp+6]
gui_api_set_mode:
	push    bp
	mov     bp, sp
	push	ax

	push	.id
	call    gui_get_widget_ptr
	jc      .err

	mov		ax, .mode
	mov		byte [gs:si + widget.attr_mode], al

	.err:
	pop		ax
	leave
	ret
%undef     .id
%undef     .mode

; -----------------------------------------------------------------------------
; gui_api_set_text
; -----------------------------------------------------------------------------
%define     .id       	word [bp+4]
%define     .segmt   	word [bp+6]
%define     .oft 	 	word [bp+8]
gui_api_set_text:
	push    bp
	mov     bp, sp
	push	ax

	push	.id
	call    gui_get_widget_ptr
	jc      .err

	mov		ax, .segmt
	mov		word [gs:si + widget.text_seg], ax
	mov		ax, .oft							; Offset du texte
	mov		word [gs:si + widget.text_ofs], ax

	.err:
	pop		ax
	leave
	ret
%undef     .id
%undef     .text_ofs
%undef     .text_seg

; -----------------------------------------------------------------------------
; gui_api_create
; Crée un widget et retourne son ID
; Out: AX = ID ou -1 si erreur
;
; parameters : type, x, y, w, h, text_ofs, text_seg
;
; -----------------------------------------------------------------------------
%define     .type       word [bp+4]
%define     .x          word [bp+6]
%define     .y	        word [bp+8]
%define     .w          word [bp+10]
%define     .h          word [bp+12]
gui_api_create:
	push    bp
	mov     bp, sp
	push    gs

	mov     ax, BDA_GUI_WIDGET
	mov     gs, ax
	call    gui_alloc_widget        ; Returns GS:SI
	mov     ax, -1
	jc      .done

	; ID = SI / widget_size
	mov     ax, si
	xor     dx, dx
	mov     cx, widget_size
	div     cx

	mov     bx, .type
	mov     byte [gs:si + widget.type], bl
	mov     bx, .x
	mov     word [gs:si + widget.x], bx
	mov     bx, .y
	mov     word [gs:si + widget.y], bx
	mov     bx, .w
	mov     word [gs:si + widget.w], bx
	mov     bx, .h
	mov     word [gs:si + widget.h], bx

	mov     byte [gs:si + widget.state], GUI_STATE_NORMAL
	mov     byte [gs:si + widget.oldstate], 0
.done:
	pop     gs
	leave
	ret
%undef     .type
%undef     .x
%undef     .y
%undef     .w
%undef     .h

; -----------------------------------------------------------------------------
; gui_api_get_state
; Arg1: ID
; Out: AX = State
; -----------------------------------------------------------------------------
%define .id word [bp+4]
gui_api_get_state:
	push    bp
	mov     bp, sp

	mov     ax, .id         ; ID
	call    gui_get_widget_ptr
	jc      .err

	xor     ax, ax
	mov     al, [gs:si + widget.state]
	jmp     .done

.err:
	mov     ax, -1
.done:
	leave
	ret
%undef .id

; -----------------------------------------------------------------------------
; gui_api_get_type
; Arg1: ID
; Out: AX = Type
; -----------------------------------------------------------------------------
%define .id word [bp+4]
gui_api_get_type:
	push    bp
	mov     bp, sp

	mov     ax, .id         ; ID
	call    gui_get_widget_ptr
	jc      .err

	xor     ax, ax
	mov     al, [gs:si + widget.type]
	jmp     .done

.err:
	mov     ax, -1
.done:
	leave
	ret
%undef .id

; -----------------------------------------------------------------------------
; gui_api_get_val
; Arg1: ID
; Out: AX = Attr Val
; -----------------------------------------------------------------------------
%define .id word [bp+4]
gui_api_get_val:
	push    bp
	mov     bp, sp

	call    gui_get_widget_ptr
	;jc      .err

	call    gui_slider_update_value
	mov     ax, [gs:si + widget.attr_val]
	jmp     .done

.err:
	mov     ax, -1
.done:
	leave
	ret
%undef .id

; -----------------------------------------------------------------------------
; gui_api_set_val
; Arg1: ID
; Arg2: Value
; -----------------------------------------------------------------------------
%define .id 	word [bp+4]
%define .val	word [bp+6]
gui_api_set_val:
	push    bp
	mov     bp, sp

	mov     ax, .id         ; ID
	call    gui_get_widget_ptr
	jc      .err

	mov     ax, .val
	mov     [gs:si + widget.thumb_pos], ax

.err:
	leave
	ret
%undef .id
%undef .val

; -----------------------------------------------------------------------------
; gui_api_destroy
; Détruit un widget via son ID
; Arg1: ID
; Out: AX = 0 (OK), -1 (Error)
; -----------------------------------------------------------------------------
%define .id word [bp+4]
gui_api_destroy:
	push    bp
	mov     bp, sp

	mov     ax, .id         ; ID
	call    gui_get_widget_ptr
	jc      .err

	call    gui_free_widget
	xor     ax, ax
	jmp     .done

.err:
	mov     ax, -1
.done:
	leave
	ret
%undef .id

; -----------------------------------------------------------------------------
; gui_get_widget_ptr
; Helper interne : Convertit ID en Pointeur
; In: ID
; Out: GS:SI = Ptr, CF=1 if error
; -----------------------------------------------------------------------------
%define .id word [bp+4]
gui_get_widget_ptr:
	push    bp
	mov     bp, sp
	push    ax
    push    cx

	mov		ax, .id
	cmp     ax, GUI_MAX_WIDGETS
	jae   	.error

	mov     cx, widget_size
	xor		dx, dx
	mul     cx              ; AX = Offset
	mov     si, ax

	mov     ax, BDA_GUI_WIDGET
	mov     gs, ax

	clc
	jmp		.done
	.error:
	stc
	.done:
	pop		cx
	pop		ax
	leave
	ret
%undef .id


; =============================================================================
;  SECTION : GESTION MÉMOIRE (ALLOCATION / LIBÉRATION)
; =============================================================================

; -----------------------------------------------------------------------------
; gui_init_system
; Initialise toute la mémoire des widgets à 0 (Libre)
; Entrée : DS doit pointer vers BDA_GUI_WIDGET
; -----------------------------------------------------------------------------
gui_init_system:
	push    eax
	push    cx
	push    es
	push    di

	mov     ax, BDA_GUI_WIDGET
	mov     es, ax

	cld
	xor     di, di
	mov     cx, (widget_size * GUI_MAX_WIDGETS) / 2
	xor     ax, ax
	rep     stosw          ; Plus sûr en mode 16 bits pour l'alignement

	pop     di
	pop     es
	pop     cx
	pop     eax
	ret

; -----------------------------------------------------------------------------
; gui_alloc_widget
; Cherche un slot vide et retourne son adresse
; Sortie :
;   - Succès : CF=0 (Carry Clear), GS:SI = Offset du widget
;   - Echec  : CF=1 (Carry Set),  GS:SI = Indéfini (ou 0)
; -----------------------------------------------------------------------------
gui_alloc_widget:
	push    ax
	push    cx
	push    bx

	mov     ax, BDA_GUI_WIDGET
	mov     gs, ax

	mov     si, 0                   ; Début du pool
	mov     cx, GUI_MAX_WIDGETS

	.loop_find:
	cmp     byte [gs:si + widget.state], GUI_STATE_FREE
	je      .found                  ; Si state == 0, c'est libre !

	add     si, widget_size         ; Sinon on passe au suivant
	loop    .loop_find

	; Pas trouvé (Plein)
	stc                             ; set Carry Flag : erreur
	jmp     .done

	.found:
	; On initialise le slot trouvé
	mov     byte [gs:si + widget.state], GUI_STATE_NORMAL   ; Marquer comme occupé
	mov     byte [gs:si + widget.type], OBJ_TYPE_BUTTON  	; Type par défaut
	mov     byte [gs:si + widget.oldstate], 0               ; doit etre dessiné

	; Reset des champs critiques pour éviter les déchets
	mov     word [gs:si + widget.event_click], 0
	mov     word [gs:si + widget.event_drag], 0
	mov     byte [gs:si + widget.thumb_pct], 10     		; 10% par défaut

	clc                             						; Clear Carry Flag
	.done:
	pop     bx
	pop     cx
	pop     ax
	ret

; -----------------------------------------------------------------------------
; gui_free_widget
; Libère un widget
; Entrée : SI = Pointeur widget
; -----------------------------------------------------------------------------
gui_free_widget:
	push    eax
	push    es

	mov     ax, BDA_GUI_WIDGET
	mov     es, ax

	cld
	mov     di, si
	mov     cx, (widget_size)
	shr     cx, 2           ; cx / 4
	xor     eax, eax
	rep     stosd          ; Remplit tout de 0

	; On efface le widget
	mov     byte [es:si + widget.state], GUI_STATE_FREE
	; Pour l'instant on le marque juste libre, il n'est pas retirer de l'écran.

	pop     es
	pop     eax
	ret

%include "./gui/lib-logic.asm"
%include "./gui/lib-draw.asm"
