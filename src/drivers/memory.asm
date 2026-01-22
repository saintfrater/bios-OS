; =======================
; API
; =======================
%define MEM_INIT        0
%define MEM_DETECT      2
%define MEM_ALLOC       4
%define MEM_FREE        6
%define MEM_DUMP_RESET  8
%define MEM_DUMP_NEXT   10

mem_api:
  dw mem_init
  dw mem_detect
  dw mem_alloc
  dw mem_free
  dw mem_dump_reset
  dw mem_dump_next

; =======================
; Contexte en RAM (DS = CTX_SEG)
; =======================
heap_seg        dw 0
heap_start      dw 0
heap_end        dw 0
free_head       dw 0
dump_cursor     dw 0

; =======================
; Constantes
; =======================
%define HDR_SIZE   8
%define FTR_SIZE   2
%define MIN_BLK    12        ; aligné (>= HDR+FTR)
%define FLAG_USED  1

; -----------------------
; mem_detect
; AX=conv_kb, DX=ebda_seg, CF=0
; -----------------------
mem_detect:
  push ds
  xor ax, ax
  int 12h                 ; AX = KiB conventionnelle
  mov bx, ax              ; conv_kb -> BX

  ; Lire EBDA segment depuis BDA:040Eh
  ; On suppose DS peut être changé temporairement
  mov ax, 0x0040
  mov ds, ax
  mov dx, [0x000E]        ; EBDA segment (souvent 0x9FC0 etc), 0 si absent
  pop ds

  mov ax, bx              ; AX=conv_kb
  clc
  ret

; -----------------------
; mem_init
; Entrée (proposée) :
;   AX = HEAP_SEG (0 => auto)
;   BX = heap_start_offset (0 => défaut 0x0200)
; Sortie:
;   CF=0 ok, CF=1 err
; -----------------------
mem_init:
  ; 1) déterminer heap_seg et heap_end en évitant EBDA
  ; 2) créer 1 seul bloc libre [heap_start..heap_end)

  ; Implémentation typique:
  ; - si AX=0 : choisir un segment RAM “safe” (ex: 0x7000) OU segment du contexte
  ; - heap_start = (BX!=0 ? BX : 0x0200)
  ; - heap_end = 0xFFFE (ou plus petit selon usage)

  ; Puis initialiser le 1er bloc libre:
  ; [heap_start+0] size = heap_end-heap_start
  ; [heap_start+2] flags=0
  ; [heap_start+4] next_free=0
  ; [heap_start+6] prev_free=0
  ; footer à (heap_start+size-2)

  clc
  ret

; -----------------------
; mem_alloc
; CX = bytes demandés
; Sortie: ES=heap_seg, DI=payload, CF=0 si ok sinon CF=1
; -----------------------
mem_alloc:
  ; need = align2(CX) + HDR_SIZE + FTR_SIZE
  ; parcourir free list (first-fit)
  ; split si reste >= MIN_BLK
  ; marquer alloué, unlink free list
  ; ES=heap_seg, DI=blk_off + HDR_SIZE
  ret

; -----------------------
; mem_free
; Entrée: ES:DI = payload
; Sortie: CF=0 ok sinon CF=1
; -----------------------
mem_free:
  ; blk_off = DI - HDR_SIZE
  ; vérifier, marquer libre
  ; coalescer prev/next via footer/header
  ; relinker dans free list
  ret

; -----------------------
; mem_dump_reset / mem_dump_next
; -----------------------
mem_dump_reset:
  mov ax, [heap_start]
  mov [dump_cursor], ax
  clc
  ret

mem_dump_next:
  ; si dump_cursor >= heap_end => CF=1
  ; lire size/flags à dump_cursor
  ; renvoyer AL état, CX taille payload, DI=offset header, ES=heap_seg
  ; dump_cursor += size
  ret
