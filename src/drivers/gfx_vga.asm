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
%define VIDEO_SEG    	0A000h

%define GFX_MODE		0x12			; VGA HiRes (640x480x16)
%define GFX_WIDTH		640
%define GFX_HEIGHT		480
%define GFX_OFFSET      80
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
	dw vga_init                 ; init de la carte graphique
	dw vga_putpixel             ; dessin d'un pixel
	dw vga_none                 ; lecture d'un pixel
	dw vga_set_charpos          ; gotoxy
	dw vga_set_writemode        ; mode texte
	dw vga_putc                 ; dessin d'un caractère
	dw vga_write                ; dessin d'une chaine de caractère
	dw vga_none                 ; dessin d'une ligne (Bresenham) avec décision horizontale/verticale
	dw vga_none                 ; dessin d'un rectangle
	dw vga_none                 ; dessin d'un rectangle plein
	dw vga_none                 ; dessin d'un rectangle arrondi
	dw vga_mouse_hide           ; cache la souris
	dw vga_mouse_show           ; montre la souris
	dw vga_mouse_cursor_move    ; déplacement du curseur

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

; Entrée: ESI = Pointeur vers le tableau de 8 octets (pattern 8x8)
;         BL  = Couleur de premier plan (0-15)
vga_background:
;    pushad

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
    mov 	ax, VIDEO_SEG
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
;    popad
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
; --- Définition des arguments ---
%define .mode   word [bp+4]
vga_set_writemode:
	push    bp
	mov     bp, sp

	push    fs
	push    ax
	mov     ax, BDA_CUSTOM_SEG
	mov     fs,ax

	mov     ax, .mode

	mov     byte [fs:PTR_GFX + gfx.cur_mode], al

	pop     ax
	pop     fs
	leave
	ret
%undef      .mode

; ---------------------------------------------------------------------------
; gfx_set_charpos (x,y)
; In : CX = x (pixels), DX = y (pixels)
; Out: variables DS:GFX_CUR_*
; Notes:
;  - calcule l'offset VRAM de la scanline y: base = (y&1?2000:0) + (y>>1)*80 + (x>>3)
;  - stocke aussi shift = x&7
; ---------------------------------------------------------------------------
; --- Définition des arguments ---
%define .x     word [bp+4]
%define .y     word [bp+6]
vga_set_charpos:
	push    bp
	mov     bp, sp

	pusha
	push    fs

	mov     ax,BDA_CUSTOM_SEG
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

    mov     [fs:PTR_GFX + gfx.cur_offset], bx
	pop     fs

    popa
	leave
	ret
; clean defs
%undef  .x
%undef  .y

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

; --- Définition des arguments ---
%define .car    word [bp+4]
vga_putc:
	push    bp
	mov     bp, sp
	; --- Définition des variables locales ---
	%define .cpt    word [bp-2]
    sub     sp, 2               ; 1 word variable locale

	pusha
	push    fs
	push    es

	call    vga_mouse_hide      ; Protection souris

	mov     bx, VIDEO_SEG
	mov     es, bx
	mov     bx, BDA_CUSTOM_SEG
	mov     fs, bx

	mov     ax, .car
	call    get_glyph_offset

	; Base offset VRAM pour la scanline Y
	mov     di, [fs:PTR_GFX + gfx.cur_offset]
	mov     ch, [fs:PTR_GFX + gfx.cur_mode]
	mov     cl, [fs:PTR_GFX + gfx.cur_shift]
    mov     bx, GFX_OFFSET

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
	mov     dx, ax

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
	; add     di,CGA_STRIDE

	dec     .cpt
	jnz     .row_loop

	; Avancer curseur d'un caractère (8 pixels)
	inc     word [fs:PTR_GFX + gfx.cur_offset]
	add     word [fs:PTR_GFX + gfx.cur_x], 8

	call    vga_mouse_show      ; Restauration souris

	pop     es
	pop     fs
	popa
	leave
	ret
%undef      .car
%undef      .cpt

;
; write string from [DS:SI] to screen
;
; --- Définition des arguments ---
%define .txt_seg   word [bp+4]
%define .txt_ofs   word [bp+6]
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
	jmp     .loops

	.done:
	pop     ds
	pop     ax
	leave
	ret
%undef  .txt_seg
%undef  .txt_ofs


; Entrée: AX = X (0-639), BX = Y (0-479), CL = Couleur (0-15)
%define .x      word [bp+4]
%define .y      word [bp+6]
%define .color  byte [bp+8]
vga_putpixel:
	push    bp
	mov     bp, sp
	pusha

	mov		bx, .y
	mov		ax, .x
	mov		cl, .color
	; Calcul de l'offset (Y * 80 + X/8)

	imul 	di, bx, 80  	; DI = Y * 80
	mov 	bx, ax        	; Sauvegarde X
	shr 	ax, 3          	; AX = X / 8
	add 	di, ax         	; DI = Offset final

	; Calcul du masque de bit (7 - (X % 8))
	and 	bx, 7           ; BX = X % 8
	mov 	ah, 80h         ; Bit 7 à 1
	shr 	ah, cl          ; Décale pour pointer le bon pixel (cl = bx ici)
	; Note: en pratique on utilise souvent une table de pré-calcul pour shr ah, bl

	; Programmation du Graphics Controller
	mov 	dx, EGAVGA_CONTROLLER

	; Sélection du Bit Mask (Index 8)
	mov 	al, 08h
	out 	dx, ax          ; AH contient le masque calculé

	; Sélection du Set/Reset (Couleur, Index 0)
	mov 	ax, 0000h
	mov 	al, 00h
	mov 	ah, cl          ; Couleur
	out 	dx, ax

	; Enable Set/Reset (On active les 4 plans, Index 1)
	mov 	ax, 0F01h
	out 	dx, ax

	; 4. Écriture (Nécessite une lecture préalable pour charger les Latches)
	mov 	ax, VIDEO_SEG
	mov 	es, ax
	mov 	al, [es:di]     ; Lecture bidon pour charger les verrous (latches)
	mov 	[es:di], al     ; L'écriture applique la couleur via le matériel

	; Reset des registres pour ne pas casser le reste du dessin
	mov 	ax, 0FF08h
	out 	dx, ax
	mov 	ax, 0001h
	out 	dx, ax

	popa
	leave
	ret
; clean defs
%undef  .x
%undef  .y
%undef  .color


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

	mov     ax, BDA_CUSTOM_SEG
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

	mov     ax, BDA_CUSTOM_SEG
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

	; BDA Data Segment
	mov		ax, BDA_CUSTOM_SEG
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
    mov     ax, VIDEO_SEG
    mov     es, ax

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
    mov     ax, VIDEO_SEG
    mov     es, ax

    mov     di, [PTR_MOUSE + mouse.cur_addr_start]
    lea     si, [PTR_MOUSE + mouse.bkg_buffer]

    ; Sécurité : S'assurer que ES pointe bien vers la vidéo pour le restore
    mov     ax, VIDEO_SEG
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
; Détruit: registres sauvegardés/restaurés (PUSHA/POPA)
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
    ; Note: pushad sauvegarde déjà tous les registres généraux (EAX...EDI)

	cld                             ; Sécurité : Direction avant
	mov     ax, BDA_CUSTOM_SEG
	mov     ds, ax
    mov     ax, VIDEO_SEG
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

