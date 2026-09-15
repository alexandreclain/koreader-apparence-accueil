-- Apparence accueil : requires, couleurs et cadres de couverture (partagés)
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

local COLORS = {
    white = Blitbuffer.COLOR_WHITE,
    gray_e = Blitbuffer.COLOR_GRAY_E,
    gray_d = Blitbuffer.COLOR_GRAY_D,
    light_gray = Blitbuffer.COLOR_LIGHT_GRAY,
    gray = Blitbuffer.COLOR_GRAY,
    dark_gray = Blitbuffer.COLOR_DARK_GRAY,
    gray_3 = Blitbuffer.COLOR_GRAY_3,
    gray_2 = Blitbuffer.COLOR_GRAY_2,
    gray_1 = Blitbuffer.COLOR_GRAY_1,
    black = Blitbuffer.COLOR_BLACK,
}
local function color(name, default)
    return name and COLORS[name] or default
end
local DIM_COLOR = color(CFG.ui_dim_color, Blitbuffer.COLOR_GRAY_1)

-- Marge autour de tout l'écran d'accueil, en px (0 = aucune)
local function pagePadding()
    return CFG.page_padding and CFG.page_padding > 0 and CFG.page_padding or 0
end

-------------------------------------------------------------------------------
-- 3. Cadres de couverture : taille, bordure, arrondi
-------------------------------------------------------------------------------

-- Bordure + espace intérieur du cadre, en px
local function coverInset()
    return (CFG.cover_border or 0) + (CFG.cover_padding or 0)
end

-- Hauteur d'une ligne de titre sous les couvertures (mesurée une fois)
local title_line_h
local function coverTitleFace()
    return Font:getFace("cfont", CFG.cover_title_font_size or 13)
end
-- Hauteur réservée sous le cadre pour le titre (0 si désactivé)
local function coverTitleBlockHeight()
    if not CFG.cover_title then return 0 end
    if not title_line_h then
        local probe = TextBoxWidget:new{ text = "Ag", face = coverTitleFace(), width = Screen:scaleBySize(100) }
        title_line_h = probe:getSize().h
        probe:free()
    end
    return Screen:scaleBySize(4) + title_line_h * (CFG.cover_title_lines or 1)
end

-- Marge à garder autour du contenu d'une vignette pour que, une fois
-- tournée, elle reste dans sa case.
local function tiltMargin(dimen)
    local deg = CFG.tilt_degrees or 0
    if deg <= 0 then return 0 end
    return math.ceil(math.sin(math.rad(deg)) * math.max(dimen.w, dimen.h) / 2) + 2
end

-- Taille cible de l'image d'une couverture dans une vignette de dimen.
local function coverTargetSize(dimen)
    local inset = coverInset()
    local tilt = tiltMargin(dimen)
    local max_w = dimen.w - 2*inset - 2*tilt
    local max_h = dimen.h - 2*inset - 2*tilt - coverTitleBlockHeight()
    if not CFG.cover_ratio then
        return max_w, max_h
    end
    local h = max_h
    local w = math.floor(h * CFG.cover_ratio + 0.5)
    if w > max_w then
        w = max_w
        h = math.floor(w / CFG.cover_ratio + 0.5)
    end
    return w, h
end

-- Peint, par-dessus une image déjà dessinée, les quatre coins situés hors de
-- l'arrondi, dans la couleur donnée : l'image paraît ainsi arrondie.
local function paintRoundedMask(bb, x, y, w, h, r, c)
    if r <= 0 then return end
    local r2 = r * r
    for dy = 0, r - 1 do
        for dx = 0, r - 1 do
            local cx, cy = dx + 0.5 - r, dy + 0.5 - r
            if cx*cx + cy*cy > r2 then
                bb:setPixel(x + dx, y + dy, c)
                bb:setPixel(x + w - 1 - dx, y + dy, c)
                bb:setPixel(x + dx, y + h - 1 - dy, c)
                bb:setPixel(x + w - 1 - dx, y + h - 1 - dy, c)
            end
        end
    end
