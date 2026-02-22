; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gfx_vga.asm
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
%define SEG_VIDEO    	0A000h

%define GFX_MODE		0x12			; VGA HiRes (640x480x16)
%define GFX_WIDTH		640
%define GFX_HEIGHT		480
%define GFX_OFFSET      80
;
; bit : descr
;  0..3  : text color : 0=black .. 15=white
;  4..7  : background color
;  8..D  : unused
;  E     : text transparent
;  F     : background transparent
;
%define GFX_TXT_WHITE_TRANSPARENT   0x0F
%define GFX_TXT_BLACK_TRANSPARENT   0x00
%define GFX_TXT_WHITE               0xF0
%define GFX_TXT_BLACK               0x0F

%define GFX_TXT_TRANSPARENT_BKG     0x8000
%define GFX_TXT_TRANSPARENT_TEXT    0x4000

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
	dw vga_init                 ; init de la carte graphique
	dw vga_putpixel             ; dessin d'un pixel
	dw vga_none                 ; lecture d'un pixel
	dw vga_set_charpos          ; gotoxy
	dw vga_set_writemode        ; mode texte
	dw vga_putc                 ; dessin d'un caractère
	dw vga_write                ; dessin d'une chaine de caractère
	dw vga_line                 ; dessin d'une ligne (Bresenham) avec décision horizontale/verticale
	dw vga_draw_rect            ; dessin d'un rectangle
	dw vga_fill_rect_32         ; dessin d'un rectangle plein
	dw vga_draw_rounded_frame   ; dessin d'un rectangle arrondi
	dw vga_mouse_hide           ; cache la souris
	dw vga_mouse_show           ; montre la souris
	dw vga_mouse_cursor_move    ; déplacement du curseur

%define	THEME_COLOR0	0
%define	THEME_COLOR1	1
%define	THEME_COLOR2	2
%define	THEME_COLOR3	3

themes:
	db	0,8,7,15      	  		; Light Gray
	db	0,2,10,15				; Rain Forest
	db	0,1,9,11				; Deep Ocean
	db 	0,4,12,15				; HELL
	db	0,3,11,15				; Hi Sky

; ------------------------------------------------------------
; dummy function
;
; cette fonction ne sert a rien, juste a "occuper" l'espace
; dans la table pour fonction qui n'existent pas
; ------------------------------------------------------------
vga_none:
	ret

