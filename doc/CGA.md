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

| ID | Macro / Constante | Arguments (pile) |  Description |
| - | - | - | - |
| 0	| INIT	| Aucun	 | Initialise le mode vidéo 0x06, efface l'écran (damier) et initialise la souris. |
| 1	| PUTPIXEL | WORD x, WORD y, BYTE couleur | Dessine un pixel. 0 (Noir), !=0 (Blanc). |
2	| GETPIXEL | WORD x, WORD y	| Retourne la couleur du pixel dans AL (0 ou 1). |
| 3	| GOTOXY |WORD x, WORD y | Positionne le curseur de texte graphique aux coordonnées pixels données.|
| 4	| TXT_MODE | Mode | Définit le mode d'écriture du texte (voir Modes Texte ci-dessous). |
| 5	| PUTCH	| char | Affiche un caractère à la position courante et avance le curseur.
| 6	| WRITE | segment, offset | Affiche une chaîne de caractères terminée par 0 (ASCIIZ). |
| 7	| GFX_CRS_UPDATE | Aucun | Force la mise à jour visuelle du curseur souris (copie background -> draw).|