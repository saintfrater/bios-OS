; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : macros.asm
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

%macro PUSH_ABCD 0
					push 				ax
					push 				bx
					push 				cx
					push 				dx
%endmacro

%macro PUSH_ID 0
					push				di
					push				si
%endmacro

%macro POP_ABCD 0
					pop					dx
					pop					cx
					pop					bx
					pop					ax
%endmacro

%macro POP_ID 0
					pop					si
					pop					di
%endmacro
