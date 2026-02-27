; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gui/window.asm
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

; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gui/window-manager.asm
;  Description : Gestionnaire de fenêtres (Window Manager)
; =============================================================================

%define MAX_WINDOWS 8

; --- États d'une fenêtre ---
%define WIN_STATE_FREE      0       ; Slot libre en mémoire
%define WIN_STATE_INACTIVE  1       ; Affichée en arrière-plan
%define WIN_STATE_ACTIVE    2       ; Au premier plan (focus)
%define WIN_STATE_HIDDEN    3       ; Invisible

struc window
    .state          resb 1      ; État de la fenêtre
    .id             resb 1      ; Identifiant unique
    .x              resw 1
    .y              resw 1
    .w              resw 1
    .h              resw 1
    .title_ofs      resw 1      ; Pointeur texte du titre
    .title_seg      resw 1
    .process_cb     resw 1      ; NOUVEAU : Offset du callback (processus de la fenêtre)
    .process_seg    resw 1      ; Segment du callback
endstruc

%define window_size 16

; Variables globales du WM (à placer dans le segment BDA_CUSTOM ou SEG_GUI)
wm_active_window_id  db 0       ; ID de la fenêtre actuellement active

; -----------------------------------------------------------------------------
; wm_process_all
; Remplace la boucle principale. Gère les processus de fenêtre puis la GUI.
; -----------------------------------------------------------------------------
wm_process_all:
    pusha
    push    ds
    push    gs

    mov     ax, SEG_GUI
    mov     gs, ax

    ; 1. Gérer les processus des fenêtres
    mov     si, 0                   ; On suppose que le pool window commence à l'offset 0 d'une zone dédiée
    mov     cx, MAX_WINDOWS

    .loop_windows:
    cmp     byte [gs:si + window.state], WIN_STATE_FREE
    je      .next_window

    ; VÉRIFICATION : Est-ce que la fenêtre est ACTIVE ?
    ; Selon votre règle : on n'appelle pas le processus si elle n'est pas active.
    cmp     byte [gs:si + window.state], WIN_STATE_ACTIVE
    jne     .next_window

    ; La fenêtre est active, a-t-elle un processus (callback) défini ?
    cmp     word [gs:si + window.process_cb], 0
    je      .next_window

    ; Exécution du processus spécifique à la fenêtre active
    pusha
    ; Appel inter-segment (Far Call) ou intra-segment (Near Call) selon l'architecture
    ; Ici on simule un near call si tout est dans CS
    call    word [gs:si + window.process_cb]
    popa

    .next_window:
    add     si, window_size
    loop    .loop_windows

    ; 2. Appeler le moteur d'événements des widgets (lib-logic)
    call    gui_process_all

    pop     gs
    pop     ds
    popa
    ret

; -----------------------------------------------------------------------------
; wm_set_active
; Change la fenêtre active (Focus)
; In: AL = window_id
; -----------------------------------------------------------------------------
wm_set_active:
    push    gs
    push    bx

    ; Sauvegarder le nouvel ID actif
    mov     [wm_active_window_id], al

    ; Note : Ici vous pourriez rajouter une boucle pour passer toutes les
    ; autres fenêtres en WIN_STATE_INACTIVE et redessiner le tout pour
    ; mettre la fenêtre active au premier plan (Z-Order).

    pop     bx
    pop     gs
    ret