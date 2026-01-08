; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : bda.asm
;  Author   : frater
;  Created  : 06 jan 2026
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
; https://wiki.nox-rhea.org/back2root/ibm-pc-ms-dos/hardware/informations/bios_data_area
;

%define BDA_SEGMENT						0x0040							; segment BDA

; custom var
%define BDA_INFO_MEM_SIZE			0x0014							; Memory size in Kbytes
%define BDA_INFO_MEM_SEG			BDA_INFO_MEM_SIZE+2	; highest Memory Segment

; video related information (compatible with VGA bios)
%define BDA_VIDEO_CURR_MODE		0x0049
%define BDA_VIDEO_COLUMNS			0x004A
%define BDA_VIDEO_BUF_SIZE		0x004C
%define BDA_VIDEO_OFS_PAGE		0x004E


; 40:50 	8 words 	Cursor position of pages 1-8, high order byte=row low order byte=column; changing this data isn't reflected immediately on the display
; 40:60 	byte 	Cursor ending (bottom) scan line (don't modify)
; 40:61 	byte 	Cursor starting (top) scan line (don't modify)
; 40:62 	byte 	Active display page number
; 40:63 	word 	Base port address for active 6845 CRT controller 3B4h = mono, 3D4h = color
; 40:65 	byte 	6845 CRT mode control register value (port 3x8h) ; EGA/VGA values emulate those of the MDA/CGA
; 40:66 	byte 	CGA current color palette mask setting (port 3d9h) ; EGA and VGA values emulate the CGA


;
; information relative à la souris
;

%define BDA_MOUSE_SEG					0x0050

%define BDA_MOUSE_BUFFER			0x0000							; dword; buffer (jusqu'à 4 octets)
%define	BDA_MOUSE_IDX					0x0004							; byte 0..3
%define DBA_MOUSE_PACKETLEN		0x0005
; 														0x0006
%define BDA_MOUSE_STATUS			0x0007							; byte
%define	BDA_MOUSE_X						0x0008							; word
%define	BDA_MOUSE_Y						0x000A							; word