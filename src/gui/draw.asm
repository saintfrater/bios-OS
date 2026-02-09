; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gui/draw.asm
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

;
; https://github.com/buserror/libmui
;

; Dessine le widget pointé par SI
gui_draw_single_widget:
	pusha

	GFX     MOUSE_HIDE              ; On cache la souris AVANT de commencer le dessin du widget

	mov		ax, GUI_RAM_SEG
	mov		gs, ax

	mov     al, [gs:si + widget.state]
	cmp     al, [gs:si + widget.oldstate]
	je      .done

	mov     [gs:si + widget.oldstate], al       ; marque comme à jour

	; Chargement coords
	mov     ax, [gs:si + widget.x]
	mov     bx, [gs:si + widget.y]

	mov     cx, [gs:si + widget.w]
	mov     dx, [gs:si + widget.h]

	; Calcul X2, Y2
	add     cx, ax
	add     dx, bx

	mov 	[gs:si + widget.x2], cx
	mov 	[gs:si + widget.y2], dx

	; Dispatch selon le type
    cmp     byte [gs:si + widget.type], OBJ_TYPE_LABEL
	jne     .case_1
    jmp     .done

    .case_1:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_SLIDER
	jne     .case_2
	call    draw_slider
	jmp     .done

	.case_2:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_BUTTON
	jne     .case_3
	call    draw_button
	jmp     .done

	.case_3:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_BUTTON_ROUNDED
	jne     .case_4
	call    draw_round_button
	jmp     .done

	.case_4:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_CHECKBOX
	jne     .case_5
	call    draw_checkbox
	jmp     .done

	.case_5:


	.done:
	GFX     MOUSE_SHOW              ; On réaffiche la souris APRES, capturant le widget fini
	popa
	ret

; --- Locals Mapping ---
%define .thumb_x1   word [bp-2]
%define .thumb_y1   word [bp-4]
%define .thumb_x2   word [bp-6]
%define .thumb_y2   word [bp-8]
%define .track_x1   word [bp-10]
%define .track_y1   word [bp-12]
%define .track_x2   word [bp-14]
%define .track_y2   word [bp-16]
draw_slider:
	push    bp
	mov     bp, sp
	sub     sp, 16          ; Reserve space for locals

	; Save track coords (Arguments passed in AX, BX, CX, DX)
	mov     .track_x1, ax
	mov     .track_y1, bx
	mov     .track_x2, cx
	mov     .track_y2, dx

	; 1. Dessiner la piste (Track)
	GFX     RECTANGLE_FILL, .track_x1, .track_y1, .track_x2, .track_y2, PATTERN_WHITE_LIGHT
	GFX     RECTANGLE, .track_x1, .track_y1, .track_x2, .track_y2, 0

	; 2. Calculer la taille du curseur (Thumb)
	cmp     byte [gs:si + widget.attr_mode], 2
	je      .calc_v

	; --- Horizontal ---
	mov     ax, [gs:si + widget.w]
	xor     bh, bh
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx                      ; AX = Thumb Width

	; Thumb X1 = attr_val
	mov     cx, [gs:si + widget.attr_val]

	; --- CLAMP X1 (Fix Overflow) ---
	; Max X1 = TrackX2 - ThumbW
	mov     dx, .track_x2
	sub     dx, ax      ; DX = Max X1
	cmp     cx, dx
	jle     .chk_min_x
	mov     cx, dx
	.chk_min_x:
	cmp     cx, .track_x1
	jge     .ok_x1
	mov     cx, .track_x1
	.ok_x1:
	mov     .thumb_x1, cx

	; Thumb X2 = X1 + Width
	add     cx, ax
	mov     .thumb_x2, cx

	; Thumb Y1 = Track Y1
	mov     ax, .track_y1
	mov     .thumb_y1, ax

	; Thumb Y2 = Track Y2
	mov     ax, .track_y2
	mov     .thumb_y2, ax
	jmp     .draw_thumb

	.calc_v:
	; --- Vertical ---
	mov     ax, [gs:si + widget.h]
	xor     bh, bh
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx                      ; AX = Thumb Height

	; Thumb Y1 = attr_val
	mov     cx, [gs:si + widget.attr_val]

	; --- CLAMP Y1 (Fix Overflow) ---
	; Max Y1 = TrackY2 - ThumbH
	mov     dx, .track_y2
	sub     dx, ax      ; DX = Max Y1
	cmp     cx, dx
	jle     .chk_min_y
	mov     cx, dx
	.chk_min_y:
	cmp     cx, .track_y1
	jge     .ok_y1
	mov     cx, .track_y1
	.ok_y1:
	mov     .thumb_y1, cx

	; Thumb Y2 = Y1 + Height
	add     cx, ax
	mov     .thumb_y2, cx

	; Thumb X1 = Track X1
	mov     ax, .track_x1
	mov     .thumb_x1, ax

	; Thumb X2 = Track X2
	mov     ax, .track_x2
	mov     .thumb_x2, ax

	.draw_thumb:
	; 3. Dessiner le curseur (Thumb)
	GFX     RECTANGLE_FILL, .thumb_x1, .thumb_y1, .thumb_x2, .thumb_y2, PATTERN_WHITE
	GFX     RECTANGLE, .thumb_x1, .thumb_y1, .thumb_x2, .thumb_y2, 0

	; --- Grip Lines (3 lignes pour un look moderne) ---
	cmp     byte [gs:si + widget.attr_mode], 2
	je      .grip_v

	; --- Grip Horizontal (Lignes verticales) ---
	; Center X
	mov     ax, .thumb_x1
	add     ax, .thumb_x2
	shr     ax, 1           ; AX = Center X

	; Y bounds (padding 3px)
	mov     bx, .thumb_y1
	add     bx, 3
	mov     dx, .thumb_y2
	sub     dx, 3

	; Center Line
	GFX     LINE, ax, bx, ax, dx, 0

	; Left Line
	mov     cx, ax
	sub     cx, 2
	cmp     cx, .thumb_x1
	jle     .skip_left
	GFX     LINE, cx, bx, cx, dx, 0
	.skip_left:

	; Right Line
	mov     cx, ax
	add     cx, 2
	cmp     cx, .thumb_x2
	jge     .grip_done
	GFX     LINE, cx, bx, cx, dx, 0
	jmp     .grip_done

	.grip_v:
	; --- Grip Vertical (Lignes horizontales) ---
	; Center Y
	mov     bx, .thumb_y1
	add     bx, .thumb_y2
	shr     bx, 1           ; BX = Center Y

	; X bounds (padding 3px)
	mov     ax, .thumb_x1
	add     ax, 3
	mov     cx, .thumb_x2
	sub     cx, 3

	; Center Line
	GFX     LINE, ax, bx, cx, bx, 0

	; Top Line
	mov     dx, bx
	sub     dx, 2
	cmp     dx, .thumb_y1
	jle     .skip_top
	GFX     LINE, ax, dx, cx, dx, 0
	.skip_top:

	; Bottom Line
	mov     dx, bx
	add     dx, 2
	cmp     dx, .thumb_y2
	jge     .grip_done
	GFX     LINE, ax, dx, cx, dx, 0

	.grip_done:
	leave
	ret

