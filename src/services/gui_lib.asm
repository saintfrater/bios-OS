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

; --- Configuration Mémoire ---
%define GUI_RAM_SEG         0x0A00      ; Segment de données UI
%define GUI_MAX_WIDGETS     32          ; Nombre max de widgets simultanés

; --- Drapeaux & États ---
%define GUI_STATE_FREE      0           ; Le slot est vide (mémoire dispo)
%define GUI_STATE_NORMAL    1           ; Affiché, repos
%define GUI_STATE_HOVER     2           ; Souris dessus
%define GUI_STATE_PRESSED   3           ; Clic enfoncé
%define GUI_STATE_DISABLED  4           ; Grisé

; --- Event mask ---
%define EVENT_NONE              00000000b
%define EVENT_HOVER             00000001b
%define EVENT_LEFT_CLICK        00000010b
%define EVENT_RIGHT_CLICK       00000100b
%define EVENT_MIDDLE_CLICK      00001000b
%define EVENT_LEFT_RELEASE      00010000b
%define EVENT_RIGHT_RELEASE     00100000b
%define EVENT_ENTER             10000000b

; --- Structure d'un OBJET (Bouton, etc) ---
struc widget
    .state      resb 1      ; État (0=libre, >0=utilisé)
    .oldstate   resb 1      ; widget a-t-il été modifié ?
    .user_id    resb 1      ; ID unique utilisateur
    .x          resw 1      ; Position X
    .y          resw 1      ; Position Y
    .w          resw 1      ; Largeur
    .h          resw 1      ; Hauteur
    .text_ofs   resw 1      ; Offset du texte
    .text_seg   resw 1      ; Segment du texte
    .event      resb 1      ; found events (0 = none)
    .event_click      resw 1      ; adresse de la fonction "on click"
    .drag_mode        resb 1      ; 0=None, 1=Horiz, 2=Vert
    .drag_min         resw 1      ; Limite Min
    .drag_max         resw 1      ; Limite Max
    .drag_anchor      resw 1      ; Offset souris au clic
;    .event_hover      resw 1      ; adresse de la fonction "on hover"
;    .event_release    resw 1      ; adresse de la fonction "on release"
;    .event_disable    resw 1      ; adresse de la fonction "on disable"
;    .event_enable     resw 1      ; adresse de la fonction "on enable"
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
    mov     cx, (widget_size * GUI_MAX_WIDGETS)
    shl     cx, 2           ; cx / 4
    xor     eax, eax
    rep     stosd          ; Remplit tout de 0

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
    mov     byte [gs:si + widget.oldstate], 0                ; doit etre dessiné

    ; Reset des champs critiques pour éviter les déchets
    mov     word [gs:si + widget.event_click], 0

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

    mov     byte [gs:si + widget.event], 0      ; no event found]

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

    ; --- on est au moins dans le widget ---
    ; Pour savoir si on vient d'entrer (ENTER), on regarde l'état PRÉCÉDENT (avant ce frame).
    ; Si l'état n'était ni HOVER ni PRESSED, c'est qu'on vient d'arriver.
    cmp     byte [gs:si + widget.state], GUI_STATE_HOVER
    je      .already_hover
    cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
    je      .already_hover

    ; Nouvel arrivant
    or      byte [gs:si + widget.event], EVENT_ENTER

    .already_hover:
    or      byte [gs:si + widget.event], EVENT_HOVER

    ; --- Hit: Souris sur le widget ---
    test    bl, 1           ; Clic gauche ?
    jz      .released

    ; Clic enfoncé
    mov     byte [gs:si + widget.state], GUI_STATE_PRESSED
    or      byte [gs:si + widget.event], EVENT_LEFT_CLICK

    ; Calcul de l'ancrage pour le drag (Mouse - WidgetPos)
    mov     ax, cx
    sub     ax, [gs:si + widget.x]
    mov     [gs:si + widget.drag_anchor], ax    ; Save X anchor
    cmp     byte [gs:si + widget.drag_mode], 2
    jne     .done
    mov     ax, dx
    sub     ax, [gs:si + widget.y]
    mov     [gs:si + widget.drag_anchor], ax    ; Save Y anchor
    jmp     .done

    .released:
    ; Bouton relâché. Était-il pressé avant ?
    and     byte [gs:si + widget.event], ~EVENT_LEFT_CLICK
    cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
    jne     .hover

    ; Clic validé !
    mov     al, 1
    mov     byte [gs:si + widget.state], GUI_STATE_HOVER
    jmp     .done

    .hover:
    mov     byte [gs:si + widget.state], GUI_STATE_HOVER
    jmp     .done

    .miss:
    ; Si on n'est plus dessus, mais qu'on l'était avant (HOVER/PRESSED), il faut redessiner !
    cmp     byte [gs:si + widget.state], GUI_STATE_NORMAL
    je      .done                           ; Déjà normal, rien à faire

    mov     byte [gs:si + widget.state], GUI_STATE_NORMAL
    and     byte [gs:si + widget.event], ~EVENT_HOVER
    jmp     .done