end

-- Cadre "moderne" autour d'une image w×h : bordure claire, espace blanc,
-- coins arrondis, image recadrée derrière l'arrondi.
local function makeCoverFrame(content, w, h, deleted, opened)
    local border = CFG.cover_border or 0
    local padding = CFG.cover_padding or 0
    if opened and CFG.cover_border_opened then
        -- Bordure plus épaisse, espace réduit d'autant : même taille de cadre
        border = CFG.cover_border_opened
        padding = math.max(0, coverInset() - border)
    end
    local radius = CFG.cover_radius or 0
    local border_color = deleted and Blitbuffer.COLOR_DARK_GRAY or color(CFG.cover_border_color, Blitbuffer.COLOR_LIGHT_GRAY)
    local frame = FrameContainer:new{
        width = w + 2*(border + padding),
        height = h + 2*(border + padding),
        margin = 0,
        padding = padding,
        bordersize = border,
        color = border_color,
        background = Blitbuffer.COLOR_WHITE,
        radius = radius + border + padding,
        dim = deleted,
        content,
    }
    if radius > 0 then
        -- Entre l'image et la bordure il y a l'espace blanc : le masque est blanc.
        -- Sans espace, il prend la couleur de la bordure (ou blanc sans bordure).
        local mask_color = Blitbuffer.COLOR_WHITE
        if padding == 0 and border > 0 then
            mask_color = border_color
        end
        frame.paintTo = function(this, bb, x, y)
            FrameContainer.paintTo(this, bb, x, y)
            paintRoundedMask(bb, math.floor(x) + border + padding, math.floor(y) + border + padding, w, h, radius, mask_color)
        end
    end
    return frame
end

-- Cadre + titre centré en dessous, dans une vignette de dimen.
-- Sans titre (dossiers), un espace de même hauteur garde l'alignement.
local function makeTile(frame, dimen, title, bold)
    local block_h = coverTitleBlockHeight()
    if block_h == 0 then
        return CenterContainer:new{ dimen = dimen, frame }
    end
    local lines_h = title_line_h * (CFG.cover_title_lines or 1)
    local label = HorizontalSpan:new{ width = dimen.w }
    if title then
        label = TextBoxWidget:new{
            text = title,
            face = coverTitleFace(),
            fgcolor = color(CFG.cover_title_color, Blitbuffer.COLOR_BLACK),
            bold = bold,
            width = dimen.w,
            height = lines_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "center",
        }
    end
    return CenterContainer:new{
        dimen = dimen,
        VerticalGroup:new{
            align = "center",
            frame,
            VerticalSpan:new{ width = Screen:scaleBySize(4) },
            -- Bloc de hauteur fixe, texte calé en haut contre le cadre
            VerticalGroup:new{
                align = "center",
                label,
                VerticalSpan:new{ width = lines_h - label:getSize().h },
            },
        },
    }
end

-- ImageWidget recadré au centre pour remplir exactement w×h.
local function makeCroppedImage(bb, w, h)
    local scale = math.max((w + 1) / bb:getWidth(), (h + 1) / bb:getHeight())
    return ImageWidget:new{
        image = bb,
        image_disposable = true,
        scale_factor = scale,
        width = w,
        height = h,
    }
end

-- Exporté pour les autres fichiers
AA.color = color
AA.DIM_COLOR = DIM_COLOR
AA.pagePadding = pagePadding
AA.coverInset = coverInset
AA.coverTargetSize = coverTargetSize
AA.coverTitleBlockHeight = coverTitleBlockHeight
AA.coverTitleFace = coverTitleFace
AA.tiltMargin = tiltMargin
AA.paintRoundedMask = paintRoundedMask
AA.makeCoverFrame = makeCoverFrame
AA.makeCroppedImage = makeCroppedImage
AA.makeTile = makeTile
