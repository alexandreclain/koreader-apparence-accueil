-- Apparence accueil : fiche du livre au tap, recherche en ligne, statut, note
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

-------------------------------------------------------------------------------
-- 4. Fiche du livre au tap
-------------------------------------------------------------------------------

-- Petit cache persistant (koreader/settings) : infos récupérées en ligne et
-- dates des dernières tentatives, par fichier.
local function onlineCache()
    return G_reader_settings:readSetting("apparence_accueil_online", {})
end
local function onlineCacheSave()
    G_reader_settings:flush()
end

-- Écrit une métadonnée personnalisée (même mécanisme que "Modifier les
-- métadonnées" de KOReader) et met à jour la base du Cover browser.
local function saveCustomProp(file, book_props, key, value)
    local DocSettings = require("docsettings")
    local custom_file = DocSettings:findCustomMetadataFile(file)
    local cds
    if custom_file then
        cds = DocSettings.openSettingsFile(custom_file)
    else
        cds = DocSettings.openSettingsFile()
        local props = {}
        for k, v in pairs(book_props or {}) do
            if k ~= "display_title" then props[k] = v end
        end
        cds:saveSetting("doc_props", props)
    end
    local custom_props = cds:readSetting("custom_props", {})
    custom_props[key] = value
    cds:flushCustomMetadata(file)
    if AA.BookInfoManager and AA.BookInfoManager.setBookInfoProperties then
        pcall(AA.BookInfoManager.setBookInfoProperties, AA.BookInfoManager, file, { [key] = value })
    end
    if book_props then
        book_props[key] = value
    end
end

-- Durée lisible : "2 h 10", "35 min"
local function formatDuration(seconds)
    if not seconds or seconds ~= seconds or seconds < 0 then return nil end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then
        return minutes .. " min"
    end
    local h = math.floor(minutes / 60)
    local m = minutes % 60
    if m == 0 then
        return h .. " h"
    end
    return string.format("%d h %02d", h, m)
end

-- Temps de lecture, d'après la base du plugin Statistiques :
-- vitesse du livre s'il a été lu, sinon vitesse moyenne de l'utilisateur.
local function readingSpeed(file)
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok then return nil end
    local DataStorage = require("datastorage")
    local db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(db, "mode") ~= "file" then return nil end
    local md5
    if BookList.hasBookBeenOpened(file) then
        md5 = BookList.getDocSettings(file):readSetting("partial_md5_checksum")
    end
    md5 = md5 or util.partialMD5(file)
    local per_page, from_book, total_time
    local ok2, err = pcall(function()
        local conn = SQ3.open(db)
        if md5 then
            local stmt = conn:prepare("SELECT total_read_time, total_read_pages FROM book WHERE md5 = ? ORDER BY last_open DESC LIMIT 1;")
            local row = stmt:reset():bind(md5):step()
            stmt:close()
            if row then
                total_time = tonumber(row[1])
                if tonumber(row[2]) and tonumber(row[2]) >= 5 then
                    per_page = tonumber(row[1]) / tonumber(row[2])
                    from_book = true
                end
            end
        end
        if not per_page then
            local t, p = conn:rowexec("SELECT sum(total_read_time), sum(total_read_pages) FROM book WHERE total_read_pages > 0;")
            if tonumber(p) and tonumber(p) > 0 then
                per_page = tonumber(t) / tonumber(p)
            end
        end
        conn:close()
    end)
    if not ok2 then
        logger.warn("apparence-accueil: statistiques illisibles :", err)
    end
    return per_page, from_book, total_time
end

-- Lecture d'une URL (http ou https), retourne le corps ou nil + message
local function fetchUrl(url, block_timeout, total_timeout)
    local http = require("socket.http")
    local socket = require("socket")
    local socketutil = require("socketutil")
    socketutil:set_timeout(block_timeout or 10, total_timeout or 30)
    local sink = {}
    local code, headers, status = socket.skip(1, http.request{
        url = url,
        method = "GET",
        sink = socketutil.table_sink(sink),
        headers = { ["User-Agent"] = "KOReader apparence-accueil (patch utilisateur)" },
    })
    socketutil:reset_timeout()
    local body = table.concat(sink)
    if code ~= 200 then
        return nil, tostring(status or code)
    end
    return body
end

-- Nom de famille du premier auteur, en minuscules (pour vérifier les résultats)
local function authorKey(authors)
    if not authors or authors == "" then return nil end
    local first = authors:match("^[^\n;&]+") or authors
    first = first:gsub("%s*%b()", "")
    local key
    if first:find(",", 1, true) then
        key = first:match("^%s*([^,]+)") -- "Coben, Harlan"
    else
        key = first:match("(%S+)%s*$")   -- "Harlan Coben"
    end
    key = key and util.trim(key):lower()
    if key and #key >= 2 then return key end
end

local function authorMatches(key, names)
    if not key then return true end
    if type(names) == "string" then names = { names } end
    for _, name in ipairs(names or {}) do
        if type(name) == "string" and name:lower():find(key, 1, true) then
            return true
        end
    end
    return false
end

-- Open Library : couverture, note moyenne et clé de l'œuvre (pour la description)
local function searchOpenLibrary(title, key)
    local JSON = require("json")
    local socket_url = require("socket.url")
    local url = "https://openlibrary.org/search.json?limit=20&fields=key,cover_i,title,author_name,ratings_average,ratings_count&title="
        .. socket_url.escape(title)
    if key then
        url = url .. "&author=" .. socket_url.escape(key)
    end
    local body, err = fetchUrl(url)
    if not body then return nil, err end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" or type(data.docs) ~= "table" then
        return nil, "réponse illisible"
    end
    local lower_title = title:lower()
    local best, fallback
    for _, doc in ipairs(data.docs) do
        if authorMatches(key, doc.author_name) then
            local exact = type(doc.title) == "string" and doc.title:lower() == lower_title
            if exact and not best then best = doc end
            if not fallback then fallback = doc end
        end
    end
    local doc = best or fallback
    if not doc then return nil end
    local result = { source = "Open Library" }
    if doc.cover_i then
        result.cover_url = "https://covers.openlibrary.org/b/id/" .. doc.cover_i .. "-L.jpg?default=false"
    end
    if tonumber(doc.ratings_average) then
        result.rating = tonumber(doc.ratings_average)
        result.rating_count = tonumber(doc.ratings_count)
    end
    if type(doc.key) == "string" then
        result.work_key = doc.key
    end
    return result
end

local function fetchOpenLibraryDescription(work_key)
    local JSON = require("json")
    local body = fetchUrl("https://openlibrary.org" .. work_key .. ".json")
    if not body then return nil end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" then return nil end
    local d = data.description
    if type(d) == "table" then d = d.value end
    if type(d) == "string" and d ~= "" then
        return (d:gsub("%s*%-%-%-%-.*$", "")) -- coupe les notes de source en fin de texte
    end
end

-- Google Books : couverture, description, note
local function searchGoogleBooks(title, key)
    local JSON = require("json")
    local socket_url = require("socket.url")
    local q = 'intitle:"' .. title .. '"'
    if key then
        q = q .. ' inauthor:"' .. key .. '"'
    end
    local url = "https://www.googleapis.com/books/v1/volumes?maxResults=10&printType=books&q=" .. socket_url.escape(q)
    local body, err = fetchUrl(url)
    if not body then return nil, err end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" or type(data.items) ~= "table" then
        return nil
    end
    for _, item in ipairs(data.items) do
        local info = item.volumeInfo
        if type(info) == "table" and authorMatches(key, info.authors) then
            local result = { source = "Google Books" }
            if type(info.imageLinks) == "table" then
                local thumb = info.imageLinks.thumbnail or info.imageLinks.smallThumbnail
                if type(thumb) == "string" then
                    thumb = thumb:gsub("^http://", "https://"):gsub("&edge=curl", "")
                    result.cover_url = (thumb:gsub("zoom=1", "zoom=2"))
                    result.alt_cover_url = thumb
                end
            end
            if type(info.description) == "string" and info.description ~= "" then
                result.description = info.description
            end
            if tonumber(info.averageRating) then
                result.rating = tonumber(info.averageRating)
                result.rating_count = tonumber(info.ratingsCount)
            end
            return result
        end
    end
    return nil
end

-- Rassemble ce qu'on trouve en ligne pour un livre : { cover_url, alt_cover_url,
-- description, rating, rating_count, source }. Peut lever une erreur (réseau).
local function fetchOnlineInfo(title, authors, want)
    local key = authorKey(authors)
    local ol, ol_err = searchOpenLibrary(title, key)
    local result = {}
    if ol then
        result.cover_url = ol.cover_url
        result.rating, result.rating_count = ol.rating, ol.rating_count
        result.source = ol.source
        if want.description and ol.work_key then
            result.description = fetchOpenLibraryDescription(ol.work_key)
        end
    end
    if not result.cover_url or (want.description and not result.description) or not result.rating then
        local gb = searchGoogleBooks(title, key)
        if gb then
            result.cover_url = result.cover_url or gb.cover_url
            result.alt_cover_url = result.cover_url == gb.cover_url and gb.alt_cover_url or nil
            result.description = result.description or gb.description
            if not result.rating then
                result.rating, result.rating_count = gb.rating, gb.rating_count
            end
            result.source = result.source or gb.source
        end
    end
    if not ol and ol_err and not result.source then
        error("Open Library injoignable (" .. ol_err .. ")")
    end
    return result, key