.logic_pressed:
    ; Si le bouton est relâché, on sort du mode Drag/Pressed
    test    bl, 1
    jz      .released   ; On saute vers la logique de relâchement standard (HitTest)

    ; --- LOGIQUE DE DÉPLACEMENT ---
    cmp     byte [gs:si + widget.drag_mode], 1
    je      .drag_h
    cmp     byte [gs:si + widget.drag_mode], 2
    je      .drag_v
    jmp     .done

.drag_h:
    mov     ax, cx
    sub     ax, [gs:si + widget.drag_anchor]    ; X = MouseX - Anchor
    ; Clamp Min
    cmp     ax, [gs:si + widget.drag_min]
    jge     .chk_max_h
    mov     ax, [gs:si + widget.drag_min]
.chk_max_h:
    ; Clamp Max
    cmp     ax, [gs:si + widget.drag_max]
    jle     .apply_pos
    mov     ax, [gs:si + widget.drag_max]
    jmp     .apply_pos

.drag_v:
    mov     ax, dx
    sub     ax, [gs:si + widget.drag_anchor]    ; Y = MouseY - Anchor
    ; Clamp (Simplifié, on pourrait ajouter drag_min_y)
    ; Ici on utilise les mêmes champs min/max pour l'axe choisi
    jmp     .apply_pos

.apply_pos:
    ; Mise à jour position (si changement)
    cmp     byte [gs:si + widget.drag_mode], 1
    je      .upd_x
    mov     [gs:si + widget.y], ax
    jmp     .force_redraw
.upd_x:
    mov     [gs:si + widget.x], ax
.force_redraw:
    mov     byte [gs:si + widget.oldstate], 255 ; Force le redessin

    .done:
    pop     ds
    ret

; (Interne) Dessine le widget pointé par SI
gui_draw_single_widget:
    pusha

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

    ; Dispatch selon état
    cmp     byte [gs:si + widget.state], GUI_STATE_PRESSED
    je      .paint_pressed
    cmp     byte [gs:si + widget.state], GUI_STATE_HOVER
    je      .paint_hover

    .paint_normal:
    GFX     RECTANGLE_FILL, ax, bx, cx, dx, 1   ; Blanc
    GFX     RECTANGLE_DRAW, ax, bx, cx, dx, 0   ; Bord Noir
    GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
    jmp     .text

    .paint_hover:
    GFX     RECTANGLE_FILL, ax, bx, cx, dx, 1   ; Blanc
    GFX     RECTANGLE_DRAW, ax, bx, cx, dx, 0   ; Bord Noir
    ; Effet gras
    inc     ax
    inc     bx
    dec     cx
    dec     dx
    GFX     RECTANGLE_DRAW, ax, bx, cx, dx, 0

    ; Restauration coords pour le texte
    mov     ax, [gs:si + widget.x]
    mov     bx, [gs:si + widget.y]
    jmp     .text_setup

    .paint_pressed:
    GFX     RECTANGLE_FILL, ax, bx, cx, dx, 0   ; Noir
    GFX     TXT_MODE, GFX_TXT_WHITE_TRANSPARENT
    jmp     .text

    .text_setup:
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
    pop     bx      ; Récupère X original dans BX (oups, on veut ajouter)
    add     ax, bx  ; X final

    push    ax      ; X final prêt

    mov     bx, [gs:si + widget.h]
    sub     bx, 8
    shr     bx, 1
    add     bx, [gs:si + widget.y] ; Y final

    pop     cx      ; CX = X Final, BX = Y Final

    GFX     GOTOXY, cx, bx

    mov     dx, [gs:si + widget.text_seg]
    mov     ax, [gs:si + widget.text_ofs]
    GFX     WRITE, dx, ax

    .done:
    popa
    ret
