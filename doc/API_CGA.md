# API Graphique (CGA Monochrome 640x200)

L'accès se fait via la macro


```assember
GFX [COMMANDE], [ARGS...]
```
ou via
```assembler
call [graph_driver + ID*2].
```

Les arguments sont empilés selon la convention C (dernier argument poussé en premier).

## Liste des fonctions disponibles

| Index | Commande | Arguments | Description |
| - | - | - | - |
| 00 | INIT | Aucun | "Initialise le mode vidéo 0x06, efface l'écran et installe le motif de fond."|
| 01 | PUTPIXEL | "x (word), y (word) |  color (byte)", "Dessine un pixel aux coordonnées (x, y). 0=Noir ,  !0=Blanc." |
| 02 | GETPIXEL | "x (word),  y (word)" | Retourne la couleur du pixel dans AL (0 ou 1). |
| 03 | GOTOXY | "x (word), y (word)" | Positionne le curseur texte interne (en pixels). |
| 04 | TXT_MODE | mode (word) | "Définit le mode d'écriture texte.Bits :0: Couleur (0=Noir, 1=Blanc)1: Transparence (1=Transparent |  0=Opaque)" |
| 05 | PUTCH | char (word) | Affiche un caractère ASCII à la position courante et avance le curseur de 8px. |
| 06 | WRITE | "seg (word) |  offset (word)" | Affiche une chaîne de caractères terminée par 0 (ASCIIZ) pointée par seg:offset. |
| 07 | LINE_VERT | "x,  y1,  y2, color" | Dessine une ligne verticale de y1 à y2 à la position x. |
| 08 | LINE_HORIZ | "x1, x2, y, color" | Dessine une ligne horizontale de x1 à x2 à la hauteur y. Optimisé par octet. |
| 09 | RECTANGLE_DRAW | "x1, y1, x2, y2, color" | Dessine le contour d'un rectangle. |
| 10 | RECTANGLE_FILL | "x1, y1, x2, y2, color" | Dessine un rectangle plein (rempli). |
| 11 | MOUSE_HIDE | Aucun | Cache le curseur souris et restaure l'arrière-plan. Gère un compteur interne (récursif). |
| 12 | MOUSE_SHOW | Aucun | Sauvegarde l'arrière-plan et affiche le curseur souris. Gère un compteur interne. |
| 13 | MOUSE_MOVE | Aucun | Force le rafraîchissement visuel du curseur souris (Efface -> Sauve fond -> Affiche). |

## Constantes Utiles (Texte)

Ces constantes sont utilisées avec la commande TXT_MODE.

    *GFX_TXT_WHITE_TRANSPARENT* (0) : Texte blanc, fond inchangé.

    *GFX_TXT_BLACK_TRANSPARENT* (1) : Texte noir, fond inchangé.

    *GFX_TXT_WHITE* (2) : Texte blanc sur fond noir (écrasement).

    *GFX_TXT_BLACK* (3) : Texte noir sur fond blanc (écrasement).
