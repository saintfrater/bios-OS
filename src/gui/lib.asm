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
%define GUI_RAM_SEG         0x080       ; Segment de données UI (Safe: après Stack, avant Heap)
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

	mov     ax, GUI_RAM_SEG
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

	mov     ax, GUI_RAM_SEG
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
; Entrée : DS doit pointer vers GUI_RAM_SEG
; -----------------------------------------------------------------------------
gui_init_system:
	push    eax
	push    cx
	push    es
	push    di

	mov     ax, GUI_RAM_SEG
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

	mov     ax, GUI_RAM_SEG
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
	push    gs

	mov     ax, BDA_DATA_SEG
	mov     ds, ax
	mov		ax, GUI_RAM_SEG
	mov		gs, ax

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

	.case_0:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_LABEL
	jne     .case_1
	call    gui_logic_label
	jmp     .done

	.case_1:
	; Dispatch selon le type
	cmp     byte [gs:si + widget.type], OBJ_TYPE_SLIDER
	jne     .case_2
	call    gui_logic_slider
	jmp     .done

	.case_2:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_BUTTON
	jne     .case_3
	call    gui_logic_button
	jmp     .done

	.case_3:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_BUTTON_ROUNDED
	jne     .case_4
	call    gui_logic_button
	jmp     .done

	.case_4:
	cmp     byte [gs:si + widget.type], OBJ_TYPE_CHECKBOX
	jne     .case_5
	call    gui_logic_checkbox
	jmp     .done

	.case_5:
	jmp     .done

	.miss:
	mov     byte [gs:si + widget.state], GUI_STATE_NORMAL
	xor     ax, ax

	.done:
	pop		gs
	pop     ds
	ret

	; --- Logique spécifique LABEL ---
gui_logic_label:
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


; -----------------------------------------------------------------------------
; gui_slider_update_value
; In: GS:SI = widget
; Calcule .attr_val à partir de .thumb_pos (pixels)
; -----------------------------------------------------------------------------
gui_slider_update_value:
    push	eax
	push	ebx
	push	ecx
	push	edx

	cmp		byte [gs:si + widget.type], OBJ_TYPE_SLIDER
	jne		.done

    ; Calculer RangePix (Amplitude totale de mouvement en pixels)
    movzx   eax, word [gs:si + widget.w]     ; Largeur par défaut
    cmp     byte [gs:si + widget.attr_mode], SLIDER_VERTICAL
    jne     .calc_thumb
    movzx   eax, word [gs:si + widget.h]     ; Hauteur si vertical

	.calc_thumb:
    push    eax                              ; Sauvegarde la dimension totale
    movzx   ebx, byte [gs:si + widget.thumb_pct]
    mul     ebx                              ; EAX = Dim * pct
    mov     ebx, 100
    xor     edx, edx
    div     ebx                              ; EAX = Taille physique du curseur

    pop     ebx                              ; EBX = Dimension totale
    sub     ebx, eax                         ; EBX = RangePix (Place disponible)
    jz      .done                            ; Si 0, division impossible


    ; Calculer DeltaPix (Distance parcourue par le curseur)
    movzx   eax, word [gs:si + widget.thumb_pos]
    movzx   ecx, word [gs:si + widget.x]     ; Origine X par défaut
    cmp     byte [gs:si + widget.attr_mode], 2
    jne     .do_sub
    movzx   ecx, word [gs:si + widget.y]     ; Origine Y si vertical
	.do_sub:
    sub     eax, ecx                         ; EAX = DeltaPix (pixels relatifs)

    ; Produit en croix : (DeltaPix * RangeLogique) / RangePix
    movzx   ecx, word [gs:si + widget.attr_max]
    movzx   edx, word [gs:si + widget.attr_min]
    sub     ecx, edx                         ; ECX = RangeLogique (Max - Min)

    mul     ecx                              ; EAX = DeltaPix * RangeLogique
    xor     edx, edx                         ; Nettoyage EDX pour div 32 bits
    div     ebx                              ; EAX = Valeur métier relative

    ; Ajouter le Min métier et stocker
    movzx   edx, word [gs:si + widget.attr_min]
    add     eax, edx                         ; EAX = Valeur métier finale
    mov     [gs:si + widget.attr_val], ax    ; Stockage (tronqué en 16 bits)

	.done:
    pop		edx
	pop		ecx
	pop		ebx
	pop		eax
    ret