end

-- Applique un résultat en ligne au livre. Retourne la liste de ce qui a changé.
local function applyOnlineInfo(ui, file, props, info, want)
    local changed = {}
    local cache = onlineCache()
    cache[file] = cache[file] or {}
    cache[file].at = os.time()
    if info.rating then
        cache[file].rating = info.rating
        cache[file].rating_count = info.rating_count
        cache[file].source = info.source
        table.insert(changed, "note")
    end
    if want.description and info.description and (not props.description or props.description == "") then
        saveCustomProp(file, props, "description", info.description)
        table.insert(changed, "description")
    end
    if want.cover and info.cover_url then
        local image, dl_err = fetchUrl(info.cover_url, 15, 60)
        if (not image or #image < 1000) and info.alt_cover_url then
            image, dl_err = fetchUrl(info.alt_cover_url, 15, 60)
        end
        if image and #image >= 1000 then
            local DataStorage = require("datastorage")
            local tmp = DataStorage:getDataDir() .. "/cache/apparence-accueil-cover.jpg"
            local f = io.open(tmp, "wb")
            if f then
                f:write(image)
                f:close()
                if ui.bookinfo.setCustomCoverFromImage then
                    ui.bookinfo:setCustomCoverFromImage(file, tmp)
                else
                    local DocSettings = require("docsettings")
                    local Event = require("ui/event")
                    DocSettings:flushCustomCover(file, tmp)
                    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
                end
                os.remove(tmp)
                table.insert(changed, "couverture")
            end
        else
            logger.warn("apparence-accueil: couverture non téléchargée :", dl_err)
        end
    end
    onlineCacheSave()
    return changed
end

local BookCard = InputContainer:extend{
    ui = nil,
    file = nil,
    props = nil,       -- métadonnées (titre, auteurs, description...)
    book_info = nil,   -- statut, progression
    cover_bb = nil,    -- image de couverture, ou nil
}

function BookCard:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.width = screen_w - Screen:scaleBySize(20)
    self.height = screen_h - Screen:scaleBySize(20)
    local pad = Screen:scaleBySize(14)
    local inner_w = self.width - 2*pad

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{ w = screen_w, h = screen_h }
        self.ges_events = {
            TapClose = { GestureRange:new{ ges = "tap", range = range } },
            MultiSwipeClose = { GestureRange:new{ ges = "multiswipe", range = range } },
        }
    end

    local props = self.props
    local book_info = self.book_info or {}
    local _, filename = util.splitFilePathName(self.file)
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local name, filetype = filemanagerutil.splitFileNameType(filename)
    local title = props.display_title or props.title or name

    -- Couverture
    local cover_h = math.floor(self.height * 0.30)
    local cover_w = math.floor(cover_h * (CFG.cover_ratio or 2/3))
    local cover_widget
    if self.cover_bb then
        cover_widget = makeCroppedImage(self.cover_bb, cover_w, cover_h)
        self.cover_bb = nil -- l'ImageWidget en est maintenant propriétaire
    elseif AA.FakeCover then
        cover_widget = AA.FakeCover:new{
            width = cover_w,
            height = cover_h,
            bordersize = 0,
            filename = filename,
            title = props.title,
            authors = props.authors,
        }
    else
        cover_widget = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = cover_h },
            TextBoxWidget:new{ text = "?", face = Font:getFace("cfont", 40), width = cover_w, alignment = "center" },
        }
    end
    local cover_frame = makeCoverFrame(cover_widget, cover_w, cover_h, false)

    -- Colonne de texte à droite de la couverture
    local col_w = inner_w - cover_frame:getSize().w - pad
    local column = VerticalGroup:new{ align = "left" }
    table.insert(column, TextBoxWidget:new{
        text = title,
        face = Font:getFace("tfont", 21),
        bold = true,
        width = col_w,
    })
    if props.authors then
        table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(4) })
        table.insert(column, TextBoxWidget:new{
            text = props.authors,
            face = Font:getFace("cfont", 17),
            width = col_w,
        })
    end

    local rows = {}
    local function addRow(key, value)
        if value and value ~= "" then
            table.insert(rows, { key, tostring(value) })
        end
    end
    if props.series then
        addRow("Série", props.series_index and (props.series .. " #" .. props.series_index) or props.series)
    end
    if props.keywords then
        addRow("Mots-clés", (props.keywords:gsub("\n", ", ")))
    end

    -- Pages et chapitres
    local pages = tonumber(props.pages) or tonumber(book_info.pages)
    local chapters
    if BookList.hasBookBeenOpened(self.file) then
        chapters = BookList.getDocSettings(self.file):readSetting("apparence_chapters")
    end
    local parts = {}
    if pages then table.insert(parts, pages .. " pages") end
    if chapters then table.insert(parts, chapters .. " chapitres") end
    addRow("Contenu", table.concat(parts, " · "))

    -- Format
    local attr = lfs.attributes(self.file)
    local format_parts = { filetype:upper() }
    if attr and attr.size then table.insert(format_parts, util.getFriendlySize(attr.size)) end
    if props.language then table.insert(format_parts, props.language) end
    addRow("Format", table.concat(format_parts, " · "))

    -- Statut et progression
    local status = book_info.been_opened and book_info.status or "new"
    local status_text = CFG.status_labels and CFG.status_labels[status] or BookList.getBookStatusString(status) or status
    if book_info.percent_finished and status ~= "complete" then
        status_text = status_text .. " · " .. math.floor(book_info.percent_finished * 100 + 0.5) .. " %"
    end
    addRow("Statut", status_text)

    -- Temps de lecture
    if CFG.card_reading_time and pages then
        local per_page, from_book = readingSpeed(self.file)
        if per_page then
            local total = formatDuration(pages * per_page)
            local time_parts = {}
            if total then table.insert(time_parts, "~" .. total) end
            if status ~= "complete" then
                local done = (book_info.percent_finished or 0) * pages
                local left = formatDuration((pages - done) * per_page)
                if left then table.insert(time_parts, "restant : ~" .. left) end
            end
            local label = from_book and "Lecture" or "Lecture*"
            addRow(label, table.concat(time_parts, " · "))
        end
    end

    -- Notes : la mienne (étoiles KOReader) et celle trouvée en ligne
    local rating = tonumber(book_info.rating) or 0
    local rating_parts = { BookList.getBookRatingString(rating) }
    local cached = onlineCache()[self.file]
    if cached and cached.rating then
        local text = string.format("%.1f/5", cached.rating):gsub("%.", ",")
        if cached.rating_count then
            text = text .. " (" .. cached.rating_count .. " avis)"
        end
        table.insert(rating_parts, (cached.source or "en ligne") .. " " .. text)
    end
    addRow("Note", table.concat(rating_parts, " · "))

    if #rows > 0 then
        table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        local key_face = Font:getFace("smallinfofontbold", 12)
        local value_face = Font:getFace("x_smallinfofont", 13)
        local key_w = math.floor(col_w * 0.28)
        for _, row in ipairs(rows) do
            local key = TextWidget:new{
                text = row[1]:upper(),
                face = key_face,
                fgcolor = Blitbuffer.COLOR_BLACK,
                bold = true,
                max_width = key_w - Screen:scaleBySize(6),
            }
            local value = TextBoxWidget:new{
                text = row[2],
                face = value_face,
                width = col_w - key_w,
            }
            table.insert(column, HorizontalGroup:new{
                align = "top",
                CenterContainer:new{
                    dimen = Geom:new{ w = key_w, h = value:getSize().h },
                    HorizontalGroup:new{ key, HorizontalSpan:new{ width = math.max(0, key_w - key:getSize().w) } },
                },
                value,
            })
            table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(2) })
        end
    end

    local header = HorizontalGroup:new{
        align = "top",
        cover_frame,
        HorizontalSpan:new{ width = pad },
        column,
    }

    -- Boutons : statut, puis actions
    local function statusLabel(s)
        return CFG.status_labels and CFG.status_labels[s] or BookList.getBookStatusString(s) or s
    end
    local function statusButton(to_status)
        local current = status == to_status
        return {
            text = statusLabel(to_status) .. (current and "  \u{2713}" or ""),
            enabled = not current,
            callback = function()
                self:onClose()
                self:setStatus(to_status)
            end,
        }
    end
    self.status_table = ButtonTable:new{
        width = inner_w,
        buttons = {{
            {
                text = "Réinitialiser",
                enabled = book_info.been_opened and true or false,
                callback = function()
                    self:onClose()
                    self:resetBook()
                end,
            },
            statusButton("abandoned"),
            statusButton("complete"),
            {
                text = "Noter",
                callback = function()
                    self:onClose()
                    self:rateBook(rating)
                end,
            },
        }},
        zero_sep = true,
        show_parent = self,
    }

    local actions = {
        {
            text = "Fermer",
            callback = function() self:onClose() end,
        },
    }
    if CFG.cover_fetch then
        table.insert(actions, {
            text = "Compléter",
            callback = function()
                self:onClose()
                self:fetchOnline()
            end,
        })
    end
    table.insert(actions, {
        text = "Détails",
        callback = function()
            self:onClose()
            self.ui.bookinfo:show(self.file)
        end,
    })
    table.insert(actions, {
        text = "Ouvrir",
        callback = function()
            self:onClose()
            if filemanagerutil.openFile then
                filemanagerutil.openFile(self.ui, self.file)
            else
                self.ui:openFile(self.file)
            end
        end,
    })
    self.button_table = ButtonTable:new{
        width = self.width - 2*Size.border.window,
        buttons = { actions },
        zero_sep = true,
        show_parent = self,
    }

    -- Description, dans l'espace restant
    local separator = LineWidget:new{
        dimen = Geom:new{ w = inner_w, h = Size.line.thin },
        background = Blitbuffer.COLOR_GRAY_D,
    }
    local used_h = pad + header:getSize().h + pad + self.status_table:getSize().h + pad + separator:getSize().h + pad + pad + self.button_table:getSize().h
    local desc_h = math.max(self.height - used_h, Screen:scaleBySize(40))
    local description = props.description and util.htmlToPlainTextIfHtml(props.description)
    if not description or description == "" then
        description = "Pas de description dans ce livre."
    end
    self.scroll_widget = ScrollTextWidget:new{
        text = description,
        face = Font:getFace("x_smallinfofont", 16),
        width = inner_w,
        height = desc_h,
        dialog = self,
        justified = true,
    }

    local function padded(widget)
        return HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, widget }
    end
    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = pad },
            padded(header),
            VerticalSpan:new{ width = pad },
            padded(self.status_table),
            VerticalSpan:new{ width = pad },
            padded(separator),
            VerticalSpan:new{ width = pad },
            padded(self.scroll_widget),
            VerticalSpan:new{ width = pad },
            CenterContainer:new{
                dimen = Geom:new{ w = self.width, h = self.button_table:getSize().h },
                self.button_table,
            },
        },
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        self.frame,
    }
