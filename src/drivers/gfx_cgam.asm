;
; graphics drivers for CGA 640x200x2
;
%define GFX_MODE			0x06								; MCGA HiRes (B/W)
%define GFX_WIDTH			640
%define GFX_HEIGHT		200

%define CGA_STRIDE    80
%define CGA_ODD_BANK  0x2000
%define BG16_SIZE     48

; ce mode est entrelacé, un bit/pixel, 8 pixels par octet

gfx_init:
						; init graphics mode
						mov 			ah, 0x00     			; AH=00h set video mode
						mov				al, GFX_MODE
						int 			0x10

						call			gfx_background

						ret

; PutPixel(x=cx, y=dx, color=al) sur page bh
gfx_putpixel:
						mov  			ah, 0Ch
						;mov  			al, 0Fh       ; couleur (0..15)
						;mov  			bh, 00h       ; page
						;mov  			cx, 100       ; x
						;mov  			dx, 50        ; y
						int  			10h
						ret

; draw background pattern
gfx_background:
						mov				ax,VIDEO_SEG
						mov				es,ax
						xor				di,di
						mov				ax,0xaaaa
						mov				cx,0x1000
						rep				stosw
						mov				ax,0x5555
						mov				cx,0x1000			; 640/8/2
						rep				stosw
						ret
