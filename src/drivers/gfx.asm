; On doit répartir sur 2 octets :
    ; mask0 = glyph >> shift
    ; mask1 = glyph << (8-shift)
    ;
    ; Utilise AH pour conserver glyph original
    mov  ah, al

    ; mask0 dans AL
    mov  al, ah
    shr  al, cl
    ; mask1 dans AH
    mov  ah, ah
    mov  dl, 8
    sub  dl, cl
    mov  cl, dl
    mov  dl, ah
    shl  dl, cl
    mov  ah, dl
    ; restaurer shift dans CL (on en a besoin pour les lignes suivantes)
    mov  cl, [ds:GFX_CUR_SHIFT]

    ; Si mask0/mask1 nuls, saute ce côté
%if GFX_CHAR_COL = 1
    test al, al
    jz   .skip0_set
    or   [es:di], al
.skip0_set:
    test ah, ah
    jz   .skip1_set
    or   [es:di+1], ah
.skip1_set:
%else
    test al, al
    jz   .skip0_clr
    not  al
    and  [es:di], al
.skip0_clr:
    test ah, ah
    jz   .skip1_clr
    not  ah
    and  [es:di+1], ah
.skip1_clr:
%endif