; Clean up defines
%undef .thumb_x1
%undef .thumb_y1
%undef .thumb_x2
%undef .thumb_y2
%undef .track_x1
%undef .track_y1
%undef .track_x2
%undef .track_y2

draw_button:
	; Dispatch selon état
	cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
	je      .paint_pressed
	cmp     byte [gs:si + widget.state], GUI_STATE_HOVER
	je      .paint_hover

	.draw_default_style:
		; Bordure extérieure épaisse (2px)
		GFX     RECTANGLE, ax, bx, cx, dx, 0
		inc     ax
		inc     bx
		dec     cx
		dec     dx
		GFX     RECTANGLE, ax, bx, cx, dx, 0

		; Bordure intérieure fine (après un gap de 1px blanc)
		add     ax, 2
		add     bx, 2
		sub     cx, 2
		sub     dx, 2
		GFX     RECTANGLE, ax, bx, cx, dx, 0
		jmp		.done

	.paint_hover:
		GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE_LIGHT
		GFX     RECTANGLE, ax, bx, cx, dx, 0
		jmp     .done

	.paint_pressed:
		GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_BLACK
		GFX     TXT_MODE, GFX_TXT_WHITE_TRANSPARENT

	.done:
		; on affiche le texte
		; Recharger les coordonnées de base pour le texte
		mov     ax, [gs:si + widget.x]
		mov     bx, [gs:si + widget.y]

		GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
		call    draw_text
	ret

