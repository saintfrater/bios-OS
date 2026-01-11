; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : debug.asm
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

debug_puts:
.next:
						push 			dx
						mov				dx, DEBUG_PORT
						lodsb                    	; AL = *SI++
						test 			al, al
						jz   			.done
						out				dx, al
						jmp  			.next
.done:
						pop 			dx
						ret

debug_putc:
						push			dx
						mov				dx, DEBUG_PORT
						out				dx, al
						pop 			dx
						ret

; AL = 0..15 -> print hex digit
debug_puthex4:
						and 			al, 0Fh
						cmp 			al, 9
						jbe 			.num
						add 			al, 'A' - 10
						jmp 			.pout
.num:
    				add 			al, '0'
.pout:
    				call debug_putc
    				ret

; AL = byte -> print 2 hex digits
debug_puthex8:
						push 			ax
						mov 			ah, al
						shr 			al, 4
						call 			debug_puthex4
						mov 			al, ah
						call 			debug_puthex4
						pop 			ax
						ret

; AX = word -> print 4 hex digits
debug_puthex16:
						push 			ax
						mov 			al, ah
						call 			debug_puthex8
						pop 			ax
						call 			debug_puthex8
						ret
