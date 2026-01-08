;
;
;
;
BITS			16
org				0

;
; configuration du bios
;
%define DEBUG_PORT		0xe9								; 0x402 ou 0xe9

%define VIDEO_SEG    	0xB800        			; ou 0xB000
%define VIDEO_ATTR   	0x07

; initial stack 
%define STACK_SEG   	0x0030
%define STACK_TOP    	0x0100        			; choix commun en RAM basse (pile descend)

%define MEM_SEG_DEB		0x0800 						  ; 0x0800:0000 = 0x8000 (32KB) évite IVT/BDA + stack 7C00
%define MEM_SEG_END   0xA000    					; 0xA000:0000 = 0xA0000 (début zone vidéo)
%define MEM_SEG_STEP  0x0040    					; 1KB = 0x400 bytes = 0x40 paragraphs

; definition du BDA
%include 		".\bda.asm"


						jmp				reset

%include 		".\drivers\debug.asm"
%include		".\drivers\gfx_cgam.asm"
%include		".\drivers\mouse_ps2.asm"

err_novga		db 				'No VGA Card BIOS',0
err_vganok	db				'VGA Not Initialized',0
err_end			db				'code completed successfully',0

reset:
						cli
						; il n'existe aucun 'stack' par défaut
						mov				ax, STACK_SEG
						mov 			ss, ax
						mov 			sp, STACK_TOP     	; haut du segment, mot-aligné
						
						; detection de la mémoire totale
						call			setup_ram
						; modification du stack en "haut" de la RAM
						mov 			ax, dx
						sub 			ax, 0x0400       ; réserver les 16 dernier KB 
						mov 			ss, ax
						mov 			sp, 0x1000       ; sommet de pile
						
						; installé une table d'interruption "dummy"
						call 			setup_ivt
						sti

						; load other Rom
						call 			setup_load_rom
						
						; on vérifie que le BIOS VGA a installer l'INT 10h
						call			setup_check_vga
						
						call			gfx_init
						
						call			mouse_init
						
						mov				ax,cs
						mov				ds,ax

						mov				si, err_end
						call			debug_puts
											
endless:		nop
						jmp				endless
						
; ---------------------------------------------------------------------------
; Détection les ROM supplementaires
; Teste la RAM de 0xC000 jusqu’à 0xE000, par pas de 2KB.
;
; Si une ROM est détectée, le code de la ROM sera appelé.
; ---------------------------------------------------------------------------	
setup_check_vga:
						; vérification de l'offset 0x0000:0x0040 qui DOIT etre différent de @default_isr
						xor				ax,ax
						mov				es,ax
						; Lire INT10: offset+segment depuis 0000:0040
						mov 			bx, [es:0x0040] 		; BX = offset INT10
						mov 			cx, [es:0x0042] 		; CX = segment INT10
						mov				ax, cs
						
						; Comparer avec default_isr (offset) et CS (segment)
						mov 			dx, default_isr 		; DX = offset default_isr (dans notre CS)
						cmp 			bx, dx
						jne 			.init_ok						; interrupt different
						cmp 			cx, ax
						jne 			.init_ok
						
						; no VGA init
						mov				ax,cs
						mov				ds,ax

						mov				si, err_vganok
						call			debug_puts
.init_ok:
						ret						
						
; ---------------------------------------------------------------------------
; Détection les ROM supplementaires
; Teste la RAM de 0xC000 jusqu’à 0xE000, par pas de 2KB.
;
; Si une ROM est détectée, le code de la ROM sera appelé.
; ---------------------------------------------------------------------------						
setup_load_rom:						
						mov 			bx, 0xC000
						mov				al,'*'
.scanloop:
						mov 			ds, bx
						cmp				word[0x0000],0xAA55	; ROM signature
						jne				.norom
						
						; Debug
						mov				al,'.'
						call 			debug_putc
						
						; appel le code (en 0x0003) de la ROM
						push 			cs
						push 			word .norom					; address de retour
						
						push			ds
						push 			0x0003
						retf													; call far ds:0x0003
.norom:
						add				bx, 0x80						; add 2kb
						cmp 			bx, 0xE000
						jbe 			.scanloop
						
						cmp				al,'.'
						je				.end
						; no rom found :
						mov				bx,cs
						mov				ds,bx

						mov				si, err_novga
						call			debug_puts
.end:						
						ret

