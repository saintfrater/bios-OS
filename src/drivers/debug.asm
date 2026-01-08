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
						lodsb                    	; AL = *SI++
						test 			al, al
						jz   			.done
						
						mov				dx, DEBUG_PORT

						out				dx, al
						jmp  			.next
.done:
						ret
						
debug_putc:
.next:
						mov				dx, DEBUG_PORT
						out				dx, al
						ret						