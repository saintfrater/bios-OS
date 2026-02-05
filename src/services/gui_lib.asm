; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gui_lib.asm
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
%define GUI_RAM_SEG         0x0A00      ; Segment de données UI
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
%define WIDGET_TYPE_BUTTON          0
%define WIDGET_TYPE_SLIDER          1
%define WIDGET_TYPE_LABEL           2
%define WIDGET_TYPE_ROUND_BUTTON    3
%define WIDGET_TYPE_CHECKBOX        4

; --- Widgets attributs ---
%define BUTTON_OK                   1

; --- Structure d'un OBJET (Bouton, etc) ---
struc widget
	.state      resb 1      ; État (0=libre, >0=utilisé)
	.type       resb 1      ; Type (0=Button, 1=Slider...)
	.oldstate   resb 1      ; widget a-t-il été modifié ?
	.user_id    resb 1      ; ID unique utilisateur
	.x          resw 1      ; Position X
	.y          resw 1      ; Position Y
	.x2         resw 1      ; Position X2 calculée
	.y2         resw 1      ; Position Y2 calculée
	.w          resw 1      ; Largeur
	.h          resw 1      ; Hauteur
	.text_ofs   resw 1      ; Offset du texte
	.text_seg   resw 1      ; Segment du texte
	.event_click      resw 1      ; adresse de la fonction "on click"
;    .event_hover      resw 1      ; adresse de la fonction "on hover"
;    .event_release    resw 1      ; adresse de la fonction "on release"
;    .event_disable    resw 1      ; adresse de la fonction "on disable"
;    .event_enable     resw 1      ; adresse de la fonction "on enable"
	.event_drag       resw 1      ; adresse de la fonction "on drag"

	.attr_mode        resb 1      ; 0=None, 1=Horiz, 2=Vert
	.attr_min         resw 1      ; Valeur/Position Min
	.attr_max         resw 1      ; Valeur/Position Max
	.attr_val         resw 1      ; Valeur/Position Actuelle
	.attr_anchor      resw 1      ; Offset interne pour le drag
	.thumb_pct        resb 1      ; Taille du curseur en % (1-100)

	alignb      2           ; Alignement mémoire pour performance
endstruc

; =============================================================================
;  SECTION : GESTION MÉMOIRE (ALLOCATION / LIBÉRATION)
; =============================================================================

; -----------------------------------------------------------------------------
; gui_init_system
; Initialise toute la mémoire des widgets à 0 (Libre)
; Entrée : DS doit pointer vers GUI_RAM_SEG
; -----------------------------------------------------------------------------
gui_init_system:
	push    eax
	push    cx
	push    es
	push    di

	mov     ax, GUI_RAM_SEG
	mov     es, ax

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

	mov     ax, GUI_RAM_SEG
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
	mov     byte [gs:si + widget.type], WIDGET_TYPE_BUTTON  ; Type par défaut
	mov     byte [gs:si + widget.oldstate], 0                ; doit etre dessiné

	; Reset des champs critiques pour éviter les déchets
	mov     word [gs:si + widget.event_click], 0
	mov     word [gs:si + widget.event_drag], 0
	mov     byte [gs:si + widget.thumb_pct], 10     ; 10% par défaut

	clc                             ; Clear Carry Flag
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

	mov     ax, GUI_RAM_SEG
	mov     es, ax

	mov     di, si
	mov     cx, (widget_size)
	shr     cx, 2           ; cx / 4
	xor     eax, eax
	rep     stosd          ; Remplit tout de 0

	mov     byte [es:si + widget.state], GUI_STATE_FREE
	; On efface visuellement le widget (optionnel, remplit de blanc)
	; Pour l'instant on le marque juste libre, il sera redessiné par-dessus.

	pop     es
	pop     eax
	ret

; =============================================================================
;  SECTION : MOTEUR D'ÉVÉNEMENTS (EVENT LOOP)
; =============================================================================