;
; dessine un bouton arrondi
;
draw_round_button:
	; Dispatch selon état
	cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
	je      .paint_pressed
	cmp     byte [gs:si + widget.state], GUI_STATE_HOVER
	je      .paint_hover

	.paint_normal:
		GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE
		mov     di, 0                       ; Couleur Noire
		call    draw_round_borders
		GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
		jmp     .draw_text_now

	.paint_hover:
		GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE
		GFX     RECTANGLE_ROUND, ax, bx, cx, dx, 0
		; GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE_LIGHT
		mov     di, 0                       ; Couleur Noire
		call    draw_round_borders
		GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
		jmp     .draw_text_now

	.paint_pressed:
		GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_BLACK
		mov     di, 1                       ; Bordure Blanche sur fond noir
		call    draw_round_borders
		GFX     TXT_MODE, GFX_TXT_WHITE_TRANSPARENT
		jmp     .draw_text_now

	.draw_text_now:
		; Recharger les coordonnées de base pour le texte
		mov     ax, [gs:si + widget.x]
		mov     bx, [gs:si + widget.y]
		call    draw_text
		jmp     .done

	.done:
	ret

draw_round_borders:
	; Bordure principale
	add     ax, 2
	add     bx, 2
	sub     cx, 2
	sub     dx, 2
	GFX     RECTANGLE_ROUND, ax, bx, cx, dx, di
	ret

draw_checkbox:
	; met un "fond" blanc
	GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE

	cmp     byte [gs:si + widget.state], GUI_STATE_HOVER
	jne      .no_hover
		GFX     RECTANGLE_ROUND, ax, bx, cx, dx, 0
	.no_hover:

	; Calcul coords box (centré verticalement)
	mov     ax, [gs:si + widget.x]
	add		ax, 4
	mov     bx, [gs:si + widget.y]

	mov     cx, [gs:si + widget.h]
	mov		dx, [gs:si + widget.w]

	sub     cx, GUI_CHECKBOX_SIZE
	shr     cx, 1
	add     bx, cx              ; Y1

	mov     cx, ax
	add     cx, GUI_CHECKBOX_SIZE         ; X2

	mov     dx, bx
	add     dx, GUI_CHECKBOX_SIZE         ; Y2

	; Sauvegarde coords pour le X
	push    ax
	push    bx
	push    cx
	push    dx

	; Fond blanc + Bordure noire
	GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE
	GFX     RECTANGLE, ax, bx, cx, dx, 0

	; Check if checked
	cmp     word [gs:si + widget.attr_val], 0
	je      .draw_label

	; Dessin du X (Diagonales)
	add     ax, 2
	add     bx, 2
	sub     cx, 2
	sub     dx, 2

	; Optimisation : Utilisation de LINE au lieu de PUTPIXEL en boucle
	; Diagonale 1 : (ax, bx) -> (cx, dx)
	GFX     LINE, ax, bx, cx, dx, 0

	; Diagonale 2 : (ax, dx) -> (cx, bx)
	GFX     LINE, ax, dx, cx, bx, 0

	.draw_label:
	pop     dx
	pop     cx
	pop     bx
	pop     ax

	; Dessin du texte à droite (BoxX2 + 6)
	add     cx, 6

	; Y = Centré par rapport au widget
	mov     bx, [gs:si + widget.y]
	mov     ax, [gs:si + widget.h]
	sub     ax, 8
	shr     ax, 1
	add     bx, ax
	inc     bx

	GFX     GOTOXY, cx, bx
	mov     dx, [gs:si + widget.text_seg]
	mov     ax, [gs:si + widget.text_ofs]
	GFX     WRITE, dx, ax

	ret
;
; affiche le texte au centre du widget gs:si
;
draw_text:
	; Petit hack pour recentrer le texte après l'effet gras
	mov     cx, [gs:si + widget.w]
	mov     dx, [gs:si + widget.h]

	.text:
	; --- Centrage Texte (Simplifié) ---
	mov     es, [gs:si + widget.text_seg]
	mov     di, [gs:si + widget.text_ofs]
	xor     cx, cx

	.strlen:
	cmp     byte [es:di], 0
	je      .calc
	inc     cx
	inc     di
	jmp     .strlen

	.calc:
	shl     cx, 3   ; Largeur texte px
	push    ax      ; Sauve X original
	mov     ax, [gs:si + widget.w]
	sub     ax, cx
	shr     ax, 1
	pop     dx      ; Récupère X original (poussé depuis AX)
	add     ax, dx  ; AX = X final centré

	push    ax      ; Sauvegarde X final pour GOTOXY

	mov     bx, [gs:si + widget.h]
	sub     bx, 8
	shr     bx, 1
	add     bx, [gs:si + widget.y] ; Y final
	inc		bx

	pop     cx      ; CX = X Final, BX = Y Final

	GFX     GOTOXY, cx, bx

	mov     dx, [gs:si + widget.text_seg]
	mov     ax, [gs:si + widget.text_ofs]
	GFX     WRITE, dx, ax
	ret