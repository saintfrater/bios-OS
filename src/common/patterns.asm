; =============================================================================
;  SECTION : PATTERNS & FILL
; https://paulsmith.github.io/classic-mac-patterns/
; =============================================================================
;
; pattern ID
%define PATTERN_BLACK               0
%define PATTERN_GRAY_DARK           1
%define PATTERN_GRAY_MID            2
%define PATTERN_GRAY_LIGHT          3
%define PATTERN_WHITE_LIGHT         4
%define PATTERN_WHITE               5

align   8
pattern_8x8:
    dq 0x0000000000000000               ; 0 : pattern_black (Tout à 0 = Noir)
    dq 0x2200880022008800               ; 1 : pattern_gray_dark (Majorité de 0)
    dq 0x2288228822882288               ; 2 : pattern_gray_mid
    dq 0xAA55AA55AA55AA55               ; 3 : pattern_gray_light (50/50)
    dq 0x77DD77DD77DD77DD               ; 4 : pattern_white_light (Majorité de 1 = Clair)
    dq 0xFFFFFFFFFFFFFFFF               ; 5 : pattern_white (Tout à 1 = Blanc)


%macro  PATTERN_PTR 		1
    mov     ax, cs
    mov     ds, ax
	lea     esi, [pattern_8x8 + (%1 * 8)]
%endmacro