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

; décommenter cette constante si vous voulez un mode aligné/non alligné différent
; sinon le code utilisé sera toujours "shifted"
; %define FULL_MODE_ALLIGNED          1

;
; bit : descr
;  0  : text color : 0=black, 1=white
;  1  : transparent : 1=apply background attribut
;
%define GFX_TXT_WHITE_TRANSPARENT   00000000b
%define GFX_TXT_BLACK_TRANSPARENT   00000001b
%define GFX_TXT_WHITE               00000010b
%define GFX_TXT_BLACK               00000011b

%macro GFX_DRV  1
    call word [cs:graph_driver + ((%1)*2)]
%endmacro

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
%define GFX_PUTPIXEL	1
%define GFX_GETPIXEL 	2
%define GOTOXY		    3
%define TXT_MODE        4
%define PUTCH           5
%define WRITE           6
%define GFX_CRS_UPDATE  7

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

graph_driver:
    dw cga_init                 ; init de la carte graphique
    dw cga_putpixel             ; dessin d'un pixel
    dw cga_getpixel             ; lecture d'un pixel
    dw cga_set_charpos          ; gotoxy
    dw cga_set_writemode        ; mode texte
    dw cga_putc                 ; dessin d'un caractère
    dw cga_write                ; dessin d'une chaine de caractère
 	dw cga_mouse_cursor_move    ; déplacement du curseur
    dw cga_line_vertical        ; dessin d'une ligne verticale


;    jmp gfx_fill_rect       ; Remplissage rectangle (Nouveau)
;    jmp gfx_invert_rect     ; Offset +12: Inversion (Nouveau pour Menus)
;    jmp gfx_draw_hline      ; Offset +15: Ligne horizontale rapide (Nouveau)

%include "./common/cursor.asm"
%include "./common/chartable.asm"

;
; convert al -> AX aligned with "cl"
%macro ALING_BYTE 0
        mov     ah,al
        xor     al,al
        shr     ax,cl

        xchg    ah,al
%endmacro
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
	mov		byte [BDA_MOUSE + mouse.bkg_saved],0	; flag image saved

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
	shr 	ax, 1                  ; ax = y/2
	mov     di, ax
	shl  	di, 4                  ; (y/2)*16
	shl     ax, 6                  ; (y/2)*64
	add     di, ax                 ; *80
	mov     ax, cx
	shr     ax, 3
	add     di, ax
	test    dl, 1
	jz      .even
	add     di, CGA_ODD_BANK
    .even:
	; masque bit = 0x80 >> (x&7)
	push	cx
	and     cl, 7
	mov     ah, 080h
	shr     ah, cl
	pop     cx
	ret

cga_set_writemode:
    push    bp
    mov     bp, sp

    push    fs
    push    ax
    mov     ax, BDA_DATA_SEG
    mov     fs,ax

    mov     ax, word arg1

    mov     byte [fs:BDA_GFX + gfx.cur_mode], al

    pop     ax
    pop     fs
    leave
    ret

; ---------------------------------------------------------------------------
; gfx_set_charpos
; In : CX = x (pixels), DX = y (pixels)
; Out: variables DS:GFX_CUR_*
; Notes:
;  - calcule l'offset VRAM de la scanline y: base = (y&1?2000:0) + (y>>1)*80 + (x>>3)
;  - stocke aussi shift = x&7
; ---------------------------------------------------------------------------
cga_set_charpos:
    push    bp
    mov     bp, sp

    pusha
    push    fs

    mov     ax,BDA_DATA_SEG
    mov     fs,ax

    ; store x,y en pixel
    mov     cx, word arg1
    mov     dx, word arg2

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
; cga_putc_unalign
; In : AL = char (ASCII)
; Uses: FS:BDA_GFX + gfx.cur_* (offset, add_ofs, shift, mode)
; Notes:
;   - x non aligné (x&7 != 0)
;   - écrit sur 2 bytes (di et di+1) dans chaque banque
; ---------------------------------------------------------------------------
cga_putc:
    push    bp
    mov     bp, sp
    sub     sp, 2               ; variable locale

    pusha
    push    fs
    push    es

    mov     bx, VIDEO_SEG
    mov     es, bx
    mov     bx, BDA_DATA_SEG
    mov     fs, bx

    mov     ax, [bp+4]          ; arg1

    call    get_glyph_offset

    ; Base offset VRAM pour la scanline Y
    mov     di, [fs:BDA_GFX + gfx.cur_offset]
    mov     bx, [fs:BDA_GFX + gfx.cur_line_ofs]
    mov     ch, [fs:BDA_GFX + gfx.cur_mode]
    mov     cl, [fs:BDA_GFX + gfx.cur_shift]

    mov     word [bp-2], 4

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
    ALING_BYTE
    mov     dx,ax

    ; ligne "impaire" du gylphe
    mov     al, [cs:si]
    inc     si
    ALING_BYTE
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

    dec     word [bp-2]
    jnz     .row_loop

    ; Avancer curseur d'un caractère (8 pixels)
    inc     word [fs:BDA_GFX + gfx.cur_offset]
    add     word [fs:BDA_GFX + gfx.cur_x], 8

    pop     es
    pop     fs
    popa
    leave
    ret

