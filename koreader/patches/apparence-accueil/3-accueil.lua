-- Apparence accueil : pagination, barre du haut, en-tête (livre en cours,
-- statistiques, objectif), dossiers virtuels, grille des couvertures
local AA = ...
local CFG = AA.CFG

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local userpatch = require("userpatch")
local util = require("util")
local Screen = Device.screen

local color, DIM_COLOR = AA.color, AA.DIM_COLOR
local pagePadding, coverInset, coverTargetSize = AA.pagePadding, AA.coverInset, AA.coverTargetSize
local coverTitleBlockHeight, coverTitleFace, tiltMargin = AA.coverTitleBlockHeight, AA.coverTitleFace, AA.tiltMargin
local makeCoverFrame, makeCroppedImage, makeTile = AA.makeCoverFrame, AA.makeCroppedImage, AA.makeTile
local formatDuration, readingSpeed = AA.formatDuration, AA.readingSpeed
local function showBookCard(...) return AA.showBookCard(...) end

-- Remplis quand le plugin coverbrowser est chargé
local BookInfoManager -- module du plugin (base des couvertures et métadonnées)
local FakeCover       -- classe du plugin : couverture dessinée pour les livres sans image

-------------------------------------------------------------------------------
-- 1. Boutons de navigation en bas de page (widget Menu, utilisé par l'accueil)
-------------------------------------------------------------------------------

-- Widget vide qui remplace un bouton qu'on veut masquer : il occupe 0 px
-- et accepte sans broncher les appels show/hide/enable que Menu lui fait.
local function makeDummyButton()
    local dummy = HorizontalSpan:new{ width = 0 }
    dummy.show = function() end
    dummy.hide = function() end
    dummy.showHide = function() end
    dummy.enable = function() end
    dummy.disable = function() end
    dummy.enableDisable = function() end
    return dummy
end

local orig_Menu_init = Menu.init
Menu.init = function(self)
    local pad = pagePadding()
    if pad > 0 and self.name == "filemanager" then
        self.width = Screen:getWidth() - 2*pad
        self.height = Screen:getHeight() - 2*pad
    end
    if CFG.footer_icon_size or CFG.footer_hide_first_last then
        local size = CFG.footer_icon_size and Screen:scaleBySize(CFG.footer_icon_size)
        local function chevron(icon, callback)
            return Button:new{
                icon = icon,
                icon_width = size,
                icon_height = size,
                callback = callback,
                bordersize = 0,
                show_parent = self.show_parent,
            }
        end
        local sfx = CFG.footer_icon_suffix or ""
        local left, right, first, last = "chevron.left" .. sfx, "chevron.right" .. sfx, "chevron.first" .. sfx, "chevron.last" .. sfx
        if BD.mirroredUILayout() then
            left, right = right, left
            first, last = last, first
        end
        -- Menu:init() garde ces boutons s'ils existent déjà, donc on les crée
        -- avant lui avec nos réglages.
        self.page_info_left_chev = self.page_info_left_chev or chevron(left, function() self:onPrevPage() end)
        self.page_info_right_chev = self.page_info_right_chev or chevron(right, function() self:onNextPage() end)
        if CFG.footer_hide_first_last then
            self.page_info_first_chev = makeDummyButton()
            self.page_info_last_chev = makeDummyButton()
        else
            self.page_info_first_chev = self.page_info_first_chev or chevron(first, function() self:onFirstPage() end)
            self.page_info_last_chev = self.page_info_last_chev or chevron(last, function() self:onLastPage() end)
        end
    end

    orig_Menu_init(self)

    if CFG.footer_spacing and self.page_info_spacer then
        self.page_info_spacer.width = Screen:scaleBySize(CFG.footer_spacing)
    end
    if (CFG.footer_text_size or CFG.footer_text_bold ~= nil) and self.page_info_text then
        local btn = self.page_info_text
        if CFG.footer_text_size then
            btn.text_font_size = CFG.footer_text_size
        end
        if CFG.footer_text_bold ~= nil then
            btn.text_font_bold = CFG.footer_text_bold
        end
        -- Même mécanique que Button:setText() : on reconstruit le bouton.
        if btn.label_widget then
            btn.label_widget:free()
        end
        btn:init()
    end
    if CFG.footer_text_color and self.page_info_text then
        -- Le bouton se reconstruit à chaque changement de page (setText) :
        -- on recolore le texte après chaque init.
        local btn = self.page_info_text
        local text_color = color(CFG.footer_text_color, Blitbuffer.COLOR_BLACK)
        local orig_btn_init = btn.init
        btn.init = function(b)
            orig_btn_init(b)
            if b.label_widget then
                b.label_widget.fgcolor = text_color
            end
        end
        if btn.label_widget then
            btn.label_widget.fgcolor = text_color
        end
    end
    if self.page_info then
        self.page_info:resetLayout()
    end
    if pad > 0 and self.name == "filemanager" then
        -- Le conteneur du bouton "dossier parent" est dimensionné sur la
        -- largeur de l'écran : on le ramène à la largeur intérieure.
        local content = self[1] and self[1][1]
        local page_return = content and content[2]
        if page_return and page_return[1] and page_return[1].dimen then
            page_return[1].dimen.w = self.inner_dimen.w
        end
    end
end

-------------------------------------------------------------------------------
-- 2. Barre du haut de l'accueil : marge des icônes
-------------------------------------------------------------------------------

local orig_TitleBar_init = TitleBar.init
TitleBar.init = function(self)
    -- On ne touche qu'à la barre de l'explorateur de fichiers (icône maison à gauche)
    local is_fm_bar = self.fullscreen and (self.left_icon == "home" or self._apparence_fm_bar)
    local sfx = CFG.titlebar_icon_suffix or ""
    if is_fm_bar and sfx ~= "" and not self.left_icon:find(sfx, 1, true) then
        self.left_icon = self.left_icon .. sfx
        if self.right_icon and not self.right_icon:find(sfx, 1, true) then
            self.right_icon = self.right_icon .. sfx
        end
        self._apparence_fm_bar = true
    end
    if is_fm_bar and pagePadding() > 0 and not self.width then
        self.width = Screen:getWidth() - 2*pagePadding()
    end
    if is_fm_bar and CFG.hide_home_subtitle then
        self.subtitle = nil
    end
    if is_fm_bar and CFG.titlebar_bottom_margin then
        self.bottom_v_padding = CFG.titlebar_bottom_margin
    end
    orig_TitleBar_init(self)
    if CFG.titlebar_side_padding and is_fm_bar then
        local pad = Screen:scaleBySize(CFG.titlebar_side_padding)
        if self.left_button then
            self.left_button.padding_left = pad
            self.left_button:update()
        end
        if self.right_button then
            self.right_button.padding_right = pad
            self.right_button:update()
        end
    end
end

-- L'explorateur remet "plus" / "check" en quittant le mode sélection : on garde le gris
local orig_TitleBar_setRightIcon = TitleBar.setRightIcon
TitleBar.setRightIcon = function(self, icon)
    local sfx = CFG.titlebar_icon_suffix or ""
    if self._apparence_fm_bar and sfx ~= "" and icon and not icon:find(sfx, 1, true) then
        icon = icon .. sfx
    end
    return orig_TitleBar_setRightIcon(self, icon)
end

-- Titre de l'accueil
local FileManager = require("apps/filemanager/filemanager")
if CFG.home_title then
    FileManager.title = CFG.home_title
end

-- Marge autour de tout l'explorateur de fichiers
if pagePadding() > 0 then
    local orig_setupLayout = FileManager.setupLayout
    FileManager.setupLayout = function(self)
        orig_setupLayout(self)
        if self[1] and self[1].padding ~= nil then
            self[1].padding = pagePadding()
        end
    end
end

-------------------------------------------------------------------------------
-- 5b. Panneaux d'accueil : livre en cours et statistiques (deux rangées)
-------------------------------------------------------------------------------

local DAY_LETTERS = { Mon = "L", Tue = "M", Wed = "M", Thu = "J", Fri = "V", Sat = "S", Sun = "D" }

-- Objectif de lecture quotidien, en minutes
local function readingGoalMinutes()
    return tonumber(G_reader_settings:readSetting("apparence_accueil_goal")) or CFG.goal_default_minutes or 30
end

-- Lit la base du plugin Statistiques : aujourd'hui, 7 derniers jours, série
-- de jours (au-dessus de l'objectif), année, total.
local function computeHomeStats()
    local stats = { week = {} }
    local ok, err = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local DataStorage = require("datastorage")
        local db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if lfs.attributes(db, "mode") ~= "file" then return end
        local conn = SQ3.open(db)
        local now = os.time()
        local d = os.date("*t", now)
        local today_start = os.time{ year = d.year, month = d.month, day = d.day, hour = 0 }
        local year_start = os.time{ year = d.year, month = 1, day = 1, hour = 0 }
        local function sums(since)
            local t, p = conn:rowexec(("SELECT sum(duration), count(*) FROM page_stat_data WHERE start_time >= %d;"):format(since))
            return tonumber(t) or 0, tonumber(p) or 0
        end
        stats.today_time, stats.today_pages = sums(today_start)
        stats.year_time, stats.year_pages = sums(year_start)
        local t, p = conn:rowexec("SELECT sum(total_read_time), sum(total_read_pages) FROM book;")
        stats.total_time, stats.total_pages = tonumber(t) or 0, tonumber(p) or 0

        -- Par jour, sur 400 jours (pour la série et la semaine)
        local stmt = conn:prepare(([[
            SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS day, sum(duration), count(*)
            FROM page_stat_data WHERE start_time >= %d GROUP BY day;
        ]]):format(today_start - 400 * 86400))
        local res, nb = stmt:reset():resultset("i")
        stmt:close()
        conn:close()
        local per_day = {}
        for i = 1, nb or 0 do
            per_day[tostring(res[1][i])] = { time = tonumber(res[2][i]) or 0, pages = tonumber(res[3][i]) or 0 }
        end
        local function dayKey(i) -- i jours avant aujourd'hui (midi, pour éviter les changements d'heure)
            return os.date("%Y-%m-%d", today_start - i * 86400 + 43200)
        end
        stats.week_time, stats.week_pages = 0, 0
        for i = 6, 0, -1 do
            local e = per_day[dayKey(i)] or { time = 0, pages = 0 }
            local wday = os.date("%a", today_start - i * 86400 + 43200)
            table.insert(stats.week, { label = DAY_LETTERS[wday] or wday:sub(1, 1), time = e.time, today = i == 0 })
            stats.week_time = stats.week_time + e.time
            stats.week_pages = stats.week_pages + e.pages
        end
        local min_time = readingGoalMinutes() * 60
        local today = per_day[dayKey(0)]
        local streak = 0
        for i = (today and today.time >= min_time) and 0 or 1, 400 do
            local e = per_day[dayKey(i)]
            if e and e.time >= min_time then
                streak = streak + 1
            else
                break
            end
        end
        stats.streak = streak
    end)
    if not ok then
        logger.warn("apparence-accueil: statistiques :", err)
    end
    return stats
