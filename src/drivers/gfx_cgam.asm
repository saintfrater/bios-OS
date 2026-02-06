; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gfx_cgam.asm
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
; graphics drivers pour carte video/mode CGA-Mono (640x200x2)
;
%define VIDEO_SEG    	0xB800        	; ou 0xB000

%define GFX_MODE		0x06			; MCGA HiRes (B/W)
%define GFX_WIDTH		640
%define GFX_HEIGHT		200

%define CGA_STRIDE      80
%define CGA_ODD_BANK    0x2000

;
; bit : descr
;  0  : text color : 0=black, 1=white
;  1  : transparent : 1=apply background attribut
;
%define GFX_TXT_WHITE_TRANSPARENT   00000000b
%define GFX_TXT_BLACK_TRANSPARENT   00000001b
%define GFX_TXT_WHITE               00000010b
%define GFX_TXT_BLACK               00000011b

%macro GFX 1-*
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
%define	INIT		    0
%define PUTPIXEL	    1
%define GETPIXEL 	    2
%define GOTOXY		    3
%define TXT_MODE        4
%define PUTCH           5
%define WRITE           6
%define LINE            7
%define RECTANGLE       8
%define RECTANGLE_FILL  9
%define RECTANGLE_ROUND 10
%define MOUSE_HIDE      11
%define MOUSE_SHOW      12
%define MOUSE_MOVE      13

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
align   2
graph_driver:
    dw cga_init                 ; init de la carte graphique
    dw cga_putpixel             ; dessin d'un pixel
    dw cga_getpixel             ; lecture d'un pixel
    dw cga_set_charpos          ; gotoxy
    dw cga_set_writemode        ; mode texte
    dw cga_putc                 ; dessin d'un caractère
    dw cga_write                ; dessin d'une chaine de caractère
    dw cga_line                 ; dessin d'une ligne (Bresenham) avec décision horizontale/verticale
    dw cga_draw_rect            ; dessin d'un rectangle
    dw cga_fill_rect            ; dessin d'un rectangle plein
    dw cga_draw_rounded_frame   ; dessin d'un rectangle arrondi
    dw cga_mouse_hide           ; déplacement du curseur
    dw cga_mouse_show           ; déplacement du curseur
 	dw cga_mouse_cursor_move    ; déplacement du curseur


; =============================================================================
;  SECTION : PATTERNS & FILL
; https://paulsmith.github.io/classic-mac-patterns/
; =============================================================================
;
; pattern ID
%define PATTERN_BLACK               0
%define PATTERN_GRAY_DARK           1
%define PATTERN_GRAY_MID            2
%define PATTERN_GRAY_LIGHT          3
%define PATTERN_WHITE_LIGHT         4
%define PATTERN_WHITE               5

align   8
pattern_8x8:
    dq 0x0000000000000000               ; pattern_black (Tout à 0 = Noir)
    dq 0x2200880022008800               ; pattern_gray_dark (Majorité de 0)
    dq 0x2288228822882288               ; pattern_gray_mid
    dq 0xAA55AA55AA55AA55               ; pattern_gray_light (50/50)
    dq 0x77DD77DD77DD77DD               ; pattern_white_light (Majorité de 1 = Clair)
    dq 0xFFFFFFFFFFFFFFFF               ; pattern_white (Tout à 1 = Blanc)