; ---------------------------------------------------------------------------
; Détection RAM conventionnelle (8088, BIOS maison) — sans BIOS
; Teste la RAM de MEM_SEG_DEB jusqu’à 0xA000 (640KB), par pas de 1KB.
; Méthode: sauvegarde 1 mot, écrit 2 patterns, relit, restaure.
;
; Résultats:
;   AX = taille détectée en Ko (KB) à partir de 0 jusqu’au “top conventionnel”
;   DX = top_segment (segment du premier Ko NON valide)  (optionnel)
;
; Précautions:
; - Ne testez PAS une zone où se trouve votre pile / variables.
; - Si votre pile est à 0000:7C00 (phys 0x7C00), commencez au moins à 0x0800.
; - Ne testez pas au-delà de 0xA000 (début VGA/vidéo).
; ---------------------------------------------------------------------------
setup_ram:
						xor 				ax, ax            ; AX = compteur KB trouvés
						mov 				dx, MEM_SEG_DEB 	; DX = segment courant testé
						mov 				cx, MEM_SEG_END   ; CX = segment fin (exclu)
						xor 				di, di            ; tester au début du bloc 1KB: ES:0000

.loop_seg:
						cmp 				dx, cx
						jae 				.done
						mov 				es, dx

						; sauvegarder le mot existant
						mov 				bx, [es:di]

						; pattern 1
						mov 				word [es:di], 0x55AA
						cmp 				word [es:di], 0x55AA
						jne 				.fail_restore

						; pattern 2 (inverse)
						mov 				word [es:di], 0xAA55
						cmp 				word [es:di], 0xAA55
						jne 				.fail_restore

						; restaurer
						mov 				[es:di], bx

						; OK: avancer d’1KB
						inc 				ax                     ; +1KB valide
						add 				dx, MEM_SEG_STEP
						jmp 				.loop_seg

.fail_restore:
						; restaurer avant de sortir
						mov [es:di], bx

.done:
						; AX contient le nb de KB valides *à partir de MEM_SEG_DEB*.
						; Si vous voulez une taille “depuis 0KB”, ajoutez MEM_SEG_DEB*16/1024 = MEM_SEG_DEB/64.
						;
						; base_kb = MEM_SEG_DEB / 0x0040 (car 1KB = 0x40 segments)
						mov 				bx, MEM_SEG_DEB
						shr 				bx, 6                 ; /64 = /0x40  => KB de base
						add 				ax, bx                ; AX = taille conventionnelle totale en KB (approx. 0..640)
						; DX = segment du premier bloc NON valide (top)
						; DX est déjà positionné (segment courant)
						
						; stocker l'information dans le BDA
						mov 				bx, BDA_SEGMENT
						mov 				ds, bx
						mov 				[BDA_INFO_MEM_SIZE], ax 
						mov					[BDA_INFO_MEM_SEG],dx
						
						ret


; ---------------------------------------------------------------------------
; IVT install (8088, mode réel) - remplit les 256 vecteurs avec un handler IRET
; Hypothèses:
; - code en ROM (CS typiquement = 0xF000), handler réside dans ce même segment
; - interruptions désactivées (CLI) pendant l'installation
; ---------------------------------------------------------------------------
setup_ivt:
						; installation de la table d'interrupts
						xor 			ax, ax
						mov 			es, ax             	; ES = 0000h -> base IVT
						xor 			di, di             	; DI = 0000h -> offset IVT

						mov 			ax, default_isr   	; offset du handler
						mov 			dx, cs              ; segment du handler (ROM)

						mov 			cx, 256             ; 256 vecteurs
.fill:
						stosw     			              ; write offset (AX)  -> [ES:DI], DI += 2
						xchg 			ax, dx  	          ; AX = segment, DX = offset
						stosw          				        ; write segment (AX) -> [ES:DI], DI += 2
						xchg 			ax, dx        		  ; AX = offset, DX = segment
						loop 			.fill
						; fin de la table d'interrupt
						ret

; ---------------------------------------------------------------------------
; Handler par défaut: fait juste IRET
; IMPORTANT: doit être FAR (appelé par le CPU via IVT), et terminer par IRET
; ---------------------------------------------------------------------------
default_isr:
						iret

; ------------------------------------------------------------------
; Padding jusqu'au reset vector
; ------------------------------------------------------------------
times 0xFFF0 - ($ - $$) db 0xFF

; ------------------------------------------------------------------
; RESET VECTOR (exécuté par le CPU)
; ------------------------------------------------------------------
reset_vector:
						jmp far 	0xF000:reset
builddate 	db 				'06/01/2026',0