end

-- Livres terminés cette année : d'après la date de passage en "terminé"
local function countFinishedThisYear(chooser, path, year, acc)
    acc = acc or { n = 0 }
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then return acc.n end
    for f in iter, dir_obj do
        if f ~= "." and f ~= ".." and (FileChooser.show_hidden or not util.stringStartsWith(f, ".")) then
            local fullpath = path .. "/" .. f
            local mode = lfs.attributes(fullpath, "mode")
            if mode == "directory" then
                if chooser:show_dir(f) then
                    countFinishedThisYear(chooser, fullpath, year, acc)
                end
            elseif mode == "file" and BookList.getBookStatus(fullpath) == "complete" then
                local summary = BookList.getDocSettings(fullpath):readSetting("summary")
                local modified = summary and summary.modified
                if type(modified) == "string" and modified:sub(1, 4) == tostring(year) then
                    acc.n = acc.n + 1
                end
            end
        end
    end
    return acc.n
end

local function fmtPages(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 10000 then
        return tostring(math.floor(n / 1000)) .. " " .. string.format("%03d", n % 1000) .. " pages"
    end
    return n .. (n > 1 and " pages" or " page")
end

-- Barres des 7 derniers jours, lettre du jour dessous
local WeekBars = require("ui/widget/widget"):extend{
    days = nil, width = nil, height = nil,
}
function WeekBars:getSize()
    return Geom:new{ w = self.width, h = self.height }
end
function WeekBars:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local n = #self.days
    if n == 0 then return end
    local gap = Screen:scaleBySize(4)
    local bar_w = math.floor((self.width - gap * (n - 1)) / n)
    local max_t = 60
    for _, day in ipairs(self.days) do
        if day.time > max_t then max_t = day.time end
    end
    for i, day in ipairs(self.days) do
        local bx = x + (i - 1) * (bar_w + gap)
        local h = math.floor(self.height * day.time / max_t + 0.5)
        if day.time > 0 and h < 3 then h = 3 end
        -- piste claire pleine hauteur, barre par-dessus, coins arrondis
        local r = math.floor(bar_w / 2)
        bb:paintRoundedRect(bx, y, bar_w, self.height, Blitbuffer.COLOR_GRAY_E, r)
        if h > 0 then
            bb:paintRoundedRect(bx, y + self.height - h, bar_w, h, day.today and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_6, math.min(r, math.floor(h / 2)))
        end
    end
end

-- Zone tactile d'un panneau (sans cadre)
local HomePanel = InputContainer:extend{
    width = nil, height = nil, content = nil, on_tap = nil, align = "left",
}
function HomePanel:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapPanel = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    local dimen = Geom:new{ w = self.width, h = self.height }
    if self.align == "center" then
        self[1] = CenterContainer:new{ dimen = dimen, self.content }
    else -- calé en haut à gauche (InputContainer peint son contenu à sa position)
        self[1] = self.content
    end
end
function HomePanel:onTapPanel()
    if self.on_tap then
        self.on_tap()
    end
    return true
end

-- Chiffre + libellé en petit dessous
local function statBlock(value, label, w, size)
    return VerticalGroup:new{ align = "left",
        TextWidget:new{ text = value, face = Font:getFace("smallinfofontbold", size or 15), bold = true, max_width = w },
        TextWidget:new{ text = label, face = Font:getFace("x_smallinfofont", 10), fgcolor = DIM_COLOR, max_width = w },
    }
end

-- Petite étiquette arrondie (badge)
local function pill(text, filled)
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("smallinfofontbold", 11),
        bold = true,
        fgcolor = filled and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
    }
    local h = label:getSize().h + 2 * Screen:scaleBySize(3)
    return FrameContainer:new{
        margin = 0,
        padding = Screen:scaleBySize(3),
        padding_left = Screen:scaleBySize(8),
        padding_right = Screen:scaleBySize(8),
        bordersize = 1,
        color = Blitbuffer.COLOR_BLACK,
        background = filled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        radius = math.floor(h / 2),
        label,
    }
end

-- Barre de progression fine : remplissage noir, piste gris clair
local function thinProgress(width, percent, height)
    local h = height or Screen:scaleBySize(5)
    local bar = ProgressWidget:new{
        width = width, height = h, margin_h = 0, margin_v = 0,
        radius = math.floor(h / 2), bordersize = 0,
        bgcolor = color(CFG.progress_track_color, Blitbuffer.COLOR_DARK_GRAY), fillcolor = Blitbuffer.COLOR_BLACK,
    }
    bar:setPercentage(percent or 0)
    return bar
end

-- Ajoute, sur un cadre de couverture, la barre de progression en haut au centre
local function addCoverProgress(frame, cover_w, percent)
    local width = math.floor(cover_w * (CFG.progress_width_ratio or 0.6))
    local bar = thinProgress(width, percent, CFG.progress_height or 6)
    local inset = coverInset()
    local prev_paintTo = frame.paintTo
    frame.paintTo = function(this, bb, x, y)
        if prev_paintTo then prev_paintTo(this, bb, x, y) else FrameContainer.paintTo(this, bb, x, y) end
        bar:paintTo(bb, math.floor(x) + inset + math.floor((cover_w - width) / 2), math.floor(y) + inset + (CFG.progress_top or 8))
    end
    return frame
end

local function formatSeconds(seconds)
    if not seconds or seconds ~= seconds or seconds <= 0 then return nil end
    if seconds < 60 then
        return math.floor(seconds + 0.5) .. " s"
    end
    local m = math.floor(seconds / 60)
    local sec = math.floor(seconds - m * 60 + 0.5)
    if sec == 0 then return m .. " min" end
    return string.format("%d min %02d", m, sec)
end

-- Libellé en petites capitales grises
local function caption(text, w)
    return TextWidget:new{ text = text:upper(), face = Font:getFace("x_smallinfofont", 10),
        fgcolor = DIM_COLOR, max_width = w }
end

