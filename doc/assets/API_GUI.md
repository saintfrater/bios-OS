# Documentation de l'API GUI (Custom BIOS / ROM)

Cette documentation décrit le fonctionnement, les constantes et les fonctions de la bibliothèque d'interface graphique (GUI) en mode réel. Le système repose sur une table de dispatch (macro `GUI`) et une boucle d'événements pour gérer jusqu'à 32 widgets simultanément.

---

## 1. Constantes et Énumérations

Les définitions globales utilisées pour paramétrer les widgets.

### Limites du système
| Constante | Valeur | Description |
| :--- | :--- | :--- |
| `GUI_MAX_WIDGETS` | `32` | Nombre maximum de widgets simultanés. |
| `GUI_CHECKBOX_SIZE` | `10` | Taille en pixels du carré d'une case à cocher. |

### États des Widgets (`GUI_STATE_*`)
| Constante | Valeur | Description |
| :--- | :--- | :--- |
| `GUI_STATE_FREE` | `0` | Slot vide, mémoire disponible. |
| `GUI_STATE_NORMAL` | `1` | Affiché, au repos. |
| `GUI_STATE_HOVER` | `2` | La souris survole le widget. |
| `GUI_STATE_PRESSED`| `3` | Le clic de la souris est maintenu enfoncé sur le widget. |
| `GUI_STATE_DISABLED`| `4` | Grisé, aucune interaction possible. |

### Types d'Objets (`OBJ_TYPE_*`)
| Constante | Valeur | Description |
| :--- | :--- | :--- |
| `OBJ_TYPE_LABEL` | `0` | Texte simple (non interactif). |
| `OBJ_TYPE_BUTTON` | `1` | Bouton rectangulaire classique. |
| `OBJ_TYPE_SLIDER` | `2` | Curseur / jauge de valeur. |
| `OBJ_TYPE_BUTTON_ROUNDED` | `3` | Bouton avec bords arrondis. |
| `OBJ_TYPE_CHECKBOX` | `4` | Case à cocher (Toggle). |

### Attributs de Modes (`SLIDER_*`)
| Constante | Valeur | Description |
| :--- | :--- | :--- |
| `SLIDER_HORIZONTAL` | `1` | Le slider se déplace sur l'axe X. |
| `SLIDER_VERTICAL` | `2` | Le slider se déplace sur l'axe Y. |

---

## 2. Appel de l'API : La Macro `GUI`

L'interaction avec les widgets doit se faire via la macro `GUI`. Elle empile les arguments dans le bon ordre et appelle la fonction correspondante via la table `gui_api_table`.

**Syntaxe NASM :**
```nasm
GUI ACTION_ID, arg1, arg2, ...