--[[
Patch KOReader : apparence de la page d'accueil (mode mosaïque du Cover browser),
barre du haut, boutons de navigation en bas, dossiers virtuels par statut
et fiche du livre au tap.

Ce fichier contient uniquement les réglages ; il est lu par
koreader/patches/2-apparence-accueil.lua, qui charge ensuite le code
(1-commun.lua, 2-fiche.lua, 3-accueil.lua, 4-lecture.lua, dans ce dossier).
Les icônes perso vont dans  koreader/icons/  avec le même nom que l'icône
d'origine (ex. chevron.left.svg, home.svg, plus.svg, back.top.svg).

Modifier une valeur puis relancer KOReader. Mettre nil sur une valeur
redonne le comportement d'origine de KOReader.

Unités : les valeurs marquées "px" sont en pixels écran réels. Les autres
sont en points logiques, convertis selon la densité (sur un Boox Go 6,
1 point ≈ 1,9 px).

Ce fichier ne contient que les réglages. Le code est dans les autres fichiers
de ce dossier, chargés par  patches/2-apparence-accueil.lua.
--]]

local CFG = {
    ---------------------------------------------------------------- Grille
    -- Espace entre les vignettes, en px (origine : 10 points).
    grid_spacing = 10,
    -- Marge autour de tout l'écran d'accueil (barre du haut, grille, pagination), en px.
    page_padding = 30,
    -- Recentrer la grille au pixel près (l'original laisse le reste à droite).
    grid_center = true,

    ----------------------------------------------------------- Couvertures
    -- Toutes les couvertures à la même taille, recadrées au centre.
    -- Rapport largeur/hauteur : 2/3 = format livre classique. nil = taille libre (origine).
    cover_ratio = 2/3,
    -- Bordure autour des couvertures, en px (0 = aucune).
    cover_border = 1,
    -- Bordure des livres en cours de lecture, en px (l'espace blanc est réduit
    -- d'autant pour garder la même taille de cadre).
    cover_border_opened = 2,
    -- Couleur de la bordure : "gray_e" (très clair) "gray_d" "light_gray" "gray" "dark_gray" "black".
    cover_border_color = "black",
    -- Espace blanc entre la bordure et l'image, en px.
    cover_padding = 3,
    -- Arrondi des coins de l'image, en px (0 = coins carrés).
    cover_radius = 8,
    -- Appliquer la même taille et le même cadre aux livres sans couverture (titre/auteur dessinés).
    cover_apply_to_fake = true,
    -- Titre du livre (ou nom du dossier) sous la vignette : centré, petit,
    -- coupé avec "…" au-delà de cover_title_lines lignes. La place est toujours
    -- réservée, pour que les cadres restent alignés. Taille en points.
    cover_title = true,
    cover_title_font_size = 11,
    cover_title_lines = 1,
    -- Couleur des titres sous les vignettes : "black", "gray_1", "gray_3", "dark_gray"...
    cover_title_color = "black",
    -- Légère rotation aléatoire de chaque vignette (cadre + titre), en degrés,
    -- à gauche ou à droite selon le livre. 0 = tout droit.
    tilt_degrees = 2,
    -- Petit rectangle "ce livre a une description" en haut à droite (origine : oui).
    description_hint = false,
    -- Un tap sur un livre ouvre une fiche (couverture, auteur, description...)
    -- avec un bouton Ouvrir, au lieu d'ouvrir le livre directement.
    -- L'appui long garde le menu d'origine.
    tap_shows_description = true,
    -- Un livre en cours de lecture s'ouvre directement au tap (la fiche reste
    -- accessible par appui long > Informations sur le livre).
    tap_opens_reading = true,
    -- Bouton "Compléter" de la fiche : cherche en ligne (Open Library puis
    -- Google Books, gratuits, sans clé) d'après le titre et l'auteur : la
    -- couverture (remplacée), la description si absente, la note moyenne.
    cover_fetch = true,
    -- À l'ouverture de la fiche, si on est déjà connecté : récupérer
    -- automatiquement la description manquante et la note moyenne
    -- (au plus une tentative par semaine et par livre).
    description_fetch = true,
    rating_fetch = true,
    -- Temps de lecture dans la fiche (d'après le plugin Statistiques de KOReader :
    -- vitesse sur ce livre, sinon vitesse moyenne, marquée d'une étoile).
    card_reading_time = true,

    ----------------------------------------------------- Statut et progression
    -- Pastille ronde en bas à droite de la couverture selon le statut
    -- (en cours / favoris / terminé), à la place du triangle de coin.
    status_badge = true,
    -- Icônes des pastilles (fichiers de koreader/icons/). Le statut KOReader
    -- "abandoned" (en attente) est utilisé ici comme "favoris".
    status_icons = { reading = "badge.reading", abandoned = "badge.favorite", complete = "badge.complete" },
    -- Libellés des statuts dans la fiche du livre.
    status_labels = { new = "Non lu", reading = "En cours", abandoned = "Favoris", complete = "Terminé" },
    -- Diamètre de la pastille, en fraction de la largeur de la couverture.
    badge_ratio = 0.22,
    -- Pastille "dans une collection" en haut à droite (marque-page).
    collection_badge = true,
    collection_icon = "badge.collection",
    -- Barre de progression en haut de la couverture, centrée, pour les livres
    -- en cours (grille et livre mis en avant).
    progress_bar = true,
    -- Épaisseur en px (origine : 8 points ≈ 15 px), largeur en fraction de la
    -- couverture, distance au bord haut en px.
    progress_height = 6,
    progress_width_ratio = 0.6,
    progress_top = 8,
    -- Couleur de la partie non lue des barres de progression.
    progress_track_color = "dark_gray",

    -------------------------------------------------------------- Dossiers
    -- Cadre autour des dossiers (false = icône, nom et compteur posés
    -- directement, sans bordure, plus léger).
    folder_frame = false,
    -- Avec cadre : même taille et même style que les couvertures.
    -- Bordure et arrondi : nil = comme les couvertures.
    folder_border = nil,
    folder_border_color = nil,
    folder_radius = nil,
    -- Fond du dossier : "white", "gray_e", "gray_d", "light_gray", "black".
    folder_background = "white",
    -- Nom du dossier, sous l'icône dans le cadre : taille et graisse.
    folder_font_size = 15,
    folder_bold = true,
    -- Afficher le nombre d'éléments sous le nom (origine : oui) et sa taille.
    folder_show_count = true,
    folder_count_font_size = 13,
    -- Icône dessinée au-dessus du nom : nom d'un fichier SVG de koreader/icons/
    -- sans extension. nil = pas d'icône (origine).
    folder_icon = "folder",
    -- Taille de cette icône, en fraction de la largeur du cadre.
    folder_icon_ratio = 0.32,
    -- Sans cadre : taille de l'icône en fraction de la largeur de la vignette.
    folder_icon_ratio_free = 0.5,

    ------------------------------------------------------ Panneaux d'accueil
    -- En tête de l'accueil, sans cadre : à gauche le livre en cours en grand
    -- (couverture, titre, auteur, progression, chapitre, pages, temps lu et
    -- restant, bouton Reprendre), à droite les statistiques de lecture. Puis le
    -- titre "Ma bibliothèque" avec un trait et les dossiers en étiquettes, et
    -- les couvertures sur les rangées restantes.
    home_panels = true,
    -- Hauteur de cet en-tête en rangées de la grille (les rangées restantes
    -- sont pour les livres).
    home_panel_rows = 2,
    -- Part de la largeur pour le livre en cours (le reste : statistiques).
    hero_width_ratio = 0.55,
    -- Largeur maximale de sa couverture, en fraction de son panneau.
    hero_cover_max = 0.5,
    -- Hauteur du graphique des 7 jours (points).
    stats_bars_height = 28,
    -- Titre de la section des livres.
    library_title = "Ma bibliothèque",
    -- Vignette "Objectif du jour" en première position de la bibliothèque
    -- (minutes lues aujourd'hui sur l'objectif, jours d'affilée ; un tap règle
    -- l'objectif). Le livre en cours, déjà en haut, est masqué de la grille.
    goal_tile = true,
    goal_default_minutes = 30,
    hide_current_in_grid = true,
    -- Variante sans panneaux : le dernier livre ouvert (s'il est en cours) en
    -- première position avec une étiquette (utilisé si home_panels = false).
    resume_tile = true,
    resume_label = "REPRENDRE",

    ------------------------------------------------------- Dossiers virtuels
    -- À la racine (dossier d'accueil), deux faux dossiers listent tous les
    -- livres terminés / en attente, où qu'ils soient rangés.
    virtual_folders = true,
    -- Dossiers virtuels affichés : "complete" (Terminés) et/ou "abandoned" (Favoris).
    virtual_statuses = { "complete" },
    -- Où les afficher : "home" (dossier d'accueil de KOReader) ou "everywhere"
    -- (dans tous les dossiers, utile si l'accueil n'est pas reconnu).
    -- On peut aussi donner un chemin précis, ex. "/storage/emulated/0/Books".
    virtual_folders_where = "home",
    -- Dans les sous-dossiers, toujours montrer une vignette pour remonter
    -- d'un niveau, avec ce nom et cette icône.
    parent_folder = true,
    parent_folder_label = "Retour",
    parent_folder_icon = "back.top",
    virtual_complete_label = "Terminés",
    virtual_complete_icon = "folder.complete",
    virtual_abandoned_label = "Favoris",
    virtual_abandoned_icon = "folder.favorite",
    -- Ne plus montrer les livres terminés (et/ou favoris) dans les dossiers
    -- normaux : ils ne sont visibles que dans leur dossier virtuel.
    hide_finished = true,
    hide_favorites = false,

    ------------------------------------------------------------- Couleurs
    -- Gris des textes secondaires (libellés des statistiques, auteur, compteurs) :
    -- "gray_1" = le cran juste avant le noir.
    ui_dim_color = "gray_1",
    -- Icônes de la barre du haut (maison, plus, coche) en gris : suffixe des
    -- fichiers home.dim.svg, plus.dim.svg, check.dim.svg ("" = noires).
    titlebar_icon_suffix = ".dim",

    ----------------------------------------------------------- Barre du haut
    -- Titre de l'accueil. nil = celui de KOReader.
    home_title = nil,
    -- Masquer la ligne sous le titre (chemin ou nom du dossier d'accueil).
    hide_home_subtitle = true,
    -- Espace entre la barre du haut et la grille, en px.
    titlebar_bottom_margin = 50,

    -- Marge des icônes maison / plus par rapport aux bords (origine : 5).
    titlebar_side_padding = 16,

    ---------------------------------------------------- Boutons du bas de page
    -- Taille des chevrons (origine : 16).
    footer_icon_size = 22,
    -- Espace entre les boutons du bas (origine : 32).
    footer_spacing = 30,
    -- Masquer les boutons "première page" / "dernière page" (|< et >|).
    footer_hide_first_last = false,
    -- Texte "Page 1 sur 3" : taille (origine : 20) et gras (origine : oui).
    footer_text_size = 17,
    footer_text_bold = false,
    -- Opacité de la pagination : couleur du texte et suffixe des icônes de
    -- chevrons (".dim" = fichiers chevron.*.dim.svg gris à 80 %).
    footer_text_color = "gray_1",
    footer_icon_suffix = ".dim",

    ------------------------------------------------ Barre de lecture (dans un livre)
    -- Préréglage de la barre d'état de KOReader : tout sur une ligne, barre de
    -- progression à gauche, à droite "12 / 300 · 4 % · Chap. 3 / 12".
    -- Appliqué une fois par numéro de version : après, tu peux retoucher
    -- librement dans le menu de KOReader (appui sur la barre > réglages) ;
    -- incrémente reader_footer_preset pour réappliquer le préréglage.
    reader_footer_preset = 2,
    -- Marge sous la barre et espace entre le texte du livre et la barre, en px.
    reader_footer_bottom_margin = 30,
    reader_footer_top_margin = 10,
    -- Chapitre courant / nombre de chapitres (à la place de "pages du chapitre").
    reader_chapter_index = true,
    reader_chapter_label = "Chap.",
    -- Ajouter le temps restant estimé du chapitre : "Chap. 3 / 12 · ~12 min".
    reader_chapter_time_left = true,
    -- En fin de livre : proposer Marquer terminé / Noter / Bibliothèque.
    end_of_book_dialog = true,
    -- Pourcentage sans symbole devant, arrondi à l'entier.
    reader_plain_percentage = true,
}

return CFG