-- "Hero" : le livre en cours, en grand (couverture à gauche, informations à droite)
local function buildHero(ui, width, height)
    local last = G_reader_settings:readSetting("lastfile")
    local reading = last and lfs.attributes(last, "mode") == "file" and BookList.getBookStatus(last) == "reading"
    if not reading then
        return HomePanel:new{ width = width, height = height, align = "center",
            content = VerticalGroup:new{ align = "center",
                IconWidget:new{ icon = "book.opened", width = Screen:scaleBySize(30), height = Screen:scaleBySize(30), alpha = true },
                VerticalSpan:new{ width = Screen:scaleBySize(8) },
                TextWidget:new{ text = "Aucun livre en cours", face = Font:getFace("x_smallinfofont", 13), fgcolor = DIM_COLOR },
            },
        }
    end
    local props = ui.bookinfo:getDocProps(last) or {}
    local book_info = BookList.getBookInfo(last)
    local ds = BookList.hasBookBeenOpened(last) and BookList.getDocSettings(last)
    local percent = book_info.percent_finished or 0
    local pages = tonumber(props.pages) or tonumber(book_info.pages)
        or (ds and (tonumber(ds:readSetting("pagemap_doc_pages")) or tonumber(ds:readSetting("doc_pages"))))
    local gap = Screen:scaleBySize(14)

    -- Couverture : toute la hauteur disponible, largeur au format livre
    local cover_h = height - 2 * coverInset()
    local cover_w = math.floor(cover_h * (CFG.cover_ratio or 2/3))
    local max_cover_w = math.floor(width * (CFG.hero_cover_max or 0.5)) - 2 * coverInset()
    if cover_w > max_cover_w then
        cover_w = max_cover_w
        cover_h = math.floor(cover_w / (CFG.cover_ratio or 2/3))
    end
    local cover_widget
    local bookinfo = BookInfoManager and BookInfoManager:getBookInfo(last, true)
    if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and not bookinfo.ignore_cover then
        cover_widget = makeCroppedImage(bookinfo.cover_bb, cover_w, cover_h)
    else
        if bookinfo and bookinfo.cover_bb then bookinfo.cover_bb:free() end
        cover_widget = FakeCover and FakeCover:new{ width = cover_w, height = cover_h, bordersize = 0,
            filename = select(2, util.splitFilePathName(last)), title = props.title, authors = props.authors }
            or HorizontalSpan:new{ width = cover_w }
    end
    local frame = makeCoverFrame(cover_widget, cover_w, cover_h, false, true)
    if CFG.progress_bar then
        addCoverProgress(frame, cover_w, percent)
    end
    -- Bouton "Reprendre" posé sur la couverture, en bas, centré
    local frame_size = frame:getSize()
    local cover_block = OverlapGroup:new{
        dimen = Geom:new{ w = frame_size.w, h = frame_size.h },
        frame,
        BottomContainer:new{
            dimen = Geom:new{ w = frame_size.w, h = frame_size.h },
            VerticalGroup:new{ align = "center",
                pill(CFG.resume_label or "Reprendre", false),
                VerticalSpan:new{ width = Screen:scaleBySize(12) },
            },
        },
    }

    -- Colonne d'informations
    local col_w = width - frame_size.w - gap
    local column = VerticalGroup:new{ align = "left" }
    local function add(widget, after)
        table.insert(column, widget)
        if after and after > 0 then table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(after) }) end
    end
    add(caption("En cours de lecture", col_w), 6)
    add(TextBoxWidget:new{
        text = props.display_title or props.title or select(2, util.splitFilePathName(last)),
        face = Font:getFace("tfont", 17), bold = true, width = col_w,
        height = Screen:scaleBySize(72), height_adjust = true, height_overflow_show_ellipsis = true,
    }, 3)
    if props.authors then
        add(TextWidget:new{ text = props.authors, face = Font:getFace("x_smallinfofont", 13),
            fgcolor = DIM_COLOR, max_width = col_w }, 14)
    else
        add(VerticalSpan:new{ width = 0 }, 8)
    end

    -- Progression : barre + pourcentage, chapitre
    local pct = TextWidget:new{ text = math.floor(percent * 100 + 0.5) .. " %", face = Font:getFace("smallinfofontbold", 13), bold = true }
    add(HorizontalGroup:new{ align = "center",
        thinProgress(col_w - pct:getSize().w - Screen:scaleBySize(10), percent, Screen:scaleBySize(6)),
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        pct,
    }, 6)
    local chap_cur = ds and ds:readSetting("apparence_chapter_current")
    local chap_tot = ds and ds:readSetting("apparence_chapters")
    if chap_cur and chap_tot then
        add(TextWidget:new{ text = "Chapitre " .. chap_cur .. " / " .. chap_tot, face = Font:getFace("x_smallinfofont", 12), max_width = col_w }, 3)
    end
    if pages then
        add(TextWidget:new{ text = "Page " .. math.floor(percent * pages + 0.5) .. " / " .. pages, face = Font:getFace("x_smallinfofont", 12), max_width = col_w }, 3)
    end
    add(VerticalSpan:new{ width = 0 }, 9)

    -- Temps : déjà lu, restant
    local per_page, from_book, total_time = readingSpeed(last)
    local left_time
    if pages and per_page then
        left_time = (pages - percent * pages) * per_page
    elseif total_time and percent > 0.02 then
        left_time = total_time * (1 - percent) / percent -- estimation d'après le rythme sur ce livre
        from_book = true
    end
    local times = HorizontalGroup:new{ align = "top" }
    local half = math.floor(col_w / 2)
    if total_time and total_time > 0 then
        table.insert(times, VerticalGroup:new{ align = "left",
            TextWidget:new{ text = formatDuration(total_time), face = Font:getFace("smallinfofontbold", 15), bold = true, max_width = half },
            caption("déjà lu", half),
        })
        table.insert(times, HorizontalSpan:new{ width = half - times[#times]:getSize().w })
    end
    if left_time then
        table.insert(times, VerticalGroup:new{ align = "left",
            TextWidget:new{ text = "~" .. formatDuration(left_time), face = Font:getFace("smallinfofontbold", 15), bold = true, max_width = half },
            caption(from_book and "restant" or "restant (moyenne)", half),
        })
    end
    if #times > 0 then add(times, 0) end

    local content = HorizontalGroup:new{ align = "top", cover_block, HorizontalSpan:new{ width = gap }, column }
    return HomePanel:new{
        width = width, height = height, content = content, align = "left",
        on_tap = function()
            local filemanagerutil = require("apps/filemanager/filemanagerutil")
            if filemanagerutil.openFile then filemanagerutil.openFile(ui, last) else ui:openFile(last) end
        end,
    }
end

-- Une "carte" de statistique : valeur en gras, libellé en petites capitales
local function statCard(value, label, w)
    return VerticalGroup:new{ align = "left",
        TextWidget:new{ text = value, face = Font:getFace("smallinfofontbold", 16), bold = true, max_width = w },
        VerticalSpan:new{ width = Screen:scaleBySize(1) },
        caption(label, w),
    }
end

-- Panneau "statistiques" : deux colonnes de cartes, graphique de la semaine
local function buildStatsPanel(ui, width, height, stats, finished_year)
    local col_gap = Screen:scaleBySize(12)
    local col_w = math.floor((width - col_gap) / 2)
    local column = VerticalGroup:new{ align = "left" }
    local function add(widget, after)
        table.insert(column, widget)
        if after and after > 0 then table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(after) }) end
    end
    local function row(a, b)
        local g = HorizontalGroup:new{ align = "top", a }
        if b then
            table.insert(g, HorizontalSpan:new{ width = col_w + col_gap - a:getSize().w })
            table.insert(g, b)
        end
        return g
    end
    local per_page
    if (stats.week_pages or 0) >= 20 then
        per_page = stats.week_time / stats.week_pages
    elseif (stats.total_pages or 0) > 0 then
        per_page = stats.total_time / stats.total_pages
    end
    local year = os.date("%Y")
    local streak = stats.streak or 0

    add(caption("Mes statistiques", width), 8)
    add(row(
        statCard((formatDuration(stats.today_time) or "0 min"), "aujourd'hui · " .. fmtPages(stats.today_pages), col_w),
        statCard((formatDuration(stats.week_time) or "0 min"), "7 derniers jours · " .. fmtPages(stats.week_pages), col_w)
    ), 8)

    -- Graphique de la semaine, avec les lettres des jours
    local bars_h = Screen:scaleBySize(CFG.stats_bars_height or 28)
    local labels = HorizontalGroup:new{}
    local n = #stats.week
    local bgap = Screen:scaleBySize(4)
    local bar_w = n > 0 and math.floor((width - bgap * (n - 1)) / n) or width
    for i, day in ipairs(stats.week) do
        table.insert(labels, CenterContainer:new{
            dimen = Geom:new{ w = bar_w + (i < n and bgap or 0), h = Screen:scaleBySize(13) },
            TextWidget:new{ text = day.label, face = Font:getFace("x_smallinfofont", 9), bold = day.today,
                fgcolor = day.today and Blitbuffer.COLOR_BLACK or DIM_COLOR },
        })
    end
    add(WeekBars:new{ days = stats.week, width = width, height = bars_h }, 2)
    add(labels, 14)

    add(row(
        statCard(per_page and formatSeconds(per_page) or "—", "par page en moyenne", col_w),
        statCard(tostring(finished_year or 0), (finished_year == 1 and "livre terminé en " or "livres terminés en ") .. year, col_w)
    ), 14)
    add(row(
        statCard(formatDuration(stats.total_time) or "0 min", "de lecture en tout", col_w),
        statCard(fmtPages(stats.total_pages), "lues en tout", col_w)
    ), 0)

    return HomePanel:new{
        width = width, height = height, content = column, align = "left",
        on_tap = function()
            local st = ui.statistics
            if not st then return end
            local ok = pcall(function() st:onShowCalendarView() end)
            if not ok then pcall(function() st:onShowReaderProgress() end) end
        end,
    }
end

-- Titre de section "Ma bibliothèque" avec un trait jusqu'au bord, et les
-- dossiers (Terminés, dossiers réels) en étiquettes tapables : sur la même
-- ligne si elles tiennent, sinon sur une ou plusieurs lignes en dessous.
local function buildSectionTitle(menu, width, dirs)
    local title = TextWidget:new{ text = CFG.library_title or "Ma bibliothèque", face = Font:getFace("tfont", 16), bold = true }
    local gap = Screen:scaleBySize(12)
    local chip_gap = Screen:scaleBySize(6)
    local chips = {}
    local ordered = {}
    for _, entry in ipairs(dirs or {}) do
        if not entry.is_virtual then table.insert(ordered, entry) end
    end
    for _, entry in ipairs(dirs or {}) do
        if entry.is_virtual then table.insert(ordered, entry) end
    end
    for _, entry in ipairs(ordered) do
        local name = entry.text or ""
        if name:match("/$") then name = name:sub(1, -2) end
        if entry.is_go_up then name = CFG.parent_folder_label or ".." end
        local count = entry.mandatory and entry.mandatory:match("^(%d+)")
        local content = pill(count and (name .. "  " .. count) or name, false)
        local size = content:getSize()
        table.insert(chips, HomePanel:new{
            width = size.w, height = size.h, content = content,
            on_tap = function() menu:onMenuSelect(entry) end,
        })
    end
    local chips_w = 0
    for i, chip in ipairs(chips) do
        chips_w = chips_w + chip.width + (i > 1 and chip_gap or 0)
    end
    local title_w = title:getSize().w
    local inline = #chips > 0 and (title_w + gap + Screen:scaleBySize(40) + gap + chips_w) <= width
    local rule_w = width - title_w - gap - (inline and (chips_w + gap) or 0)
    local rule = LineWidget:new{ dimen = Geom:new{ w = math.max(rule_w, Screen:scaleBySize(20)), h = Size.line.thin }, background = Blitbuffer.COLOR_BLACK }
    local line = HorizontalGroup:new{ align = "center", title, HorizontalSpan:new{ width = gap }, rule }
    local block = VerticalGroup:new{ align = "left", line }
    if inline then
        table.insert(line, HorizontalSpan:new{ width = gap })
        for i, chip in ipairs(chips) do
            if i > 1 then table.insert(line, HorizontalSpan:new{ width = chip_gap }) end
            table.insert(line, chip)
        end
    elseif #chips > 0 then
        -- Lignes d'étiquettes sous le titre
        local row, row_w = HorizontalGroup:new{ align = "center" }, 0
        local function flush()
            if row_w > 0 then
                table.insert(block, VerticalSpan:new{ width = Screen:scaleBySize(6) })
                table.insert(block, row)
            end
            row, row_w = HorizontalGroup:new{ align = "center" }, 0
        end
        for _, chip in ipairs(chips) do
            local w = chip.width + (row_w > 0 and chip_gap or 0)
            if row_w > 0 and row_w + w > width then flush() end
            if row_w > 0 then table.insert(row, HorizontalSpan:new{ width = chip_gap }) end
            table.insert(row, chip)
            row_w = row_w + chip.width + (row_w > 0 and chip_gap or 0)
        end
        flush()
    end
    return block
end

-------------------------------------------------------------------------------
-- 5. Dossiers virtuels "Terminés" et "En attente" à la racine
-------------------------------------------------------------------------------

local VIRTUAL = {
    complete = { label = function() return CFG.virtual_complete_label end, icon = function() return CFG.virtual_complete_icon end },
    abandoned = { label = function() return CFG.virtual_abandoned_label end, icon = function() return CFG.virtual_abandoned_icon end },
}

-- Le FileChooser de l'explorateur (pas ceux des boîtes de dialogue)
local function isFM(chooser)
    return chooser.name == "filemanager"
end

local function getHomeDir()
    local home = require("apps/filemanager/filemanagerutil").getHomeFolder()
    return require("ffi/util").realpath(home) or home
end

local function normalizePath(path)
    if not path then return nil end
    path = require("ffi/util").realpath(path) or path
    return (path:gsub("/+$", ""))
end

-- Le dossier affiché est-il celui où l'on montre les dossiers virtuels ?
local function isHomePath(path)
    return normalizePath(path) == normalizePath(getHomeDir())
end

local function showVirtualFoldersIn(path)
    local where = CFG.virtual_folders_where or "home"
    if where == "everywhere" then
        return true
    end
    if where == "home" then
        return isHomePath(path)
    end
    return normalizePath(path) == normalizePath(where)
end

-- Compte les livres par statut sous un dossier, en respectant les filtres
-- d'affichage de KOReader (fichiers cachés, formats non supportés).
local function countBooksByStatus(chooser, path, counts)
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then return end
    for f in iter, dir_obj do
        if f ~= "." and f ~= ".." and (FileChooser.show_hidden or not util.stringStartsWith(f, ".")) then
            local fullpath = path .. "/" .. f
            local mode = lfs.attributes(fullpath, "mode")
            if mode == "directory" then
                if chooser:show_dir(f) then
                    countBooksByStatus(chooser, fullpath, counts)
                end
            elseif mode == "file" and not util.stringStartsWith(f, "._") and chooser:show_file(f, fullpath) then
                local status = BookList.getBookStatus(fullpath)
                counts[status] = (counts[status] or 0) + 1
            end
        end
    end
end

-- Rassemble, récursivement, les entrées de menu des livres d'un statut donné.
local function collectBooksWithStatus(chooser, path, status, collate, files)
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then return end
    for f in iter, dir_obj do
        if f ~= "." and f ~= ".." and (FileChooser.show_hidden or not util.stringStartsWith(f, ".")) then
            local fullpath = path .. "/" .. f
            local attributes = lfs.attributes(fullpath) or {}
            if attributes.mode == "directory" then
                if chooser:show_dir(f) then
                    collectBooksWithStatus(chooser, fullpath, status, collate, files)
                end
            elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                    and chooser:show_file(f, fullpath) and BookList.getBookStatus(fullpath) == status then
                table.insert(files, chooser:getListItem(path, f, fullpath, attributes, collate))
            end
        end
    end
end

if CFG.virtual_folders then
    local orig_genItemTableFromPath = FileChooser.genItemTableFromPath
    FileChooser.genItemTableFromPath = function(self, path)
        local item_table = orig_genItemTableFromPath(self, path)
        if isFM(self) and not self.virtual_status and CFG.parent_folder and path ~= "/"
                and not isHomePath(path) and not (item_table[1] and item_table[1].is_go_up) then
            -- Sous-dossier sans "../" (option KOReader désactivée) : on l'ajoute
            table.insert(item_table, 1, {
                text = "../",
                path = path .. "/..",
                is_go_up = true,
            })
        end
        if CFG.home_panels and isFM(self) and not self.virtual_status and isHomePath(path)
                and self.display_mode_type == "mosaic" then
            local cols = self.nb_cols
                or (Screen:getWidth() <= Screen:getHeight() and self.nb_cols_portrait or self.nb_cols_landscape) or 3
            local rows = self.nb_rows
                or (Screen:getWidth() <= Screen:getHeight() and self.nb_rows_portrait or self.nb_rows_landscape) or 3
            local panel_rows = math.max(1, math.min(CFG.home_panel_rows or 2, rows - 1))
            for _ = 1, cols * panel_rows do
                table.insert(item_table, 1, { text = "", path = path, is_placeholder = true })
            end
            self._home_stats = computeHomeStats()
            local ok, n = pcall(countFinishedThisYear, self, path, os.date("%Y"))
            self._home_finished_year = ok and n or 0
            self._home_layout = { cols = cols, rows = rows - panel_rows }
        end
        if CFG.resume_tile and not CFG.home_panels and isFM(self) and not self.virtual_status and isHomePath(path) then
            local last = G_reader_settings:readSetting("lastfile")
            if last and lfs.attributes(last, "mode") == "file" and BookList.getBookStatus(last) == "reading" then
                -- Retire le livre de sa place normale s'il est listé ici
                for i = #item_table, 1, -1 do
                    if item_table[i].path == last then
                        table.remove(item_table, i)
                    end
                end
                local dirpath, fname = util.splitFilePathName(last)
                local ok, entry = pcall(self.getListItem, self, dirpath:gsub("/$", ""), fname, last, lfs.attributes(last) or {}, self:getCollate())
                if ok and entry then
                    entry.is_resume = true
                    local pos = (item_table[1] and item_table[1].is_go_up) and 2 or 1
                    table.insert(item_table, pos, entry)
                end
            end
        end
        local want_virtual = isFM(self) and not self.virtual_status and showVirtualFoldersIn(path)
        if want_virtual then
            local counts = {}
            self._counting_books = true
            pcall(countBooksByStatus, self, path, counts)
            self._counting_books = nil
            local pos = 1
            while item_table[pos] and (item_table[pos].is_go_up or item_table[pos].is_resume or item_table[pos].is_placeholder) do
                pos = pos + 1
            end
            for _, status in ipairs(CFG.virtual_statuses or { "complete", "abandoned" }) do
                table.insert(item_table, pos, {
                    text = VIRTUAL[status].label(),
                    path = path .. "/#" .. status,
                    mandatory = tostring(counts[status] or 0) .. " \u{F016}",
                    is_virtual = status,
                    icon = VIRTUAL[status].icon(),
                })
                pos = pos + 1
            end
        end
        if self._home_layout and item_table[1] and item_table[1].is_placeholder then
            -- Les dossiers deviennent des étiquettes sous le titre "Ma bibliothèque",
            -- la grille ne montre que des livres
            local kept, dirs = {}, {}
            for _, entry in ipairs(item_table) do
                if entry.is_placeholder or entry.is_file then
                    table.insert(kept, entry)
                else
                    table.insert(dirs, entry)
                end
            end
            item_table = kept
            self._home_dirs = dirs
            self._home_layout = nil
            -- Le livre en cours est déjà en haut : on le retire de la grille
            local last = G_reader_settings:readSetting("lastfile")
            if CFG.hide_current_in_grid and last and BookList.getBookStatus(last) == "reading" then
                for i = #item_table, 1, -1 do
                    if item_table[i].path == last then table.remove(item_table, i) end
                end
            end
            -- Et la vignette "Objectif du jour" prend la première place
            if CFG.goal_tile then
                local pos = 1
                while item_table[pos] and item_table[pos].is_placeholder do pos = pos + 1 end
                table.insert(item_table, pos, { text = "", path = path, is_goal = true })
            end
        end
        return item_table
    end

    local orig_refreshPath = FileChooser.refreshPath
    FileChooser.refreshPath = function(self)
        if not (isFM(self) and self.virtual_status) then
            return orig_refreshPath(self)
        end
        local home = getHomeDir()
        local status = self.virtual_status
        -- Tous les livres de ce statut sous le dossier d'accueil, à plat
        local files = {}
        collectBooksWithStatus(self, home, status, self:getCollate(), files)
        local item_table = self:genItemTable({}, files, home)
        -- Le "../" ramène à l'accueil
        if item_table[1] and item_table[1].is_go_up then
            item_table[1].path = home
        else
            table.insert(item_table, 1, {
                text = BD.mirroredUILayout() and BD.ltr("../ ⬆") or "⬆ ../",
                path = home,
                is_go_up = true,
            })
        end
        local key = home .. "/#" .. status
        self:switchItemTable(nil, item_table, self.path_items[key])
        if self.ui and self.ui.title_bar then
            self.ui.title_bar:setTitle(FileManager.title .. " · " .. VIRTUAL[status].label())
        end
    end

    -- Cacher les livres terminés / favoris hors de leur dossier virtuel
    local orig_show_file = FileChooser.show_file
    FileChooser.show_file = function(self, filename, fullpath)
        if not orig_show_file(self, filename, fullpath) then
            return false
        end
        if fullpath and isFM(self) and not self.virtual_status and not self._counting_books
                and (CFG.hide_finished or CFG.hide_favorites) then
            local status = BookList.getBookStatus(fullpath)
            if (CFG.hide_finished and status == "complete") or (CFG.hide_favorites and status == "abandoned") then
                return false
            end
        end
        return true
    end

    local orig_updateItems = FileChooser.updateItems
    FileChooser.updateItems = function(self, select_number, no_recalculate_dimen)
        local saved = self.path_items[self.path]
        orig_updateItems(self, select_number, no_recalculate_dimen)
        if self.virtual_status then
            -- Mémoriser la page du dossier virtuel sous sa propre clé, sans
            -- écraser celle de l'accueil
            self.path_items[self.path] = saved
            self.path_items[getHomeDir() .. "/#" .. self.virtual_status] = (self.page - 1) * self.perpage + (select_number or 1)
        end
    end

    local orig_onMenuSelect = FileChooser.onMenuSelect
    FileChooser.onMenuSelect = function(self, item)
        if item.is_virtual then
            self.virtual_status = item.is_virtual
            self:refreshPath()
            return true
        end
        if self.virtual_status and item.is_go_up then
            self:changeToPath(getHomeDir()) -- remet aussi le titre
            return true
        end
        return orig_onMenuSelect(self, item)
    end

    local orig_onMenuHold = FileChooser.onMenuHold
    FileChooser.onMenuHold = function(self, item)
        if item.is_virtual then
            return true -- rien à proposer sur un dossier virtuel
        end
        return orig_onMenuHold(self, item)
    end

    -- Toute navigation quitte le dossier virtuel
    local orig_changeToPath = FileChooser.changeToPath
    FileChooser.changeToPath = function(self, path, focused_path)
        local was_virtual = self.virtual_status
        self.virtual_status = nil
        orig_changeToPath(self, path, focused_path)
        if was_virtual and self.ui and self.ui.title_bar then
            self.ui.title_bar:setTitle(FileManager.title)
        end
    end
    local orig_onFolderUp = FileChooser.onFolderUp
    FileChooser.onFolderUp = function(self)
        if self.virtual_status then
            self:changeToPath(getHomeDir()) -- remet aussi le titre
            return
        end
        return orig_onFolderUp(self)
    end
end

-------------------------------------------------------------------------------
-- 6. Dossiers et couvertures (plugin coverbrowser, mode mosaïque)
-------------------------------------------------------------------------------

-- Vignette "Objectif du jour", à la place d'une couverture
local function buildGoalTile(item, dimen)
    local tw, th = coverTargetSize(dimen)
    local frame_w = tw + 2*coverInset()
    local frame_h = th + 2*coverInset()
    local stats = item.menu and item.menu._home_stats or {}
    local goal = readingGoalMinutes()
    local minutes = math.floor((stats.today_time or 0) / 60 + 0.5)
    local ratio = math.min(1, goal > 0 and minutes / goal or 0)
    local done = minutes >= goal
    local inner_w = frame_w - 2 * Screen:scaleBySize(6)
    local group = VerticalGroup:new{ align = "center" }
    local function add(widget, after)
        table.insert(group, widget)
        if after then table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(after) }) end
    end
    local streak = stats.streak or 0
    add(IconWidget:new{ icon = "goal", width = Screen:scaleBySize(24), height = Screen:scaleBySize(24), alpha = true }, 4)
    add(TextWidget:new{ text = streak .. (streak > 1 and " jours d'affilée" or " jour d'affilée"),
        face = Font:getFace("x_smallinfofont", 11), fgcolor = DIM_COLOR, max_width = inner_w }, 12)
    add(TextWidget:new{ text = minutes .. " min", face = Font:getFace("tfont", 24), bold = true, max_width = inner_w }, 2)
    add(TextWidget:new{ text = (done and "objectif atteint · " or "sur ") .. goal .. " min", face = Font:getFace("x_smallinfofont", 11), fgcolor = DIM_COLOR, max_width = inner_w }, 10)
    add(thinProgress(inner_w, ratio, Screen:scaleBySize(6)), nil)
    return makeTile(CenterContainer:new{ dimen = Geom:new{ w = frame_w, h = frame_h }, group }, dimen, "Objectif du jour")