;
; write string from [DS:SI] to screen
;
cga_write:
    push    bp
    mov     bp, sp
    push    ax

    mov     ax, arg1
    mov     ds, ax
    mov     si, arg2

    .loops:
    lodsb
    cmp     al,0
    je      .done
    push    ax
    call    cga_putc
    jmp     .loops

    .done:
    pop     ax
    leave
    ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   ES = Target Segment (usually VIDEO_SEG)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
cga_local_putpixel:
	call   	cga_calc_addr

	; write
	cmp     bl, 0
	je    	.clear

    .set:
	or      byte [es:di], ah
	jmp     .done

    .clear:
	not     ah
	and     byte [es:di], ah

    .done:
	ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
cga_putpixel:
	push	ax
	push  	di
	push    es
	mov		ax,	VIDEO_SEG
	mov		es,ax
	call   	cga_calc_addr

	; write
	cmp  	bl, 0
	je    	.clear

    .set:
	or   	byte [es:di], ah
	jmp     .done

    .clear:
	not     ah
	and     byte [es:di], ah

    .done:
	pop 	es
	pop   	di
	pop		ax
	ret

; ------------------------------------------------------------
; Lit un pixel (CX=x, DX=y)
; Out: AL=0/1
; ------------------------------------------------------------
cga_getpixel:
	push    	di
	push    	es

	call    	cga_calc_addr
	mov     	al, [es:di]
	and     	al, ah
	setnz   	al

	pop     	es
	pop     	di
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
; Dessine un pixel, en [ES:DI] accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
cga_putpixel_fast:
	cmp  	bl, 0
	je    	.clear

    .set:
	or      byte [es:di], ah
	jmp     .done

    .clear:
	not     ah
	and     byte [es:di], ah
    .done:
	ret

; ------------------------------------------------------------
; Lit un pixel, en [ES:DI] accès VRAM direct.
;
; ------------------------------------------------------------
cga_getpixel_fast:
	mov     al, [es:di]
	and     al, ah
	setnz   al
	ret

