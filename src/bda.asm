; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : bda.asm
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

; compatible with IBM PC BIOS Data Area (BDA):
; https://wiki.nox-rhea.org/back2root/ibm-pc-ms-dos/hardware/informations/bios_data_area
;

%define BDA_SEGMENT		0x0040			; segment BDA

; custom vars
%define BDA_INFO_MEM_SIZE	0x0014		        ; Memory size in Kbytes
%define BDA_INFO_MEM_SEG	BDA_INFO_MEM_SIZE+2	; highest Memory Segment

; video related information (compatible with VGA bios)
%define BDA_VIDEO_CURR_MODE	0x0049
%define BDA_VIDEO_COLUMNS	0x004A
%define BDA_VIDEO_BUF_SIZE	0x004C
%define BDA_VIDEO_OFS_PAGE	0x004E

; keyboard related information
%define BDA_KBD_HEAD            0x0080      ; byte
%define BDA_KBD_TAIL            0x0081      ; byte
%define BDA_KBD_FLAGS           0x0082      ; byte: bit0=shift, bit1=ctrl, bit2=alt, bit3=caps, bit4=ext(E0)
%define BDA_KBD_BUF             0x0090      ; buffer circulaire (par ex 32 entrées *2 = 64 bytes)

%define KBD_BUF_MASK            0x1F        ; 32 entrées => index 0..31

;
; information relative à la souris
;
%define BDA_DATA_SEG	        0x0050

%define BKG_DWORDS_PER_LINE     1          ; 1 dword stocké par ligne
%define BKG_LINES               16
%define BKG_TOTAL_DWORDS        (BKG_LINES * BKG_DWORDS_PER_LINE) ; 16
%define BKG_TOTAL_BYTES         (BKG_TOTAL_DWORDS * 4)            ; 64

struc  mouse
        .buffer         resb    4       ; i8042 input buffer                         0..3
        .idx            resb    1       ; index in the buffer                        4
        .packetlen      resb    1       ; max buffer len (3 ou 4)                    5
        .blinker        resb    1       ;

        .status         resb    1       ; mouse status (button etc)                  6
        .wheel          resb    1       ; if a packet size is 4; experimental        7
        .x              resw    1       ;                                            8..9
        .y              resw    1       ;                                            A..B
        ; cursor management
        .cur_x          resw    1       ; preservation des x,y du background         C..D
        .cur_y          resw    1       ;                                            E..F
        .cur_addr_start resw    1       ; adresse de départ de la sauvegarde        10..11
        .cur_bank_add   resw    1       ; + ou - 0x2000                             12..13

        .cur_drawing    resb    1       ;                                           14
        .cur_visible    resb    1       ;                                           15
        .cur_seg        resw    1       ; segment / offset of the pointer           16..17
        .cur_ofs        resw    1       ;                                           18..19
        .cur_mask       resb    1       ; pixels mask (bit per pixel)               1A
        .cur_bit_ofs    resb    1       ; 0..7 bits d'offset (x&7)                  1B
        .bkg_saved      resb    1       ; background saved                          1C
        alignb                  4       ; alignement 4 bytes                        1D
        .bkg_buffer     resd    16      ; buffer for saved background
endstruc

struc   gfx
        .cur_x          resw    1       ; x,y en pixel
        .cur_y          resw    1
        .cur_offset     resw    1       ; offset calculé pour le prochain caractère
        .cur_line_ofs   resw    1       ; "interligne" +2000h ou -2000h
        .cur_shift      resb    1       ; x&7 (0..7)
        .cur_mode       resb    1       ;
endstruc

%define BDA_MOUSE               0x0000
%define BDA_GFX                 (BDA_MOUSE + mouse_size)

%warning offset Mouse: BAD_MOUSE, Gfx : BDA_GFX

;
; memory map
;
;   0x00000-0x003FF : IVT (1kB)
;   0x00400-0x007FF : BDA (1kB) pour les options 'ROMS' carte graphique, etc...
;   0x00800-0x009FF : Varibles custom.
;
;   0x03C00-0x08000 : stack segment
;   0x



; -----------------------------------------------------------------------------------
; PC components I/O ports
; -----------------------------------------------------------------------------------

; controleur clavier/souris i8042 (AT-PS/2)
%define i8042_PS2_DATA          0x60
%define i8042_PS2_CTRL          0x64

; PIC 8259 ports (Programmable Interrupt Controller)
; PIC 1 : Master
%define i8259_MASTER_CMD        0x20
%define i8259_MASTER_DATA	0x21
; PIC 2 : Slave
%define i8259_SLAVE_CMD         0xA0
%define i8259_SLAVE_DATA	0xA1

; i8259 Commands
%define ICW1_ICW4               0x01            ; Indicates that ICW4 will be present
%define ICW1_SINGLE	        0x02            ; Single (cascade) mode
%define ICW1_INTERVAL4          0x04            ; Call address interval 4 (8)
%define ICW1_LEVEL              0x08            ; Level triggered (edge) mode
%define ICW1_INIT               0x10            ; Initialization - required!

%define ICW4_8086               0x01            ; 8086/88 (MCS-80/85) mode
%define ICW4_AUTO	        0x02		; Auto (normal) EOI
%define ICW4_BUF_SLAVE	        0x08		; Buffered mode/slave
%define ICW4_BUF_MASTER	        0x0C		; Buffered mode/master
%define ICW4_SFNM	        0x10		; Special fully nested (not)
%define PIC_EOI                 0x20

; Remap : IRQ0..7 -> 0x08..0x0F, IRQ8..15 -> 0x70..0x77
%define i8259_MASTER_INT        0x08
%define i8259_SLAVE_INT         0x70

%define IRQ_ENABLED             0x00
%define IRQ_DISABLED            0x01

; -----------------------------------------------------------------------------------
;  bda_setup
;  Initialise la BDA à zéro
; -----------------------------------------------------------------------------------
bda_setup:
            pusha
            push        ds

            mov 	ax, BDA_DATA_SEG
            mov 	es, ax

            mov 	ax, 0x5F
            mov 	cx,0xFF
            xor 	di, di
            rep         stosb                ; clear BDA area

            pop 	ds
            popa
            ret