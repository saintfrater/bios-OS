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

	mov     ax, SEG_GUI
	mov     gs, ax

	; Charger l'état de la souris pour toute la passe
	push    ds
	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax
	mov     bl, [PTR_MOUSE + mouse.status]
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

	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax
	mov		ax, SEG_GUI
	mov		gs, ax

	mov     al, byte [gs:si + widget.state]
	cmp     al, GUI_STATE_DISABLED
	je      .done

	xor     ax, ax

	; les macros peuvent modifer les registres cx, dx & bx
	mov     cx, [PTR_MOUSE + mouse.x]
	mov     dx, [PTR_MOUSE + mouse.y]

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

	mov     bl, [PTR_MOUSE + mouse.status]

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
	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax
	mov     ax, [PTR_MOUSE + mouse.x]
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
	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax
	mov     ax, [PTR_MOUSE + mouse.y]
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
	xor     word [gs:si + widget.attr_val], 1
	mov     byte [gs:si + widget.oldstate], 255 ; Force redraw

	mov     al, 1
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	ret

	.hover:
	mov     byte [gs:si + widget.state], GUI_STATE_HOVER
	xor     ax, ax
	ret
