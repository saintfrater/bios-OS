; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : memory.asm
;  Author   : Gemini
;
;  Description :
;  Gestionnaire de mémoire dynamique (Heap) simple pour mode réel.
;  Utilise un algorithme "First-Fit" avec fusion des blocs libres (coalescing).
;
;  Layout Mémoire :
;  [STATUS (1b)] [SIZE (2b)] [NEXT (2b)] [ DATA ... ]
;
; =============================================================================

%define MEM_HEAP_SEG    0x2000          ; Segment du tas (Phys: 0x20000)
%define MEM_HEAP_SIZE   0x8000          ; Taille totale (32 Ko)

%define MEM_STATUS_FREE 0
%define MEM_STATUS_USED 1

; --- API Codes ---
%define MEM_ALLOC       0
%define MEM_GET_SIZE    1
%define MEM_FREE        2
%define MEM_RESOLVE     3

; --- Macro API ---
; Usage: MEM FUNCTION, [ARG1], [ARG2]...
%macro MEM 1-*
    %rep %0 - 1
        %rotate -1
        push %1
    %endrep
    %rotate -1
    call word [cs:mem_api_table + ((%1)*2)]
    add sp, (%0 - 1) * 2
%endmacro

mem_api_table:
    dw mem_alloc
    dw mem_get_size
    dw mem_free
    dw mem_resolve

struc mem_block
    .status resb 1      ; État du bloc (0=Libre, 1=Occupé)
    .size   resw 1      ; Taille des données (sans le header)
    .next   resw 1      ; Offset du prochain bloc (0 = Fin)
endstruc

; -----------------------------------------------------------------------------
; mem_init
; Initialise le gestionnaire de mémoire.
; Crée un seul gros bloc libre couvrant tout le segment.
; -----------------------------------------------------------------------------
mem_init:
    push    ax
    push    es
    push    di

    mov     ax, MEM_HEAP_SEG
    mov     es, ax
    xor     di, di

    ; Initialisation du premier bloc (Header)
    mov     byte [es:di + mem_block.status], MEM_STATUS_FREE

    ; Taille disponible = Total - TailleHeader
    mov     ax, MEM_HEAP_SIZE
    sub     ax, mem_block_size
    mov     word [es:di + mem_block.size], ax

    mov     word [es:di + mem_block.next], 0

    pop     di
    pop     es
    pop     ax
    ret

; -----------------------------------------------------------------------------
; mem_alloc
; Alloue un bloc de mémoire.
;
; Stack:  [BP+4] = Taille demandée (word)
; Output: AX = Handle (Offset du bloc de données) ou 0 si échec
; -----------------------------------------------------------------------------
mem_alloc:
    push    bp
    mov     bp, sp
    sub     sp, 2

    %define .curr_ptr       word [bp-2]
    %define .size_requested word [bp+4]

    push    bx
    push    cx
    push    es
    push    di

    mov     .curr_ptr, 0        ; On commence la recherche à l'offset 0

    mov     ax, MEM_HEAP_SEG
    mov     es, ax

.scan_loop:
    mov     di, .curr_ptr       ; DI = Ptr courant

    ; 1. Le bloc est-il LIBRE ?
    cmp     byte [es:di + mem_block.status], MEM_STATUS_FREE
    jne     .next_block

    ; 2. Tentative de FUSION (Coalescing) avec les blocs suivants
.try_merge:
    mov     bx, [es:di + mem_block.next]
    cmp     bx, 0
    je      .check_size         ; Pas de suivant, on vérifie la taille

    ; Si le suivant est aussi libre, on fusionne
    cmp     byte [es:bx + mem_block.status], MEM_STATUS_FREE
    jne     .check_size

    ; Nouvelle Taille = TailleActuelle + Header + TailleSuivant
    mov     ax, [es:bx + mem_block.size]
    add     ax, mem_block_size
    add     [es:di + mem_block.size], ax

    ; Mise à jour du chainage (saute le bloc fusionné)
    mov     ax, [es:bx + mem_block.next]
    mov     [es:di + mem_block.next], ax

    jmp     .try_merge          ; On boucle pour voir si le suivant du suivant est libre