end

local function showGoalDialog(menu)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = "Objectif de lecture",
        info_text = "Minutes de lecture par jour",
        value = readingGoalMinutes(),
        value_min = 5,
        value_max = 300,
        value_step = 5,
        value_hold_step = 15,
        ok_text = "Enregistrer",
        cancel_text = "Annuler",
        callback = function(spin)
            G_reader_settings:saveSetting("apparence_accueil_goal", spin.value)
            G_reader_settings:flush()
            if menu and menu.refreshPath then menu:refreshPath() end
        end,
    })
end

-- Reconstruit la vignette d'un dossier avec les réglages de CFG, dans un
-- cadre de la même taille que les couvertures.
local function buildFolderWidget(item, dimen)
    local tw, th = coverTargetSize(dimen)
    local border = CFG.folder_border or CFG.cover_border or 0
    local border_color = color(CFG.folder_border_color or CFG.cover_border_color, Blitbuffer.COLOR_LIGHT_GRAY)
    local radius = (CFG.folder_radius or CFG.cover_radius or 0) + border + (CFG.cover_padding or 0)
    local background = color(CFG.folder_background, Blitbuffer.COLOR_WHITE)
    local padding = Screen:scaleBySize(6)
    local frame_w = tw + 2*coverInset()
    local frame_h = th + 2*coverInset()
    local dimen_in = Geom:new{
        w = frame_w - (padding + border)*2,
        h = frame_h - (padding + border)*2,
    }

    local is_go_up = item.entry and item.entry.is_go_up
    local text = item.text
    if text:match("/$") then
        text = text:sub(1, -2)
    end
    text = BD.directory(text)
    if is_go_up and CFG.parent_folder_label then
        text = CFG.parent_folder_label
    end

    local text_color = background == Blitbuffer.COLOR_BLACK and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

    local nbitems, nbitems_h = nil, 0
    if CFG.folder_show_count and not is_go_up then
        nbitems = TextBoxWidget:new{
            text = item.mandatory or "",
            face = Font:getFace("infont", CFG.folder_count_font_size or 15),
            fgcolor = text_color,
            bgcolor = background,
            width = dimen_in.w,
            alignment = "center",
        }
        nbitems_h = nbitems:getSize().h
    end

    local icon_name = item.entry and item.entry.icon or CFG.folder_icon
    if is_go_up and CFG.parent_folder_icon then
        icon_name = CFG.parent_folder_icon
    end
    local icon, icon_h = nil, 0
    if icon_name then
        local icon_size = math.floor(dimen_in.w * (CFG.folder_icon_ratio or 0.35))
        icon = IconWidget:new{
            icon = icon_name,
            width = icon_size,
            height = icon_size,
            alpha = true,
        }
        icon_h = icon_size + Screen:scaleBySize(4)
    end

    -- Le nom est sous l'icône, le compteur en bas ; on réduit la police tant
    -- que le nom ne tient pas dans la hauteur restante.
    local available_height = dimen_in.h - 3 * nbitems_h - icon_h
    local dir_font_size = CFG.folder_font_size or 15
    local directory
    while true do
        if directory then
            directory:free(true)
        end
        directory = TextBoxWidget:new{
            text = text,
            face = Font:getFace("cfont", dir_font_size),
            fgcolor = text_color,
            bgcolor = background,
            width = dimen_in.w,
            alignment = "center",
            bold = CFG.folder_bold,
        }
        if directory:getSize().h <= available_height then
            break
        end
        dir_font_size = dir_font_size - 1
        if dir_font_size < 8 then
            directory:free()
            directory.height = math.max(available_height, 1)
            directory.height_adjust = true
            directory.height_overflow_show_ellipsis = true
            directory:init()
            break
        end
    end

    local content = directory
    if icon then
        content = VerticalGroup:new{
            align = "center",
            icon,
            VerticalSpan:new{ width = Screen:scaleBySize(4) },
            directory,
        }
    end

    local overlap = OverlapGroup:new{
        dimen = dimen_in,
        CenterContainer:new{ dimen = dimen_in, content },
    }
    if nbitems then
        table.insert(overlap, BottomContainer:new{ dimen = dimen_in, nbitems })
    end

    if CFG.folder_frame == false then
        -- Sans cadre : grande icône, nom, compteur, posés dans l'espace de la couverture
        local free = VerticalGroup:new{ align = "center" }
        if icon_name then
            local icon_size = math.floor(frame_w * (CFG.folder_icon_ratio_free or 0.5))
            table.insert(free, IconWidget:new{ icon = icon_name, width = icon_size, height = icon_size, alpha = true })
            table.insert(free, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        end
        table.insert(free, TextBoxWidget:new{
            text = text,
            face = Font:getFace("cfont", CFG.folder_font_size or 15),
            width = frame_w,
            alignment = "center",
            bold = CFG.folder_bold,
            height = Screen:scaleBySize(2 * (CFG.folder_font_size or 15) * 1.4),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        })
        if nbitems then
            table.insert(free, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(free, TextWidget:new{
                text = item.mandatory or "",
                face = Font:getFace("infont", CFG.folder_count_font_size or 15),
                fgcolor = DIM_COLOR,
                max_width = frame_w,
            })
        end
        return makeTile(CenterContainer:new{ dimen = Geom:new{ w = frame_w, h = frame_h }, free }, dimen)
    end

    return makeTile(FrameContainer:new{
        width = frame_w,
        height = frame_h,
        margin = 0,
        padding = padding,
        bordersize = border,
        color = border_color,
        radius = radius,
        background = background,
        overlap,
    }, dimen)
end

-- Étiquette "REPRENDRE" (texte dans un cartouche blanc arrondi), centrée en cx,
-- bord haut en y
local resume_widget
local function paintResumeLabel(bb, cx, y)
    if not resume_widget then
        resume_widget = TextWidget:new{
            text = CFG.resume_label or "REPRENDRE",
            face = Font:getFace("smallinfofontbold", 11),
            bold = true,
        }
    end
    local size = resume_widget:getSize()
    local px, py = Screen:scaleBySize(6), Screen:scaleBySize(3)
    local w, h = size.w + 2*px, size.h + 2*py
    local x = cx - math.floor(w / 2)
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, math.floor(h / 2))
    bb:paintBorder(x, y, w, h, 1, Blitbuffer.COLOR_BLACK, math.floor(h / 2))
    resume_widget:paintTo(bb, x + px, y + py)
end

-- Pastille ronde avec une icône, centrée en (cx, cy)
local badge_icons = {}
local function paintBadge(bb, cx, cy, r, icon_name)
    bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_WHITE)
    bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_GRAY_9, math.max(1, math.floor(r / 12)))
    local size = math.floor(r * 1.15)
    local key = icon_name .. size
    if not badge_icons[key] then
        badge_icons[key] = IconWidget:new{ icon = icon_name, width = size, height = size, alpha = true }
    end
    badge_icons[key]:paintTo(bb, cx - math.floor(size / 2), cy - math.floor(size / 2))
