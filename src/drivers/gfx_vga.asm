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
%define MOUSE_DRAW		14

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
	dw vga_none                 ; gotoxy
	dw vga_none                 ; mode texte
	dw vga_none                 ; dessin d'un caractère
	dw vga_none                 ; dessin d'une chaine de caractère
	dw vga_none                 ; dessin d'une ligne (Bresenham) avec décision horizontale/verticale
	dw vga_none                 ; dessin d'un rectangle
	dw vga_none                 ; dessin d'un rectangle plein
	dw vga_none                 ; dessin d'un rectangle arrondi
	dw vga_mouse_hide           ; cache la souris
	dw vga_mouse_show           ; montre la souris
	dw vga_mouse_cursor_move    ; déplacement du curseur
	dw vga_cursor_draw

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
; ce mode est entrelacé, un bit/pixel, 8 pixels par octet
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
	ISADBG	ISA_GREEN, 0x88
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
    mov 	ecx, 480

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
	dec     byte [BDA_MOUSE + mouse.cur_counter]

	; Vérifier si on vient juste de passer en mode caché (c-à-d on est à -1)
	cmp     byte [BDA_MOUSE + mouse.cur_counter], -1
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
	inc     byte [BDA_MOUSE + mouse.cur_counter]

	; Vérifier si on est revenu à 0 (Visible)
	cmp     byte [BDA_MOUSE + mouse.cur_counter], 0
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

	cmp     byte [BDA_MOUSE + mouse.cur_counter], 0
	jl      .done       ; Si < 0, on ne dessine rien !

	cmp		byte [BDA_MOUSE + mouse.cur_drawing],0
	jne		.done

	mov 	byte [BDA_MOUSE + mouse.cur_drawing],1

	call 	vga_cursor_restorebg
	call	vga_cursor_savebg
	call 	vga_cursor_draw
	mov 	byte [BDA_MOUSE + mouse.cur_drawing],0
	.done:
	pop 	es
	pop 	ds
	popa
	ret

; Buffer requis : 192 octets (16 lignes * 3 octets * 4 plans)
; ATTENTION : Vérifiez que mouse.bkg_buffer dans bda.asm est assez grand !
vga_cursor_savebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    jne     .done

    push    es
    mov     ax, VIDEO_SEG
    mov     es, ax

    ; Calculer l'adresse de départ (y * 80 + x / 8)
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]
    call    vga_calc_addr   ; Doit retourner DI = offset VRAM
    mov     [BDA_MOUSE + mouse.cur_addr_start], di

    lea     si, [BDA_MOUSE + mouse.bkg_buffer]

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
    mov     byte [BDA_MOUSE + mouse.bkg_saved], 1
	.done:
    ret

vga_cursor_restorebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    je      .done

    push    es
    mov     ax, VIDEO_SEG
    mov     es, ax

    mov     di, [BDA_MOUSE + mouse.cur_addr_start]
    lea     si, [BDA_MOUSE + mouse.bkg_buffer]

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
    mov     byte [BDA_MOUSE + mouse.bkg_saved], 0
	.done:
    ret

; ============================================================
; vga_cursor_draw
; Détruit: registres sauvegardés/restaurés (PUSHA/POPA)
; ============================================================
vga_cursor_draw:
    push    bp
    mov     bp, sp
    sub     sp, 4           	; [bp-2]: height, [bp-4]: x_bit_offset
	; local variables
	%define .height 	word [bp-2]
	%define .bit_ofs   	word [bp-4]

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
    mov     dx, [BDA_MOUSE + mouse.y]
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

    ; --- Calcul Adresse et Shift ---
    mov     ax, [BDA_MOUSE + mouse.x]
	mov		cx, ax
    and     ax, 7           	; Reste (0-7) = décalage de bit
    mov     .bit_ofs, ax
    call    vga_calc_addr   	; DI = VRAM Offset

    ; --- CONFIG VGA (Write Mode 0, Logic Ops) ---
    mov     dx, VGA_SEQUENCER
    mov     ax, 0x0F02      	; Map Mask = All planes
    out     dx, ax

    mov     dx, 0x3CE       	; Graphics Controller
    mov     ax, 0x0005      	; Mode 0
    out     dx, ax
    mov     ax, 0x0001      	; Enable Set/Reset = 0 (CPU Data)
    out     dx, ax
    mov     ax, 0xFF08      	; Bit Mask = 0xFF
    out     dx, ax

    ; Source du Sprite -> (GS:SI)
    mov     ax, [BDA_MOUSE + mouse.cur_seg]
    mov     gs, ax
    mov     si, [BDA_MOUSE + mouse.cur_ofs]

	.row_loop:
    ; --- PREPARE MASKS ---
    ; On récupère le masque de l'image (AND) et du curseur (XOR)
    mov     ax, [gs:si]         ; AX = AND Mask (16 bits)
    xchg    al, ah              ; Souvent nécessaire selon l'endianness du sprite
    xor     ebx, ebx
    mov     bx, ax
    not     ebx                 ; On veut des 1 partout sauf là où le curseur est présent

    ; Décalage pour l'alignement au pixel près
    mov     cx, .bit_ofs
    ror     ebx, cl             ; Rotation pour ne pas perdre de bits

    ; --- CONFIG VGA POUR AND ---
    mov     dx, 0x3CE
    mov     ax, 0x0803          ; Data Rotate/Function Select: AND (bits 3-4 = 01b)
    out     dx, ax

    ; Application sur 3 octets (pour couvrir les 16 pixels + le shift)
    %rep 3
        mov     al, [es:di]     ; CHARGE LES LATCHES (Indispensable)
        mov     eax, ebx
        shr     eax, 16         ; Récupère la partie haute (si 32-bit shift utilisé)
        stosb                   ; Écrit AL et DI++ (Applique le AND sur les 4 plans)
    %endrep
    sub     di, 3               ; Revient au début de la ligne pour le XOR

    ; --- CONFIG VGA POUR XOR ---
    mov     ax, 0x1803          ; Data Rotate/Function Select: XOR (bits 3-4 = 11b)
    out     dx, ax

    ; Récupération du masque XOR (la forme blanche/noire du curseur)
    mov     ax, [gs:si+32]
    ; ... (Appliquer le même décalage et stosb que pour le AND) ...

    ; --- NEXT ROW ---
    add     di, 80 - 3          ; Ligne suivante (80 octets par ligne)
    add     si, 2
    dec     word .height
    jnz     .row_loop

    ; --- RESTORE VGA ---
    mov     dx, 0x3CE
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
    ret
%undef  .height
%undef  .mask
