local Json = require("json")
local Scores = {}

local PRECISION = {
    creative_chaos = { damageBonus = 0, pointsPerHp = 1 },
    effective = { damageBonus = 10, pointsPerHp = 2 },
    super_funny_ko = { damageBonus = 20, pointsPerHp = 4 },
}
local COMBO = { damageBonus = 25, pointsPerHp = 5 }
local FIELDS = { "arrowPoints", "promptPoints", "arrowHits" }
local SAVE_FILES = { "battle_scores_a.json", "battle_scores_b.json" }

function Scores.new()
    return { arrowPoints = 0, promptPoints = 0, arrowHits = 0 }
end

function Scores.total(score)
    return score.arrowPoints + score.promptPoints + (score.osuPoints or 0)
end

function Scores.attack(result, power, enemyHp)
    local precision = result.combo_triggered ~= "none" and COMBO or PRECISION[result.outcome_type]
    local bonus = precision and precision.damageBonus or 0
    local damage = math.floor(result.damage_to_enemy * power * (1 + bonus / 100) + 0.5)
    local points = precision and math.min(enemyHp, damage) * precision.pointsPerHp or 0
    return damage, points, bonus
end

function Scores.addTurn(score, ritual, promptPoints)
    score.arrowPoints = score.arrowPoints + ritual.arrowPoints
    score.promptPoints = score.promptPoints + promptPoints
    score.arrowHits = score.arrowHits + ritual.arrowHits
end

local function validPoints(number)
    return type(number) == "number" and number >= 0 and number <= 2147483647 and number % 1 == 0
end

local function readHistory(filesystem, path)
    if not filesystem.getInfo(path) then return {} end
    local raw = filesystem.read(path)
    if not raw then return {} end
    local ok, history = pcall(Json.decode, raw)
    if not ok or type(history) ~= "table" then return {} end
    for index, entry in pairs(history) do
        if type(index) ~= "number" or index < 1 or index > #history or index % 1 ~= 0 then return {} end
        if type(entry) ~= "table" or type(entry.rival) ~= "string" or type(entry.won) ~= "boolean" then
            return {}
        end
        for _, key in ipairs(FIELDS) do
            if not validPoints(entry[key]) then return {} end
        end
        -- Old entries include points from mouse targets in their recorded totals.
        if entry.osuPoints ~= nil and not validPoints(entry.osuPoints) then return {} end
    end
    return history
end

function Scores.load(filesystem)
    local first = readHistory(filesystem, SAVE_FILES[1])
    local second = readHistory(filesystem, SAVE_FILES[2])
    if #first == 0 and #second == 0 then return { entries = {}, nextFile = 1 } end
    if #first >= #second then return { entries = first, nextFile = 2 } end
    return { entries = second, nextFile = 1 }
end

function Scores.record(filesystem, history, score, rival, won)
    local entry = { rival = rival, won = won }
    for _, key in ipairs(FIELDS) do entry[key] = score[key] end
    local entries = history.entries
    entries[#entries + 1] = entry
    -- Alternate files so an interrupted write leaves the previous history readable.
    local saved, err = filesystem.write(SAVE_FILES[history.nextFile], Json.encode(entries))
    if saved then history.nextFile = 3 - history.nextFile end
    return saved, err
end

return Scores
