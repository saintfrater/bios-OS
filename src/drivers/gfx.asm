%define GFX_MODE			0x06								; MCGA HiRes (B/W)
%define GFX_WIDTH			640
%define GFX_HEIGHT		200

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

; gfx_background:
						xor				dx,dx						; Y

.loop_y:
						test			dl,1
						jnz				.pair

						mov				cx,0						; X = 0
						jmp				.loop_x
.pair:
						mov				cx,1						; X = 1

.loop_x:
						mov				ah,0x0c					; putpixel
						mov				al,0x0f					;	blanc
						xor				bh,bh
						int				10h

						add				cx,2						; x=x+2
						cmp				cx,GFX_WIDTH
						jb				.loop_x

						inc				dx
						cmp				dx,GFX_HEIGHT
						jb				.loop_y
						ret