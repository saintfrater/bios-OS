;
; https://wiki.nox-rhea.org/back2root/ibm-pc-ms-dos/hardware/informations/bios_data_area
;
%define BDA_SEGMENT						0x0040							; segment BDA

; custom var
%define BDA_INFO_MEM_SIZE			0x0014							; Memory size in Kbytes
%define BDA_INFO_MEM_SEG			BDA_INFO_MEM_SIZE+2	; highest Memory Segment


%define BDA_MOUSE_BUFFER			0x0068							; dword
%define	BDA_MOUSE_IDX					BDA_MOUSE_BUFFER+4	; byte
%define	BDA_MOUSE_X						BDA_MOUSE_BUFFER+5	; word	
%define	BDA_MOUSE_Y						BDA_MOUSE_BUFFER+7	; word

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