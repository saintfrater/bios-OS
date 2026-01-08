; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : boot.asm
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