; ------------------------------------------------------------
; cga_line_vertical
; Dessine une ligne x, y0, y1, color
; ------------------------------------------------------------
cga_line_vertical:
    push    bp
    mov     bp, sp

    ; --- Définition des arguments ---
    %define .x      word [bp+4]
    %define .y1     word [bp+6]
    %define .y2     word [bp+8]
    %define .color  byte [bp+10] ; (Attention à l'alignement sur pile)

    pusha
    push    es

    ; Setup ES = Video Segment (0xB800)
    mov     si, VIDEO_SEG
    mov     es, si

    call    cga_mouse_hide

    mov     bx, .y1
    mov     dx, .y2

    ; Ordonner Y (BX < DX)
    cmp     bx, dx
    jle     .y_sorted
    xchg    bx, dx
    .y_sorted:

    ; Calculer l'adresse du premier point (X, Y_Start)
;    push    dx              ; Sauve Y_Fin
;    push    cx              ; Sauve Couleur

    mov     cx, arg1        ; CX = X (pour cga_calc_addr)
    mov     dx, arg3        ; DX = Y_Start (pour cga_calc_addr)
    call    cga_calc_addr   ; Return: DI=Offset, AH=BitMask (ex: 00100000)

    pop     cx              ; Récup Couleur
    pop     dx              ; Récup Y_Fin (dans DX)

    ; Préparer le masque inverse pour le cas "Noir" (AND)
    mov     al, ah          ; AL = Masque (00100000)
    not     al              ; AL = ~Masque (11011111)

    ; BX sert maintenant de compteur courant, on a Y_Fin dans DX
    ; Utilisons BP comme compteur de hauteur.

    sub     dx, bx          ; DX = Hauteur - 1 (delta)
    inc     dx              ; DX = Nombre de pixels à dessiner

    .v_loop:
    cmp     cl, 0
    jz      .draw_black

    .draw_white:
    or      byte [es:di], ah    ; Allumer le bit
    jmp     .next_line

    .draw_black:
    and     byte [es:di], al    ; Eteindre le bit

    .next_line:
    ; --- Logique Next Line CGA (Optimisée) ---
    xor     di, 0x2000          ; Flip banque (Pair <-> Impair)
    test    di, 0x2000          ; Si on est passé à 0x2000 (Impair), on a juste descendu de 1 ligne visuelle
    jnz     .skip_add           ; C'est bon.
    add     di, 80              ; Si on revient à 0x0000 (Pair), on doit avancer de 80 octets
    .skip_add:

    dec     dx
    jnz     .v_loop

    call    cga_mouse_show

    pop     es
    popa
    ret
; ------------------------------------------------------------
; cga_line_horizontal
; Dessine une ligne de (AX, DX) à (BX, DX) CL: color
; ------------------------------------------------------------
cga_line_horizontal:
    pusha
    push    es

    call    cga_mouse_hide

    mov     si, VIDEO_SEG
    mov     es, si

    ; 1. Ordonner X (AX < BX)
    cmp     ax, bx
    jle     .x_sorted
    xchg    ax, bx

    .x_sorted:
    ; Calculer l'adresse de départ
    ; On a besoin de l'adresse de l'octet de AX.
    push    cx              ; Sauve Couleur
    push    bx              ; Sauve X_Fin

    mov     cx, ax          ; CX = X_Start
    ; DX est déjà Y
    call    cga_calc_addr   ; DI = Offset du premier byte
                            ; AH = Masque du bit précis (pas utile pour le remplissage, on recalculera)

    pop     bx              ; Récup X_Fin
    pop     cx              ; Récup Couleur (CL)

    ; --- ANALYSE DES OCTETS ---
    ; Start Byte Index = AX >> 3
    ; End Byte Index   = BX >> 3

    mov     si, ax          ; SI = X_Start
    shr     si, 3           ; Byte index start

    mov     bp, bx          ; BP = X_Fin
    shr     bp, 3           ; Byte index end

    ; Cas spécial : Tout tient dans le même octet ?
    cmp     si, bp
    je      .single_byte

    ; ============================================
    ; CAS MULTI-BYTE
    ; ============================================

    ; --- 1. Gérer l'octet de GAUCHE (Start) ---
    ; On doit dessiner du bit (AX&7) jusqu'au bit 0 (droite de l'octet)
    ; Masque = 0xFF >> (AX & 7)

    push    cx              ; Save couleur
    mov     cx, ax
    and     cx, 7           ; X % 8
    mov     al, 0xFF
    shr     al, cl          ; AL = Masque Gauche (ex: si X%8=2, 00111111)
    pop     cx              ; Restore couleur

    call    .apply_mask_at_di ; Applique AL sur [ES:DI] selon CL

    inc     di              ; Octet suivant
    inc     si              ; Index suivant

    ; --- 2. Gérer le MILIEU (Full Bytes) ---
    ; Tant que SI < BP, on remplit tout l'octet
    jmp     .check_middle

    .loop_middle:
    cmp     cl, 0
    jz      .middle_black
    mov     byte [es:di], 0xFF  ; Blanc total
    jmp     .middle_next

    .middle_black:
    mov     byte [es:di], 0x00  ; Noir total

    .middle_next:
    inc     di
    inc     si

    .check_middle:
    cmp     si, bp
    jl      .loop_middle    ; Continue tant qu'on n'est pas au dernier octet

    ; Gérer l'octet de DROITE (End) ---
    ; On doit dessiner du bit 7 jusqu'au bit (BX&7)
    ; Masque = ~(0xFF >> ((BX & 7) + 1))
    ; Ex: Si Fin%8 = 0 (1 pixel), shift 1 -> 01111111, NOT -> 10000000. Correct.

    push    cx
    mov     cx, bx
    and     cx, 7
    inc     cx              ; Nb de pixels à garder à gauche
    mov     al, 0xFF
    shr     al, cl          ; Masque des pixels à IGNORER (droite)
    not     al              ; Masque des pixels à DESSINER (gauche)
    pop     cx

    call    .apply_mask_at_di
    jmp     .done

    ; ============================================
    ; CAS SINGLE BYTE (Début et Fin dans le même octet)
    ; ============================================
    .single_byte:
    ; Masque Start = 0xFF >> (AX & 7)
    push    cx
    mov     cx, ax
    and     cx, 7
    mov     ah, 0xFF
    shr     ah, cl          ; AH = Masque départ (ex: 00011111)

    ; Masque End (Pixels à garder jusqu'à BX)
    ; On veut garder les pixels de 7 jusqu'à BX&7
    ; Astuce: Masque Combiné = MasqueStart AND MasqueEnd

    mov     cx, bx
    and     cx, 7
    inc     cx
    mov     al, 0xFF
    shr     al, cl
    not     al              ; AL = Masque Fin (ex: 11110000)

    and     al, ah          ; Intersection des deux masques
    pop     cx

    call    .apply_mask_at_di
    jmp     .done

    ; --- Helper interne : Applique le masque AL à l'adresse DI selon couleur CL ---
    .apply_mask_at_di:
    cmp     cl, 0
    jz      .apply_black
    or      [es:di], al     ; Blanc: OR Masque
    ret

    .apply_black:
    not     al              ; Noir: AND ~Masque
    and     [es:di], al
    ret

    .done:

    call    cga_mouse_show
    pop     es
    popa
    ret
;
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
    push    ax
    push    ds

    mov     ax, BDA_DATA_SEG
    mov     ds, ax

    ; Décrémenter le compteur
    dec     byte [BDA_MOUSE + mouse.cur_counter]

    ; Vérifier si on vient juste de passer en mode caché (c-à-d on est à -1)
    cmp     byte [BDA_MOUSE + mouse.cur_counter], -1
    jne     .skip_restore   ; Si on est à -2, -3... elle est déjà cachée

    ; C'est la transition Visible -> Caché : On efface le curseur
    call    cga_cursor_restorebg
    ; On marque qu'on ne dessine plus
    mov     byte [BDA_MOUSE + mouse.bkg_saved], 0

    .skip_restore:
    pop     ds
    pop     ax
    popf                    ; Restaure les interruptions (STI si elles étaient là)
    ret

; ------------------------------------------------------------
; gère la demande d'affichage du curseur souris
;
; ------------------------------------------------------------
cga_mouse_show:
    pushf
    cli
    push    ax
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
    pop     ax
    popf
    ret


; ------------------------------------------------------------
; gère le déplacement du curseur souris
;
; ------------------------------------------------------------
cga_mouse_cursor_move:
	push    ax
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
	pop     ax
	ret

; ------------------------------------------------------------
; cga_cursor_savebg
; Sauve 16 lignes (4 bytes/ligne) sous le curseur.
; Stocke 16 DWORDs: chaque DWORD contient les 4 bytes de la ligne
; ------------------------------------------------------------
cga_cursor_savebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0       ; le buffer n'a pas encore été restauré
    jne     .done

    mov     byte [BDA_MOUSE + mouse.bkg_saved], 1

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

    .done:
    ret

; ------------------------------------------------------------
; cga_cursor_restorebg
; Restaure 16 lignes sauvegardées.
; ------------------------------------------------------------
cga_cursor_restorebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    je      .done

    mov     byte [BDA_MOUSE + mouse.bkg_saved], 0

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

    .done:
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
    bswap   eax
    ror     eax, cl

    or      eax, [esp+2]            ; Force les bits clippés à 1 (garde le fond)

    ; --- MASQUE XOR (EBX) ---
    xor     ebx, ebx
    mov     bx, [gs:si+32]          ; masque XOR
    xchg    bl, bh
    bswap   ebx
    ror     ebx, cl

    mov     edx, [esp+2]            ; charge le masque de protection
    not     edx                     ; inverse le masque de protection
    and     ebx, edx                ; applique le masque de protection


    ; --- LECTURE ET MODIFICATION (EDX) ---
    mov     edx, [es:di]        ; lecture des 16 bits a la position du curseur
    bswap   edx
    and     edx, eax            ; application du masque AND (AX)
    xor     edx, ebx            ; application du masque XOR (BX)
    bswap   edx
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
    pop     es
    pop     ds
    popad
    ret