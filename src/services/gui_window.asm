; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gui_window.asm
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

%macro GUI 1-*
    ; %1 est l'index de la fonction
    ; On itère sur les arguments suivants en sens inverse (Convention C)

    %rep %0 - 1       ; Répéter pour (Nombre d'args - 1)
        %rotate -1    ; Prend le dernier argument
        push %1       ; L'empile
    %endrep

    %rotate -1        ; On revient au premier argument (l'index de fonction)
    call word [cs:graph_driver + ((%1)*2)]

    ; Nettoyage de la pile (Convention CDECL: l'appelant nettoie)
    ; Chaque argument = 2 octets (1 word).
    add sp, (%0 - 1) * 2
%endmacro

; ------------------------------------------------------------
; TABLE DE SAUT (VECTEURS API)
; Cette table doit être située au début du driver pour être
; accessible par la GUI à des offsets fixes.
; ------------------------------------------------------------
%define	WINDOW		    0

; ------------------------------------------------------------
; COMMENTAIRE SUR LA MÉTHODE D'APPEL
;
; GFX FUNCTION, Arg1, Arg2, Arg3
;
; GFX GFX_PUTPIXEL, 320, 100, 1
;
; Si vous changez le code du driver, tant que la table au début
; ne change pas d'ordre, la GUI n'a pas besoin d'être recompilée.
; ------------------------------------------------------------

gui_driver:
    dw  draw_white

; =============================================================================
; Fonction : draw_window
; Description : Dessine une fenêtre style Mac System 1.0
; Entrées (Pile) :
;   Arg1 : X (Word)
;   Arg2 : Y (Word)
;   Arg3 : Largeur (Word)
;   Arg4 : Hauteur (Word)
;   Arg5 : Pointeur vers titre (DS:Offset) (Word)
; =============================================================================
draw_window:
    push    bp
    mov     bp, sp

    ; --- Arguments ---
    %define .x      word [bp+4]
    %define .y      word [bp+6]
    %define .w      word [bp+8]
    %define .h      word [bp+10]
    %define .title  word [bp+12]

    pusha

    ; Variables locales (registres)
    ; BX = x2, DX = y2

    ; ----------------------------------------------------
    ; Ombre Portée (Drop Shadow)
    ; ----------------------------------------------------
    ; On dessine un rectangle noir décalé de +1,+1
    ; x1+1, y1+1, x2+1, y2+1 -> NOIR
    mov     ax, .x
    add     ax, .w
    inc     ax          ; x2 + 1
    mov     bx, ax      ; BX = right limit

    mov     ax, .y
    add     ax, .h
    inc     ax          ; y2 + 1
    mov     dx, ax      ; DX = bottom limit

    mov     ax, .x
    inc     ax          ; x1 + 1
    mov     cx, .y
    inc     cx          ; y1 + 1

    ; Appel cga_fill_rect(x+1, y+1, x+w+1, y+h+1, BLACK)
    push    word 0      ; Couleur 0 (Noir) pour l'ombre
    push    dx          ; y2
    push    bx          ; x2
    push    cx          ; y1
    push    ax          ; x1
    call    cga_fill_rect
    add     sp, 10

    ; ----------------------------------------------------
    ; Corps de la Fenêtre (Main Body)
    ; ----------------------------------------------------
    ; On dessine un rectangle BLANC par dessus l'ombre
    ; Cela crée le corps et "découpe" l'ombre pour ne laisser que le bord visible.

    mov     bx, .x
    add     bx, .w      ; BX = x2
    mov     dx, .y
    add     dx, .h      ; DX = y2

    ; Remplissage Blanc (Corps)
    push    word 1      ; Couleur 1 (Blanc)
    push    dx
    push    bx
    push    word .y
    push    word .x
    call    cga_fill_rect
    add     sp, 10

    ; Contour Noir (Border)
    push    word 0      ; Couleur 0 (Noir)
    push    dx
    push    bx
    push    word .y
    push    word .x
    call    cga_draw_rect
    add     sp, 10

    ; ----------------------------------------------------
    ; Barre de Titre (Title Bar)
    ; ----------------------------------------------------
    ; Hauteur standard ~18 pixels
    %define TITLE_HEIGHT 18

    ; Dessiner la ligne de séparation sous le titre
    mov     cx, .y
    add     cx, TITLE_HEIGHT

    push    word 0      ; Couleur Noir
    push    cx          ; Y de la ligne
    push    bx          ; X2 (largeur fenêtre)
    push    word .x     ; X1
    call    cga_line_horizontal
    add     sp, 8

    ; --- Pinstripes (Lignes horizontales) ---
    ; On dessine une ligne noire une ligne sur deux à l'intérieur du titre
    ; De y+1 à y+17, step 2

    mov     si, .y
    inc     si          ; Commence à y+1
    inc     si          ; Premier trait noir à y+2 (laissons 1px blanc sous le cadre haut)

    mov     di, .y
    add     di, TITLE_HEIGHT
    dec     di          ; Fin juste avant la ligne de séparation

    .pinstripe_loop:
    cmp     si, di
    jae     .pinstripe_done

    push    word 0      ; Noir
    push    si          ; Y courant
    push    bx          ; X2
    push    word .x     ; X1
    call    cga_line_horizontal
    add     sp, 8

    add     si, 2       ; Sauter 2 pixels (1 blanc, 1 noir)
    jmp     .pinstripe_loop
    .pinstripe_done:

    ; ----------------------------------------------------
    ; Le Carré de Fermeture (Close Box)
    ; ----------------------------------------------------
    ; Petit carré blanc à gauche avec contour noir
    ; Position: x+6, y+4, taille 9x9 (exemple)

    mov     cx, .x
    add     cx, 6       ; Box X1
    mov     dx, .y
    add     dx, 4       ; Box Y1

    mov     si, cx
    add     si, 9       ; Box X2
    mov     di, dx
    add     di, 9       ; Box Y2

    ; Remplir en blanc (pour effacer les pinstripes)
    push    word 1
    push    di
    push    si
    push    dx
    push    cx
    call    cga_fill_rect
    add     sp, 10

    ; Contour noir
    push    word 0
    push    di
    push    si
    push    dx
    push    cx
    call    cga_draw_rect
    add     sp, 10

    ; ----------------------------------------------------
    ; Le Titre (Texte)
    ; ----------------------------------------------------
    ; Il faut centrer le texte et effacer les lignes derrière lui.

    ; a) Calculer la longueur du titre
    mov     si, .title
    xor     cx, cx      ; CX = longueur
    .strlen:
    lodsb
    test    al, al
    jz      .calc_center
    inc     cx
    jmp     .strlen

    .calc_center:
    ; b) Calcul X Centré = X_win + (W_win/2) - (Len * 8 / 2)
    mov     ax, .w
    shr     ax, 1       ; W / 2
    add     ax, .x      ; Centre de la fenêtre

    mov     bx, cx      ; Sauver Len
    shl     cx, 2       ; Len * 4 (car Len * 8 / 2 = Len * 4)
    sub     ax, cx      ; AX = X de départ du texte

    ; c) Effacer la zone derrière le texte (Remplir Blanc)
    ; On ajoute un padding de 4px autour du texte
    mov     cx, ax      ; Text X start
    sub     cx, 4       ; Padding gauche (Rect X1)

    mov     dx, .y
    add     dx, 2       ; Rect Y1 (juste sous le cadre haut)

    push    bx          ; Sauve longueur char pour plus tard

    ; Calcul Rect X2 = Text X + (Len * 8) + 4
    mov     si, ax      ; Start Text
    mov     ax, bx      ; Len
    shl     ax, 3       ; Len * 8 (largeur pixel texte)
    add     si, ax
    add     si, 4       ; Padding droite (Rect X2)

    mov     di, .y
    add     di, TITLE_HEIGHT
    dec     di          ; Rect Y2 (juste au dessus ligne séparation)

    ; Dessiner le rectangle blanc de masquage
    push    word 1      ; Blanc
    push    di          ; Y2
    push    si          ; X2
    push    dx          ; Y1
    push    cx          ; X1
    call    cga_fill_rect
    add     sp, 10

    pop     bx          ; Récupérer longueur

    ; d) Écrire le texte
    ; Recalculer position X exacte (CX avait X1 du rect, on veut X1 + 4)
    add     cx, 4

    ; GFX GOTOXY (X, Y) -> Y centré dans la barre de titre
    ; Centre barre ~9px. Font 8px. Y = Win_Y + 5
    mov     dx, .y
    add     dx, 5

    ; Note: GFX GOTOXY utilise des arguments pile, attention à l'ordre API
    ; On suppose que vous utilisez votre macro GFX ou appel direct

    ; GFX GOTOXY, cx, dx
    push    dx          ; Y
    push    cx          ; X
    push    word 3      ; ID GOTOXY
    call    cga_set_charpos ; Appel direct driver ou via vecteur
    add     sp, 6

    ; Mode texte Noir sur Blanc (ou Transparent, car on a mis un fond blanc)
    ; GFX TXT_MODE, GFX_TXT_BLACK
    push    word 3      ; GFX_TXT_BLACK_ON_WHITE (ou transparent)
    push    word 4      ; ID TXT_MODE
    call    cga_set_writemode
    add     sp, 4

    ; GFX WRITE, cs, title
    push    word .title ; Offset
    push    ds          ; Segment (supposé DS, sinon passer le seg en arg)
    push    word 6      ; ID WRITE
    call    cga_write
    add     sp, 6

    popa
    leave
    ret