.check_size:
    ; 3. Vérifier si la taille est suffisante
    mov     ax, .size_requested ; Taille demandée (Argument)
    cmp     [es:di + mem_block.size], ax
    jb      .next_block         ; Trop petit

    ; 4. Allocation (Split si possible)
    ; Calculer l'espace restant
    mov     cx, [es:di + mem_block.size]
    sub     cx, ax              ; CX = Reste

    ; Peut-on créer un nouveau bloc dans le reste ? (Header + au moins 1 octet)
    cmp     cx, mem_block_size + 1
    jb      .allocate_full

    ; --- SPLIT ---
    ; Marquer le bloc actuel comme utilisé avec la taille demandée
    mov     byte [es:di + mem_block.status], MEM_STATUS_USED
    mov     [es:di + mem_block.size], ax

    ; Créer le nouveau header dans l'espace restant
    mov     bx, di
    add     bx, mem_block_size
    add     bx, ax              ; BX = Offset du nouveau bloc

    mov     byte [es:bx + mem_block.status], MEM_STATUS_FREE

    sub     cx, mem_block_size  ; Taille utile du nouveau bloc
    mov     [es:bx + mem_block.size], cx

    ; Insérer dans la liste chainée
    mov     dx, [es:di + mem_block.next]
    mov     [es:bx + mem_block.next], dx
    mov     [es:di + mem_block.next], bx

    jmp     .success

.allocate_full:
    ; On prend tout le bloc sans le couper
    mov     byte [es:di + mem_block.status], MEM_STATUS_USED

.success:
    ; Retourner le handle (Offset des DONNÉES = DI + Header)
    mov     ax, di
    add     ax, mem_block_size
    jmp     .done

.next_block:
    ; Passer au bloc suivant
    mov     di, .curr_ptr
    mov     ax, [es:di + mem_block.next]
    mov     .curr_ptr, ax
    cmp     ax, 0
    jne     .scan_loop

    ; Échec : Plus de mémoire ou fragmentation trop élevée
    xor     ax, ax

.done:
    pop     di
    pop     es
    pop     cx
    pop     bx
    %undef .curr_ptr
    %undef .size_requested
    leave                       ; Restaure SP et BP
    ret

; -----------------------------------------------------------------------------
; mem_free
; Libère un bloc mémoire.
; Stack:  [BP+4] = Handle (word)
; -----------------------------------------------------------------------------
mem_free:
    push    bp
    mov     bp, sp

    %define .handle word [bp+4]

    push    es
    push    di
    push    bx

    mov     ax, .handle         ; Handle
    test    ax, ax
    jz      .done               ; Sécurité Handle NULL

    mov     bx, MEM_HEAP_SEG
    mov     es, bx

    ; Retrouver le header (Handle - HeaderSize)
    mov     di, ax
    sub     di, mem_block_size

    ; Marquer simplement comme libre (le coalescing se fera au prochain alloc)
    mov     byte [es:di + mem_block.status], MEM_STATUS_FREE

.done:
    pop     bx
    pop     di
    pop     es
    %undef .handle
    leave
    ret

; -----------------------------------------------------------------------------
; mem_get_size
; Retourne la taille utile d'un bloc.
; Stack:  [BP+4] = Handle (word)
; Output: AX = Taille
; -----------------------------------------------------------------------------
mem_get_size:
    push    bp
    mov     bp, sp

    %define .handle word [bp+4]

    push    es
    push    di

    mov     ax, .handle         ; Handle
    test    ax, ax
    jz      .error

    mov     bx, MEM_HEAP_SEG
    mov     es, bx

    mov     di, ax
    sub     di, mem_block_size

    mov     ax, [es:di + mem_block.size]
    jmp     .done

.error:
    xor     ax, ax
.done:
    pop     di
    pop     es
    %undef .handle
    leave
    ret

; -----------------------------------------------------------------------------
; mem_resolve
; Convertit un handle en pointeur complet Segment:Offset.
; Stack:  [BP+4] = Handle (word)
; Output: DX:AX = Segment:Offset
;         ES:DI = Segment:Offset (pour utilisation immédiate avec stos/movs)
; -----------------------------------------------------------------------------
mem_resolve:
    push    bp
    mov     bp, sp

    mov     ax, [bp+4]          ; Handle
    mov     dx, MEM_HEAP_SEG
    mov     es, dx
    mov     di, ax      ; L'offset est le handle lui-même

    ; DX contient déjà le segment, AX contient déjà l'offset

    leave
    ret
