# API

Le système utilise plusieurs macro *GFX*,*GUI*, etc pour appeler les fonctions du driver via une table de saut.

Les arguments sont passés sur la pile (Convention C : dernier argument empilé en premier, nettoyage par l'appelant géré par la macro).

  * [CGA](/doc/API_CGA.md) : controleur graphique CGA
  * [MEMORY](/doc/API_MEMORY.md) : controleur graphique CGA

  * [MEMORY MAP](/doc/MEMORY_MAP.md) : Plan de la mémoire