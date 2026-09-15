# KOReader · Apparence accueil

Un *user patch* pour [KOReader](https://koreader.rocks) qui transforme l'écran d'accueil en vraie page de bibliothèque : le livre en cours mis en avant avec sa progression, des statistiques de lecture, un objectif quotidien, une étagère de couvertures uniformes, une fiche par livre avec récupération en ligne des couvertures et descriptions, et une barre de lecture repensée.

Conçu et testé sur **Boox Go 6** (6 pouces, noir et blanc) et **Boox Note Air 4C** (10,3 pouces, écran couleur), sous Android avec KOReader 2026.07, en mode mosaïque du Cover browser. Il devrait fonctionner sur toute liseuse KOReader qui accepte les user patches (Kobo, Kindle, PocketBook, Android…), avec des réglages de taille à adapter.

> *English summary: a KOReader user patch that redesigns the file browser into a reader home page — current book hero with progress and reading-time estimates, reading statistics from the Statistics plugin, a daily reading goal, uniform cropped covers with status badges, a per-book card that fetches covers, descriptions and ratings from Open Library / Google Books, virtual folders by status, and a cleaner reading footer. All settings live in one `config.lua`. Comments and UI strings are in French.*

---

## Ce que ça fait, concrètement

### L'accueil

- **En-tête « livre en cours »** : grande couverture avec la barre de progression posée dessus et un bouton *Reprendre*, puis titre, auteur, barre de progression et pourcentage, chapitre courant / nombre de chapitres, page courante / total, temps déjà passé sur le livre, temps restant estimé. Un tap ouvre le livre.
- **« Mes statistiques »**, à droite de l'en-tête, d'après le plugin Statistiques de KOReader : temps et pages d'aujourd'hui, des 7 derniers jours (avec un petit graphique par jour), temps moyen par page, livres terminés dans l'année, temps et pages en tout. Un tap ouvre le calendrier de lecture de KOReader.
- **« Ma bibliothèque »** : un titre, un trait, et les dossiers en petites étiquettes tapables (les vrais dossiers, puis le dossier virtuel *Terminés*). En dessous, uniquement des livres.
- **Objectif du jour** : une vignette, en première position, montre les minutes lues aujourd'hui sur l'objectif (30 min par défaut), une barre, et le nombre de jours d'affilée où l'objectif est atteint. Un tap règle l'objectif.
- **Couvertures** : toutes au même format (2:3), recadrées au centre, coins arrondis, bordure fine (plus épaisse pour les livres en cours), titre sur une ligne en dessous, légère rotation aléatoire de chaque vignette pour casser l'alignement mécanique. Pastille ronde de statut en bas à droite (en cours, favori, terminé), marque-page si le livre est dans une collection KOReader, barre de progression en haut pour les livres en cours.
- **Dossiers virtuels** : *Terminés* liste tous les livres terminés, où qu'ils soient rangés ; ils disparaissent de la navigation normale. Le statut KOReader « en attente » est utilisé comme *Favoris* (pastille étoile, bouton dans la fiche).
- **Habillage** : marge autour de l'écran, barre du haut sans ligne de chemin, pagination fine et grise, icônes [Lucide](https://lucide.dev) à la place des icônes Material de KOReader, un tap sur un livre en cours l'ouvre directement, sur les autres ouvre sa fiche.

### La fiche d'un livre

Ouverte d'un tap sur une couverture : couverture, titre, auteur, série, mots-clés, pages et chapitres, format et taille, statut et progression, temps de lecture total et restant (d'après ta vitesse mesurée), ta note (étoiles KOReader) et la note moyenne trouvée en ligne, puis la description. Boutons : *Réinitialiser*, *Favoris*, *Terminé*, *Noter*, et *Fermer*, *Compléter*, *Détails*, *Ouvrir*.

