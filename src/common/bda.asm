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

%define BDA_SEGMENT		    0x0040			    ; segment BDA

; custom vars
%define BDA_INFO_MEM_SIZE	0x0014		        ; Memory size in Kbytes
%define BDA_INFO_MEM_SEG	BDA_INFO_MEM_SIZE+2	; highest Memory Segment

; video related information (compatible with VGA bios)
%define BDA_VIDEO_CURR_MODE	0x0049
%define BDA_VIDEO_COLUMNS	0x004A
%define BDA_VIDEO_BUF_SIZE	0x004C
%define BDA_VIDEO_OFS_PAGE	0x004E
;
; information relative à la souris
;
%define BDA_DATA_SEG	        0x0050

%define BKG_DWORDS_PER_LINE     1          ; 1 dword stocké par ligne
%define BKG_LINES               16
%define BKG_TOTAL_DWORDS        (BKG_LINES * BKG_DWORDS_PER_LINE) ; 16
%define BKG_TOTAL_BYTES         (BKG_TOTAL_DWORDS * 4)            ; 64

struc  mouse
    .buffer         resb    4       ; i8042 input buffer
    .idx            resb    1       ; index in the buffer
    .packetlen      resb    1       ; max buffer len (3 ou 4)
    .status         resb    1       ; mouse status (button etc)
    .wheel          resb    1       ; if a packet size is 4; experimental
    .x              resw    1       ;
    .y              resw    1       ;
    ; cursor management
    .cur_x          resw    1       ; preservation des x,y du background
    .cur_y          resw    1       ;
    .cur_addr_start resw    1       ; adresse de départ de la sauvegarde
    .cur_drawing    resb    1       ;
    .cur_counter    resb    1       ; compteur de fois que le curseur a été caché (0 = visible, <0 = invisible)
    .cur_seg        resw    1       ; segment / offset of the pointer
    .cur_ofs        resw    1       ;
    .bkg_saved      resb    1       ; background saved
    alignb                  4       ; alignement 4 bytes
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