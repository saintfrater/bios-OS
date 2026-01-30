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
%define GUI_RAM_SEG         0x0800      ; Segment de données UI
%define GUI_MAX_WIDGETS     32          ; Nombre max de widgets simultanés

; --- Drapeaux & États ---
%define GUI_STATE_FREE      0           ; Le slot est vide (mémoire dispo)
%define GUI_STATE_NORMAL    1           ; Affiché, repos
%define GUI_STATE_HOVER     2           ; Souris dessus
%define GUI_STATE_PRESSED   3           ; Clic enfoncé
%define GUI_STATE_DISABLED  4           ; Grisé

; --- Structure d'un OBJET (Bouton, etc) ---
struc widget
    .state      resb 1      ; État (0=libre, >0=utilisé)
    .user_id    resb 1      ; ID unique utilisateur
    .x          resw 1      ; Position X
    .y          resw 1      ; Position Y
    .w          resw 1      ; Largeur
    .h          resw 1      ; Hauteur
    .state      resb 1      ; État (0=Normal, 1=Hover, 2=Pressed, 3=Disabled)
    .text_ofs   resw 1      ; Offset du texte
    .text_seg   resw 1      ; Segment du texte
    .event_click      resw 1      ; adresse de la fonction "on click"
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
    pushad
    push    ds

    mov     ax, GUI_RAM_SEG
    mov     ds, ax

    mov     di, 0           ; On commence au début du segment 0x0800
    mov     cx, (widget_size * GUI_MAX_WIDGETS)
    shl     cx, 2           ; cx / 4
    xor     eax, eax
    rep     stosd          ; Remplit tout de 0

    pop     ds
    popad
    ret

; -----------------------------------------------------------------------------
; gui_alloc_widget
; Cherche un slot vide et retourne son adresse
; Sortie :
;   - Succès : CF=0 (Carry Clear), SI = Offset du widget
;   - Echec  : CF=1 (Carry Set),  SI = Indéfini (ou 0)
; -----------------------------------------------------------------------------
gui_alloc_widget:
    push    cx
    push    bx
    push    ds

    mov     ax, GUI_RAM_SEG
    mov     ds, ax

    mov     si, 0                   ; Début du pool
    mov     cx, GUI_MAX_WIDGETS

.loop_find:
    cmp     byte [si + widget.state], GUI_STATE_FREE
    je      .found                  ; Si state == 0, c'est libre !

    add     si, widget_size         ; Sinon on passe au suivant
    loop    .loop_find

    ; Pas trouvé (Plein)
    stc                             ; set Carry Flag : erreur
    jmp     .done

.found:
    ; On initialise le slot trouvé
    mov     byte [si + widget.state], GUI_STATE_NORMAL ; Marquer comme occupé

    ; Reset des champs critiques pour éviter les déchets
    mov     word [si + widget.callback], 0

    clc                             ; Clear Carry Flag
.done:
    pop     ds
    pop     bx
    pop     cx
    ret