; ------------------------------------------------------------
; initialise le mode graphique (via l'int 10h)
;
; ce mode est divisé en bitplane; 4 bits/pixel, 8 pixels par octet
; ------------------------------------------------------------
vga_init:
	; init graphics mode
	mov 	ah, 0x00     	                		; AH=00h set video mode
	mov		al, GFX_MODE
	int 	0x10

	; dessine un background "check-board"
	; Les patterns sont dans le segment de code (CS)
	push    cs
	pop     ds

	PATTERN_PTR PATTERN_GRAY_LIGHT
	mov     bl, 15
 	call	vga_background

	ret

; ------------------------------------------------------------
; get_glyph_offset
; In : AL = char (ASCII)
; Out: CS:SI -> 8 bytes
; ------------------------------------------------------------
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

; ------------------------------------------------------------
; vga_calc_addr
; Entrée:
;   CX = X (0-639)
;   DX = Y (0-479)
; Sortie:
;   DI = Offset dans le segment A000h
; ------------------------------------------------------------
vga_calc_addr:
	push    ax
	push    dx

	; Calcul de Y * 80
	; 80 = 64 + 16 (soit Y<<6 + Y<<4) pour éviter une multiplication lente
	mov     ax, dx      ; AX = Y
	shl     ax, 4       ; AX = Y * 16
	mov     di, ax      ; DI = Y * 16
	shl     ax, 2       ; AX = (Y * 16) * 4 = Y * 64
	add     di, ax      ; DI = (Y * 64) + (Y * 16) = Y * 80

	; Ajout de X / 8
	shr     cx, 3       ; CX = X / 8 (octet horizontal)
	add     di, cx      ; DI = (Y * 80) + (X / 8)

	pop     dx
	pop     ax
	ret

; ------------------------------------------------------------
; vga_background
; ------------------------------------------------------------
vga_background:
	; Configuration VGA pour le remplissage de masse
	mov 	dx, VGA_SEQUENCER  	; Sequencer
	mov 	ax, 0F02h       	; Map Mask (Index 2) = 0Fh (Tous les plans)
	out 	dx, ax

	; Graphics Controller
	mov 	dx, EGAVGA_CONTROLLER
	mov 	ax, 0305h       	; Mode Register (Index 5) = Mode 3
	out 	dx, ax

	mov 	al, 00h         	; Set/Reset (Index 0) = Couleur
	mov 	ah, bl
	out 	dx, ax

	; Initialisation mémoire
	mov 	ax, SEG_VIDEO
	mov 	es, ax
	xor 	edi, edi        	; ES:EDI = Début mémoire vidéo
	movzx   esi, si             ; Nettoyer ESI (garder SI) pour l'adressage

	; Boucle principale (480 lignes)
	xor 	edx, edx        	; EDX servira d'index pour le pattern (0-7)
	mov 	ecx, GFX_HEIGHT

	.line_loop:
	mov 	al, [esi + edx]		; Charger l'octet du pattern pour la ligne actuelle
	; Répliquer l'octet AL dans EAX (ex: 0xAA -> 0xAAAAAAAA) pour le 32-bit
	mov 	ah, al				; copy byte 0 -> byte 1
	mov		bx, ax				; préserve word
	shl 	eax, 16				; shift low word -> hi word
	mov		ax, bx             	; EAX contient maintenant 4 fois le pattern de 8 pixels

	mov 	bp, 20 	        	; 80 octets / 4 (32-bit) = 20 itérations par ligne
	.row_loop:
		mov 	bl, [es:di]   	; LATCH LOAD : Lecture indispensable en Mode 3
		stosd
		;mov 	[es:edi], eax  	; Écrit 32 pixels d'un coup avec le pattern
		;add 	edi, 4
		dec		bp
	jne 	.row_loop

	; Passer à la ligne suivante du pattern (modulo 8)
	inc 	edx
	and 	edx, 7          	; Si EDX=8, revient à 0
	loop 	.line_loop

	; Cleanup
	mov 	dx, EGAVGA_CONTROLLER
	mov 	ax, 0005h       	; Reset Write Mode 0
	out 	dx, ax
	ret

; ------------------------------------------------------------
; gfx_set_writemode (mode)
;  Défini le mode d'écriture :
;
; bit : descr
;  0  : text color : 0=black, 1=white
;  1  : transparent : 1=apply background attribut
;
; si le mode n'est pas transparent, la couleur de fond
; est l'inverse de la couleur du texte
%define .mode   word [bp+4]
; -------------------------------------------------------------
vga_set_writemode:
	push    bp
	mov     bp, sp

	push    fs
	push    ax
	mov     ax, SEG_BDA_CUSTOM
	mov     fs,ax

	mov     ax, .mode

	mov     byte [fs:PTR_GFX + gfx.cur_mode], al

	pop     ax
	pop     fs
	leave
	%undef  .mode
	ret


; ---------------------------------------------------------------------------
; gfx_set_charpos (x,y)
; In : x (pixels), y (pixels)
; Out: variables DS:GFX_CUR_*
; Notes:
;  - calcule l'offset VRAM de la scanline y: base = (y*80) + (x>>3)
;  - stocke aussi shift = x&7
%define .x     word [bp+4]
%define .y     word [bp+6]
; ---------------------------------------------------------------------------
vga_set_charpos:
	push    bp
	mov     bp, sp

	pusha
	push    fs

	mov     ax,SEG_BDA_CUSTOM
	mov     fs,ax

	; store x,y en pixel
	mov     cx, .x
	mov     dx, .y

	mov     [fs:PTR_GFX + gfx.cur_x], cx
	mov     [fs:PTR_GFX + gfx.cur_y], dx

	mov     ax, cx
	and     ax, 0x07
	mov     [fs:PTR_GFX + gfx.cur_shift], al

	call    vga_calc_addr

	mov     [fs:PTR_GFX + gfx.cur_offset], di
	pop     fs

	popa
	leave
	; clean defs
	%undef  .x
	%undef  .y
	ret

; ---------------------------------------------------------------------------
; vga_putc_unalign (car)
;   - x non aligné (x&7 != 0)
;   - écrit sur 2 bytes (di et di+1) dans chaque banque
%define .car    word [bp+4]
; ---------------------------------------------------------------------------
vga_putc:
	push    bp
	mov     bp, sp
	sub     sp, 4               ; .cpt [bp-2], .glyph_row [bp-4]
	%define .cpt        word [bp-2]
	%define .glyph_row  word [bp-4]

	pusha
	push    gs                  ; VRAM segment
	push    fs
	push    es

	call    vga_mouse_hide      ; Protection souris

	; --- CONFIGURATION VGA ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0205          ; Mode 2
	out     dx, ax
	mov     ax, 0x0003          ; Function REPLACE
	out     dx, ax
	mov     dx, VGA_SEQUENCER
	mov     ax, 0x0F02          ; Tous les plans
	out     dx, ax

	mov     ax, SEG_VIDEO
	mov     gs, ax
	mov     ax, SEG_BDA_CUSTOM
	mov     fs, ax
	push	cs
	pop		ds

	mov     ax, .car
	call    get_glyph_offset    ; cs:si = offset font

	mov     di, [fs:PTR_GFX + gfx.cur_offset]
	mov     cl, [fs:PTR_GFX + gfx.cur_shift]

	; --- RÉCUPÉRATION DES COULEURS ---
	mov     ax, [fs:PTR_GFX + gfx.cur_mode]
	mov     bl, al              ; BL = Couleur texte (low nibble)
	and     bl, 0x0F
	mov     bh, al              ; BH = Couleur fond (high nibble)
	shr     bh, 4

	mov     .cpt, 8
	mov     dx, EGAVGA_CONTROLLER

	.row_loop:
	lodsb                       ; AL = octet glyphe
	xor     ah, ah
	mov     .glyph_row, ax      ; Image 16 bits du glyphe non décalé

	; --- PASSE 1 : DESSIN DU FOND (SI OPAQUE) ---
	mov     ax, [fs:PTR_GFX + gfx.cur_mode]
	test    ax, GFX_TXT_TRANSPARENT_BKG
	jz	    .skip_bkg

	mov     ax, .glyph_row
	not     al                  ; Inverser le glyphe pour le fond
	ror     ax, cl              ; Aligner le fond sur les octets VRAM

	; Octet 1 (DI)
	push    ax                  ; Sauver masque décalé (AH:AL)
	mov     ah, al              ; Masque pour octet 1
	mov     al, 0x08            ; Bit Mask register
	out     dx, ax
	mov     al, [gs:di]         ; LATCH LOAD (Charger le fond actuel)
	mov     [gs:di], bh         ; WRITE Fond (BH)
	pop     ax

	; Octet 2 (DI+1)
	test    cl, cl
	jz      .skip_bkg
	; AH contient déjà le masque pour l'octet 2
	mov     al, 0x08
	out     dx, ax
	mov     al, [gs:di+1]       ; LATCH LOAD Octet suivant
	mov     [gs:di+1], bh       ; WRITE Fond (BH)
	.skip_bkg:

	; --- PASSE 2 : DESSIN DU TEXTE ---
	mov     ax, [fs:PTR_GFX + gfx.cur_mode]
	test    ax, GFX_TXT_TRANSPARENT_TEXT
	jnz     .next_line

	mov     ax, .glyph_row
	ror     ax, cl              ; Aligner le texte sur les octets VRAM

	; Octet 1 (DI)
	push    ax
	mov     ah, al
	mov     al, 0x08
	out     dx, ax
	mov     al, [gs:di]         ; LATCH LOAD
	mov     [gs:di], bl         ; WRITE Texte (BL)
	pop     ax

	; Octet 2 (DI+1)
	test    cl, cl
	jz      .next_line
	mov     al, 0x08
	; AH contient le glyphe décalé pour l'octet 2
	out     dx, ax
	mov     al, [gs:di+1]       ; LATCH LOAD
	mov     [gs:di+1], bl

	.next_line:
	add     di, 80              ; Ligne suivante
	dec     .cpt
	jnz     .row_loop

	; --- NETTOYAGE ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005          ; Write Mode 0
	out     dx, ax
	mov     ax, 0xFF08          ; Bit Mask = FF
	out     dx, ax

	; Mise à jour position
	add     word [fs:PTR_GFX + gfx.cur_x], 8
	mov     cx, [fs:PTR_GFX + gfx.cur_x]
	mov     dx, [fs:PTR_GFX + gfx.cur_y]
	call    vga_calc_addr
	mov     [fs:PTR_GFX + gfx.cur_offset], di

	call    vga_mouse_show
	pop     es
	pop     fs
	pop     gs
	popa
	leave
	; clean defs
	%undef	.cpt
	%undef	.glyph_row
	ret

; ---------------------------------------------------------------------------
; write string from [DS:SI] to screen
%define .txt_seg   word [bp+4]
%define .txt_ofs   word [bp+6]
; ---------------------------------------------------------------------------
vga_write:
	push    bp
	mov     bp, sp
	push    ax
	push    ds

	mov     ax, .txt_seg
	mov     ds, ax
	mov     si, .txt_ofs
	cld

	.loops:
	lodsb
	cmp     al,0
	je      .done
	push    ax
	call    vga_putc
	pop		ax
	jmp     .loops

	.done:
	pop     ds
	pop     ax
	leave
	%undef  .txt_seg
	%undef  .txt_ofs
	ret

; ------------------------------------------------------------
; vga_line (x1, y1, x2, y2, color)
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .color  byte [bp+12]
; ------------------------------------------------------------
vga_line:
	push    bp
	mov     bp, sp
	pusha

	call    vga_mouse_hide

	mov     ax, .x1
	mov     bx, .x2

	mov     cx, .y1
	mov     dx, .y2

	; Cas 1 : Ligne Verticale (x1 == x2)
	cmp     ax, bx
	je      .call_vertical

	; Cas 2 : Ligne Horizontale (y1 == y2)
	cmp     cx, dx
	je      .call_horizontal

	; Cas 3 : Ligne diagonale quelconque (Bresenham)
	.bresenham:

	push	word .color
	push	.y2
	push	.x2
	push	.y1
	push	.x1

	; ... Algorithme classique
	; call	vga_line_bresenham
	; ... Algorithme accéléré
	call	vga_line_fast

	add		sp, 10
	jmp     .done

	.call_vertical:
	push    word .color
	push    dx              ; y2
	push    cx              ; y1
	push    ax              ; x1
	call    vga_line_vertical
	add     sp, 8
	jmp     .done

	.call_horizontal:
	push    word .color
	push    bx              ; x2
	push    ax              ; x1
	push    cx              ; y1
	call    vga_line_horizontal
	add     sp, 8

	.done:
	call    vga_mouse_show
	popa
	leave
	; clean defs
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .color
	ret

%ifdef ____CLASSIC_LINE_____
; ------------------------------------------------------------
; vga_line_bresenham (x1, y1, x2, y2, color)
%define .x1      word [bp+4]
%define .y1      word [bp+6]
%define .x2      word [bp+8]
%define .y2      word [bp+10]
%define .color   word [bp+12]
; ------------------------------------------------------------
vga_line_bresenham:
	push    bp
	mov     bp, sp
	sub     sp, 12              ; Variables locales : dx, dy, sx, sy, err, e2
	%define _dx  word [bp-2]
	%define _dy  word [bp-4]
	%define _sx  word [bp-6]
	%define _sy  word [bp-8]
	%define _err word [bp-10]
	%define _e2  word [bp-12]

	pusha
	push    es

	; --- Calculs préliminaires Bresenham ---
	mov     ax, .x2
	sub     ax, .x1
	mov     _sx, 1
	jns     .dx_ok
	neg     ax
	mov     _sx, -1
	.dx_ok:
	mov     _dx, ax

	mov     ax, .y2
	sub     ax, .y1
	mov     _sy, 1
	jns     .dy_ok
	neg     ax
	mov     _sy, -1
	.dy_ok:
	neg     ax                  ; dy doit être négatif
	mov     _dy, ax

	mov     ax, _dx
	add     ax, _dy
	mov     _err, ax

	; --- CONFIGURATION VGA MODE 2 ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0205          ; Write Mode 2
	out     dx, ax
	mov     ax, 0x0003          ; Function Replace
	out     dx, ax

	mov     ax, SEG_VIDEO
	mov     es, ax

	mov     cx, .x1            ; Courant X
	mov     dx, .y1            ; Courant Y

	.plot_loop:
	; Calculer l'adresse et le Bit Mask pour le pixel courant
	push    dx
	push    cx
	call    vga_calc_addr       ; DI = offset VRAM, CL = bit shift (0-7)

	; Configurer le Bit Mask (Index 8)
	mov     cx, .x1
	and     cl, 7               ; <-- SÉCURITÉ : On force le masque entre 0 et 7
	mov     ah, 0x80
	shr     ah, cl              ; AH = Masque du pixel
	mov     al, 0x08
	mov     dx, EGAVGA_CONTROLLER
	out     dx, ax

	; Écriture Mode 2 (Latches + Couleur)
	mov     al, [es:di]         ; LOAD LATCHES
	mov     ax, .color
	mov     [es:di], al         ; WRITE Couleur

	pop     cx
	pop     dx

	; Vérifier si on a atteint la destination
	cmp     cx, .x2
	jne     .continue
	cmp     dx, .y2
	je      .exit_loop

	.continue:
	; e2 = 2 * err
	mov     ax, _err
	shl     ax, 1
	mov     _e2, ax

	; if e2 >= dy: err += dy; x1 += sx
	mov     bx, _dy
	cmp     ax, bx
	jl      .skip_x
	add     _err, bx
	add     cx, _sx
	.skip_x:

	; if e2 <= dx: err += dx; y1 += sy
	mov     bx, _dx
	cmp     _e2, bx
	jg      .plot_loop
	add     _err, bx
	add     dx, _sy
	jmp     .plot_loop

	.exit_loop:
	; --- NETTOYAGE VGA ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005          ; Reset Mode 0
	out     dx, ax
	mov     ax, 0xFF08          ; Reset Bit Mask
	out     dx, ax
	mov     ax, 0x0003          ; <-- SÉCURITÉ : Remettre Function Select à 0
	out     dx, ax

	pop     es
	popa
	leave
	; clean defs
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .color
	%undef  _dx
	%undef  _dy
	%undef  _sx
	%undef  _sy
	%undef  _err
	%undef  _e2
	ret
%endif

; ------------------------------------------------------------
; vga_line_fast (x1, y1, x2, y2, color)
%define .x1      word [bp+4]
%define .y1      word [bp+6]
%define .x2      word [bp+8]
%define .y2      word [bp+10]
%define .color   word [bp+12]
; ------------------------------------------------------------
vga_line_fast:
	push    bp
	mov     bp, sp
	sub     sp, 10              ; Variables locales : dx, dy, err, sy_offset, count
	%define _dx         word [bp-2]
	%define _dy         word [bp-4]
	%define _err        word [bp-6]
	%define _sy_offset  word [bp-8]  ; Vaudra +80 ou -80
	%define _count      word [bp-10] ; Nombre exact de pixels à tracer

	pusha
	push    es

	; --- CALCUL DE L'ADRESSE INITIALE ---
	mov     dx, .y1
	mov     cx, .x1
	call    vga_calc_addr       ; DI = Offset, CL = Alignement bit

	mov     cx, .x1
	and     cl, 7
	mov     bh, 0x80            ; <-- CHANGEMENT : On utilise BH temporairement
	shr     bh, cl              ; BH contient maintenant le Masque de départ

	; --- CALCUL DE L'ADRESSE INITIALE (UNE SEULE FOIS) ---
	mov     ax, .x2
	sub     ax, .x1
	jns     .dx_ok
	neg     ax
	.dx_ok:
	mov     _dx, ax

	mov     ax, .y2
	sub     ax, .y1
	mov     cx, 80              ; Par défaut, on descend
	jns     .dy_ok
	neg     ax
	mov     cx, -80             ; On monte
	.dy_ok:

	mov     _sy_offset, cx
	neg     ax                  ; DY doit être négatif
	mov     _dy, ax

	mov     ax, _dx
	add     ax, _dy
	mov     _err, ax

	; --- CALCUL DU NOMBRE DE PIXELS ---
	mov     ax, _dx
	mov     cx, _dy
	neg     cx                  ; abs(dy)
	cmp     ax, cx
	jge     .set_count
	mov     ax, cx              ; DY est plus grand
	.set_count:
	inc     ax
	mov     _count, ax

	; --- CONFIGURATION VGA ---
	mov     dx, EGAVGA_CONTROLLER ; 0x03CE
	mov     ax, 0x0205          ; Write Mode 2 (AX est légal !)
	out     dx, ax
	mov     ax, 0x0003          ; Function Replace
	out     dx, ax

	mov     ax, SEG_VIDEO
	mov     es, ax

	mov     ah, bh

	; --- CHOIX DE LA BOUCLE (Gauche ou Droite) ---
	mov     bx, .x2
	cmp     .x1, bx
	jg      .loop_left          ; Si x1 > x2, on trace vers la gauche

	; ==========================================================
	; BOUCLE DE TRACÉ VERS LA DROITE
	; ==========================================================
	.loop_right:
	; A. Dessiner le pixel
	mov     al, 0x08
	out     dx, ax              ; AL=0x08, AH=Masque courant
	mov     al, [es:di]         ; Latch
	mov     cl, byte .color
	mov     [es:di], cl         ; Write

	; B. Vérifier la fin
	dec     word _count
	jz      .exit_line

	; C. Mise à jour Bresenham
	mov     bx, _err
	shl     bx, 1               ; e2 = 2 * err

	; Pas sur Y ? (if e2 <= dx)
	mov     cx, _dx
	cmp     bx, cx
	jg      .check_x_right
	add     _err, cx            ; err += dx
	add     di, _sy_offset      ; DI glisse d'une ligne (+80 ou -80)

	.check_x_right:
	; Pas sur X ? (if e2 >= dy)
	mov     cx, _dy
	cmp     bx, cx
	jl      .loop_right
	add     _err, cx            ; err += dy

	; MAGIE : Glissement du masque vers la DROITE
	shr     ah, 1               ; On décale le bit.
	jnz     .loop_right         ; S'il n'est pas zéro, on reste dans le même octet !
	mov     ah, 0x80            ; Le bit est sorti : on le remet tout à gauche...
	inc     di                  ; ... et on avance l'adresse VRAM d'un octet !
	jmp     .loop_right

	; ==========================================================
	; BOUCLE DE TRACÉ VERS LA GAUCHE
	; ==========================================================
	.loop_left:
	; A. Dessiner le pixel
	mov     al, 0x08
	out     dx, ax
	mov     al, [es:di]
	mov     cl, byte .color
	mov     [es:di], cl

	; B. Vérifier la fin
	dec     word _count
	jz      .exit_line

	; C. Mise à jour Bresenham
	mov     bx, _err
	shl     bx, 1               ; e2 = 2 * err

	; Pas sur Y ?
	mov     cx, _dx
	cmp     bx, cx
	jg      .check_x_left
	add     _err, cx
	add     di, _sy_offset

	.check_x_left:
	; Pas sur X ?
	mov     cx, _dy
	cmp     bx, cx
	jl      .loop_left
	add     _err, cx

	; MAGIE : Glissement du masque vers la GAUCHE
	shl     ah, 1               ; On décale le bit vers la gauche.
	jnz     .loop_left          ; S'il n'est pas zéro, tout va bien.
	mov     ah, 0x01            ; Le bit est sorti : on le remet tout à droite...
	dec     di                  ; ... et on recule l'adresse VRAM d'un octet !
	jmp     .loop_left

	; ==========================================================

	.exit_line:
	; --- NETTOYAGE VGA ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005          ; Reset Mode 0
	out     dx, ax
	mov     ax, 0xFF08          ; Reset Bit Mask
	out     dx, ax
	mov     ax, 0x0003          ; Reset Function
	out     dx, ax

	pop     es
	popa
	leave
	; clean defs
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .color
	%undef  _dx
	%undef  _dy
	%undef  _err
	%undef  _sy_offset
	%undef  _count
	ret

; ------------------------------------------------------------
; vga_line_horizontal (y, x1, x2, color)
%define .y      word [bp+4]
%define .x1     word [bp+6]
%define .x2     word [bp+8]
%define .color  word [bp+10]
; ------------------------------------------------------------
vga_line_horizontal:
	push    bp
	mov     bp, sp
	sub     sp, 4
	%define .oft_end     word [bp-2]

	pusha
	push    es

	call    vga_mouse_hide      ; Protection souris

	; Trier x1 et x2 (Garantir que x1 <= x2)
	mov     ax, .x1
	mov     bx, .x2
	cmp     ax, bx
	jbe     .sorted
	mov     .x1, bx
	mov     .x2, ax
	.sorted:

	; Calculer l'adresse pour x1
	mov     dx, .y
	mov     cx, .x1
	call    vga_calc_addr   ; DI = offset de départ (on suppose que vga_calc_addr préserve les registres)

	; Calculer l'offset de fin CORRECTEMENT
	mov     ax, .x2
	shr     ax, 3           ; x2 divisé par 8 (octet de fin)
	mov     bx, .x1
	shr     bx, 3           ; x1 divisé par 8 (octet de début)
	sub     ax, bx          ; Distance en octets absolus
	add     ax, di          ; On ajoute l'offset de départ
	mov     .oft_end, ax    ; Sauvegarde de l'offset de fin réel

	; Setup VGA (Write Mode 2)
	mov     ax, SEG_VIDEO   ; ex: 0xA000
	mov     es, ax
	mov     bh, byte .color

	mov     ax, 0x0205      ; Index 5, Val 2 (Write Mode 2)
	mov     dx, EGAVGA_CONTROLLER ; 0x03CE
	out     dx, ax

	; Cas où x1 et x2 sont strictement dans le MÊME octet
	mov     cx, .oft_end
	cmp     di, cx          ; Comparer offset départ (DI) et fin (CX)
	je      .single_byte

	; --- BORD GAUCHE ---
	mov     cl, byte .x1
	and     cl, 7           ; CL = x1 % 8
	mov     ah, 0xFF
	shr     ah, cl          ; Masque : les bits à droite du shift
	mov     al, 0x08        ; Index du registre Bit Mask
	out     dx, ax          ; DX = 0x03CE

	mov     al, [es:di]     ; Latch load (lire pour charger les loquets VGA)
	mov     [es:di], bh     ; Écrire la couleur (Write Mode 2 applique le masque)
	inc     di

	; --- MILIEU (Octets complets) ---
	mov     ax, 0xFF08      ; Masque plein (0xFF)
	out     dx, ax
	.middle_loop:
	cmp     di, .oft_end    ; Compare l'offset actuel avec l'offset de fin
	jae     .right_edge     ; Si on a atteint le dernier octet, on sort
	mov     al, [es:di]
	mov     [es:di], bh
	inc     di
	jmp     .middle_loop

	.right_edge:
	; --- BORD DROIT ---
	mov     cl, 7
	mov     bl, byte .x2
	and     bl, 7           ; BL = x2 % 8
	sub     cl, bl          ; CL = 7 - (x2 % 8)
	mov     ah, 0xFF
	shl     ah, cl          ; Masque : les bits à gauche
	mov     al, 0x08
	out     dx, ax

	mov     al, [es:di]
	mov     [es:di], bh
	jmp     .done

	.single_byte:
	; --- UN SEUL OCTET ---
	; On génère le masque gauche
	mov     cl, byte .x1
	and     cl, 7
	mov     ah, 0xFF
	shr     ah, cl          ; AH = Masque gauche

	; On génère le masque droit
	mov     cl, 7
	mov     bl, byte .x2
	and     bl, 7
	sub     cl, bl
	mov     al, 0xFF
	shl     al, cl          ; AL = Masque droit

	; On fusionne les deux masques
	and     ah, al          ; AH = Intersection des deux masques
	mov     al, 0x08
	out     dx, ax

	mov     al, [es:di]
	mov     [es:di], bh

	.done:
	call    vga_mouse_show
	; Reset VGA
	mov     ax, 0x0005      ; Mode 0 (Index 5, Val 0)
	out     dx, ax
	mov     ax, 0xFF08      ; Bitmask reset (Index 8, Val 0xFF)
	out     dx, ax
	pop     es
	popa
	leave
	; clean defs
	%undef  .y
	%undef  .x1
	%undef  .x2
	%undef  .color
	ret

; ------------------------------------------------------------
; vga_line_vertical (x, y1, y2, color)
%define .x      word [bp+4]
%define .y1     word [bp+6]
%define .y2     word [bp+8]
%define .color  word [bp+10]
; ------------------------------------------------------------
vga_line_vertical:
	push    bp
	mov     bp, sp
	sub     sp, 2           ; Allocation d'une variable locale (2 octets)
	%define .height 	word [bp-2]
	pusha
	push	es

	call 	vga_mouse_hide
	; --- Trier Y ---
	mov     ax, .y1
	mov     bx, .y2
	cmp     ax, bx
	jbe     .y_ok
	xchg    ax, bx          ; inverser y1 et y2
	.y_ok:

	; --- Calculer le nombre de pixels (Hauteur) ---
	mov     cx, bx
	sub     cx, ax
	inc     cx              ; CX = Nombre de lignes à tracer
	mov     .height, cx     ; On SAUVEGARDE dans la pile, on garde CX propre !

	; --- Calculer l'adresse initiale ---
	mov     dx, ax          ; DX = Y-start
	mov     cx, .x          ; CX = X
	call    vga_calc_addr   ; DI = offset VRAM, CL = bit shift (X % 8)

	; --- Configurer le GPU (Mode 2) ---
	mov     dx, EGAVGA_CONTROLLER ; 0x03CE
	mov     ax, 0x0205      ; Write Mode 2 (Index 5, Val 2)
	out     dx, ax

	mov		cx, .x
	and 	cl, 0x07
	mov     ah, 0x80        ; Bit Mask : 1 pixel (le bit de poids fort)
	shr     ah, cl          ; CL n'a pas été écrasé, l'alignement est parfait !
	mov     al, 0x08        ; Index 8
	out     dx, ax

	mov     ax, SEG_VIDEO   ; 0xA000
	mov     es, ax
	mov     al, byte .color ; AL = Couleur pour le Mode 2

	mov     cx, .height     ; On restaure la hauteur depuis la variable locale
	.v_loop:
	mov     ah, [es:di]     ; LATCH LOAD
	mov     [es:di], al     ; WRITE COLOR
	add     di, 80          ; Scanline suivante (VGA 640x480 = 80 octets par ligne)
	loop    .v_loop         ; Répéter CX fois

	; --- Reset ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005      ; Mode 0
	out     dx, ax
	mov     ax, 0xFF08      ; Reset Mask
	out     dx, ax

	call 	vga_mouse_show
	pop     es
	popa
	leave                   ; Nettoie la variable locale (mov sp, bp / pop bp)
	; clean defs
	%undef  .x
	%undef  .y1
	%undef  .y2
	%undef  .color
	%undef  .height
	ret

; ------------------------------------------------------------
; vga_draw_rect
; Dessine un rectangle vide (contour)
; Entrée : x1, y1, x2, y2, color
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .color  word [bp+12] ; word pour l'alignement pile (mais on utilise byte)
; ------------------------------------------------------------
vga_draw_rect:
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

	call    vga_mouse_hide

	; 3. Dessiner les 4 lignes
	; Pour éviter les pixels en double dans les coins, on peut ajuster légèrement,
	; mais pour un driver simple, tracer les 4 lignes brutes est acceptable.

	GFX     LINE, .x1, .y1, .x2, .y1, .color
	GFX     LINE, .x1, .y2, .x2, .y2, .color

	GFX     LINE, .x1, .y1, .x1, .y2, .color
	GFX     LINE, .x2, .y1, .x2, .y2, .color

	call    vga_mouse_show
	popa
	leave
	; clean defs
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .color
	ret

; ------------------------------------------------------------
; cga_draw_rounded_frame
; dessiner un cadre arrondi
; Entrée : AX=x1, BX=y1, CX=x2, DX=y2
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .color  word [bp+12]
; ------------------------------------------------------------
vga_draw_rounded_frame:
	push    bp
	mov     bp, sp
	sub     sp, 4           ; Reserve espace pour .coord1 et .coord2
	; Variable locale pour l'index du motif (y % 8)
	%define .coord1 word [bp-2]
	%define .coord2 word [bp-4]
	pusha

	call    vga_mouse_hide

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

	call    vga_mouse_show

	popa
	leave
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .color
	%undef	.coord1
	%undef	.coord2
	ret

; ------------------------------------------------------------
; vga_fill_rect
; Dessine un rectangle plein avec un motif (Pattern)
; Entrée : x1, y1, x2, y2, pattern_offset
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .pat_id word [bp+12]   ; offset du pattern 8x8 bits
; ------------------------------------------------------------
vga_fill_rect:
	push    bp
	mov     bp, sp
	sub     sp, 6
	%define _left_mask  byte [bp-2]
	%define _right_mask byte [bp-4]
	%define _width      word [bp-6] ; Largeur en octets VRAM

	pusha
	push    es

	call	vga_mouse_hide

	; --- 1. Trier Y1 et Y2 ---
	mov     ax, .y1
	mov     bx, .y2
	cmp     ax, bx
	jbe     .y_ok
	xchg    ax, bx
	mov     .y1, ax
	mov     .y2, bx
	.y_ok:

	; --- 2. Trier X1 et X2 ---
	mov     ax, .x1
	mov     bx, .x2
	cmp     ax, bx
	jbe     .x_ok
	xchg    ax, bx
	mov     .x1, ax
	mov     .x2, bx
	.x_ok:

	; --- 3. Préparer les Masques (Gauches et Droits) ---
	; Masque Gauche
	mov     cx, .x1
	and     cl, 7
	mov     ah, 0xFF
	shr     ah, cl
	mov     _left_mask, ah

	; Masque Droit
	mov     cx, .x2
	and     cl, 7
	mov     ah, 0xFF
	mov     ch, 7
	sub     ch, cl
	mov     cl, ch
	shl     ah, cl
	mov     _right_mask, ah

	; Calcul du nombre d'octets d'écart entre X1 et X2
	mov     ax, .x2
	shr     ax, 3
	mov     bx, .x1
	shr     bx, 3
	sub     ax, bx
	mov     _width, ax          ; Nombre d'octets à traverser

	; Si X1 et X2 sont dans le même octet (Width = 0)
	cmp     ax, 0
	jne     .mask_ok
	mov     al, _left_mask
	and     al, _right_mask
	mov     _left_mask, al      ; On fusionne les deux masques
	.mask_ok:

	; --- 4. Configuration VGA ---
	mov     dx, EGAVGA_CONTROLLER ; 0x03CE
	mov     ax, 0x0005          ; Write Mode 0 (Écriture directe)
	out     dx, ax

	mov     ax, SEG_VIDEO
	mov     es, ax

	; --- 5. Initialisation du point de départ ---
	mov     dx, .y1
	mov     cx, .x1
	call    vga_calc_addr       ; DI = Offset de départ (en haut à gauche)

	mov     bx, .y1             ; BX va nous servir de compteur Y

	; ==========================================================
	; BOUCLE PRINCIPALE (LIGNE PAR LIGNE)
	; ==========================================================
	.y_loop:
	push    di                  ; Sauver l'offset VRAM du début de ligne

	; Récupérer la ligne du pattern correspondant au Y actuel
	mov     si, bx
	and     si, 7               ; SI = Y % 8
	add     si, .pat_id         ; SI = Adresse exacte de l'octet dans le pattern
	mov     ch, byte [si]       ; CH = La donnée du pattern à dessiner

	; --- BORD GAUCHE ---
	mov     dx, EGAVGA_CONTROLLER
	mov     al, 0x08            ; Index du Bit Mask
	mov     ah, _left_mask
	out     dx, ax

	mov     al, [es:di]         ; Latch
	mov     [es:di], ch         ; Write (Le VGA applique le masque automatiquement)

	; Si on est dans un seul octet, on passe directement à la ligne suivante
	cmp     word _width, 0
	je      .next_line

	inc     di                  ; Avancer d'un octet

	; --- MILIEU (Octets complets) ---
	mov     cx, _width
	dec     cx                  ; CX = Nombre d'octets pleins
	jz      .right_edge         ; S'il n'y a pas de milieu, on saute au bord droit

	mov     ax, 0xFF08          ; Masque 100% plein (0xFF)
	out     dx, ax
	.mid_loop:
	mov     al, [es:di]
	mov     [es:di], ch         ; Dessine le pattern plein
	inc     di
	dec     cx
	jnz     .mid_loop

	.right_edge:
	; --- BORD DROIT ---
	mov     al, 0x08
	mov     ah, _right_mask
	out     dx, ax

	mov     al, [es:di]
	mov     [es:di], ch

	.next_line:
	pop     di                  ; Restaurer l'offset du début de ligne
	add     di, 80              ; Descendre d'une ligne (+80 octets)

	inc     bx                  ; Y++
	cmp     bx, .y2
	jle     .y_loop

	; --- 6. Nettoyage VGA ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0xFF08          ; Reset Bit Mask
	out     dx, ax

	call	vga_mouse_show

	pop     es
	popa
	leave
	; Clean defs
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .pat_id
	%undef  _left_mask
	%undef  _right_mask
	%undef  _width
	ret

; ------------------------------------------------------------
; vga_fill_rect_32
; Dessine un rectangle plein avec un motif (Pattern 8x8) en 2 couleurs
; Entrée : x1, y1, x2, y2, pat_id, fg_col, bg_col
%define .x1     word [bp+4]
%define .y1     word [bp+6]
%define .x2     word [bp+8]
%define .y2     word [bp+10]
%define .pat_id word [bp+12]
%define .fg_col word [bp+14]
%define .bg_col word [bp+16]
; ------------------------------------------------------------
vga_fill_rect_32:
	push    bp
	mov     bp, sp
	sub     sp, 8
	%define _left_mask  byte [bp-2]
	%define _right_mask byte [bp-4]
	%define _width      word [bp-6]
	%define _patofst	word [bp-8]

	pushad
	push    es
	push	fs

	call	vga_mouse_hide

	push	cs
	pop		fs					; fs = CS

		; calcul de l'offset du pattern
	mov		ax, .pat_id
	shl		ax, 3
	add		ax, pattern_8x8
	mov		_patofst, ax

	; --- Trier Y ---
	mov     ax, .y1
	mov     bx, .y2
	cmp     ax, bx
	jbe     .y_ok
	xchg    ax, bx
	mov     .y1, ax
	mov     .y2, bx
	.y_ok:

	; --- Trier X ---
	mov     ax, .x1
	mov     bx, .x2
	cmp     ax, bx
	jbe     .x_ok
	xchg    ax, bx
	mov     .x1, ax
	mov     .x2, bx
	.x_ok:

	; --- 3. Préparer les Masques de Bords ---
	mov     cl, byte .x1
	and     cl, 7
	mov     ah, 0xFF
	shr     ah, cl
	mov     _left_mask, ah

	mov     cl, byte .x2
	and     cl, 7
	mov     ch, 7
	sub     ch, cl
	mov     cl, ch
	mov     ah, 0xFF
	shl     ah, cl
	mov     _right_mask, ah

	mov     ax, .x2
	shr     ax, 3
	mov     bx, .x1
	shr     bx, 3
	sub     ax, bx
	mov     _width, ax          ; Largeur en octets pleins

	jnz     .mask_ok
	mov     al, _left_mask
	and     al, _right_mask
	mov     _left_mask, al      ; Fusion si tout tient dans 1 seul octet
	.mask_ok:

	; --- 4. Setup VRAM ---
	mov     ax, SEG_VIDEO
	mov     es, ax

	mov     dx, .y1
	mov     cx, .x1
	call    vga_calc_addr       ; DI = Offset de départ
	mov     bx, .y1             ; BX = Compteur Y

	; ==========================================================
	; BOUCLE PRINCIPALE (Y)
	; ==========================================================
	.y_loop:
	push    di                  ; Sauver l'offset pour la passe FG

	; ----------------------------------------------------------
	; ETAPE 1 : PASSE DE FOND (SOLID BACKGROUND)
	; ----------------------------------------------------------
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005          ; Write Mode 0
	out     dx, ax
	mov     ax, 0x0F01          ; Enable Set/Reset (Toutes les planches activées)
	out     dx, ax
	mov     ah, byte .bg_col    ; AH = Couleur de fond
	mov     al, 0x00            ; Index 0 : Set/Reset Register
	out     dx, ax

	; -- Bord Gauche (BG) --
	mov     ah, _left_mask
	mov     al, 0x08
	out     dx, ax              ; Application du Bit Mask
	test    byte [es:di], 0xFF  ; LATCH READ Magique (ne modifie aucun registre)
	mov     byte [es:di], 0xFF  ; WRITE (Remplissage solide contraint par le masque)
	cmp     word _width, 0
	je      .do_fg              ; Si pas d'autres octets, on saute à la passe FG
	inc     di

	; -- Milieu (BG) --
	mov     cx, _width
	dec     cx
	jz      .bg_right
	mov     ax, 0xFF08          ; Masque 100%
	out     dx, ax

	mov     eax, 0xFFFFFFFF     ; Remplissage solide 32 bits
	push    cx
	mov     dx, cx
	shr     cx, 2
	rep     stosd               ; Remplit 4 octets d'un coup
	mov     cx, dx
	and     cx, 3
	rep     stosb               ; Remplit le reste
	pop     cx
	mov     dx, EGAVGA_CONTROLLER

	.bg_right:
	; -- Bord Droit (BG) --
	mov     ah, _right_mask
	mov     al, 0x08
	out     dx, ax
	test    byte [es:di], 0xFF  ; LATCH
	mov     byte [es:di], 0xFF  ; WRITE

	.do_fg:
	; ----------------------------------------------------------
	; ETAPE 2 : PASSE DE FORME (FOREGROUND PATTERN)
	; ----------------------------------------------------------
	pop     di                  ; Retour au début de la ligne
	push    di                  ; Sauvegarde pour la descente Y

	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0305          ; Write Mode 3 (Transforme le Pattern CPU en Masque)
	out     dx, ax
	mov     ah, byte .fg_col    ; AH = Couleur du motif
	mov     al, 0x00            ; Index Set/Reset
	out     dx, ax

	; -- Préparation du Pattern --
	mov     si, bx
	and     si, 7
	add     si, _patofst
	movzx   esi, byte [fs:si]   ; ESI = l'octet de la ligne du pattern
	imul    esi, esi, 0x01010101; ESI = 0xPPPPPPPP (Broadcast sur 32 bits)

	; -- Bord Gauche (FG) --
	mov     ah, _left_mask
	mov     al, 0x08
	out     dx, ax
	test    byte [es:di], 0xFF  ; LATCH
	mov     eax, esi            ; EAX = Pattern complet
	mov     [es:di], al         ; WRITE (En Mode 3, AL = le Pattern de masquage)
	cmp     word _width, 0
	je      .next_line
	inc     di

	; -- Milieu (FG) --
	mov     cx, _width
	dec     cx
	jz      .fg_right
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0xFF08          ; Masque 100%
	out     dx, ax

	; TRICK : On charge le loquet avec la couleur de fond qu'on vient d'écrire
	test    byte [es:di], 0xFF

	mov     eax, esi            ; EAX = 0xPPPPPPPP
	push    cx
	mov     dx, cx
	shr     cx, 2
	rep     stosd               ; Applique le pattern par blocs de 32 pixels !
	mov     cx, dx
	and     cx, 3
	rep     stosb
	pop     cx
	mov     dx, EGAVGA_CONTROLLER

	.fg_right:
	; -- Bord Droit (FG) --
	mov     ah, _right_mask
	mov     al, 0x08
	out     dx, ax
	test    byte [es:di], 0xFF  ; LATCH
	mov     eax, esi
	mov     [es:di], al         ; WRITE

	.next_line:
	pop     di
	add     di, 80              ; VRAM Scanline pitch (+80)
	inc     bx                  ; Y++
	cmp     bx, .y2
	jle     .y_loop

	; --- 5. Reset VGA ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0xFF08          ; Reset Bit Mask
	out     dx, ax
	mov     ax, 0x0005          ; Reset Mode 0
	out     dx, ax
	mov     ax, 0x0001          ; Reset Enable Set/Reset
	out     dx, ax

	call	vga_mouse_show

	pop		fs
	pop     es
	popad
	leave
	; Clean defs
	%undef  .x1
	%undef  .y1
	%undef  .x2
	%undef  .y2
	%undef  .pat_id
	%undef  .fg_col
	%undef  .bg_col
	%undef  _left_mask
	%undef  _right_mask
	%undef  _width
	ret

; ------------------------------------------------------------
; vga_putpixel
%define .x      word [bp+4]
%define .y      word [bp+6]
%define .color  byte [bp+8]
; ------------------------------------------------------------
vga_putpixel:
	push    bp
	mov     bp, sp
	pusha
	push	es

	; 1. Calcul de l'offset (Y * 80 + X / 8) sans IMUL
	mov     ax, .y
	mov     di, ax          ; DI = Y
	shl     di, 6           ; DI = Y * 64
	shl     ax, 4           ; AX = Y * 16
	add     di, ax          ; DI = Y * 80

	mov     cx, .x          ; CX = X
	mov     bx, cx          ; Sauvegarde X pour le masque
	shr     cx, 3           ; CX = X / 8
	add     di, cx          ; DI = Offset final

	; 2. Configuration du contrôleur graphique (Mode d'écriture 2)
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0205h       ; Index 5 : Mode d'écriture 2
	out     dx, ax          ; Ce mode permet d'envoyer la couleur via AL directement

	; 3. Calcul du Bit Mask (7 - (X % 8))
	and     bx, 7           ; BX = X % 8
	mov     ah, 80h         ; Bit 7 à 1
	mov     cl, bl          ; Utilise le reste pour décaler
	shr     ah, cl          ; AH = Masque du pixel
	mov     al, 08h         ; Index 8 : Bit Mask
	out     dx, ax          ; AH contient le masque calculé

	; 4. Écriture du pixel
	mov     ax, SEG_VIDEO
	mov     es, ax

	mov     al, [es:di]     ; LATCH LOAD : Indispensable pour préserver les autres plans
	mov     al, .color      ; AL = Index de couleur (0-15)
	mov     [es:di], al     ; WRITE : Le GPU applique AL là où le Bit Mask est à 1

	; 5. Nettoyage minimal (Reset Mode 0)
	mov     ax, 0005h       ; Index 5 : Mode d'écriture 0
	out     dx, ax
	mov     ax, 0FF08h      ; Index 8 : Reset Bit Mask
	out     dx, ax

	pop     es
	popa
	leave
	; clean defs
	%undef  .x
	%undef  .y
	%undef  .color
	ret

; ------------------------------------------------------------
; GESTION DU CURSEUR
; ------------------------------------------------------------
;
; ------------------------------------------------------------
; gère la demande d'effacement du curseur souris
;
; ------------------------------------------------------------
vga_mouse_hide:
	pushf                   ; Sauver l'état des flags (interrupts)
	cli                     ; Désactiver les interruptions (CRITIQUE)
	pusha 	                ; Sauvegarder TOUS les registres 32-bits
	push    ds

	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax

	; Décrémenter le compteur
	dec     byte [PTR_MOUSE + mouse.cur_counter]

	; Vérifier si on vient juste de passer en mode caché (c-à-d on est à -1)
	cmp     byte [PTR_MOUSE + mouse.cur_counter], -1
	jne     .skip_restore   ; Si on est à -2, -3... elle est déjà cachée

	call    vga_cursor_restorebg

	.skip_restore:
	pop     ds
	popa
	popf                    ; Restaure les interruptions (STI si elles étaient là)
	ret

; ------------------------------------------------------------
; gère la demande d'affichage du curseur souris
;
; ------------------------------------------------------------
vga_mouse_show:
	pushf
	cli
	pusha
	push    ds

	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax

	; Incrémenter le compteur
	inc     byte [PTR_MOUSE + mouse.cur_counter]

	; Vérifier si on est revenu à 0 (Visible)
	cmp     byte [PTR_MOUSE + mouse.cur_counter], 0
	jne     .skip_draw      ; Si on est encore à -1, -2... on reste caché

	; C'est la transition Caché -> Visible : On affiche le curseur
	; IMPORTANT : On sauve le fond ACTUEL (qui a peut-être changé pendant le hide)
	call    vga_cursor_savebg
	call    vga_cursor_draw

	.skip_draw:
	pop     ds
	popa
	popf                ; restore également le flag d'interruption
	ret


; ------------------------------------------------------------
; gère le déplacement du curseur souris
;
; ------------------------------------------------------------
vga_mouse_cursor_move:
	pusha
	push 	ds
	push 	es
	cld

	; BDA Data Segment
	mov		ax, SEG_BDA_CUSTOM
	mov		ds, ax

	cmp     byte [PTR_MOUSE + mouse.cur_counter], 0
	jl      .done       ; Si < 0, on ne dessine rien !

	cmp		byte [PTR_MOUSE + mouse.cur_drawing],0
	jne		.done

	mov 	byte [PTR_MOUSE + mouse.cur_drawing],1

	call 	vga_cursor_restorebg
	call	vga_cursor_savebg
	call 	vga_cursor_draw
	mov 	byte [PTR_MOUSE + mouse.cur_drawing],0
	.done:
	pop 	es
	pop 	ds
	popa
	ret

; Buffer requis : 192 octets (16 lignes * 3 octets * 4 plans)
; ATTENTION : Vérifiez que mouse.bkg_buffer dans bda.asm est assez grand !
vga_cursor_savebg:
	cmp     byte [PTR_MOUSE + mouse.bkg_saved], 0
	jne     .done

	push    es
	mov     ax, SEG_VIDEO
	mov     es, ax
	cld

	; Calculer l'adresse de départ (y * 80 + x / 8)
	mov     cx, [PTR_MOUSE + mouse.x]
	mov     dx, [PTR_MOUSE + mouse.y]
	call    vga_calc_addr   ; Doit retourner DI = offset VRAM
	mov     [PTR_MOUSE + mouse.cur_addr_start], di

	lea     si, [PTR_MOUSE + mouse.bkg_buffer]

	mov     dx, EGAVGA_CONTROLLER      ; Graphics Controller Port
	mov     al, 0x04        ; Read Plane Select Register
	out     dx, al
	inc     dx              ; Point sur Data Port (0x03CF)

	xor     bl, bl          ; BL = Index du plan (0 à 3)
	.plan_loop:
	mov     al, bl
	out     dx, al          ; Sélectionner le plan à lire

	push    di              ; Sauver l'adresse de départ du curseur
	mov     cx, 16          ; 16 lignes
	.row_loop:
	mov     ax, [es:di]     ; Lit 16 pixels (2 octets)
	mov     [ds:si], ax
	mov     al, [es:di+2]   ; Lit le 3eme octet (pour le shift)
	mov     [ds:si+2], al
	add     si, 3
	add     di, 80          ; Ligne suivante (VGA linéaire)
	loop    .row_loop

	pop     di              ; Revenir en haut pour le plan suivant
	inc     bl
	cmp     bl, 4
	jne     .plan_loop

	; Reset Read Map Select to 0 (Nettoyage)
	mov     dx, 0x3CE
	mov     ax, 0x0004
	out     dx, ax

	pop     es
	mov     byte [PTR_MOUSE + mouse.bkg_saved], 1
	.done:
	ret

vga_cursor_restorebg:
	cmp     byte [PTR_MOUSE + mouse.bkg_saved], 0
	je      .done

	push    es
	mov     ax, SEG_VIDEO
	mov     es, ax
	cld

	mov     di, [PTR_MOUSE + mouse.cur_addr_start]
	lea     si, [PTR_MOUSE + mouse.bkg_buffer]

	; Sécurité : S'assurer que ES pointe bien vers la vidéo pour le restore
	mov     ax, SEG_VIDEO
	mov     es, ax

	; Sécurité : Réinitialiser le contrôleur graphique pour l'écriture CPU brute
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005          ; Mode 0
	out     dx, ax
	mov     ax, 0x0001          ; Enable Set/Reset = 0 (Important !)
	out     dx, ax
	mov     ax, 0xFF08          ; Bit Mask = 0xFF
	out     dx, ax
	mov     ax, 0x0003          ; Function = Replace
	out     dx, ax

	mov     dx, VGA_SEQUENCER   ; Sequencer Port
	mov     al, 0x02        	; Map Mask Register
	out     dx, al
	inc     dx              	; Data Port (0x03C5)

	mov     bl, 1           	; Mask initial : Plan 0 (0001b)
	.plan_loop:
	mov     al, bl
	out     dx, al          	; Activer l'écriture uniquement sur ce plan

	push    di
	mov     cx, 16
	.row_loop:
	lodsw                   	; Lit 2 octets
	mov     [es:di], ax
	lodsb                   	; Lit le 3eme octet
	mov     [es:di+2], al
	add     di, 80
	loop    .row_loop

	pop     di
	shl     bl, 1           	; Plan suivant (1 -> 2 -> 4 -> 8)
	cmp     bl, 16          	; Fini après le plan 3 (8)
	jne     .plan_loop

	; Rétablir le Map Mask sur tous les plans (0x0F)
	mov     dx, VGA_SEQUENCER
	mov     ax, 0x0F02
	out     dx, ax

	pop     es
	mov     byte [PTR_MOUSE + mouse.bkg_saved], 0
	.done:
	ret

; ============================================================
; vga_cursor_draw
; Détruit: registres sauvegardés/restaurés (PUSHAD/POPAD)
; ============================================================
%define     BYTES_SHIFT     3
vga_cursor_draw:
	push    bp
	mov     bp, sp
	; local variables
	%define .height     word [bp-2]
	%define .bit_ofs    word [bp-4]
	%define .mask       dword [bp-6]
	sub     sp, 8           	; [bp-2]: height, [bp-4]: x_bit_offset

	pushad
	push    ds
	push    es
	push	gs
	cld                             ; Sécurité : Direction avant

	mov     ax, SEG_BDA_CUSTOM
	mov     ds, ax
	mov     ax, SEG_VIDEO
	mov     es, ax

	; --- CLIPPING VERTICAL ---
	mov     dx, [PTR_MOUSE + mouse.y]
	mov		bx, GFX_HEIGHT
	cmp		dx, bx
	jae		.exit_total

	mov     ax, 16
	sub     bx, dx
	cmp     ax, bx
	jbe     .y_ok

	mov     ax, bx
	.y_ok:
	mov     .height, ax

	; --- CLIPPING HORIZONTAL ---
	; On calcule si les 4 octets vont dépasser la ligne (80 octets)
	; X est en bits (0-639). X >> 3 donne l'octet de départ (0-79).
	; Si StartByte >= 77, on déborde.

	mov     cx, [PTR_MOUSE + mouse.x]
	shr     cx, 3                   ; CX = Byte Offset (0-79)
	xor     eax, eax                ; ESI = Masque de protection (0 = tout dessiner)

	cmp     cx, 76                  ; 76 est le dernier offset sûr (76,77,78,79)
	jbe     .mask_ready             ; Si <= 76, pas de débordement

	; Calcul du débordement
	; Si CX=77 (Déborde 1 byte) -> Masque 0x000000FF (LSB car bswap)
	; Si CX=78 (Déborde 2 bytes)-> Masque 0x0000FFFF
	; Si CX=79 (Déborde 3 bytes)-> Masque 0x00FFFFFF
	cmp     cx, 77
	jne     .check_78
	mov     eax, 0x000000FF
	jmp     .mask_ready

	.check_78:
	cmp     cx, 78
	jne     .check_79
	mov     eax, 0x0000FFFF
	jmp     .mask_ready

	.check_79:
	mov     eax, 0x00FFFFFF         ; Cas extrême (bord droit)

	.mask_ready:
	mov     .mask, eax

	; --- Calcul Adresse et Shift ---
	mov     ax, [PTR_MOUSE + mouse.x]
	mov		cx, ax
	and     ax, 7           	; Reste (0-7) = décalage de bit
	mov     .bit_ofs, ax
	call    vga_calc_addr   	; DI = VRAM Offset

	; --- CONFIG VGA (Write Mode 0, Logic Ops) ---
	mov     dx, VGA_SEQUENCER
	mov     ax, 0x0F02      	; Map Mask = All planes
	out     dx, ax

	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0005      	; Mode 0
	out     dx, ax
	mov     ax, 0x0001      	; Enable Set/Reset = 0 (CPU Data)
	out     dx, ax
	mov     ax, 0xFF08      	; Bit Mask = 0xFF
	out     dx, ax

	; Source du Sprite -> (GS:SI)
	mov     ax, [PTR_MOUSE + mouse.cur_seg]
	mov     gs, ax
	mov     si, [PTR_MOUSE + mouse.cur_ofs]

	.row_loop:
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0803          ; Data Rotate/Function Select: AND (bits 3-4 = 01b)
	out     dx, ax

	; --- PASSE 1 : MASQUE AND (Effacement du fond) ---
	mov     ax, [gs:si]         ; Charger 16 pixels (0=curseur, 1=fond)
	shl     eax, 16             ; décalage de AX vers le poid for: XXXX0000
	mov     ax, 0xFFFF
	mov     cx, .bit_ofs
	ror     eax, cl             ; Décaler : 1 là où on veut effacer (0 ailleurs)
	or      eax, .mask          ; Appliquer le masque de clipping à droite


	mov     ebx, eax            ; EBX contient le masque AND sur 3 octets
	mov     cx, BYTES_SHIFT     ; Appliquer sur 3 octets (24 pixels potentiels)
	.block_AND:
		mov     al, [es:di]     ; Charger les latches VGA
		rol     ebx, 8          ; Extraire l'octet suivant (poids fort d'abord)
		mov     al, bl
		stosb                   ; Écrire et DI++
	loop    .block_AND
	sub     di, BYTES_SHIFT     ; Revenir au début de la ligne pour le XOR

	mov     ax, 0x1803          ; Data Rotate/Function Select: XOR (bits 3-4 = 11b)
	out     dx, ax

	; --- PASSE 2 : MASQUE XOR (Dessin du curseur) ---
	xor     eax, eax
	mov     ax, [gs:si+32]      ; Charger 16 pixels (1=blanc, 0=transparent)
	movzx   eax, ax             ; S'assurer que le reste est à 0
	shl     eax, 16             ; Aligner
	mov     cx, .bit_ofs
	shr     eax, cl             ; Décaler (les bits de padding restent à 0)
	mov     ebx, .mask          ; Appliquer le masque de clipping à droite
	not     ebx
	and     eax, ebx            ; Appliquer le masque de clipping à droite

	mov     ebx, eax            ; EBX contient le masque XOR sur 3 octets
	mov     cx, BYTES_SHIFT
	.block_XOR:
		mov     al, [es:di]     ; Charger les latches
		rol     ebx, 8
		mov     al, bl
		stosb
	loop    .block_XOR

	; --- NEXT ROW ---
	add     di, 80 - BYTES_SHIFT        ; Ligne suivante en VRAM (80 octets/ligne)
	add     si, 2
	dec     word .height
	jnz     .row_loop

	; --- RESTORE VGA ---
	mov     dx, EGAVGA_CONTROLLER
	mov     ax, 0x0003      	; Function = Replace
	out     dx, ax
	mov     ax, 0xFF08      	; Bit Mask = 0xFF
	out     dx, ax
	mov     ax, 0x0001      	; Enable Set/Reset = 0
	out     dx, ax

	.exit_total:
	pop		gs
	pop     es
	pop     ds
	popad
	leave
	%undef  .height
	%undef  .bit_ofs
	%undef  .mask
	ret