; ------------------------------------------------------------
; initialise le mode graphique (via l'int 10h)
;
; ce mode est entrelacé, un bit/pixel, 8 pixels par octet
; ------------------------------------------------------------
cga_init:
    mov     ax, BDA_DATA_SEG
    mov     ds, ax

	; init graphics mode
	mov 	ah, 0x00     	                		; AH=00h set video mode
	mov		al, GFX_MODE
	int 	0x10

    ; mov     byte [BDA_GFX + gfx.cur_mode], 1
	; dessine un background "check-board"
	call	cga_background
	ret

; dummy functions
cga_none:
    ret

; ------------------------------------------------------------
; Calcule DI + AH=mask pour (CX=x, DX=y) en mode CGA 640x200
;
; Out: ES=VIDEO_SEG, DI=offset, AH=bitmask (0x80 >> (x&7))
; ------------------------------------------------------------
cga_calc_addr:
	; calcul de l'offset 'y':
	; si y est impaire, DI+=0x2000
	; DI = (y>>1)*80 + (x>>3) + (y&1)*0x2000
	mov	    ax, dx
	shr 	ax, 1              ; ax = y/2
	mov     di, ax
	shl  	di, 4              ; (y/2)*16
	shl     ax, 6              ; (y/2)*64
	add     di, ax             ; *80

	mov     ax, cx
	shr     ax, 3              ; x / 3
	add     di, ax             ; di = offset banque paire

    mov     bx, dx
    and     bx, 1              ; BX = 0 ou 1
    neg     bx                 ; BX = 0 ou 0xFFFF (-1)
    and     bx, 0x2000         ; BX = 0 ou 0x2000 (CGA_ODD_BANK)
    add     di, bx             ; Application de l'offset

    ; calcul du masque du pixel
    and     cl, 7
    mov     ah, 0x80
    shr     ah, cl
	ret


; ---------------------------------------------------------------------------
; gfx_set_writemode (mode)
;  Défini le mode d'écriture :
;
; bit : descr
;  0  : text color : 0=black, 1=white
;  1  : transparent : 1=apply background attribut
;
; si le mode n'est pas transparent, la couleur de fond
; est l'inverse de la couleur du texte
; ---------------------------------------------------------------------------
cga_set_writemode:
    push    bp
    mov     bp, sp

    ; --- Définition des arguments ---
    %define .mode   word [bp+4]

    push    fs
    push    ax
    mov     ax, BDA_DATA_SEG
    mov     fs,ax

    mov     ax, .mode

    mov     byte [fs:BDA_GFX + gfx.cur_mode], al

    pop     ax
    pop     fs
    leave
    ret

; ---------------------------------------------------------------------------
; gfx_set_charpos (x,y)
; In : CX = x (pixels), DX = y (pixels)
; Out: variables DS:GFX_CUR_*
; Notes:
;  - calcule l'offset VRAM de la scanline y: base = (y&1?2000:0) + (y>>1)*80 + (x>>3)
;  - stocke aussi shift = x&7
; ---------------------------------------------------------------------------
cga_set_charpos:
    push    bp
    mov     bp, sp

    ; --- Définition des arguments ---
    %define .x     word [bp+4]
    %define .y     word [bp+6]

    pusha
    push    fs

    mov     ax,BDA_DATA_SEG
    mov     fs,ax

    ; store x,y en pixel
    mov     cx, .x
    mov     dx, .y

    mov     [fs:BDA_GFX + gfx.cur_x], cx
    mov     [fs:BDA_GFX + gfx.cur_y], dx

    mov     ax, cx
    and     ax, 0x07
    mov     [fs:BDA_GFX + gfx.cur_shift], al

    ; calcul de l'offset de la position 'x,y':
    ; si 'y' est paire, DI < 0x2000 & add = 0x2000
    ; si 'y' est impaire, DI> 0x2000 & add = -0x2000
    ; DI = (y>>1)*80 + (x>>3) + (y&1)*
    mov     ax, dx
    shr     ax, 1
    mov     bx, ax                          ; bx = dx>>1
    shl     bx, 4                           ; bx = bx * 16
    shl     ax, 6                           ; ax = ax * 64
    add     bx, ax
    mov     ax, cx
    shr     ax, 3                           ; ax = x/8
    add     bx, ax
    mov     ax, CGA_ODD_BANK

    test    dl, 1
    jz      .even
    add     bx, ax
    neg     ax
    add     ax, CGA_STRIDE
    .even:
    mov     [fs:BDA_GFX + gfx.cur_line_ofs], ax
    mov     [fs:BDA_GFX + gfx.cur_offset], bx

    pop     fs

    ; clean defs
    %undef  .x
    %undef  .y
    popa
    leave
    ret

; ---------------------------------------------------------------------------
; get_glyph_offset
; In : AL = char (ASCII)
; Out: CS:SI -> 8 bytes
; ---------------------------------------------------------------------------
get_glyph_offset:
    cmp     al, 0x20
    jb      .qmark              ; al < 20h (' '
    cmp     al, 0x7E
    ja      .qmark              ; al > 7Eh ('~')
    sub     al, 0x20
    jmp     .ok

    .qmark:
    mov     al, '?'
    sub     al, 0x20

    .ok:
    xor     ah, ah
    mov     si, ax
    shl     si, 3
    add     si, font8x8
    ret

; ---------------------------------------------------------------------------
; cga_putc_unalign (car)
;   - x non aligné (x&7 != 0)
;   - écrit sur 2 bytes (di et di+1) dans chaque banque
; ---------------------------------------------------------------------------
; convert al -> AX aligned with "cl"
%macro ALIGN_BYTE 0
        mov     ah,al
        xor     al,al
        shr     ax,cl
        xchg    ah,al
%endmacro

cga_putc:
    push    bp
    mov     bp, sp
    sub     sp, 2               ; 1 word variable locale

    ; --- Définition des arguments ---
    %define .car    word [bp+4]

    ; --- Définition des variables locales ---
    %define .cpt    word [bp-2]

    pusha
    push    fs
    push    es

    call    cga_mouse_hide      ; Protection souris

    mov     bx, VIDEO_SEG
    mov     es, bx
    mov     bx, BDA_DATA_SEG
    mov     fs, bx

    mov     ax, .car

    call    get_glyph_offset

    ; Base offset VRAM pour la scanline Y
    mov     di, [fs:BDA_GFX + gfx.cur_offset]
    mov     bx, [fs:BDA_GFX + gfx.cur_line_ofs]
    mov     ch, [fs:BDA_GFX + gfx.cur_mode]
    mov     cl, [fs:BDA_GFX + gfx.cur_shift]

    mov     .cpt, 4

    .row_loop:
    ; gestion du fond de texte
    test    ch, 00000010b               ; transparent background ?
    jz      .skip_attribut              ; oui

    test    ch, 00000001b               ; background blanc ?
    je      .bkg_black

    ; background = white
    mov     ax, 0xFF00
    shr     ax, cl
    xchg    al, ah
    or      [es:di], ax
    or      [es:di+bx], ax
    jmp     .skip_attribut

    .bkg_black:                        ; OK
    ; background = black
    mov     ax, 0xFF00
    shr     ax, cl
    xchg    al, ah
    not     ax
    and     [es:di], ax
    and     [es:di+bx], ax

    .skip_attribut:
    ; ligne "paire" du gylphe
    xor     ax, ax
    mov     al, [cs:si]
    inc     si
    ALIGN_BYTE
    mov     dx,ax

    ; ligne "impaire" du gylphe
    mov     al, [cs:si]
    inc     si
    ALIGN_BYTE
    xchg    ax, dx

    test   ch,00000001b
    jz     .black_text

    ; white text
    not      ax
    not      dx
    and      [es:di], ax
    and      [es:di+bx], dx

    jmp     .next

    .black_text:
    or      [es:di], ax
    or      [es:di+bx], dx

    .next:
    add     di,CGA_STRIDE

    dec     .cpt
    jnz     .row_loop

    ; Avancer curseur d'un caractère (8 pixels)
    inc     word [fs:BDA_GFX + gfx.cur_offset]
    add     word [fs:BDA_GFX + gfx.cur_x], 8

    call    cga_mouse_show      ; Restauration souris

    pop     es
    pop     fs
    popa
    leave
    ret

;
; write string from [DS:SI] to screen
;
; --- Définition des arguments ---
%define .txt_seg   word [bp+4]
%define .txt_ofs   word [bp+6]
cga_write:
    push    bp
    mov     bp, sp
    push    ax
    push    ds

    mov     ax, .txt_seg
    mov     ds, ax
    mov     si, .txt_ofs

    .loops:
    lodsb
    cmp     al,0
    je      .done
    push    ax
    call    cga_putc
    jmp     .loops

    .done:
    pop     ds
    pop     ax
    leave
    ret
%undef  .txt_seg
%undef  .txt_ofs

; ------------------------------------------------------------
; cga_putpixel (x,y,color)
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   ES = Target Segment (usually VIDEO_SEG)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
; --- Définition des arguments ---
%define .x      word [bp+4]
%define .y      word [bp+6]
%define .color  byte [bp+8]
cga_putpixel:
    push    bp
    mov     bp, sp
    pusha

    mov     ax, VIDEO_SEG
    mov     es, ax

    call    cga_mouse_hide      ; Protection souris
    mov     cx, .x
    mov     dx, .y
    call    cga_calc_addr

	; write
	cmp     .color, 0
	je    	.clear

    .set:
	or      byte [es:di], ah
	jmp     .done

    .clear:
	not     ah
	and     byte [es:di], ah

    .done:
    call    cga_mouse_show      ; Restauration souris
    popa
    leave
	ret
; clean defs
%undef  .x
%undef  .y
%undef  .color

; ------------------------------------------------------------
; cga_getpixel (x,y)
; Lit un pixel, accès VRAM direct.
;
; Out: AL=0/1
; ------------------------------------------------------------
cga_getpixel:
    push    bp
    mov     bp, sp

        ; --- Définition des arguments ---
    %define .x      word [bp+4]
    %define .y      word [bp+6]

	push   	di
	push   	es

    mov     cx, .x
    mov     dx, .y

    mov     ax, VIDEO_SEG
    mov     es, ax
	call    cga_calc_addr

	mov     al, [es:di]
	and     al, ah
	setnz   al

	pop     es
	pop     di

    ; clean defs
    %undef  .x
    %undef  .y
    leave
	ret

; ------------------------------------------------------------
; Dessine un background "check-board", accès VRAM direct.
;
; ------------------------------------------------------------
cga_background:
	mov		ax,VIDEO_SEG
	mov		es,ax
	mov		di,0x0000
	mov		eax,0xaaaaaaaa
	mov		cx,0x800
	rep		stosd
	mov		di,0x2000
	mov		eax,0x55555555
	mov		cx,0x800			; 640/8/4
	rep		stosd
	ret

; ------------------------------------------------------------
; cga_line_vertical (x, y0, y1, color)
;
; Dessine une ligne x, y0, y1, color
; ------------------------------------------------------------
%define .x      word [bp+4]
%define .y1     word [bp+6]
%define .y2     word [bp+8]
%define .color  byte [bp+10]
cga_line_vertical:
    push    bp
    mov     bp, sp
    pusha
    push    es

    ; Setup ES = Video Segment
    mov     ax, VIDEO_SEG       ; Utiliser AX plutot que SI pour setup ES
    mov     es, ax

    call    cga_mouse_hide

    mov     bx, .y1
    mov     dx, .y2

    ; 1. Ordonner Y (BX = Debut, DX = Fin)
    cmp     bx, dx
    jle     .y_sorted
    xchg    bx, dx
    .y_sorted:

    ; 2. Calculer la hauteur MAINTENANT (avant que DX/BX ne soient modifiés)
    sub     dx, bx              ; DX = Hauteur - 1
    inc     dx                  ; DX = Hauteur en pixels
    push    dx                  ; Sauvegarde de la hauteur (compteur) sur la pile [1]

    ; 3. Calculer l'adresse de départ
    mov     cx, .x              ; CX = X
    mov     dx, bx              ; DX = Y_Start (Argument pour cga_calc_addr)
    call    cga_calc_addr       ; DI = Offset, AH = Masque Bit

    ; 4. Préparer les registres pour la boucle
    mov     al, ah              ; AL = Masque
    not     al                  ; AL = ~Masque (pour effacer/noir)

    ; Charger la couleur (CORRECTION BUG COULEUR)
    mov     cl, .color          ; On charge la couleur dans CL maintenant

    ; Récupérer le compteur de hauteur
    pop     dx                  ; DX = Hauteur restaurée [1]

    .v_loop:
    cmp     cl, 0               ; Test de la couleur (CL)
    jz      .draw_black

    .draw_white:
    or      byte [es:di], ah    ; Allumer le bit (AH)
    jmp     .next_line

    .draw_black:
    and     byte [es:di], al    ; Eteindre le bit (AL)

    .next_line:
    ; --- Logique Next Line CGA ---
    xor     di, 0x2000          ; Bascule banque 0 <-> 1
    test    di, 0x2000          ; Si on est passé à la banque 1 (0x2000)
    jnz     .skip_add           ; On a visuellement descendu d'une ligne, c'est bon.
    add     di, 80              ; Si on revient banque 0, il faut avancer de 80 octets.
    .skip_add:

    dec     dx                  ; Décrémenter le compteur de hauteur
    jnz     .v_loop

    call    cga_mouse_show

    pop     es
    popa
    leave                       ; Leave gère le 'mov sp, bp / pop bp'
    ret
; clean defs
%undef  .x
%undef  .y1
%undef  .y2
%undef  .color
; ------------------------------------------------------------
; cga_line_horizontal
; Dessine une ligne horizontale de (x1, y) à (x2, y)
; ------------------------------------------------------------
; --- Définition des arguments ---
%define .x1     word [bp+4]
%define .x2     word [bp+6]
%define .y      word [bp+8]
%define .color  byte [bp+10]
cga_line_horizontal:
    push    bp
    mov     bp, sp
    pusha
    push    es

    ; Setup ES = Video Segment
    mov     ax, VIDEO_SEG
    mov     es, ax

    call    cga_mouse_hide

    mov     ax, .x1
    mov     bx, .x2

    ; 1. Ordonner X (AX = Gauche, BX = Droite)
    cmp     ax, bx
    jle     .x_sorted
    xchg    ax, bx
    .x_sorted:

    ; 2. Calculer l'adresse de départ
    mov     cx, ax          ; CX = X_Start pour cga_calc_addr
    mov     dx, .y          ; DX = Y

    push    bx              ; Sauve X_End
    push    ax              ; <--- AJOUT CRITIQUE : Sauve X_Start (AX)
    call    cga_calc_addr   ; DI = Offset VRAM (AX est détruit ici !)
    pop     ax              ; <--- RESTAURATION : On récupère le bon X1
    pop     bx              ; Restaure X_End

    ; 3. Préparer la couleur
    mov     dl, .color      ; DL = Couleur

    ; --- ANALYSE DES OCTETS ---
    mov     si, ax
    shr     si, 3           ; SI = Index octet start (Calcul correct maintenant)

    mov     cx, bx
    shr     cx, 3           ; CX = Index octet end

    ; Cas spécial : Tout dans le même octet ?
    cmp     si, cx
    je      .single_byte

    ; ============================================
    ; CAS MULTI-BYTE (Gauche -> Milieu -> Droite)
    ; ============================================

    ; --- A. PARTIE GAUCHE (Start) ---
    push    cx              ; Sauve Index End
    mov     cx, ax
    and     cx, 7           ; CL = X1 % 8
    mov     dh, 0xFF
    shr     dh, cl          ; DH = Masque Gauche

    call    .apply_mask     ; Applique DH sur [ES:DI]

    inc     di              ; Octet suivant
    inc     si              ; Index suivant
    pop     cx              ; Restaure Index End

    ; --- B. PARTIE CENTRALE (Full Bytes) ---
    cmp     si, cx
    jge     .do_right_part

    mov     al, 0x00        ; Noir
    cmp     dl, 0
    jz      .fill_loop
    mov     al, 0xFF        ; Blanc

    .fill_loop:
    mov     byte [es:di], al
    inc     di
    inc     si
    cmp     si, cx
    jl      .fill_loop

    .do_right_part:
    ; --- C. PARTIE DROITE (End) ---
    mov     cx, bx
    and     cx, 7
    inc     cx
    mov     dh, 0xFF
    shr     dh, cl
    not     dh              ; DH = Masque Droite

    call    .apply_mask
    jmp     .done

    ; ============================================
    ; CAS SINGLE BYTE
    ; ============================================
    .single_byte:
    ; Masque Gauche
    mov     cx, ax
    and     cx, 7
    mov     dh, 0xFF
    shr     dh, cl

    ; Masque Droite
    mov     cx, bx
    and     cx, 7
    inc     cx
    mov     ah, 0xFF
    shr     ah, cl
    not     ah

    ; Intersection
    and     dh, ah
    call    .apply_mask
    jmp     .done

    ; --- Helper local ---
    .apply_mask:
    cmp     dl, 0
    jz      .apply_black
    or      byte [es:di], dh
    ret
    .apply_black:
    not     dh
    and     byte [es:di], dh
    not     dh
    ret

    .done:
    call    cga_mouse_show
    pop     es
    popa
    leave
    ret
; clean defs
%undef  .x1
%undef  .x2
%undef  .y

; ------------------------------------------------------------
; cga_line (x1, y1, x2, y2, color)
; Algorithme de Bresenham pour tracer une ligne arbitraire
; ------------------------------------------------------------
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .color  byte [bp+12]

cga_line:
    push    bp
    mov     bp, sp
    pusha                   ; Sauvegarde de tous les registres (AX, BX, CX, DX, SI, DI)
    push    es              ; Sauvegarde ES

    ; --- Optimisation : Lignes H/V ---
    mov     ax, .y1
    cmp     ax, .y2
    je      .do_horiz
    mov     ax, .x1
    cmp     ax, .x2
    je      .do_vert

    ; --- Bresenham ---
    mov     ax, VIDEO_SEG
    mov     es, ax

    call    cga_mouse_hide

    sub     sp, 10          ; Variables locales: dx, dy, sx, sy, err

    ; --- Definitions locales ---
    ; BP pointe sur l'ancien BP.
    ; PUSHA (16 octets) + PUSH ES (2 octets) = 18 octets
    ; Les variables locales commencent donc à BP-18
    %define .dx     word [bp-20]
    %define .dy     word [bp-22]
    %define .sx     word [bp-24]
    %define .sy     word [bp-26]
    %define .err    word [bp-28]

    ; --- Initialisation Bresenham ---
    ; dx = abs(x2 - x1), sx = sign(x2 - x1)
    mov     ax, .x2
    sub     ax, .x1
    mov     bx, 1           ; sx = 1
    jge     .calc_dx
    neg     ax
    neg     bx              ; sx = -1
.calc_dx:
    mov     .dx, ax      ; save dx
    mov     .sx, bx      ; save sx

    ; dy = abs(y2 - y1), sy = sign(y2 - y1)
    mov     ax, .y2
    sub     ax, .y1
    mov     bx, 1           ; sy = 1
    jge     .calc_dy
    neg     ax
    neg     bx              ; sy = -1
.calc_dy:
    mov     .dy, ax      ; save dy
    mov     .sy, bx      ; save sy

    ; err = dx - dy
    mov     ax, .dx      ; dx
    sub     ax, .dy      ; dy
    mov     .err, ax     ; err

    ; Coordonnées courantes
    mov     cx, .x1
    mov     dx, .y1

.loop:
    ; Plot pixel (CX, DX)
    push    cx
    push    dx
    call    cga_calc_addr   ; Out: DI=offset, AH=mask

    mov     bl, .color
    cmp     bl, 0
    je      .plot_black
    or      byte [es:di], ah
    jmp     .plot_next
.plot_black:
    not     ah
    and     byte [es:di], ah
.plot_next:
    pop     dx
    pop     cx

    ; Check fin
    cmp     cx, .x2
    jne     .step
    cmp     dx, .y2
    je      .done

.step:
    mov     ax, .err     ; e2 = err
    shl     ax, 1           ; e2 = 2*err

    mov     bx, .dy      ; dy
    neg     bx              ; -dy
    cmp     ax, bx
    jle     .check_y

    add     .err, bx     ; err += -dy
    add     cx, .sx      ; x += sx

.check_y:
    mov     bx, .dx      ; dx
    cmp     ax, bx
    jge     .loop           ; if e2 >= dx, skip y step

    add     .err, bx     ; err += dx
    add     dx, .sy      ; y += sy
    jmp     .loop

.done:
    call    cga_mouse_show
    add     sp, 10          ; Libération variables locales
    jmp     .exit

.do_horiz:
    push    word [bp+12]    ; color
    push    word [bp+6]     ; y
    push    word [bp+8]     ; x2
    push    word [bp+4]     ; x1
    call    cga_line_horizontal
    add     sp, 8
    jmp     .exit

.do_vert:
    push    word [bp+12]    ; color
    push    word [bp+10]    ; y2
    push    word [bp+6]     ; y1
    push    word [bp+4]     ; x
    call    cga_line_vertical
    add     sp, 8

.exit:
    pop     es
    popa
    pop     bp
    ret

%undef .x1
%undef .y1
%undef .x2
%undef .y2
%undef .color
%undef .dx
%undef .dy
%undef .sx
%undef .sy
%undef .err

; ------------------------------------------------------------
; cga_draw_rect
; Dessine un rectangle vide (contour)
; Entrée : x1, y1, x2, y2, color
; ------------------------------------------------------------
; Arguments
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .color  word [bp+12] ; word pour l'alignement pile (mais on utilise byte)
cga_draw_rect:
    push    bp
    mov     bp, sp
    pusha

    ; 1. Ordonner X (x1 < x2)
    mov     ax, .x1
    mov     bx, .x2
    cmp     ax, bx
    jle     .x_ok
    xchg    ax, bx
    mov     .x1, ax
    mov     .x2, bx
    .x_ok:

    ; 2. Ordonner Y (y1 < y2)
    mov     ax, .y1
    mov     bx, .y2
    cmp     ax, bx
    jle     .y_ok
    xchg    ax, bx
    mov     .y1, ax
    mov     .y2, bx
    .y_ok:

    call    cga_mouse_hide

    ; 3. Dessiner les 4 lignes
    ; Pour éviter les pixels en double dans les coins, on peut ajuster légèrement,
    ; mais pour un driver simple, tracer les 4 lignes brutes est acceptable.

    GFX     LINE, .x1, .y1, .x2, .y1, .color
    GFX     LINE, .x1, .y2, .x2, .y2, .color

    GFX     LINE, .x1, .y1, .x1, .y2, .color
    GFX     LINE, .x2, .y1, .x2, .y2, .color

    call    cga_mouse_show
    popa
    leave
    ret
; clean defs
%undef  .x1
%undef  .y1
%undef  .x2
%undef  .y2
%undef  .color

; ------------------------------------------------------------
; cga_fill_rect
; Dessine un rectangle plein
; Entrée : x1, y1, x2, y2, pattern_offset (CS:Offset)
; ------------------------------------------------------------
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .pat_id word [bp+12]

; Variable locale pour l'index du motif (y % 8)
%define .pat_idx        word [bp-2]
%define .x_end_idx      word [bp-4]
%define .pattern_offset word [bp-6]

cga_fill_rect:
    push    bp
    mov     bp, sp
    sub     sp, 6           ; Reserve espace pour .pat_idx et .x_end_idx
    pusha
    push    es

    mov     ax, VIDEO_SEG
    mov     es, ax

    ; calcul de l'offset de départ du pattern
    mov     ax, .pat_id
    shl     ax, 3                           ; * 8
    add     ax, pattern_8x8
    mov     .pattern_offset, ax

    call    cga_mouse_hide

    ; --- 1. Tri des coordonnées (X et Y) ---
    ; Tri X
    mov     ax, .x1
    mov     bx, .x2
    cmp     ax, bx
    jle     .x_sorted
    xchg    ax, bx
    mov     .x1, ax
    mov     .x2, bx
    .x_sorted:

    ; Tri Y
    mov     ax, .y1
    mov     bx, .y2
    cmp     ax, bx
    jle     .y_sorted
    xchg    ax, bx
    mov     .y1, ax
    mov     .y2, bx
    .y_sorted:

    ; --- Init Pattern Index ---
    mov     ax, .y1
    and     ax, 7
    mov     .pat_idx, ax

    ; --- 2. Calcul de la hauteur ---
    mov     bx, .y2
    sub     bx, .y1
    inc     bx              ; BX = Hauteur finale
    push    bx              ; SAUVEGARDER LA HAUTEUR SUR LA PILE [STACK A]
                            ; (Car on va utiliser BX dans cga_calc_addr ou juste après)

    ; --- 3. Calcul adresse de départ ---
    mov     cx, .x1
    mov     dx, .y1


    ; Note: cga_calc_addr attend CX=x, DX=y et retourne DI
    ; Si cga_calc_addr modifie BX, la sauvegarde [STACK A] est vitale.
    call    cga_calc_addr   ; DI = Offset début ligne

    ; --- 4. Préparer les masques ---
    ; Masque Gauche (DH)
    mov     cx, .x1
    and     cx, 7
    mov     dh, 0xFF
    shr     dh, cl

    ; Masque Droite (AH)
    mov     cx, .x2
    and     cx, 7
    inc     cx
    mov     ah, 0xFF
    shr     ah, cl
    not     ah

    ; Index octets
    mov     si, .x1
    shr     si, 3           ; SI = Index start byte
    mov     cx, .x2
    shr     cx, 3           ; CX = Index end byte
    mov     .x_end_idx, cx  ; Sauvegarde de l'index de fin pour la boucle horizontale

    ; --- 5. Récupérer la hauteur dans un registre sûr ---
    pop     bx              ; RESTAURER HAUTEUR DANS BX [STACK A]
                            ; BX est maintenant notre compteur de boucle.
    ; --- BOUCLE VERTICALE ---
    .row_loop:
        push    di          ; Sauve début ligne
        push    si          ; Sauve index byte

        ; --- Récupérer le byte du motif pour cette ligne ---
        push    bx
        mov     bx, .pat_idx
        push    si
        mov     si, .pattern_offset
        mov     dl, [cs:si + bx]    ; DL = Pattern Byte
        pop     si
        pop     bx

        ; --- Remplissage Horizontal ---
        mov     cx, .x_end_idx  ; Restaurer l'index de fin pour la ligne

        ; Cas Single Byte (Start == End)
        cmp     si, cx
        je      .single_byte_row

        ; Partie Gauche
        mov     al, dh
        call    .apply_mask_fill
        inc     di
        inc     si

        ; Partie Centrale (Boucle tant que SI < CX)
        jmp     .check_mid
        .mid_loop:
            mov     byte [es:di], dl
            inc     di
            inc     si
        .check_mid:
            cmp     si, cx
            jl      .mid_loop

        ; Partie Droite
        mov     al, ah
        call    .apply_mask_fill
        jmp     .row_done

        .single_byte_row:
        mov     al, dh
        and     al, ah      ; Intersection des masques
        call    .apply_mask_fill

        .row_done:
        pop     si
        pop     di

        ; Incrémenter index motif pour la prochaine ligne
        inc     word .pat_idx
        and     word .pat_idx, 7

        ; --- Passage ligne suivante (CGA Bank Switch) ---
        xor     di, 0x2000
        test    di, 0x2000
        jnz     .bank_switch_ok
        add     di, 80
        .bank_switch_ok:

        dec     bx          ; On décrémente BX (Hauteur) au lieu de BP
        jnz     .row_loop

    call    cga_mouse_show
    pop     es

    popa
    leave
    ret

    ; helper
    .apply_mask_fill:
    push    ax
    not     al
    and     byte [es:di], al
    pop     ax
    and     al, dl              ; Motif masqué
    or      byte [es:di], al    ; Applique
    ret
; Nettoyage des defines
%undef  .x1
%undef  .y1
%undef  .x2
%undef  .y2
%undef  .pat_idx

; ------------------------------------------------------------
; cga_draw_rounded_frame
; dessiner un cadre arrondi
; Entrée : AX=x1, BX=y1, CX=x2, DX=y2
; ------------------------------------------------------------
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .color  word [bp+12]
; Variable locale pour l'index du motif (y % 8)
%define .coord1 word [bp-2]
%define .coord2 word [bp-4]
cga_draw_rounded_frame:
    push    bp
    mov     bp, sp
    sub     sp, 4           ; Reserve espace pour .coord1 et .coord2
    pusha

    call    cga_mouse_hide

    ; Lignes horizontales (raccourcies de 2px pour laisser place à l'arrondi)
    mov     ax, .x1
    add     ax, 2
    mov     .coord1, ax
    mov     bx, .x2
    sub     bx, 2
    mov     .coord2, bx
    GFX     LINE, .coord1, .y1, .coord2, .y1, .color
    GFX     LINE, .coord1, .y2, .coord2, .y2, .color

    ; Lignes verticales (raccourcies de 1px en haut et en bas)
    mov     cx, .y1
    add     cx, 2
    mov     .coord1, cx
    mov     dx, .y2
    sub     dx, 2
    mov     .coord2, dx
    GFX     LINE, .x1, .coord1, .x1, .coord2, .color
    GFX     LINE, .x2, .coord1, .x2, .coord2, .color

    ; Ajout des pixels de transition pour adoucir les coins (chanfrein)
    mov     ax, .x1
    inc     ax              ; x1 + 1
    mov     bx, .y1
    inc     bx              ; y1 + 1
    GFX     PUTPIXEL, ax, bx, .color        ; Coin haut-gauche

    mov     ax, .x1
    inc     ax
    mov     bx, .y2
    dec     bx              ; y2 - 1
    GFX     PUTPIXEL, ax, bx, .color        ; Coin bas-gauche

    mov     ax, .x2
    dec     ax              ; x2 - 1
    mov     bx, .y1
    inc     bx              ; y1 + 1
    GFX     PUTPIXEL, ax, bx, .color        ; Coin haut-droite

    mov     ax, .x2
    dec     ax
    mov     bx, .y2
    dec     bx              ; y2 - 1
    GFX     PUTPIXEL, ax, bx, .color        ; Coin bas-droite

    call    cga_mouse_show

    popa
    leave
    ret
%undef  .x1
%undef  .y1
%undef  .x2
%undef  .y2
%undef  .color

; -----------------------------------------------------------------------------

; ------------------------------------------------------------
; GESTION DU CURSEUR
; ------------------------------------------------------------
;
; ------------------------------------------------------------
; gère la demande d'effacement du curseur souris
;
; ------------------------------------------------------------
cga_mouse_hide:
    pushf                   ; Sauver l'état des flags (interrupts)
    cli                     ; Désactiver les interruptions (CRITIQUE)
    pushad                  ; Sauvegarder TOUS les registres 32-bits
    push    ds

    mov     ax, BDA_DATA_SEG
    mov     ds, ax

    ; Décrémenter le compteur
    dec     byte [BDA_MOUSE + mouse.cur_counter]

    ; Vérifier si on vient juste de passer en mode caché (c-à-d on est à -1)
    cmp     byte [BDA_MOUSE + mouse.cur_counter], -1
    jne     .skip_restore   ; Si on est à -2, -3... elle est déjà cachée

    call    cga_cursor_restorebg

    .skip_restore:
    pop     ds
    popad
    popf                    ; Restaure les interruptions (STI si elles étaient là)
    ret

; ------------------------------------------------------------
; gère la demande d'affichage du curseur souris
;
; ------------------------------------------------------------
cga_mouse_show:
    pushf
    cli
    pushad
    push    ds

    mov     ax, BDA_DATA_SEG
    mov     ds, ax

    ; Incrémenter le compteur
    inc     byte [BDA_MOUSE + mouse.cur_counter]

    ; Vérifier si on est revenu à 0 (Visible)
    cmp     byte [BDA_MOUSE + mouse.cur_counter], 0
    jne     .skip_draw      ; Si on est encore à -1, -2... on reste caché

    ; C'est la transition Caché -> Visible : On affiche le curseur
    ; IMPORTANT : On sauve le fond ACTUEL (qui a peut-être changé pendant le hide)
    call    cga_cursor_savebg
    call    cga_cursor_draw

    .skip_draw:
    pop     ds
    popad
    popf
    ret


; ------------------------------------------------------------
; gère le déplacement du curseur souris
;
; ------------------------------------------------------------
cga_mouse_cursor_move:
	pushad
	push 	ds
	push 	es

	; move Data Segment
	mov		ax, BDA_DATA_SEG
	mov		ds, ax

    cmp     byte [BDA_MOUSE + mouse.cur_counter], 0
    jl      .done       ; Si < 0, on ne dessine rien !

	cmp		byte [BDA_MOUSE + mouse.cur_drawing],0
	jne		.done

	mov 	byte [BDA_MOUSE + mouse.cur_drawing],1

	mov		ax, VIDEO_SEG
	mov		es, ax

	call 	cga_cursor_restorebg

	call	cga_cursor_savebg

	call 	cga_cursor_draw
	mov 	byte [BDA_MOUSE + mouse.cur_drawing],0
    .done:
	pop 	es
	pop 	ds
	popad
	ret

; ------------------------------------------------------------
; cga_cursor_savebg
; Sauve 16 lignes (4 bytes/ligne) sous le curseur.
; Stocke 16 DWORDs: chaque DWORD contient les 4 bytes de la ligne
; ------------------------------------------------------------
cga_cursor_savebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0       ; le buffer n'a pas encore été restauré
    jne     .done

    push    es
    mov     ax, VIDEO_SEG
    mov     es, ax

    ; mémoriser position courante (utilisée pour restore)
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]
    mov     [BDA_MOUSE + mouse.cur_x], cx
    mov     [BDA_MOUSE + mouse.cur_y], dx

    ; calcule ES:DI pour (x,y)
    call    cga_calc_addr

    mov     [BDA_MOUSE + mouse.cur_addr_start], di
    lea     si, [BDA_MOUSE + mouse.bkg_buffer]

    mov     cx,16

    .row_loop:
    ; ---- ligne bank courant ----
    mov     eax, [es:di]               ; lit b0 b1 b2 b3
    mov     [ds:si], eax               ; stocke 4 bytes (le byte haut sera 0)
    add     si, 4

    xor     di, 0x2000
    test    di, 0x2000
    jnz     .next_line
    add     di, CGA_STRIDE            ; avance de 2 lignes dans bank courant

    .next_line:
    loop    .row_loop

    pop     es

    .done:
    mov     byte [BDA_MOUSE + mouse.bkg_saved], 1       ; Flag mis à jour après la copie
    ret

; ------------------------------------------------------------
; cga_cursor_restorebg
; Restaure 16 lignes sauvegardées.
; ------------------------------------------------------------
cga_cursor_restorebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    je      .done

    push    es
    mov     ax, VIDEO_SEG
    mov     es, ax

    ; restaurer depuis la dernière position sauvegardée
    mov     di, [BDA_MOUSE + mouse.cur_addr_start]
    lea     si, [BDA_MOUSE + mouse.bkg_buffer]
    mov     cx, 16

    .row_loop:
    ; ---- ligne bank courant ----
    mov     eax, [ds:si]               ; saved (32 bits)
    mov     [es:di], eax               ; restore line
    add     si, 4

    xor     di, 0x2000
    test    di, 0x2000
    jnz     .next_line
    add     di, CGA_STRIDE            ; avance de 2 lignes dans bank courant

    .next_line:
    loop    .row_loop

    pop     es
    .done:
    mov     byte [BDA_MOUSE + mouse.bkg_saved], 0       ; Flag mis à jour après la restauration
    ret

; ============================================================
; gfx_cursor_draw_rm16_i386_self
; Entrée:
;   DS = BDA_DATA_SEG
; Sortie: rien
; Détruit: registres sauvegardés/restaurés (PUSHA/POPA)
; ============================================================
cga_cursor_draw:
    pushad
    push    ds
    push    es
    push    gs

    mov     ax, BDA_DATA_SEG
    mov     ds, ax
    mov     ax, VIDEO_SEG
    mov     es, ax

    ; --- CLIPPING VERTICAL ---
    mov     dx, [ds:BDA_MOUSE + mouse.y]
    cmp     dx, 200
    jae     .exit_total

    mov     bp, 16
    mov     ax, 200
    sub     ax, dx                                  ; 200-y
    cmp     bp, ax
    jbe     .y_ok                                   ; y<= 200-16

    mov     bp, ax

    .y_ok:
    ; On calcule si les 4 octets vont dépasser la ligne (80 octets)
    ; X est en bits (0-639). X >> 3 donne l'octet de départ (0-79).
    ; Si StartByte >= 77, on déborde.

    mov     cx, [BDA_MOUSE + mouse.x]
    shr     cx, 3                   ; CX = Byte Offset (0-79)
    xor     esi, esi                ; ESI = Masque de protection (0 = tout dessiner)

    cmp     cx, 76                  ; 76 est le dernier offset sûr (76,77,78,79)
    jbe     .mask_ready             ; Si <= 76, pas de débordement

    ; Calcul du débordement
    ; Si CX=77 (Déborde 1 byte) -> Masque 0x000000FF (LSB car bswap)
    ; Si CX=78 (Déborde 2 bytes)-> Masque 0x0000FFFF
    ; Si CX=79 (Déborde 3 bytes)-> Masque 0x00FFFFFF

    cmp     cx, 77
    jne     .check_78
    mov     esi, 0x000000FF
    jmp     .mask_ready

    .check_78:
    cmp     cx, 78
    jne     .check_79
    mov     esi, 0x0000FFFF
    jmp     .mask_ready

    .check_79:
    mov     esi, 0x00FFFFFF         ; Cas extrême (bord droit)

    .mask_ready:
    ; On sauvegarde ce masque pour l'utiliser dans la boucle
    ; On utilise la pile pour libérer les registres
    push    esi                     ; [ESP] contient maintenant le masque

    ; --- ADRESSAGE ---
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]
    call    cga_calc_addr                           ; DI = Offset VRAM

    mov     ax, [BDA_MOUSE + mouse.cur_seg]
    mov     gs, ax
    mov     si, [BDA_MOUSE + mouse.cur_ofs]

    ; --- CALCUL de l'offset entre 2 lignes +0x2000 ou -0x2000 ---
    mov     ax, 0x2000          ; Banque +1
    mov     cx, [BDA_MOUSE + mouse.y]
    test    cx, 1
    jz      .setup_done
    neg     ax                  ; banque -1

    .setup_done:
    mov     cx, ax

    .row_loop:
    ; --- CONSTRUCTION DES MASQUES (EAX/EBX) ---
    push    cx                  ; préserver la banque "suivante"
    mov     cl, [BDA_MOUSE + mouse.x]
    and     cl, 0x07

    ; --- MASQUE AND (EAX) ---
    mov     eax, 0xFFFFFFFF
    mov     ax, [gs:si]             ; masque AND
    xchg    al, ah                  ; Redresser pour l'ordre des pixels CGA
    ;bswap   eax                    ; equivalence i386+
    xchg    ah, al                  ; Échange les octets de poids faible (AL <-> AH)
    rol     eax, 16                 ; Bascule les 16 bits de poids fort vers le bas
    xchg    ah, al                  ; Échange les nouveaux octets de poids faible
    ; fin bswap eax equivalence i386+

    ror     eax, cl

    or      eax, [esp+2]            ; Force les bits clippés à 1 (garde le fond)

    ; --- MASQUE XOR (EBX) ---
    xor     ebx, ebx
    mov     bx, [gs:si+32]          ; masque XOR
    ;xchg    bl, bh
    ;bswap   ebx
    rol     ebx, 16
    xchg    bh, bl
    ror     ebx, cl

    mov     edx, [esp+2]            ; charge le masque de protection
    not     edx                     ; inverse le masque de protection
    and     ebx, edx                ; applique le masque de protection


    ; --- LECTURE ET MODIFICATION (EDX) ---
    mov     edx, [es:di]        ; lecture des 16 bits a la position du curseur
    ; bswap   edx
    xchg    dh, dl
    rol     edx, 16
    xchg    dh, dl

    and     edx, eax            ; application du masque AND (AX)
    xor     edx, ebx            ; application du masque XOR (BX)
    ; bswap   edx
    xchg    dh, dl
    rol     edx, 16
    xchg    dh, dl

    mov     [es:di], edx        ; ecriture du résultat

    ; --- GESTION DES BANQUES ---
    pop     cx
    add     di, cx              ; banque suivante
    test    cx,0x8000
    jz      .next_line
    add     di,80

    .next_line:
    neg     cx                  ; prochaine banque = -banque
    add     si, 2               ; Prochaine ligne du sprite
    dec     bp
    jnz     .row_loop

    pop     esi

    .exit_total:
    pop     gs
    pop     es
    pop     ds
    popad
    ret
