# Apparence accueil — patch KOReader pour Boox Go 6

Deux mécanismes natifs de KOReader, aucun plugin à déclarer :

- `koreader/patches/2-apparence-accueil.lua` : le chargeur. Il lit `koreader/patches/apparence-accueil/config.lua` (tous les réglages) puis les quatre fichiers de code du même dossier : `1-commun.lua` (couleurs, cadres de couverture), `2-fiche.lua` (fiche du livre, recherche en ligne, statut, note), `3-accueil.lua` (pagination, barre du haut, en-tête, dossiers virtuels, grille) et `4-lecture.lua` (barre de lecture, fin de livre).
- `koreader/icons/*.svg` : toute icône déposée ici avec le nom d'une icône d'origine la remplace partout dans l'interface. Le jeu fourni vient de [Lucide](https://lucide.dev) (licence ISC, fichier `LICENSE-lucide.txt`).

## Installation sur le Boox

1. Brancher le Boox en USB (ou passer par l'explorateur de fichiers du Boox).
2. Ouvrir le dossier `koreader` à la racine du stockage interne (celui qui contient `settings.reader.lua`).
3. Copier dedans le contenu du dossier `koreader` de ce paquet : les sous-dossiers `patches` (avec son sous-dossier `apparence-accueil`) et `icons`. Les créer s'ils n'existent pas.
4. Fermer complètement KOReader et le relancer.
5. Vérifier que l'accueil est en mode mosaïque : menu ☰ > Cover browser > Display mode > Mosaic.

Si le patch plante, KOReader affiche `Error applying patch` au démarrage et continue sans lui : rien ne bloque la liseuse. Pour le désactiver, renommer `2-apparence-accueil.lua` en `.lua.off` ou le supprimer (le dossier `apparence-accueil` peut rester, KOReader n'y touche pas).

## Ce que ça change

- **Couvertures** : toutes au même format (2:3), recadrées au centre, coins arrondis, bordure de 1 px noire à 3 px de l'image (2 px pour les livres en cours de lecture). Titre centré sous la vignette, une ligne puis « … », en noir. Chaque vignette (cadre + titre) est légèrement tournée, jusqu'à 2°, à gauche ou à droite selon le livre, toujours de la même façon pour un même fichier. Le soulignement noir que KOReader met sous le dernier livre ouvert est masqué. Les livres sans couverture (titre/auteur dessinés) prennent le même cadre. Le petit rectangle « ce livre a une description » en haut à droite est retiré.
- **Statut** : pastille ronde en bas à droite de la couverture (livre ouvert = en cours, étoile = favoris, coche = terminé) à la place du triangle de coin. Marque-page en haut à droite si le livre est dans une collection KOReader. Le statut KOReader « En attente » (on hold) est utilisé comme « Favoris ».
- **Progression** : barre fine, noire sur piste gris foncé (`progress_track_color`), en haut de la couverture des livres en cours (grille et livre mis en avant).
- **Tap sur un livre** : un livre en cours de lecture s'ouvre directement. Sinon, ouvre une fiche avec la couverture, le titre, l'auteur, la série, les mots-clés, pages et chapitres, format, statut et progression, temps de lecture (« ~5 h 20 · restant : ~2 h 10 », d'après le plugin Statistiques : vitesse sur ce livre, ou vitesse moyenne marquée d'une étoile), note (mes étoiles KOReader, et la note moyenne trouvée en ligne), puis la description (défilable). Si la liseuse est connectée, la description manquante et la note moyenne sont récupérées automatiquement à l'ouverture de la fiche (une tentative par semaine et par livre). Le nombre de chapitres est connu après la première ouverture du livre. Les boutons de statut (Réinitialiser, Favoris, Terminé, Noter) sont sous les métadonnées, au-dessus de la description ; les actions (Fermer, Compléter, Détails, Ouvrir) en bas. « Compléter » cherche en ligne (Open Library, puis Google Books en secours, gratuits, sans compte) d'après le titre et l'auteur, en ne retenant qu'un résultat dont l'auteur correspond : la couverture (remplacée), la description si elle manque, la note moyenne ; le WiFi est demandé si besoin. La description récupérée est enregistrée comme métadonnée personnalisée du livre (comme « Modifier les métadonnées » de KOReader). Réinitialiser supprime le fichier de réglages du livre, comme le « Reset » de KOReader, après confirmation. L'appui long garde le menu d'origine de KOReader. Le mode sélection multiple n'est pas affecté.
- **Dossiers** : sans cadre (`folder_frame = false`) : grande icône, nom en gras, compteur en gris, dans l'espace d'une couverture ; ou avec un cadre du même style que les couvertures. Même rotation légère que les livres. Dans les sous-dossiers, une vignette « Retour » remonte d'un niveau.
- **En-tête de l'accueil** (deux rangées de la grille, sans cadre) : à gauche le livre en cours en grand : la couverture pleine hauteur avec la barre de progression en haut et le bouton « Reprendre » (blanc, texte noir) posé en bas, puis « EN COURS DE LECTURE », titre, auteur, barre de progression + pourcentage, chapitre, page, temps déjà lu et temps restant estimé ; un trait vertical d'un pixel sépare ce bloc des statistiques ; un tap n'importe où l'ouvre (dans la grille, ce même livre ouvre sa fiche). À droite « MES STATISTIQUES » en cartes sur deux colonnes : aujourd'hui, 7 derniers jours, le graphique des 7 jours, temps moyen par page, livres terminés dans l'année, temps et pages en tout ; un tap ouvre le calendrier de lecture de KOReader. Puis, après le même espace que sous la barre du haut, le titre « Ma bibliothèque » suivi d'un trait jusqu'au bord, avec les dossiers en étiquettes tapables (les vrais dossiers, puis « Terminés » tout à droite) sur la même ligne ou en dessous ; les rangées restantes ne montrent que des livres, sauf la première case : la vignette « Objectif du jour » (minutes lues aujourd'hui sur l'objectif, barre, jours d'affilée au-dessus de l'objectif ; un tap règle l'objectif, 30 min par défaut). Le livre en cours, déjà en haut, n'est pas répété dans la grille.
- **Dossiers virtuels** : un faux dossier « Terminés » (et « Favoris » si on l'ajoute à `virtual_statuses`) liste tous les livres de ce statut, où qu'ils soient rangés (le chiffre affiché est le compte). Rien à créer sur la liseuse. Ils n'apparaissent que dans le dossier d'accueil défini dans KOReader (`virtual_folders_where = "home"` ; `"everywhere"` pour tous les dossiers, ou un chemin exact). Les livres terminés n'apparaissent plus dans les dossiers normaux (`hide_finished`), seulement dans « Terminés ». « ../ » ou le bouton retour ramènent à l'accueil.
- **Grille** : 10 px entre les vignettes, grille recentrée au pixel près, et une marge de 30 px autour de tout l'écran (barre du haut, grille, pagination).
- **Barre du haut** : titre de KOReader (« KOReader · Favoris » dans un dossier virtuel), 50 px d'espace sous la barre avant la grille, plus de ligne de chemin en dessous, icônes maison et plus décollées des bords.
- **Bas de page** : chevrons fins (les quatre : |< < > >|) et texte de page un peu plus petit que les chevrons, non gras, le tout en gris à 80 %. Ces réglages du bas s'appliquent à tous les menus de KOReader, pour rester cohérent.

- **Fin de livre** : en dépassant la dernière page, une fenêtre propose Marquer terminé, Noter, Terminé et noter, Bibliothèque, Fermer (remplace celle de KOReader).
- **Barre de lecture (dans un livre)** : préréglage appliqué une fois : barre de progression à gauche, texte à droite sur la même ligne « 12 / 300 · 4 % · Chap. 3 / 12 · ~12 min » (temps restant estimé du chapitre) (page / total, pourcentage, chapitre courant / nombre de chapitres du même niveau), alignée sur les marges du texte du livre, 30 px sous la barre et 10 px entre le texte et la barre. Ensuite les réglages se retouchent librement dans KOReader (appui sur la barre d'état > réglages) ; pour réappliquer le préréglage, augmenter `reader_footer_preset`.

## Régler l'apparence

Tout se passe dans `koreader/patches/apparence-accueil/config.lua`. Modifier la valeur, relancer KOReader. `nil` redonne le comportement d'origine.

| Réglage | Effet | Valeur |
|---|---|---|
| `grid_spacing` | espace entre les vignettes et autour de la page, px | 10 |
| `page_padding` | marge autour de tout l'écran d'accueil, px | 30 |
| `grid_center` | recentrer la grille | true |
| `cover_ratio` | format des couvertures (largeur/hauteur), `nil` = libre | 2/3 |
| `cover_border` / `cover_border_opened` / `cover_border_color` | bordure des couvertures, px (livre en cours : plus épaisse) | 1 / 2 / black |
| `cover_padding` | blanc entre bordure et image, px | 3 |
| `cover_title` / `cover_title_font_size` / `cover_title_lines` / `cover_title_color` | titre sous la vignette | true / 11 / 1 / black |
| `tilt_degrees` | rotation aléatoire des vignettes, en degrés (0 = aucune) | 2 |
| `tap_opens_reading` | un livre en cours s'ouvre directement au tap | true |
| `cover_fetch` | bouton « Compléter » (Open Library, Google Books) dans la fiche | true |
| `description_fetch` / `rating_fetch` | récupération automatique de la description manquante et de la note à l'ouverture de la fiche | true / true |
| `card_reading_time` | temps de lecture dans la fiche | true |
| `home_panels` / `home_panel_rows` | en-tête livre en cours + statistiques, hauteur en rangées | true / 2 |
| `hero_width_ratio` / `hero_cover_max` | part de largeur du livre en cours, largeur max de sa couverture | 0.55 / 0.5 |
| `stats_bars_height` / `library_title` | hauteur du graphique ; titre de la section des livres | 28 / Ma bibliothèque |
| `goal_tile` / `goal_default_minutes` / `hide_current_in_grid` | vignette Objectif du jour, objectif par défaut, livre en cours masqué de la grille | true / 30 / true |
| `reader_chapter_time_left` / `end_of_book_dialog` | temps restant du chapitre dans la barre ; fenêtre de fin de livre | true / true |
| `virtual_statuses` | dossiers virtuels affichés (`complete`, `abandoned`) | { complete } |
| `folder_frame` / `folder_icon_ratio_free` | cadre autour des dossiers ; taille de l'icône sans cadre | false / 0.5 |
| `resume_tile` / `resume_label` | vignette « Reprendre » (si `home_panels = false`) | true / REPRENDRE |
| `cover_radius` | arrondi des coins de l'image, px | 8 |
| `cover_apply_to_fake` | même cadre pour les livres sans couverture | true |
| `description_hint` | rectangle « a une description » en haut à droite | false |
| `tap_shows_description` | fiche au tap au lieu d'ouvrir | true |
| `status_badge` / `badge_ratio` | pastille de statut, diamètre en fraction de la largeur | true / 0.22 |
| `status_icons` / `status_labels` | icônes des pastilles et libellés des statuts | |
| `collection_badge` / `collection_icon` | marque-page si dans une collection | true |
| `progress_bar` / `progress_height` / `progress_width_ratio` / `progress_top` | barre de progression | false / 6 / 0.6 / 8 |
| `folder_border` / `folder_border_color` / `folder_radius` | cadre des dossiers, `nil` = comme les couvertures | nil |
| `folder_background` | fond des dossiers | white |
| `folder_font_size` / `folder_bold` | nom du dossier | 15 / true |
| `folder_show_count` / `folder_count_font_size` | compteur d'éléments | true / 13 |
| `folder_icon` / `folder_icon_ratio` | icône au-dessus du nom | folder / 0.32 |
| `virtual_folders` / `virtual_folders_where` | dossiers « Terminés » / « Favoris », et où les afficher (`home`, `everywhere` ou un chemin) | true / home |
| `parent_folder` / `parent_folder_label` / `parent_folder_icon` | vignette de retour dans les sous-dossiers | true / Retour / back.top |
| `hide_finished` / `hide_favorites` | cacher ces livres hors de leur dossier virtuel | true / false |
| `home_title` / `hide_home_subtitle` | titre de l'accueil (nil = celui de KOReader) et ligne de chemin | nil / true |
| `titlebar_bottom_margin` | espace entre la barre du haut et la grille, px | 50 |
| `virtual_*_label` / `virtual_*_icon` | leurs noms et icônes | |
| `titlebar_side_padding` | marge des icônes de la barre du haut | 16 |
| `footer_icon_size` / `footer_spacing` | chevrons du bas | 22 / 30 |
| `footer_hide_first_last` | cacher \|< et >\| | false |
| `footer_text_size` / `footer_text_bold` | texte « Page 1 sur 3 » | 17 / false |
| `footer_text_color` / `footer_icon_suffix` | opacité de la pagination (texte, et icônes `chevron.*.dim.svg`) | gray_1 / .dim |
| `ui_dim_color` / `titlebar_icon_suffix` | gris des textes secondaires ; icônes grises de la barre du haut (`home.dim.svg`, `plus.dim.svg`, `check.dim.svg`) | gray_1 / .dim |
| `reader_footer_preset` / `reader_footer_bottom_margin` / `reader_footer_top_margin` | préréglage de la barre de lecture, marge basse et espace au-dessus, px | 2 / 30 / 10 |
| `reader_chapter_index` / `reader_chapter_label` | « Chap. 3 / 12 » à la place des pages du chapitre | true / Chap. |
| `reader_plain_percentage` | pourcentage sans symbole devant | true |

Les valeurs marquées px sont en pixels écran réels ; les autres sont des points logiques que KOReader convertit selon la densité (sur le Go 6, 1 point ≈ 1,9 pixel).

Le nombre de colonnes et de lignes se règle déjà dans KOReader sans patch : menu ☰ > Cover browser > Mosaic > Items per page.

## Icônes

Le dossier `koreader/icons/` contient une cinquantaine d'icônes Lucide renommées aux noms KOReader : pagination, barre du haut, menus du lecteur (réglages, recherche, outils, typographie, rotation, etc.), alertes, favoris, wifi, alignements, plus les pastilles de statut (`badge.*`) et les dossiers virtuels (`folder.*`) ajoutés par le patch. Les originales de l'écran d'accueil sont dans `icones-originales/` pour comparaison.

Pour en remplacer une autre : prendre le nom du fichier dans `koreader/resources/icons/mdlight/` sur la liseuse, déposer un SVG carré de ce nom dans `koreader/icons/`. Les SVG Lucide se récupèrent sur https://lucide.dev, en remplaçant `stroke="currentColor"` par `stroke="#000000"` et `width`/`height` 24 par 48.

Les icônes sont mises en cache au premier affichage : relancer KOReader après chaque changement.