end

-- Change le statut du livre (crée le fichier de réglages s'il n'existe pas)
-- et rafraîchit l'explorateur.
function BookCard:setStatus(to_status)
    local DocSettings = require("docsettings")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local doc_settings = DocSettings:open(self.file)
    local summary = doc_settings:readSetting("summary") or {}
    summary.status = to_status
    filemanagerutil.saveSummary(doc_settings, summary)
    BookList.setBookInfoCache(self.file, doc_settings)
    if self.ui.file_chooser then
        self.ui.file_chooser:refreshPath()
    end
end

-- Note de 0 à 5 étoiles (celle de KOReader, dans le fichier de réglages)
function BookCard:rateBook(current)
    local ButtonDialog = require("ui/widget/buttondialog")
    local file, ui = self.file, self.ui
    local dialog
    local function star(n)
        return {
            text = (n == 0 and "Aucune" or BookList.getBookRatingString(n)) .. (n == current and "  \u{2713}" or ""),
            callback = function()
                UIManager:close(dialog)
                local DocSettings = require("docsettings")
                local filemanagerutil = require("apps/filemanager/filemanagerutil")
                local doc_settings = DocSettings:open(file)
                local summary = doc_settings:readSetting("summary") or {}
                summary.rating = n
                filemanagerutil.saveSummary(doc_settings, summary)
                BookList.setBookInfoCache(file, doc_settings)
                AA.showBookCard(ui, file, true)
            end,
        }
    end
    dialog = ButtonDialog:new{
        title = "Ma note",
        buttons = {
            { star(5), star(4), star(3) },
            { star(2), star(1), star(0) },
        },
    }
    UIManager:show(dialog)