**En ligne** (uniquement si la liseuse est connectée) : à l'ouverture de la fiche, la description manquante et la note moyenne sont récupérées automatiquement ; le bouton *Compléter* cherche en plus la couverture et la remplace. Sources : [Open Library](https://openlibrary.org) d'abord, [Google Books](https://books.google.com) en secours, sans compte ni clé. Le résultat n'est retenu que si l'auteur correspond, pour ne pas coller la couverture d'un autre livre. Ce qui est trouvé est enregistré avec les mécanismes natifs de KOReader (couverture et métadonnées personnalisées), donc conservé.

### La lecture

- **Barre de lecture** : sur une ligne, alignée sur les marges du texte, « 12 / 300 · 4 % · Chap. 3 / 12 · ~12 min » (page, pourcentage, chapitre courant sur le total, temps restant estimé du chapitre), avec de l'air au-dessus et en dessous. Préréglage appliqué une fois, ensuite tu restes libre de retoucher dans le menu de KOReader.
- **Fin de livre** : en dépassant la dernière page, une fenêtre propose *Marquer terminé*, *Noter*, *Terminé et noter*, *Bibliothèque*.

---

## Installation

1. Copier le contenu du dossier `koreader/` de ce dépôt dans le dossier `koreader/` de la liseuse (celui qui contient `settings.reader.lua`) :
   - `patches/2-apparence-accueil.lua` et le sous-dossier `patches/apparence-accueil/`
   - `icons/` (les icônes Lucide renommées aux noms KOReader, plus celles ajoutées par le patch)
2. Fermer complètement KOReader et le relancer.
3. Vérifier que l'accueil est en mode mosaïque : menu ☰ → Cover browser → Display mode → Mosaic, et définir ton dossier de livres comme dossier d'accueil (appui long sur le dossier → *Définir comme dossier d'accueil*).

Si le patch échoue, KOReader affiche « Error applying patch » au démarrage et continue sans lui : rien ne bloque la liseuse. Pour désactiver : renommer `2-apparence-accueil.lua` en `.lua.off` ou le supprimer.

**Prérequis** : KOReader 2025.04 ou plus récent (testé avec 2026.07.1 sur Boox Go 6 et Boox Note Air 4C), le plugin Cover browser en mode mosaïque, le plugin Statistiques activé pour les temps et statistiques (il l'est par défaut). Sur Android, la version F-Droid de KOReader n'exécute pas les user patches.

## Réglages

Tout est dans **`koreader/patches/apparence-accueil/config.lua`**, un seul tableau `CFG` commenté ligne par ligne : couleurs, tailles, marges, ce qui est affiché ou non, libellés, sources en ligne. Modifier une valeur, relancer KOReader ; `nil` redonne le comportement d'origine de KOReader pour ce réglage. Le tableau complet des réglages est dans [LISEZMOI.md](LISEZMOI.md).

Quelques réglages qu'on change en premier :

| Réglage | Rôle |
|---|---|
| `page_padding`, `titlebar_bottom_margin`, `grid_spacing` | marges de l'écran, sous la barre du haut, entre les vignettes (px) |
| `cover_ratio`, `cover_radius`, `cover_border`, `tilt_degrees` | format, arrondi, bordure et rotation des couvertures |
| `home_panels`, `home_panel_rows`, `hero_width_ratio` | l'en-tête (livre en cours + statistiques) et sa taille |
| `goal_tile`, `goal_default_minutes` | vignette Objectif du jour |
| `virtual_statuses`, `virtual_folders_where` | dossiers virtuels affichés, et où |
| `cover_fetch`, `description_fetch`, `rating_fetch` | recherche en ligne |
| `reader_footer_preset`, `reader_footer_bottom_margin` | barre de lecture |
| `ui_dim_color`, `cover_title_color`, `progress_track_color` | couleurs |

Le nombre de colonnes et de lignes de la grille reste un réglage de KOReader : ☰ → Cover browser → Mosaic → Items per page.

## Comment ça marche

- KOReader charge au démarrage les fichiers `koreader/patches/2-*.lua` ([user patches](https://github.com/koreader/koreader/wiki/User-patches)). `2-apparence-accueil.lua` est un petit chargeur qui lit `config.lua` puis quatre modules, dans l'ordre :
  - `1-commun.lua` : couleurs, cadres et vignettes de couverture ;
  - `2-fiche.lua` : fiche du livre, recherche en ligne, statut, note ;
  - `3-accueil.lua` : pagination, barre du haut, en-tête, objectif, dossiers virtuels, grille ;
  - `4-lecture.lua` : barre de lecture, fin de livre.
- Les modules surchargent des méthodes de KOReader (Menu, TitleBar, FileChooser, ReaderFooter, ReaderStatus) et du plugin Cover browser (MosaicMenu), sans modifier ses fichiers : une mise à jour de KOReader ne l'écrase pas.
- Les icônes viennent du dossier `koreader/icons/`, que KOReader consulte avant ses icônes intégrées. Il suffit de déposer un SVG portant le nom d'une icône d'origine pour la remplacer.
- Les données lues : la base du Cover browser (métadonnées et couvertures), les fichiers de réglages des livres (statut, progression, note, nombre de chapitres mémorisé à la lecture), la base du plugin Statistiques (temps par page, par jour). Rien n'est envoyé ailleurs que les requêtes de recherche (titre et auteur) à Open Library et Google Books, et seulement si tu es connecté.

## Limites connues

- Mode mosaïque uniquement ; le mode liste du Cover browser n'est pas habillé.
- Sur un écran couleur (Boox 4C), les couvertures restent en couleur, y compris dans les vignettes tournées.
- La rotation des vignettes est calculée pixel par pixel (en couleur sur les écrans couleur) : imperceptible sur un Boox Go 6, à désactiver (`tilt_degrees = 0`) si une liseuse lente ou un grand écran rame au changement de page.
- Le nombre de chapitres d'un livre n'est connu qu'après sa première ouverture.
- Les notes moyennes d'Open Library sont souvent absentes pour les éditions françaises ; Google Books prend le relais mais a aussi des trous.
- Les temps de lecture n'existent que pour ce qui a été lu avec le plugin Statistiques activé.
- Les textes de l'interface ajoutés par le patch sont en français.

## Crédits et licence

- [KOReader](https://github.com/koreader/koreader), AGPL-3.0, et son mécanisme de user patches.
- Icônes [Lucide](https://lucide.dev), licence ISC (`koreader/icons/LICENSE-lucide.txt`).
- Données en ligne : [Open Library](https://openlibrary.org) (Internet Archive) et l'API [Google Books](https://developers.google.com/books).

Le code de ce dépôt est sous licence MIT (voir [LICENSE](LICENSE)). Écrit par Alexandre Clain avec l'aide de Claude (Anthropic).
