; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : generic.asm
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

; ---------------------------------------------------------------------------
; Détection les ROM supplementaires
; Teste la RAM de 0xC000 jusqu’à 0xE000, par pas de 2KB.
;
; Si une ROM est détectée, le code de la ROM sera appelé.
; ---------------------------------------------------------------------------
setup_load_rom:
	mov 	bx, 0xC000

	.scanloop:
	mov 	ds, bx
	cmp		word[0x0000],0xAA55	; ROM signature
	jne		.norom

	; appel le code (en 0x0003) de la ROM
	push 	cs
	push 	word .norom			; address de retour

	push	ds
	push 	0x0003
	retf						; call far ds:0x0003
	.norom:
	add		bx, 0x80			; add 2kb
	cmp 	bx, 0xE000
	jbe 	.scanloop
	.end:
	ret

; ---------------------------------------------------------------------------
; Test si le vecteur INT 10h à été modifié (par la ROM)
;
; Si le vecteur n'a pas été modifiée, on considère que la ROM video n'a pas
; été chargée.
; ---------------------------------------------------------------------------
setup_check_vga:
	; vérification de l'offset 0x0000:0x0040 qui DOIT etre différent de @default_isr
	xor		ax,ax
	mov		es,ax
	; Lire INT10: offset+segment depuis 0000:0040
	mov	 	bx, [es:0x0040] 		; BX = offset INT10
	mov 	cx, [es:0x0042] 		; CX = segment INT10
	mov		ax, cs

	; Comparer avec default_isr (offset) et CS (segment)
	mov		dx, default_isr 		; DX = offset default_isr (dans notre CS)
	cmp 	bx, dx
	jne 	.init_ok	; vecteur different, bios initialisé
	cmp 	cx, ax
	jne 	.init_ok

	mov		ax,cs			; vecteur identique, sans doute pas d'initialisation
	mov		ds,ax
	.init_ok:
	ret

; ---------------------------------------------------------------------------
; IVT install (8088, mode réel) - remplit les 256 vecteurs avec un handler IRET
; ---------------------------------------------------------------------------
ivt_setup:
	; installation de la table d'interrupts
	xor 	ax, ax
	mov 	es, ax	 	; ES = 0000h -> base IVT
	xor 	di, di	 	; DI = 0000h -> offset IVT

	mov 	ax, default_isr   	; offset du handler
	mov 	dx, cs	  ; segment du handler (ROM)

	mov 	cx, 256	 ; 256 vecteurs

	.fill:
	stosw     				  ; write offset (AX)  -> [ES:DI], DI += 2
	xchg 	ax, dx  	          ; AX = segment, DX = offset
	stosw          	        ; write segment (AX) -> [ES:DI], DI += 2
	xchg 	ax, dx        		  ; AX = offset, DX = segment
	loop 	.fill
	; fin de la table d'interrupt
	ret

; ---------------------------------------------------------------------------
; IVT install (8088, mode réel) - installe un handler a une interrupt calculée
;
; ax = int id
; dx = segment handler
; bx = offset handler
; ---------------------------------------------------------------------------
ivt_setvector:
	push	es
	push	di

	shl		ax,2			; ax=id *4
	mov		di,ax

	xor		ax,ax
	mov 	es, ax	 	; ES = 0000h -> base IVT

	mov 	ax, bx		; offset du handler
	cli
	stosw     				  ; write offset (AX)  -> [ES:DI], DI += 2
	xchg 	ax, dx  	          ; AX = segment, DX = offset
	stosw          	        ; write segment (AX) -> [ES:DI], DI += 2
	sti

	pop		di
	pop		es
	ret

io_wait:
	xor		al,al
	out		0x80,al
	ret

; ---------------------------------------------------------------------------
; Initialise les PIC 8259 (PC/AT):
; - Master offset 0x08
; - Slave  offset 0x70
; - Cascade: IRQ2
; https://wiki.nox-rhea.org/back2root/ibm-pc-ms-dos/hardware/8259
; ---------------------------------------------------------------------------
pic_init:
	cli
	push 	ax

	; force un End Of Interrupt sur les 2 PIC
	mov 	al, 0x20
	out 	i8259_SLAVE_CMD, al        ; EOI PIC esclave
	out 	i8259_MASTER_CMD, al       ; EOI PIC maître

	; starts the initialization sequence (in cascade mode)
	mov 	al, ICW1_INIT | ICW1_ICW4
	out 	i8259_MASTER_CMD, al
	out 	i8259_SLAVE_CMD, al

	mov		 			al, i8259_MASTER_INT
	out 	i8259_MASTER_DATA, al	; ICW2: Master PIC vector offset
	mov 	al, i8259_SLAVE_INT
	out 	i8259_SLAVE_DATA, al	; ICW2: Slave PIC vector offset

	; Master: cascade (IRQ2 => 1 << IRQ2  = 0x04)
	mov 	al, 0x04       			 	; master: slave on IRQ2: 0100b
	out 	i8259_MASTER_DATA, al	; ICW3: tell Master PIC that there is a slave PIC at IRQ2

	; Slave: numéro de ligne sur master (2)
	mov 	al, 0x02        	; slave: cascade identity 2
	out 	i8259_SLAVE_DATA, al	; ICW3: tell Slave PIC its cascade identity (0000 0010)

	; ICW4: 8086 mode
	mov 	al, ICW4_8086
	out 	i8259_MASTER_DATA, al
	out 	i8259_SLAVE_DATA, al

	pop 	ax
	ret

; ------------------------------------------------------------------
; set_irq_mask
; AH = 0 (Enable/Unmask) ou 1 (Disable/Mask)
; AL = Numéro de l'IRQ (0 à 15)
; ------------------------------------------------------------------
pic_set_irq_mask:
	pusha

	mov     cl, al          ; CL = numéro d'IRQ
	; Par défaut, PIC Maître (Data port)
	mov     dx, i8259_MASTER_DATA

	cmp     cl, 8
	jl      .is_master

	; Si IRQ >= 8, on passe sur le PIC Esclave
	sub     cl, 8           ; Ajuste l'index du bit (8-15 -> 0-7)
	; Port Data du PIC Esclave
	mov     dx, i8259_SLAVE_DATA

.is_master:
	; Préparation du masque de bit
	mov     bl, 1
	shl     bl, cl          ; BL contient maintenant le bit correspondant (ex: IRQ 3 -> 00001000)

	in      al, dx          ; Lire l'IMR actuel depuis le port (0x21 ou 0xA1)

	test    ah, ah          ; AH est-il à 1 (Disable) ?
	jnz     .do_disable

	.do_enable:
	not     bl	  			; Inverser le masque (ex: 11110111)
	and     al, bl          ; Mettre le bit à 0 (Unmask)
	jmp     .write_back

	.do_disable:
	or      al, bl          ; Mettre le bit à 1 (Mask)

	.write_back:
	out     dx, al          ; Écrire le nouveau masque dans l'IMR

	popa
	ret

; ---------------------------------------------------------------------------
; Handler par défaut: fait juste IRET
; IMPORTANT: doit être FAR (appelé par le CPU via IVT), et terminer par IRET
; ---------------------------------------------------------------------------
default_isr:
	iret