; -----------------------------------------------------------------------------
; gui_slider_update_pixels
; In: GS:SI = widget
; Calcule .thumb_pos (pixels) à partir de .attr_val (métier)
; -----------------------------------------------------------------------------
gui_slider_update_pixels:
    pushad                          ; Sauvegarde EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI

    ; Calculer la dimension totale du widget (W ou H)
    movzx   eax, word [gs:si + widget.w]
    cmp     byte [gs:si + widget.attr_mode], 2 ; Mode Vertical ?
    jne     .calc_range
    movzx   eax, word [gs:si + widget.h]

	.calc_range:
    ; Calculer RangePix (Amplitude max du mouvement)
    ; RangePix = DimensionTotale - (DimensionTotale * thumb_pct / 100)
    push    eax                             ; Sauvegarde DimTotale
    movzx   ebx, byte [gs:si + widget.thumb_pct]
    mul     ebx                             ; EAX = Dim * pct
    mov     ebx, 100
    xor     edx, edx
    div     ebx                             ; EAX = Taille physique du thumb

    pop     ebx                             ; EBX = DimTotale
    sub     ebx, eax                        ; EBX = RangePix (Amplitude)
    jz      .done                           ; Sécurité : si RangePix = 0

    ; Calculer DeltaLogique (Progression métier)
    movzx   eax, word [gs:si + widget.attr_val]
    movzx   ecx, word [gs:si + widget.attr_min]
    sub     eax, ecx                        ; EAX = DeltaLogique (Val - Min)
    js      .set_min                        ; Sécurité si Val < Min

    ; Produit en croix : (DeltaLogique * RangePix) / RangeLogique
    movzx   ecx, word [gs:si + widget.attr_max]
    movzx   edx, word [gs:si + widget.attr_min]
    sub     ecx, edx                        ; ECX = RangeLogique (Max - Min)
    jz      .done                           ; Sécurité : RangeLogique ne peut être 0

    mul     ebx                             ; EAX = DeltaLogique * RangePix
    xor     edx, edx
    div     ecx                             ; EAX = Offset pixel relatif

    ; 5. Ajouter l'origine physique (X ou Y)
    movzx   edx, word [gs:si + widget.x]
    cmp     byte [gs:si + widget.attr_mode], 2
    jne     .store
    movzx   edx, word [gs:si + widget.y]
	.store:
    add     eax, edx                        ; EAX = Position pixel finale
    mov     [gs:si + widget.thumb_pos], ax
    jmp     .done

	.set_min:
    ; Si la valeur est sous le minimum, on colle au début
    movzx   ax, word [gs:si + widget.x]
    cmp     byte [gs:si + widget.attr_mode], 2
    jne     .force_store
    movzx   ax, word [gs:si + widget.y]
	.force_store:
    mov     [gs:si + widget.thumb_pos], ax

	.done:
    popad                           ; Restauration propre
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
	mov     bx, [gs:si + widget.thumb_pos]
	cmp     cx, bx
	jb      .click_outside_h        ; Click avant le thumb
	add     bx, ax
	cmp     cx, bx
	ja      .click_outside_h        ; Click après le thumb

	; Click DANS le thumb : Anchor = MouseX - AttrVal
	mov     ax, cx
	sub     ax, [gs:si + widget.thumb_pos]
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
	mov     bx, [gs:si + widget.thumb_pos]
	cmp     dx, bx
	jb      .click_outside_v
	add     bx, ax
	cmp     dx, bx
	ja      .click_outside_v

	; Click DANS le thumb
	mov     ax, dx
	sub     ax, [gs:si + widget.thumb_pos]
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

	xor     ax, ax
	xor     bx, bx

	cmp     byte [gs:si + widget.attr_mode], 1
	je      .drag_h
	cmp     byte [gs:si + widget.attr_mode], 2
	je      .drag_v

	xor     ax, ax
	ret

	.drag_h:
	; 1. Thumb Width -> AX
	mov     ax, [gs:si + widget.w]
	mov     bl, [gs:si + widget.thumb_pct]
	xor		bh, bh			; Sécurité
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
	; On recharge MouseX depuis la BDA pour être sûr
	push    ds
	mov     ax, BDA_DATA_SEG
	mov     ds, ax
	mov     ax, [BDA_MOUSE + mouse.x]
	pop     ds

	sub     ax, [gs:si + widget.attr_anchor]
	jmp     .apply_clamp

	.drag_v:
	; 1. Thumb Height -> AX
	mov     ax, [gs:si + widget.h]
	mov     bl, [gs:si + widget.thumb_pct]
	xor		bh, bh			; Sécurité
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
	; On recharge MouseY depuis la BDA pour être sûr
	push    ds
	mov     ax, BDA_DATA_SEG
	mov     ds, ax
	mov     ax, [BDA_MOUSE + mouse.y]
	pop     ds

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
	cmp     ax, [gs:si + widget.thumb_pos]
	je      .no_change
	mov     [gs:si + widget.thumb_pos], ax

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
	xor     word [gs:si + widget.thumb_pos], 1
	mov     byte [gs:si + widget.oldstate], 255 ; Force redraw

	mov     al, 1
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	ret

	.hover:
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	xor     ax, ax
	ret
