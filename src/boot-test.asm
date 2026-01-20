; Compilation: nasm -f bin bios.asm -o bios.bin
; Taille: 64 KB

BITS 16

section .text
org 0x0000

%define     BIOS_DATA_SEG       0x0050

; ------------------------------------------------------------------
; POINT D'ENTRÉE DU BIOS (Cible du jump du reset vector)
; ------------------------------------------------------------------
start:
            cli
            cld
            xor       ax, ax
            mov       ds, ax
            mov       es, ax
            mov       ss, ax
            mov       sp, 0x7000

            ; Créer une table "cohérente" de handler
            call      setup_ivt

            ; Initialisation du PIC (Indispensable pour IRQ0/IRQ1)
            mov       al, 0x11
            out       0x20, al
            out       0xA0, al
            mov       al, 0x08        ; IRQ0-7 -> INT 08h-0Fh
            out       0x21, al
            mov       al, 0x70        ; IRQ8-15 -> INT 70h-77h
            out       0xA1, al

            mov       al, 0x04
            out       0x21, al
            mov       al, 0x02
            out       0xA1, al
            
            mov       al, 0x01
            out       0x21, al
            out       0xA1, al

            ; Scan et Initialisation des options ROMS (VGA BIOS, etc)
            call      setup_load_rom

            ; initialise l'écran en mode texte
            mov       ax,0x0003
            int       0x10

            ; Installation des ISR
            mov       word [0x08*4], timer_isr
            mov       word [0x08*4+2], 0xF000

            mov       word [0x09*4], keyboard_isr
            mov       word [0x09*4+2], 0xF000

            ; Démasquer IRQ0 et IRQ1
            mov       al, 0xFC
            out       0x21, al
            sti

            mov       ax, BIOS_DATA_SEG
            mov       es, ax
            mov       di, 0x0           ; Adresse physique de tes variables
            mov       cx, 4
            xor       ax,ax
            rep stosb                   ; Met 4 octets à zéro

main_loop:
            mov       ax,BIOS_DATA_SEG
            mov       fs,ax

            mov       al, [fs:0x00]     ; Timer
            mov       di, 0
            call      draw_hex_byte

            mov       al, [fs:0x01]     ; Clavier
            mov       di, 6
            call      draw_hex_byte

            mov       al, [fs:0x02]     ; Clavier
            mov       di, 12
            call      draw_hex_byte

            jmp       main_loop

; ------------------------------------------------------------------
; HANDLERS & HELPERS
; ------------------------------------------------------------------
default_isr:
            iret


timer_isr:
            push      ax
            push      gs

            mov       ax, BIOS_DATA_SEG
            mov       gs, ax

            inc       byte [gs:0x00]

            mov       al, 0x20
            out       0x20, al

            pop       gs
            pop       ax
            iret

keyboard_isr:
            push      ax
            push      gs

            mov       ax, BIOS_DATA_SEG
            mov       gs, ax

            in        al, 0x60         ; Ack clavier
            mov       byte [gs:0x02],al

            inc       byte [gs:0x01]

            mov       al, 0x20
            out       0x20, al

            pop       gs
            pop       ax
            iret

draw_hex_byte:
            push      ax

            mov       bx, 0xb800
            mov       es,bx

            shr       al, 4
            call      .draw_nibble
            pop       ax
;            add       di, 2

.draw_nibble:
            and       al, 0x0F
            add       al, '0'
            cmp       al, '9'
            jbe       .print
            add       al, 7
.print:
            mov       ah, 0x0F        ; Blanc sur Noir
            stosw
            ret

; ----------------------------------------------------------------------------
; construire une table "vide" de pointeur ISR
; ----------------------------------------------------------------------------
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
; Détection les ROM supplementaires
; Teste la RAM de 0xC000 jusqu’à 0xE000, par pas de 2KB.
;
; Si une ROM est détectée, le code de la ROM sera appelé.
; ---------------------------------------------------------------------------
setup_load_rom:
						mov 			bx, 0xC000
.scanloop:
						mov 			gs, bx
						cmp				word[gs:0x0000],0xAA55	; ROM signature
						jne				.nextblock

						; appel le code (en 0x0003) de la ROM
						push 			cs
						push 			word .nextblock			; address de retour

						push			bx                  ; segment
						push 			0x0003              ; offset entry rom
						retf													; call far ds:0x0003
.nextblock:
						add				bx, 0x80						; add 2kb
						cmp 			bx, 0xE000
						jbe 			.scanloop
						ret

; ------------------------------------------------------------------
; Padding jusqu'au reset vector
; ------------------------------------------------------------------
times 0xFFF0 - ($ - $$) db 0xFF


reset_vector:
            jmp       0xF000:start
            db        '06/01/2026'
            db        0   ; le stub tient dans 16 octets (ou moins)