; -----------------------------------------------------------------------------
; gui_process_all
; 1. Redessine tous les widgets actifs
; 2. Vérifie les clics et appelle les callbacks
; Entrée :
;   CX = Mouse X
;   DX = Mouse Y
;   BL = Mouse Buttons
; -----------------------------------------------------------------------------
gui_process_all:
	pusha
	push    ds
	push    gs

	mov     ax, GUI_RAM_SEG
	mov     gs, ax

	; Charger l'état de la souris pour toute la passe
	push    ds
	mov     ax, BDA_DATA_SEG
	mov     ds, ax
	mov     bl, [BDA_MOUSE + mouse.status]
	pop     ds

	mov     si, 0                   ; Pointeur début tableau
	mov     di, GUI_MAX_WIDGETS     ; Compteur

	.loop_widgets:
	; Est-ce que ce slot est occupé ?
	cmp     byte [gs:si + widget.state], GUI_STATE_FREE
	je      .next_widget

	; --- Logique Widget ---
	push    bx                      ; Sauver état boutons souris
	call    gui_update_logic        ; Vérifier collision/clic

	; Si AL=1 (Clic relâché validé), exécuter le callback
	cmp     al, 1
	jne     .no_action

	; Vérifier si un callback est défini
	cmp     word [gs:si + widget.event_click], 0
	je      .no_action

	; APPEL DU CALLBACK (Fonction utilisateur)
	; On sauve les registres car le callback peut faire n'importe quoi
	pusha
	call    word [gs:si + widget.event_click]
	popa

	.no_action:
	pop     bx                      ; Restaurer boutons

	mov     al, byte [gs:si + widget.oldstate]
	mov     ah, byte [gs:si + widget.state]

	; Dessiner (si l'état a changé ou pour refresh)

	cmp     al,ah
	je      .next_widget            ; Si != 0, le widget est à jour, on passe.
	call    gui_draw_single_widget

	.next_widget:
	add     si, widget_size
	dec     di
	jnz     .loop_widgets

	pop     gs
	pop     ds
	popa
	ret

; =============================================================================
;  SECTION : LOGIQUE INTERNE ET DESSIN
; =============================================================================

; (Interne) Met à jour l'état d'un seul widget
; Entrée : SI=Widget, CX=MouseX, DX=MouseY, BL=Buttons
; Sortie : AL=1 si Clicked, 0 sinon. Met à jour [gs:si].state
gui_update_logic:
	push    ds
	mov     ax, BDA_DATA_SEG
	mov     ds, ax

	mov     al, byte [gs:si + widget.state]
	cmp     al, GUI_STATE_DISABLED
	je      .done

	xor     ax, ax

	; les macros peuvent modifer les registres cx, dx & bx
	mov     cx, [BDA_MOUSE + mouse.x]
	mov     dx, [BDA_MOUSE + mouse.y]

	; --- Hit Test ---
	cmp     cx, [gs:si + widget.x]
	jl      .miss                               ; mouse.x < widget.x ?
	mov     bx, [gs:si + widget.x]
	add     bx, [gs:si + widget.w]
	cmp     cx, bx
	jg      .miss                               ; mouse.x >= widget.x ?

	cmp     dx, [gs:si + widget.y]
	jl      .miss                               ; mouse.y < widget.y ?
	mov     bx, [gs:si + widget.y]
	add     bx, [gs:si + widget.h]
	cmp     dx, bx
	jg      .miss                               ; mouse.y >= widget.y ?

	mov     bl, [BDA_MOUSE + mouse.status]

	; Dispatch selon le type
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_SLIDER
	jne     .case_2
	call    gui_logic_slider
	jmp     .done

	.case_2:
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_BUTTON
	jne     .case_3
	call    gui_logic_button
	jmp     .done

	.case_3:
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_ROUND_BUTTON
	jne     .case_4
	call    gui_logic_button
	jmp     .done

	.case_4:
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_CHECKBOX
	jne     .case_5
	call    gui_logic_checkbox

	.case_5:
	jmp     .done
	.miss:
	; Si on n'est plus dessus, mais qu'on l'était avant (HOVER/PRESSED), il faut redessiner !
	cmp     byte [gs:si + widget.state], GUI_STATE_NORMAL
	je      .done                           ; Déjà normal, rien à faire

	; Cas particulier : si c'est un slider en cours de drag, on continue la logique
;    cmp     byte [gs:si + widget.type], WIDGET_TYPE_SLIDER
;    jne     .reset_state
;    cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
;    je      .gui_logic_slider

	.reset_state:
	mov     byte [gs:si + widget.state], GUI_STATE_NORMAL
	xor     ax, ax

	.done:
	pop     ds
	ret

; --- Logique spécifique Bouton ---
gui_logic_button:
	test    bl, 1           ; Clic gauche ?
	jz      .released

	; Clic enfoncé
	mov     byte [gs:si + widget.state], GUI_STATE_PRESSED
	xor     ax, ax
	ret

	.released:
	cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
	jne     .hover

	; Clic validé !
	mov     al, 1
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	ret

	.hover:
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	xor     ax, ax
	ret

; --- Logique spécifique Slider ---
gui_logic_slider:
	test    bl, 1           ; Bouton enfoncé ?
	jz      .released

	; Si on vient de cliquer (pas encore PRESSED), on initialise l'ancrage
	cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
	je      .do_drag

	mov     byte [gs:si + widget.state], GUI_STATE_PRESSED

	; Calcul de l'ancrage
	mov     ax, cx
	sub     ax, [gs:si + widget.attr_val]
	mov     [gs:si + widget.attr_anchor], ax
	cmp     byte [gs:si + widget.attr_mode], 2
	jne     .do_drag
	mov     ax, dx
	sub     ax, [gs:si + widget.attr_val]
	mov     [gs:si + widget.attr_anchor], ax

	.do_drag:
	; --- LOGIQUE DE DÉPLACEMENT ---
	cmp     byte [gs:si + widget.attr_mode], 1
	je      .drag_h
	cmp     byte [gs:si + widget.attr_mode], 2
	je      .drag_v
	xor     ax, ax
	ret

	.drag_h:
	mov     ax, cx
	sub     ax, [gs:si + widget.attr_anchor]    ; Nouvelle pos = MouseX - Anchor
	; Clamp Min
	cmp     ax, [gs:si + widget.attr_min]
	jge     .chk_max_h
	mov     ax, [gs:si + widget.attr_min]
	.chk_max_h:
	; Clamp Max
	cmp     ax, [gs:si + widget.attr_max]
	jle     .apply_pos
	mov     ax, [gs:si + widget.attr_max]
	jmp     .apply_pos

	.drag_v:
	mov     ax, dx
	sub     ax, [gs:si + widget.attr_anchor]
	; Clamp Min
	cmp     ax, [gs:si + widget.attr_min]
	jge     .chk_max_v
	mov     ax, [gs:si + widget.attr_min]

	.chk_max_v:
	; Clamp Max
	cmp     ax, [gs:si + widget.attr_max]
	jle     .apply_pos
	mov     ax, [gs:si + widget.attr_max]
	jmp     .apply_pos

	.apply_pos:
	cmp     ax, [gs:si + widget.attr_val]
	je      .no_change
	mov     [gs:si + widget.attr_val], ax

	; Appel du callback on_drag
	cmp     word [gs:si + widget.event_drag], 0
	je      .force_redraw
	pusha
	call    word [gs:si + widget.event_drag]
	popa

	.force_redraw:
	mov     byte [gs:si + widget.oldstate], 255 ; Force le redessin

	.no_change:
	xor     ax, ax
	ret

	.released:
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	xor     ax, ax
	ret

; --- Logique spécifique Checkbox ---
gui_logic_checkbox:
	test    bl, 1           ; Clic gauche ?
	jz      .released

	; Clic enfoncé
	mov     byte [gs:si + widget.state], GUI_STATE_PRESSED
	xor     ax, ax
	ret

	.released:
	cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
	jne     .hover

	; Clic validé ! Toggle value
	xor     word [gs:si + widget.attr_val], 1
	mov     byte [gs:si + widget.oldstate], 255 ; Force redraw

	mov     al, 1
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	ret

	.hover:
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	xor     ax, ax
	ret



; Dessine le widget pointé par SI
gui_draw_single_widget:
	pusha

	GFX     MOUSE_HIDE              ; On cache la souris AVANT de commencer le dessin du widget

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
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_SLIDER
	jne     .case_2
	call    draw_slider
	jmp     .done

	.case_2:
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_BUTTON
	jne     .case_3
	call    draw_button
	jmp     .done

	.case_3:
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_ROUND_BUTTON
	jne     .case_4
	call    draw_round_button
	jmp     .done

	.case_4:
	cmp     byte [gs:si + widget.type], WIDGET_TYPE_CHECKBOX
	jne     .case_5
	call    draw_checkbox
	jmp     .done

	.case_5:



	.done:
	GFX     MOUSE_SHOW              ; On réaffiche la souris APRES, capturant le widget fini
	popa
	ret

draw_slider:
	; 1. Dessiner la piste (Track)
	GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE_LIGHT
	GFX     RECTANGLE, ax, bx, cx, dx, 0

	; 2. Calculer la taille du curseur (Thumb)
	push    ax                      ; Sauvegarde coords track (X1, Y1, X2, Y2)
	push    bx
	push    cx
	push    dx

	cmp     byte [gs:si + widget.attr_mode], 2
	je      .calc_v

	; --- Horizontal ---
	mov     ax, [gs:si + widget.w]
	xor     bh, bh
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx                      ; AX = Thumb Width

	mov     bx, [gs:si + widget.y]        ; BX = Y1
	mov     dx, bx
	add     dx, [gs:si + widget.h]        ; DX = Y2
	mov     cx, [gs:si + widget.attr_val] ; CX = X1
	add     ax, cx                        ; AX = X1 + Width = X2
	xchg    ax, cx                        ; AX = X1, CX = X2
	jmp     .draw_thumb

	.calc_v:
	; --- Vertical ---
	mov     ax, [gs:si + widget.h]
	xor     bh, bh
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx                      ; AX = Thumb Height

	mov     bx, [gs:si + widget.attr_val] ; BX = Y1
	mov     dx, bx
	add     dx, ax                        ; DX = Y2
	mov     ax, [gs:si + widget.x]        ; AX = X1
	mov     cx, ax
	add     cx, [gs:si + widget.w]        ; CX = X2

	.draw_thumb:
	; 3. Dessiner le curseur (Thumb)
	GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE
	GFX     RECTANGLE, ax, bx, cx, dx, 0
	add     sp, 8                   ; Nettoyer la pile des push ax..dx
	GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
	call    draw_text
	ret



draw_button:
	; Dispatch selon état
	cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
	je      .paint_pressed
	cmp     byte [gs:si + widget.state], GUI_STATE_HOVER
	je      .paint_hover

;	.paint_normal:
;		GFX     RECTANGLE_FILL, ax, bx, cx, dx, PATTERN_WHITE

		; Si user_id == 1, on dessine le style "OK" (Double bordure épaisse)
		;test    byte [gs:si + widget.attr_mode], BUTTON_OK
		;jnz     .draw_default_style

;		GFX     RECTANGLE, ax, bx, cx, dx, 0
;		jmp     .done

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
	; Si style "OK" (attr_mode & BUTTON_OK), on ajoute la double bordure
	;test    byte [gs:si + widget.attr_mode], BUTTON_OK
	;jz      .done_borders
	add     ax, 2
	add     bx, 2
	sub     cx, 2
	sub     dx, 2
	GFX     RECTANGLE_ROUND, ax, bx, cx, dx, di
	.done_borders:
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

	push    ax
	push    bx
	push    dx
	.loop_x:
		cmp     ax, cx
		jg      .end_x
		GFX     PUTPIXEL, ax, bx, 0
		GFX     PUTPIXEL, ax, dx, 0
		inc     ax
		inc     bx
		dec     dx
		jmp     .loop_x
	.end_x:
	pop     dx
	pop     bx
	pop     ax

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