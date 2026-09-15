--[[
Patch KOReader "apparence accueil" : chargeur.

Les réglages sont dans  patches/apparence-accueil/config.lua
Le code est dans      patches/apparence-accueil/1-commun.lua, 2-fiche.lua,
                      3-accueil.lua, 4-lecture.lua (chargés dans cet ordre).
Ce fichier doit rester dans  koreader/patches/  avec un nom commençant par "2-".
--]]

local DataStorage = require("datastorage")
local logger = require("logger")

local dir = DataStorage:getPatchesDir() .. "/apparence-accueil"
local AA = {} -- table partagée entre les fichiers

local config, err = loadfile(dir .. "/config.lua")
if not config then error("apparence-accueil: config.lua illisible : " .. tostring(err)) end
AA.CFG = config()

for _, name in ipairs({ "1-commun", "2-fiche", "3-accueil", "4-lecture" }) do
    local chunk, load_err = loadfile(dir .. "/" .. name .. ".lua")
    if not chunk then
        error("apparence-accueil: " .. name .. ".lua illisible : " .. tostring(load_err))
    end
    chunk(AA)
end

logger.info("apparence-accueil: patch chargé")