end

-- Efface le statut et la progression (le fichier de réglages KOReader du
-- livre est supprimé, comme le fait le bouton "Reset" de KOReader).
function BookCard:resetBook()
    local ConfirmBox = require("ui/widget/confirmbox")
    local DocSettings = require("docsettings")
    local file = self.file
    local ui = self.ui
    UIManager:show(ConfirmBox:new{
        text = "Réinitialiser ce livre ?\n\nStatut, progression, marque-pages et surlignages seront effacés.",
        ok_text = "Réinitialiser",
        cancel_text = "Annuler",
        ok_callback = function()
            DocSettings:open(file):purge(nil, { doc_settings = true })
            BookList.setBookInfoCacheProperty(file, "been_opened", false)
            if ui.file_chooser then
                ui.file_chooser:refreshPath()
            end
        end,
    })
end

-- Bouton "Compléter" : couverture (remplacée), description si absente, note.
function BookCard:fetchOnline()
    local NetworkMgr = require("ui/network/manager")
    local InfoMessage = require("ui/widget/infomessage")
    local file, ui, props = self.file, self.ui, self.props
    local title = props.title
    if not title or title == "" then
        UIManager:show(InfoMessage:new{ text = "Ce livre n'a pas de titre dans ses métadonnées : impossible de chercher en ligne." })
        return
    end
    NetworkMgr:runWhenOnline(function()
        local info_msg = InfoMessage:new{ text = "Recherche en ligne (Open Library, Google Books)…" }
        UIManager:show(info_msg)
        UIManager:scheduleIn(0.2, function()
            local want = { cover = true, description = true }
            local ok, err = pcall(function()
                local info, key = fetchOnlineInfo(title, props.authors, want)
                local changed = applyOnlineInfo(ui, file, props, info, want)
                if #changed == 0 then
                    error("Rien trouvé pour « " .. title .. " »" .. (key and (" de " .. key) or "") .. ".")
                end
                return changed
            end)
            UIManager:close(info_msg)
            if ok then
                UIManager:show(InfoMessage:new{ text = "Mis à jour : " .. table.concat(err, ", ") .. ".", timeout = 2 })
                if ui.file_chooser then
                    ui.file_chooser:refreshPath()
                end
                AA.showBookCard(ui, file, true)
            else
                UIManager:show(InfoMessage:new{ text = tostring(err):gsub("^.-:%d+: ", "") })
            end
        end)
    end)
