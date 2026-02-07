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
%define GUI_RAM_SEG         0x0600      ; Segment de données UI (Safe: après Stack, avant Heap)
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

%define SLIDER_HORIZONTAL			1
%define SLIDER_VERTICAL				2

; =============================================================================
;  SECTION : API ACTIONS
; =============================================================================

%define GUI_CREATE      0
%define GUI_DESTROY     1
%define GUI_GET_STATE   2
%define GUI_GET_TYPE    3
%define GUI_GET_VAL     4

gui_api_table:
    dw gui_api_create
	dw gui_api_destroy
    dw gui_api_get_state
    dw gui_api_get_type
    dw gui_api_get_val

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
; gui_api_create
; Crée un widget et retourne son ID
; Out: AX = ID ou -1 si erreur
; -----------------------------------------------------------------------------
gui_api_create:
    call    gui_alloc_widget        ; Returns GS:SI
    jc      .error

    ; ID = SI / widget_size
    mov     ax, si
    xor     dx, dx
    mov     cx, widget_size
    div     cx
    ret

.error:
    mov     ax, -1
    ret

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


    mov     ax, .id         ; ID
    call    gui_get_widget_ptr
    jc      .err

    mov     ax, [gs:si + widget.attr_val]
    jmp     .done

.err:
    mov     ax, -1
.done:
    leave
    ret
%undef .id

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
; In: AX = ID
; Out: GS:SI = Ptr, CF=1 if error
; -----------------------------------------------------------------------------
gui_get_widget_ptr:
    cmp     ax, GUI_MAX_WIDGETS
    jae     .error

    push    dx
    mov     cx, widget_size
    mul     cx              ; AX = Offset
    mov     si, ax
    pop     dx

    mov     ax, GUI_RAM_SEG
    mov     gs, ax

    clc
    ret
.error:
    stc
    ret

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
	jb      .miss                               ; mouse.x < widget.x ?
	mov     bx, [gs:si + widget.x]
	add     bx, [gs:si + widget.w]
	cmp     cx, bx
	ja      .miss                               ; mouse.x >= widget.x ?

	cmp     dx, [gs:si + widget.y]
	jb      .miss                               ; mouse.y < widget.y ?
	mov     bx, [gs:si + widget.y]
	add     bx, [gs:si + widget.h]
	cmp     dx, bx
	ja      .miss                               ; mouse.y >= widget.y ?

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

	; --- CALCUL TAILLE THUMB POUR HIT TEST ---
	; On doit savoir si le clic est SUR le curseur ou SUR la piste
	push    ax
	push    bx
	push    dx

	xor     ax, ax
	xor     bx, bx

	cmp     byte [gs:si + widget.attr_mode], 2
	je      .calc_v

	; --- Horizontal ---
	mov     ax, [gs:si + widget.w]
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx                      ; AX = Thumb Width

	; Check collision avec le thumb actuel
	mov     bx, [gs:si + widget.attr_val]
	cmp     cx, bx
	jb      .click_outside_h        ; Click avant le thumb
	add     bx, ax
	cmp     cx, bx
	ja      .click_outside_h        ; Click après le thumb

	; Click DANS le thumb : Anchor = MouseX - AttrVal
	mov     ax, cx
	sub     ax, [gs:si + widget.attr_val]
	mov     [gs:si + widget.attr_anchor], ax
	jmp     .init_done

	.click_outside_h:
	; Click HORS du thumb : On centre le thumb sur la souris
	shr     ax, 1
	mov     [gs:si + widget.attr_anchor], ax
	jmp     .init_done

	.calc_v:
	; --- Vertical ---
	mov     ax, [gs:si + widget.h]
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx                      ; AX = Thumb Height

	; Check collision avec le thumb actuel
	mov     bx, [gs:si + widget.attr_val]
	cmp     dx, bx
	jb      .click_outside_v
	add     bx, ax
	cmp     dx, bx
	ja      .click_outside_v

	; Click DANS le thumb
	mov     ax, dx
	sub     ax, [gs:si + widget.attr_val]
	mov     [gs:si + widget.attr_anchor], ax
	jmp     .init_done

	.click_outside_v:
	; Click HORS du thumb
	shr     ax, 1
	mov     [gs:si + widget.attr_anchor], ax

	.init_done:
	pop     dx
	pop     bx
	pop     ax

	.do_drag:
	; --- LOGIQUE DE DÉPLACEMENT ---
	; On calcule les limites dynamiquement pour éviter que le curseur ne sorte
	push    ax
	push    bx
	push    dx

	xor     ax, ax
	xor     bx, bx

	cmp     byte [gs:si + widget.attr_mode], 1
	je      .drag_h
	cmp     byte [gs:si + widget.attr_mode], 2
	je      .drag_v

	pop     dx
	pop     bx
	pop     ax
	xor     ax, ax
	ret

	.drag_h:
	; 1. Thumb Width -> AX
	mov     ax, [gs:si + widget.w]
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx      ; AX = Thumb Width

	; 2. Max Pos = X + W - ThumbWidth
	mov     bx, [gs:si + widget.x]
	add     bx, [gs:si + widget.w]
	sub     bx, ax  ; BX = Max Pos

	; 3. Min Pos = X
	mov     dx, [gs:si + widget.x] ; DX = Min Pos

	; 4. Target Pos = MouseX - Anchor
	mov     ax, cx
	sub     ax, [gs:si + widget.attr_anchor]
	jmp     .apply_clamp

	.drag_v:
	; 1. Thumb Height -> AX
	mov     ax, [gs:si + widget.h]
	mov     bl, [gs:si + widget.thumb_pct]
	mul     bx
	mov     bx, 100
	div     bx      ; AX = Thumb Height

	; 2. Max Pos = Y + H - ThumbHeight
	mov     bx, [gs:si + widget.y]
	add     bx, [gs:si + widget.h]
	sub     bx, ax  ; BX = Max Pos

	; 3. Min Pos = Y
	mov     dx, [gs:si + widget.y] ; DX = Min Pos

	; 4. Target Pos = MouseY - Anchor
	; MouseY est sur la pile (push dx initial), on le recupere via SP
	mov     bp, sp
	mov     ax, [bp]    ; [bp] = Saved DX (MouseY)
	sub     ax, [gs:si + widget.attr_anchor]

	.apply_clamp:
	; AX = Target, DX = Min, BX = Max
	cmp     ax, dx
	jge     .chk_max
	mov     ax, dx
	jmp     .apply_pos
	.chk_max:
	cmp     ax, bx
	jle     .apply_pos
	mov     ax, bx

	.apply_pos:
	pop     dx
	pop     bx
	add     sp, 2   ; Clean AX from stack

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
