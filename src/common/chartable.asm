; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : chartable.asm
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

font8x8:
;
; https://github.com/viler-int10h/vga-text-mode-fonts
;
; Bien que le fichiers F08 définissent les 256 caractères de la table ASCII,
; on importe uniquement les caractères entre ' ' (0x20) et '~' (0x7E).
; ce choix est fait pour limiter la taille de la police; de même nous ne gérons
; qu'une seule police.
;
; Si l'on désire augmenter le nombre de caratères ou ajouter plusieurs polices, il faudra
; adapter les fonctions "putc" en accord.
;
incbin  "./assets/8X8ITAL.F08", 0x20*8, 0x7e*8
; incbin  "./assets/FM-T-437.F08", 0x20*8, 0x7e*8
;incbin  "./assets/CGA-TH.F08", 0x20*8, 0x7e*8