; -----------------------------------------------------------------------------
; gui_free_widget
; Libère un widget
; Entrée : SI = Pointeur widget
; -----------------------------------------------------------------------------
gui_free_widget:
    mov     byte [si + widget.state], GUI_STATE_FREE
    ; On efface visuellement le widget (optionnel, remplit de blanc)
    ; Pour l'instant on le marque juste libre, il sera redessiné par-dessus.
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

    mov     si, 0                   ; Pointeur début tableau
    mov     di, GUI_MAX_WIDGETS     ; Compteur

    .loop_widgets:
    ; Est-ce que ce slot est occupé ?
    cmp     byte [si + widget.state], GUI_STATE_FREE
    je      .next_widget

    ; --- Logique Widget ---
    push    bx                      ; Sauver état boutons souris
    call    gui_update_logic        ; Vérifier collision/clic

    ; Si AL=1 (Clic relâché validé), exécuter le callback
    cmp     al, 1
    jne     .no_action

    ; Vérifier si un callback est défini
    cmp     word [si + widget.callback], 0
    je      .no_action

    ; APPEL DU CALLBACK (Fonction utilisateur)
    ; On sauve les registres car le callback peut faire n'importe quoi
    pusha
    call    word [si + widget.callback]
    popa

    .no_action:
    pop     bx                      ; Restaurer boutons

    ; Dessiner (si l'état a changé ou pour refresh)
    call    gui_draw_single_widget

    .next_widget:
    add     si, widget_size
    dec     di
    jnz     .loop_widgets

    popa
    ret

; =============================================================================
;  SECTION : LOGIQUE INTERNE ET DESSIN
; =============================================================================

; (Interne) Met à jour l'état d'un seul widget
; Entrée : SI=Widget, CX=MouseX, DX=MouseY, BL=Buttons
; Sortie : AL=1 si Clicked, 0 sinon. Met à jour [SI].state
gui_update_logic:
    xor     ax, ax

    cmp     byte [si + widget.state], GUI_STATE_DISABLED
    je      .done

    ; --- Hit Test ---
    cmp     cx, [si + widget.x]
    jl      .miss
    mov     bp, [si + widget.x]
    add     bp, [si + widget.w]
    cmp     cx, bp
    jg      .miss

    cmp     dx, [si + widget.y]
    jl      .miss
    mov     bp, [si + widget.y]
    add     bp, [si + widget.h]
    cmp     dx, bp
    jg      .miss

    ; --- Hit: Souris sur le widget ---
    test    bl, 1           ; Clic gauche ?
    jz      .released

    ; Clic enfoncé
    mov     byte [si + widget.state], GUI_STATE_PRESSED
    jmp     .done

.released:
    ; Bouton relâché. Était-il pressé avant ?
    cmp     byte [si + widget.state], GUI_STATE_PRESSED
    jne     .hover

    ; Clic validé !
    mov     al, 1
    mov     byte [si + widget.state], GUI_STATE_HOVER
    jmp     .done

.hover:
    mov     byte [si + widget.state], GUI_STATE_HOVER
    jmp     .done

.miss:
    mov     byte [si + widget.state], GUI_STATE_NORMAL
.done:
    ret

; (Interne) Dessine le widget pointé par SI
gui_draw_single_widget:
    pusha

    ; Chargement coords
    mov     ax, [si + widget.x]
    mov     bx, [si + widget.y]
    mov     cx, [si + widget.w]
    mov     dx, [si + widget.h]

    ; Calcul X2, Y2
    mov     di, ax
    add     di, cx
    mov     bp, bx
    add     bp, dx

    ; Dispatch selon état
    mov     al, [si + widget.state]
    cmp     al, GUI_STATE_PRESSED
    je      .paint_pressed
    cmp     al, GUI_STATE_HOVER
    je      .paint_hover

.paint_normal:
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 1   ; Blanc
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0   ; Bord Noir
    GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
    jmp     .text

.paint_hover:
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 1
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0
    ; Effet gras
    inc     ax
    inc     bx
    dec     di
    dec     bp
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0

    ; Restauration coords pour le texte
    mov     ax, [si + widget.x]
    mov     bx, [si + widget.y]
    jmp     .text_setup

.paint_pressed:
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 0   ; Noir
    GFX     TXT_MODE, GFX_TXT_WHITE_TRANSPARENT
    jmp     .text

.text_setup:
    ; Petit hack pour recentrer le texte après l'effet gras
    mov     cx, [si + widget.w]
    mov     dx, [si + widget.h]

.text:
    ; --- Centrage Texte (Simplifié) ---
    push    si
    mov     es, [si + widget.text_seg]
    mov     di, [si + widget.text_ofs]
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
    mov     ax, [si + widget.w]
    sub     ax, cx
    shr     ax, 1
    pop     bx      ; Récupère X original dans BX (oups, on veut ajouter)
    add     ax, bx  ; X final

    push    ax      ; X final prêt

    mov     bx, [si + widget.h]
    sub     bx, 8
    shr     bx, 1
    add     bx, [si + widget.y] ; Y final

    pop     cx      ; CX = X Final, BX = Y Final

    GFX     GOTOXY, cx, bx

    mov     dx, [si + widget.text_seg]
    mov     ax, [si + widget.text_ofs]
    GFX     WRITE, dx, ax

    pop     si
    popa
    ret



; =============================================================================
; Fonction : gui_draw_button
; Description : Dessine un bouton selon son état (.state)
; Entrée : SI = Pointeur vers la structure widget (DS:SI)
; =============================================================================
gui_draw_button:
    pusha

    ; Charger les propriétés depuis la structure
    mov     ax, [si + widget.x]
    mov     bx, [si + widget.y]
    mov     cx, [si + widget.w]
    mov     dx, [si + widget.h]

    ; Calculer X2 et Y2 pour le rectangle
    mov     di, ax      ; X1
    add     di, cx      ; X2 = X + W
    mov     bp, bx      ; Y1
    add     bp, dx      ; Y2 = Y + H

    ; Vérifier l'état
    cmp     byte [si + widget.state], GUI_STATE_PRESSED
    je      .draw_pressed

    cmp     byte [si + widget.state], GUI_STATE_HOVER
    je      .draw_hover

    cmp     byte [si + widget.state], GUI_STATE_DISABLED
    je      .draw_disabled

    .draw_normal:
    ; Fond BLANC, Bordure NOIRE, Texte NOIR
    ; 1. Effacer le fond (Rectangle plein blanc) -> On triche, on dessine un rect plein blanc
    ; Note: GFX RECTANGLE_FILL utilise une couleur 0 ou 1. 1 = Blanc.
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 1   ; Fond blanc
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0   ; Bordure noire

    ; Configuration texte : Noir sur Transparent
    GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
    jmp     .draw_text

    .draw_hover:
    ; Comme normal, mais bordure plus épaisse ou autre effet
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 1
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0

    ; Effet "Gras" sur le cadre (on dessine un 2eme rectangle à l'intérieur)
    inc     ax
    inc     bx
    dec     di
    dec     bp
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0

    ; Restaurer les coords pour le texte
    mov     ax, [si + widget.x]
    mov     bx, [si + widget.y]
    mov     di, ax
    add     di, [si + widget.w]

    GFX     TXT_MODE, GFX_TXT_BLACK_TRANSPARENT
    jmp     .draw_text

    .draw_pressed:
    ; Fond NOIR, Texte BLANC (Inversé)
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 0   ; Fond Noir
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 1   ; Bordure Blanche (optionnel)

    ; Configuration texte : Blanc sur Noir (ou transparent sur fond noir)
    GFX     TXT_MODE, GFX_TXT_WHITE_TRANSPARENT
    jmp     .draw_text

    .draw_disabled:
    ; Fond Blanc, Bordure en pointillé (difficile sans support pointillé),
    ; on va faire simple : Bordure noire, mais on n'écrit pas le texte ou texte gris ?
    ; Pour CGA mono, "Disabled" = Texte normal mais cadre incomplet ou hachuré.
    ; Faisons simple : Cadre normal, mais texte non affiché ou "..."
    GFX     RECTANGLE_FILL, ax, bx, di, bp, 1
    GFX     RECTANGLE_DRAW, ax, bx, di, bp, 0
    jmp     .done   ; Pas de texte pour montrer qu'il est désactivé

    .draw_text:
    ; --- Centrage du texte ---
    ; Calcul simple : PosX = BoutonX + (LargeurBouton - (LenChaine * 8)) / 2
    ; Calcul simple : PosY = BoutonY + (HauteurBouton - 8) / 2

    push    si
    ; 1. Calculer longueur chaine
    mov     es, [si + widget.text_seg]
    mov     di, [si + widget.text_ofs]
    xor     cx, cx

    .strlen:
    cmp     byte [es:di], 0
    je      .calc_pos
    inc     cx
    inc     di
    jmp     .strlen

    .calc_pos:
    ; CX = Longueur chaine
    shl     cx, 3           ; CX * 8 (largeur en pixels du texte)

    mov     ax, [si + widget.w]
    sub     ax, cx          ; Marge horizontale totale
    shr     ax, 1           ; Diviser par 2
    add     ax, [si + widget.x] ; X final

    mov     bx, [si + widget.h]
    sub     bx, 8           ; Hauteur fonte (8px)
    shr     bx, 1           ; Diviser par 2
    add     bx, [si + widget.y] ; Y final

    ; 2. Dessiner
    GFX     GOTOXY, ax, bx

    mov     dx, [si + widget.text_seg]
    mov     ax, [si + widget.text_ofs]
    GFX     WRITE, dx, ax

    pop     si

    .done:
    popa
    ret

; =============================================================================
; Fonction : gui_update_button
; Description : Met à jour l'état du bouton en fonction de la souris
; Entrée :
;   SI = Pointeur vers widget
;   CX = Mouse X
;   DX = Mouse Y
;   BL = Mouse Status (Bit 0 = Clic gauche)
; Sortie :
;   AL = 1 si le bouton vient d'être cliqué (Relâché), 0 sinon
; =============================================================================
gui_update_button:
    push    bx
    push    cx
    push    dx

    xor     ax, ax          ; AL = Return value (0)

    ; Si désactivé, on ne fait rien
    cmp     byte [si + widget.state], GUI_STATE_DISABLED
    je      .quit

    ; 1. Test de collision (Hit Test)
    ; X >= Widget.X ?
    cmp     cx, [si + widget.x]
    jl      .no_hit

    ; X <= Widget.X + Widget.W ?
    mov     di, [si + widget.x]
    add     di, [si + widget.w]
    cmp     cx, di
    jg      .no_hit

    ; Y >= Widget.Y ?
    cmp     dx, [si + widget.y]
    jl      .no_hit

    ; Y <= Widget.Y + Widget.H ?
    mov     di, [si + widget.y]
    add     di, [si + widget.h]
    cmp     dx, di
    jg      .no_hit

    ; --- HIT ! La souris est sur le bouton ---

    ; Test du clic (BL bit 0)
    test    bl, 1
    jz      .hovering

    ; -> Clic maintenu
    mov     byte [si + widget.state], GUI_STATE_PRESSED
    jmp     .draw_update

.hovering:
    ; Souris dessus, mais pas de clic
    ; Si on était en PRESSED juste avant, c'est un "CLICK" valide (Relâchement)
    cmp     byte [si + widget.state], GUI_STATE_PRESSED
    jne     .just_hover

    ; C'est un click valide !
    mov     al, 1           ; Return CLICKED
    mov     byte [si + widget.state], GUI_STATE_HOVER
    jmp     .draw_update

.just_hover:
    mov     byte [si + widget.state], GUI_STATE_HOVER
    jmp     .draw_update

.no_hit:
    ; Souris en dehors
    mov     byte [si + widget.state], GUI_STATE_NORMAL

.draw_update:
    ; Appelle la fonction de dessin pour mettre à jour le visuel
    call    gui_draw_button

.quit:
    pop     dx
    pop     cx
    pop     bx
    ret