end

local progress_widgets = {}
local function getProgressWidget(width)
    if not progress_widgets[width] then
        local h = CFG.progress_height or 6
        progress_widgets[width] = ProgressWidget:new{
            width = width,
            height = h,
            margin_h = 0,
            margin_v = 0,
            radius = math.floor(h / 2),
            bordersize = 0,
            bgcolor = color(CFG.progress_track_color, Blitbuffer.COLOR_DARK_GRAY),
            fillcolor = Blitbuffer.COLOR_BLACK,
        }
    end
    return progress_widgets[width]
end

userpatch.registerPatchPluginFunc("coverbrowser", function(plugin)
    local MosaicMenu = require("mosaicmenu")
    if MosaicMenu.__apparence_accueil_patched then
        return -- déjà fait pour cette session (le plugin est réinstancié à chaque FileManager)
    end
    MosaicMenu.__apparence_accueil_patched = true

    BookInfoManager = require("bookinfomanager")
    AA.BookInfoManager = BookInfoManager
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        logger.warn("apparence-accueil: MosaicMenuItem introuvable, dossiers non patchés")
        return
    end
    FakeCover = userpatch.getUpValue(MosaicMenuItem.update, "FakeCover")
    AA.FakeCover = FakeCover
    local ReadCollection = userpatch.getUpValue(MosaicMenuItem.paintTo, "ReadCollection") or require("readcollection")

    -- Espace entre les vignettes (et autour de la page)
    if CFG.grid_spacing then
        local orig_recalculateDimen = MosaicMenu._recalculateDimen
        MosaicMenu._recalculateDimen = function(self)
            orig_recalculateDimen(self)
            self.item_margin = CFG.grid_spacing
            self.item_height = math.floor((self.inner_dimen.h - self.others_height - (1+self.nb_rows)*self.item_margin) / self.nb_rows)
            self.item_width = math.floor((self.inner_dimen.w - (1+self.nb_cols)*self.item_margin) / self.nb_cols)
            self.item_dimen = Geom:new{ x = 0, y = 0, w = self.item_width, h = self.item_height }
        end
        -- Le plugin a déjà copié la fonction d'origine sur FileChooser : on la remplace.
        if FileChooser._recalculateDimen == orig_recalculateDimen then
            FileChooser._recalculateDimen = MosaicMenu._recalculateDimen
        end
    end

    -- Centrage de la grille : l'original laisse les pixels de reste à droite.
    if CFG.grid_center then
        local orig_buildUI = MosaicMenu._updateItemsBuildUI
        MosaicMenu._updateItemsBuildUI = function(self)
            local select_number = orig_buildUI(self)
            local leftover = self.inner_dimen.w - self.nb_cols*self.item_width - (self.nb_cols+1)*self.item_margin
            local lead = self.item_margin + math.floor(leftover / 2)
            for _, row_container in ipairs(self.item_group) do
                local row = row_container[1]
                if row and row[1] and row[1].width and #row > 1 then
                    row[1].width = lead
                    row:resetLayout()
                end
            end
            -- Première rangée de l'accueil : panneaux livre en cours + statistiques
            if CFG.home_panels and self.page == 1 and self.item_table[1] and self.item_table[1].is_placeholder and self.ui then
                local ok, err = pcall(function()
                    -- Rangées occupées par les cases vides (en tête de la page)
                    local n_placeholders = 0
                    for _, entry in ipairs(self.item_table) do
                        if entry.is_placeholder then n_placeholders = n_placeholders + 1 else break end
                    end
                    local panel_rows = math.max(1, math.floor(n_placeholders / self.nb_cols))
                    -- Conteneurs de rangées (les autres entrées sont des espaces)
                    local rows = {}
                    for idx, row_container in ipairs(self.item_group) do
                        if row_container[1] and row_container[1][1] then
                            table.insert(rows, idx)
                        end
                    end
                    if #rows < panel_rows then return end
                    -- La première rangée prend la hauteur des rangées fusionnées ;
                    -- les suivantes (et l'espace qui les précède) disparaissent.
                    local first = self.item_group[rows[1]]
                    local total_h = panel_rows * self.item_height + (panel_rows - 1) * self.item_margin
                    for r = panel_rows, 2, -1 do
                        local idx = rows[r]
                        table.remove(self.item_group, idx)
                        if self.item_group[idx - 1] and not self.item_group[idx - 1][1] then
                            table.remove(self.item_group, idx - 1) -- l'espace vertical
                        end
                    end
                    first.dimen = Geom:new{ w = self.inner_dimen.w, h = total_h }
                    local above = tiltMargin(self.item_dimen)
                    local below = Screen:scaleBySize(6) + tiltMargin(self.item_dimen)
                    local content_w = self.inner_dimen.w - 2 * lead
                    -- Titre de section + dossiers, dont la hauteur se retranche de l'en-tête
                    local section = buildSectionTitle(self, content_w, self._home_dirs)
                    local section_h = section:getSize().h
                    local section_gap = CFG.titlebar_bottom_margin or Screen:scaleBySize(16)
                    local panel_h = total_h - above - section_gap - section_h - below
                    local gap = Screen:scaleBySize(20)
                    local w_hero = math.floor((content_w - gap) * (CFG.hero_width_ratio or 0.55))
                    local w_stats = content_w - gap - w_hero
                    local stats = self._home_stats or computeHomeStats()
                    first[1] = VerticalGroup:new{ align = "left",
                        VerticalSpan:new{ width = above },
                        HorizontalGroup:new{ align = "top",
                            HorizontalSpan:new{ width = lead },
                            buildHero(self.ui, w_hero, panel_h),
                            HorizontalSpan:new{ width = math.floor(gap / 2) },
                            LineWidget:new{ dimen = Geom:new{ w = 1, h = panel_h }, background = DIM_COLOR },
                            HorizontalSpan:new{ width = gap - math.floor(gap / 2) - 1 },
                            buildStatsPanel(self.ui, w_stats, panel_h, stats, self._home_finished_year),
                        },
                        VerticalSpan:new{ width = section_gap },
                        HorizontalGroup:new{ HorizontalSpan:new{ width = lead }, section },
                        VerticalSpan:new{ width = below },
                    }
                end)
                if not ok then
                    logger.warn("apparence-accueil: panneaux d'accueil :", err)
                end
            end
            return select_number
        end
        if FileChooser._updateItemsBuildUI == orig_buildUI then
            FileChooser._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
        end
    end

    -- Dossiers et couvertures
    local orig_update = MosaicMenuItem.update
    MosaicMenuItem.update = function(self)
        self.is_directory = not (self.entry.is_file or self.entry.file)

        if not self.is_directory then
            -- On intercepte les métadonnées lues par l'original pour avoir le titre
            local captured
            local orig_getBookInfo = BookInfoManager.getBookInfo
            BookInfoManager.getBookInfo = function(...)
                captured = orig_getBookInfo(...)
                return captured
            end
            local ok, err = pcall(orig_update, self)
            BookInfoManager.getBookInfo = orig_getBookInfo
            if not ok then error(err) end

            local container = self._underline_container[1]
            local old = container and container[1]
            if not old then return end
            local dimen = Geom:new{ w = self.width, h = self.height }
            local tw, th = coverTargetSize(dimen)
            local opened = self.been_opened and self.status == "reading"
            local title
            if CFG.cover_title then
                if captured and captured.title and not captured.ignore_meta then
                    title = captured.title
                else
                    title = (self.text:gsub("%.[^%.]+$", ""))
                end
                title = BD.auto(title)
            end

            if self._has_cover_image and old[1] and old[1]._bb then
                -- Vraie couverture : on récupère l'image déjà mise à l'échelle par
                -- l'original et on la recadre à la taille cible.
                local img = old[1]
                local src = img._bb
                img._bb = nil -- on en prend la propriété
                local cover = makeCroppedImage(src, tw, th)
                old:free()
                self._cover_frame = makeCoverFrame(cover, tw, th, self.file_deleted, opened)
                container[1] = makeTile(self._cover_frame, dimen, title)
            elseif CFG.cover_apply_to_fake and FakeCover and self.bookinfo_found and old.filename ~= nil then
                -- Livre sans couverture : même taille, même cadre.
                local fake = FakeCover:new{
                    width = tw,
                    height = th,
                    bordersize = 0,
                    filename = old.filename,
                    filename_add = old.filename_add,
                    title = old.title,
                    authors = old.authors,
                    title_add = old.title_add,
                    authors_add = old.authors_add,
                    book_lang = old.book_lang,
                    file_deleted = old.file_deleted,
                    bottom_pad = old.bottom_pad,
                    bottom_right_compensate = old.bottom_right_compensate,
                    initial_sizedec = old.initial_sizedec,
                }
                old:free()
                self._cover_frame = makeCoverFrame(fake, tw, th, self.file_deleted, opened)
                container[1] = makeTile(self._cover_frame, dimen, title)
            end
            return
        end

        if self.entry.is_goal then
            if self._underline_container[1] then
                self._underline_container[1]:free()
            end
            self._underline_container[1] = buildGoalTile(self, Geom:new{ w = self.width, h = self.height })
            return
        end
        if self.entry.is_placeholder then
            self.ges_events = {}
            if self._underline_container[1] then
                self._underline_container[1]:free()
            end
            self._underline_container[1] = HorizontalSpan:new{ width = 0 }
            return
        end

        local dimen = Geom:new{ w = self.width, h = self.height }
        -- Comme l'original : indique au menu la taille de couverture attendue
        local border_size = Screen:scaleBySize(0.5)
        if self.do_cover_image then
            self.menu.cover_specs = {
                max_cover_w = dimen.w - 2*border_size,
                max_cover_h = dimen.h - 2*border_size,
            }
        else
            self.menu.cover_specs = false
        end

        local widget = buildFolderWidget(self, dimen)
        if self._underline_container[1] then
            self._underline_container[1]:free()
        end
        self._underline_container[1] = widget
    end

    -- Peinture : pastilles de statut, barre de progression, plus de marques de coin
    local function paintContent(self, bb, x, y)
        InputContainer.paintTo(self, bb, x, y)

        if self.shortcut_icon then
            local ix = BD.mirroredUILayout() and (self.dimen.w - self.shortcut_icon.dimen.w) or 0
            self.shortcut_icon:paintTo(bb, x + ix, y)
        end
        if self.is_directory then return end

        local target = self._cover_frame -- le cadre de la couverture
        if not target or not target.dimen then return end
        local inset = coverInset()
        local inner_x = target.dimen.x + inset
        local inner_y = target.dimen.y + inset
        local inner_w = target.dimen.w - 2*inset
        local inner_h = target.dimen.h - 2*inset
        local r = math.floor(inner_w * (CFG.badge_ratio or 0.22) / 2)
        local margin = math.max(2, math.floor(r * 0.3))

        if CFG.status_badge and self.been_opened then
            local icons = CFG.status_icons or {}
            local icon = icons[self.status] or icons.reading or "badge.reading"
            local cx = BD.mirroredUILayout() and (inner_x + margin + r) or (inner_x + inner_w - margin - r)
            paintBadge(bb, cx, inner_y + inner_h - margin - r, r, icon)
        end

        if self.entry and self.entry.is_resume then
            paintResumeLabel(bb, inner_x + math.floor(inner_w / 2), inner_y + margin)
        end

        if CFG.collection_badge and self.menu.name ~= "collections"
                and ReadCollection:isFileInCollections(self.filepath) then
            local cx = BD.mirroredUILayout() and (inner_x + margin + r) or (inner_x + inner_w - margin - r)
            paintBadge(bb, cx, inner_y + margin + r, r, CFG.collection_icon or "badge.collection")
        end

        if CFG.progress_bar and self.percent_finished and self.status ~= "complete" then
            local width = math.floor(inner_w * (CFG.progress_width_ratio or 0.6))
            local progress = getProgressWidget(width)
            progress.fillcolor = self.status == "abandoned" and Blitbuffer.COLOR_GRAY_6 or Blitbuffer.COLOR_BLACK
            progress:setPercentage(self.percent_finished)
            progress:paintTo(bb, inner_x + math.floor((inner_w - width) / 2), inner_y + (CFG.progress_top or 8))
        end

        if CFG.description_hint and self.has_description and not BookInfoManager:getSetting("no_hint_description") then
            local d_w = Screen:scaleBySize(3)
            local d_h = math.ceil(target.dimen.h / 8)
            local ix = BD.mirroredUILayout() and (-d_w + 1) or (target.dimen.w - 1)
            bb:paintBorder(target.dimen.x + ix, target.dimen.y, d_w, d_h, 1)
        end
    end

    -- Angle de rotation propre à chaque entrée, stable d'un affichage à l'autre
    local function tiltAngle(key)
        local deg = CFG.tilt_degrees or 0
        if deg <= 0 then return 0 end
        local h = 7
        for i = 1, #key do
            h = (h * 31 + key:byte(i)) % 1000003
        end
        local sign = (h % 2 == 0) and 1 or -1
        return sign * deg * (0.6 + (h % 400) / 1000) -- entre 60 % et 100 % de l'angle
    end

    -- Dessine la vignette hors écran (en niveaux de gris), la tourne de
    -- quelques degrés avec un léger lissage, puis la recopie à l'écran.
    -- Sur un écran couleur (Boox 4C par exemple), on travaille en RGB32
    -- (4 octets par pixel) pour garder les couleurs ; sinon en gris (1 octet).
    local function paintTilted(self, bb, x, y, angle)
        local size = self:getSize()
        local w, h = size.w, size.h
        local screen_type = bb:getType()
        local color_screen = screen_type == Blitbuffer.TYPE_BBRGB32
        local bb_type = color_screen and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8
        local bpp = color_screen and 4 or 1
        local src = Blitbuffer.new(w, h, bb_type)
        local dst = Blitbuffer.new(w, h, bb_type)
        src:fill(Blitbuffer.COLOR_WHITE)
        dst:fill(Blitbuffer.COLOR_WHITE)
        paintContent(self, src, 0, 0)
        -- Les zones de tap doivent rester aux vraies coordonnées écran
        self.dimen.x, self.dimen.y = x, y

        local sp = ffi.cast("uint8_t*", src.data)
        local dp = ffi.cast("uint8_t*", dst.data)
        local ss, ds = tonumber(src.stride), tonumber(dst.stride)
        local rad = math.rad(angle)
        local c, sn = math.cos(rad), math.sin(rad)
        local cx, cy = w / 2, h / 2
        local floor = math.floor
        local channels = color_screen and 3 or 1 -- RGB32 : R, G, B puis alpha (laissé opaque)
        for dy = 0, h - 1 do
            local ry = dy + 0.5 - cy
            local row = dy * ds
            for dx = 0, w - 1 do
                local rx = dx + 0.5 - cx
                local sx = cx + c * rx - sn * ry
                local sy = cy + sn * rx + c * ry
                local out = row + dx * bpp
                for ch = 0, channels - 1 do
                    -- 4 échantillons pour adoucir les bords
                    local sum = 0
                    for oy = -0.25, 0.25, 0.5 do
                        local iy = floor(sy + oy)
                        for ox = -0.25, 0.25, 0.5 do
                            local ix = floor(sx + ox)
                            if ix >= 0 and ix < w and iy >= 0 and iy < h then
                                sum = sum + sp[iy * ss + ix * bpp + ch]
                            else
                                sum = sum + 255
                            end
                        end
                    end
                    dp[out + ch] = floor(sum * 0.25 + 0.5)
                end
                if color_screen then
                    dp[out + 3] = 0xFF
                end
            end
        end
        bb:blitFrom(dst, x, y, 0, 0, w, h)
        src:free()
        dst:free()
    end

    MosaicMenuItem.paintTo = function(self, bb, x, y)
        local angle = tiltAngle(self.filepath or self.text or "")
        if angle ~= 0 and x >= 0 and y >= 0 then
            local ok, err = pcall(paintTilted, self, bb, x, y, angle)
            if ok then return end
            logger.warn("apparence-accueil: rotation impossible, affichage droit :", err)
        end
        paintContent(self, bb, x, y)
    end

    -- KOReader souligne en noir le dernier livre ouvert (indicateur de focus
    -- clavier) : on garde ce trait blanc, donc invisible.
    MosaicMenuItem.onFocus = function(self)
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end

    -- Tap sur un livre : fiche au lieu d'ouverture directe
    local orig_onTapSelect = MosaicMenuItem.onTapSelect
    local orig_onHoldSelect = MosaicMenuItem.onHoldSelect
    MosaicMenuItem.onHoldSelect = function(self, arg, ges)
        if self.entry and (self.entry.is_goal or self.entry.is_placeholder) then
            if self.entry.is_goal then showGoalDialog(self.menu) end
            return true
        end
        return orig_onHoldSelect(self, arg, ges)
    end

    MosaicMenuItem.onTapSelect = function(self, arg)
        if self.entry and self.entry.is_goal then
            showGoalDialog(self.menu)
            return true
        end
        if self.entry and self.entry.is_placeholder then
            return true
        end
        local reading = CFG.tap_opens_reading and self.been_opened and self.status == "reading"
        if reading and CFG.home_panels and self.filepath == G_reader_settings:readSetting("lastfile") then
            reading = false -- l'en-tête ouvre déjà ce livre : ici, sa fiche
        end
        if CFG.tap_shows_description and not reading and not self.is_directory and not self.file_deleted
                and self.menu and self.menu.name == "filemanager" then
            local FileManager = require("apps/filemanager/filemanager")
            local ui = FileManager.instance
            if ui and ui.bookinfo and not ui.selected_files then
                showBookCard(ui, self.filepath)
                return true
            end
        end
        return orig_onTapSelect(self, arg)
    end
end)
