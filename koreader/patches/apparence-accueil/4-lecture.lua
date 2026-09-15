-- Apparence accueil : barre de lecture (ReaderFooter) et fin de livre
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

local formatDuration = AA.formatDuration

-------------------------------------------------------------------------------
-- 7. Barre de lecture (ReaderFooter) : marge, une ligne, chapitre X / N
-------------------------------------------------------------------------------

local ok_footer, ReaderFooter = pcall(require, "apps/reader/modules/readerfooter")
if ok_footer and ReaderFooter then
    -- Chapitre courant / nombre de chapitres du même niveau, à la place des
    -- pages lues dans le chapitre.
    local orig_getChapterProgress = ReaderFooter.getChapterProgress
    ReaderFooter.getChapterProgress = function(self, get_percentage, pageno)
        if not CFG.reader_chapter_index or get_percentage then
            return orig_getChapterProgress(self, get_percentage, pageno)
        end
        pageno = pageno or self.pageno
        local toc = self.ui and self.ui.toc
        local idx = toc and toc:getTocIndexByPage(pageno)
        local entry = idx and toc.toc and toc.toc[idx]
        if not entry then
            return orig_getChapterProgress(self, get_percentage, pageno)
        end
        local current, total = 0, 0
        for i, item in ipairs(toc.toc) do
            if item.depth == entry.depth then
                total = total + 1
                if i <= idx then
                    current = current + 1
                end
            end
        end
        if self.ui.doc_settings then
            self.ui.doc_settings:saveSetting("apparence_chapter_current", current)
            self.ui.doc_settings:saveSetting("apparence_chapters", total)
        end
        local text = string.format("%s %d / %d", CFG.reader_chapter_label or "Chap.", current, total)
        if CFG.reader_chapter_time_left then
            local st = self.ui.statistics
            local left = toc.getChapterPagesLeft and toc:getChapterPagesLeft(pageno)
            if st and st.avg_time and st.avg_time == st.avg_time and left and left > 0 then
                local d = formatDuration(left * st.avg_time)
                if d then text = text .. " · ~" .. d end
            end
        end
        return text
    end

    -- Pourcentage sans préfixe
    if CFG.reader_plain_percentage and ReaderFooter.textGeneratorMap then
        ReaderFooter.textGeneratorMap.percentage = function(footer)
            return string.format("%d %%", math.floor((footer.percent_finished or 0) * 100 + 0.5))
        end
    end

    -- Préréglage, appliqué une fois par version
    local orig_footer_init = ReaderFooter.init
    ReaderFooter.init = function(self)
        local preset = CFG.reader_footer_preset
        if preset then
            local st = G_reader_settings:readSetting("footer")
            if not st then
                st = util.tableDeepCopy(ReaderFooter.default_settings)
            end
            if st.apparence_accueil_preset ~= preset then
                for _, name in ipairs({ "time", "pages_left", "pages_left_book", "battery", "book_time_to_read",
                        "chapter_time_to_read", "frontlight", "frontlight_warmth", "mem_usage", "wifi_status",
                        "book_title", "book_chapter", "book_author", "bookmark_count", "custom_text",
                        "page_turning_inverted", "dynamic_filler", "additional_content" }) do
                    st[name] = false
                end
                st.page_progress = true
                st.percentage = true
                st.chapter_progress = true
                st.all_at_once = true
                st.disabled = false
                st.disable_progress_bar = false
                st.progress_bar_position = "alongside"
                st.progress_margin = true -- mêmes marges que le texte du livre
                st.align = "center" -- seul alignement symétrique avec la barre "à côté"
                st.items_separator = "dot"
                st.item_prefix = "icons"
                st.hide_empty_generators = true
                st.order = { [0] = "off", "page_progress", "percentage", "chapter_progress" }
                local px_per_point = Screen:scaleBySize(100) / 100
                st.container_bottom_padding = math.max(0, math.floor((CFG.reader_footer_bottom_margin or 0) / px_per_point + 0.5))
                st.apparence_accueil_preset = preset
                G_reader_settings:saveSetting("footer", st)
            end
        end
        orig_footer_init(self)
    end

    -- Nombre de chapitres, mémorisé dans les réglages du livre pour la fiche
    local orig_onReaderReady = ReaderFooter.onReaderReady
    ReaderFooter.onReaderReady = function(self, ...)
        local result = orig_onReaderReady(self, ...)
        pcall(function()
            local toc = self.ui and self.ui.toc
            if not toc or not self.ui.doc_settings then return end
            if toc.fillToc then toc:fillToc() end
            local per_depth = {}
            for _, item in ipairs(toc.toc or {}) do
                per_depth[item.depth] = (per_depth[item.depth] or 0) + 1
            end
            local best = 0
            for _, n in pairs(per_depth) do
                if n > best then best = n end
            end
            if best > 0 then
                self.ui.doc_settings:saveSetting("apparence_chapters", best)
            end
        end)
        return result
    end

    -- Espace entre le texte du livre et la barre
    if CFG.reader_footer_top_margin and CFG.reader_footer_top_margin > 0 then
        local orig_updateFooterContainer = ReaderFooter.updateFooterContainer
        ReaderFooter.updateFooterContainer = function(self)
            orig_updateFooterContainer(self)
            if self.vertical_frame then
                table.insert(self.vertical_frame, 1, VerticalSpan:new{ width = CFG.reader_footer_top_margin })
                if self.vertical_frame.resetLayout then
                    self.vertical_frame:resetLayout()
                end
            end
        end
    end