end

function BookCard:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

function BookCard:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

function BookCard:onClose()
    UIManager:close(self)
    return true
end

function BookCard:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function BookCard:onMultiSwipeClose()
    self:onClose()
    return true
end

local function openBookCard(ui, file)
    local props = ui.bookinfo:getDocProps(file) or {}
    local cover_bb
    if AA.BookInfoManager then
        local bookinfo = AA.BookInfoManager:getBookInfo(file, true)
        if bookinfo and bookinfo.cover_bb then
            if bookinfo.has_cover and not bookinfo.ignore_cover then
                cover_bb = bookinfo.cover_bb
            else
                bookinfo.cover_bb:free()
            end
        end
    end
    UIManager:show(BookCard:new{
        ui = ui,
        file = file,
        props = props,
        book_info = BookList.getBookInfo(file),
        cover_bb = cover_bb,
    })
end

-- Ouvre la fiche ; si on est en ligne et qu'il manque la description ou la
-- note, va les chercher d'abord (au plus une fois par semaine par livre).
AA.showBookCard = function(ui, file, skip_online)
    local props = ui.bookinfo:getDocProps(file) or {}
    local cached = onlineCache()[file]
    local need_desc = CFG.description_fetch and (not props.description or props.description == "")
    local need_rating = CFG.rating_fetch and not (cached and cached.rating)
    local recently = cached and cached.at and (os.time() - cached.at) < 7 * 24 * 3600
    if skip_online or recently or not (need_desc or need_rating) or not props.title or props.title == "" then
        return openBookCard(ui, file)
    end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isOnline() then
        return openBookCard(ui, file)
    end
    local InfoMessage = require("ui/widget/infomessage")
    local info_msg = InfoMessage:new{ text = "Recherche de la description et de la note…" }
    UIManager:show(info_msg)
    UIManager:scheduleIn(0.2, function()
        local want = { description = need_desc }
        local ok, err = pcall(function()
            local info = fetchOnlineInfo(props.title, props.authors, want)
            applyOnlineInfo(ui, file, props, info, want)
        end)
        if not ok then
            logger.warn("apparence-accueil: recherche en ligne :", err)
            local cache = onlineCache()
            cache[file] = cache[file] or {}
            cache[file].at = os.time() -- on ne réessaie pas tout de suite
            onlineCacheSave()
        end
        UIManager:close(info_msg)
        openBookCard(ui, file)
    end)
end

-- Exporté pour les autres fichiers
AA.formatDuration = formatDuration
AA.readingSpeed = readingSpeed
AA.onlineCache = onlineCache