else
    logger.warn("apparence-accueil: barre de lecture non patchée :", ReaderFooter)
end

-------------------------------------------------------------------------------
-- 8. Fin de livre : Marquer terminé / Noter / Bibliothèque
-------------------------------------------------------------------------------

local ok_status, ReaderStatus = pcall(require, "apps/reader/modules/readerstatus")
if ok_status and ReaderStatus and CFG.end_of_book_dialog then
    local orig_onEndOfBook = ReaderStatus.onEndOfBook
    ReaderStatus.onEndOfBook = function(self)
        local top = UIManager:getTopmostVisibleWidget() or {}
        if top.name == "end_document" then return true end
        local ButtonDialog = require("ui/widget/buttondialog")
        local InfoMessage = require("ui/widget/infomessage")
        local file = self.document and self.document.file
        local function markFinished()
            self:markBook(true)
            UIManager:show(InfoMessage:new{ text = "Livre marqué comme terminé.", timeout = 2 })
        end
        local dialog
        local function rate()
            local summary = self.ui.doc_settings:readSetting("summary") or {}
            local current = tonumber(summary.rating) or 0
            local rating_dialog
            local function star(n)
                return {
                    text = (n == 0 and "Aucune" or BookList.getBookRatingString(n)) .. (n == current and "  \u{2713}" or ""),
                    callback = function()
                        UIManager:close(rating_dialog)
                        summary.rating = n
                        self.ui.doc_settings:saveSetting("summary", summary)
                        if file then BookList.setBookInfoCacheProperty(file, "rating", n) end
                    end,
                }
            end
            rating_dialog = ButtonDialog:new{
                name = "end_document",
                title = "Ma note",
                title_align = "center",
                buttons = { { star(5), star(4), star(3) }, { star(2), star(1), star(0) } },
            }
            UIManager:show(rating_dialog)
        end
        dialog = ButtonDialog:new{
            name = "end_document",
            title = "Vous avez terminé ce livre.",
            title_align = "center",
            buttons = {
                {
                    {
                        text = "Marquer terminé",
                        enabled = (self.ui.doc_settings:readSetting("summary") or {}).status ~= "complete",
                        callback = function()
                            UIManager:close(dialog)
                            markFinished()
                        end,
                    },
                    {
                        text = "Noter",
                        callback = function()
                            UIManager:close(dialog)
                            rate()
                        end,
                    },
                },
                {
                    {
                        text = "Terminé et noter",
                        callback = function()
                            UIManager:close(dialog)
                            markFinished()
                            rate()
                        end,
                    },
                    {
                        text = "Bibliothèque",
                        callback = function()
                            UIManager:close(dialog)
                            UIManager:nextTick(function() self:openFileBrowser() end)
                        end,
                    },
                },
                {
                    {
                        text = "Fermer",
                        callback = function() UIManager:close(dialog) end,
                    },
                },
            },
        }
        UIManager:show(dialog)
        return true
    end
end
