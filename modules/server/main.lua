local config = require 'config'

-- ─── Runtime state ───────────────────────────────────────────────────────────
--
-- All props are indexed by group for O(1) group-level operations (toggle).
--
--   groups[groupName] = {
--       enabled = bool,
--       props   = {
--           [dbId] = {
--               model          = string,
--               position       = { x, y, z },
--               quat           = { x, y, z, w },
--               renderDistance = number,
--               expiresAt      = number | nil,
--           }
--       }
--   }

groups = {}

function getOrCreateGroup(name, enabled)
    if not groups[name] then
        groups[name] = { enabled = (enabled ~= false), props = {} }
    end
    return groups[name]
end

-- ─── Permission & identity helpers ───────────────────────────────────────────

--- Returns the player's permission level (0 = none, 1 = toggleGroups, 2 = manage, 3 = playerAccess).
--- Levels are cumulative — level 3 implies levels 1 and 2.
function getPlayerLevel(source)
    if IsPlayerAceAllowed(source, config.ace[3]) then return 3 end
    if IsPlayerAceAllowed(source, config.ace[2]) then return 2 end
    if IsPlayerAceAllowed(source, config.ace[1]) then return 1 end
    return 0
end

function getIdentifier(source)
    return GetPlayerIdentifierByType(source, 'license')
end

--- 2-D point-in-polygon via ray-casting (ignores Z).
local function pointInZone(px, py, points)
    if not points or #points < 3 then return false end
    local inside = false
    local j = #points
    for i = 1, #points do
        local xi, yi = points[i].x, points[i].y
        local xj, yj = points[j].x, points[j].y
        if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

--- Checks whether a player has access to a group/position.
--- Players with level >= 2 always pass; level-0 players are checked against ar_player_access.
function hasPlayerAccess(source, group, position)
    if getPlayerLevel(source) >= 2 then return true end

    local identifier = getIdentifier(source)
    if not identifier then return false end

    local rows = MySQL.query.await(
        'SELECT * FROM `ar_player_access` WHERE identifier = ? AND JSON_CONTAINS(`groups`, JSON_QUOTE(?))',
        { identifier, group }
    )
    if not rows or #rows == 0 then return false end

    for _, row in ipairs(rows) do
        if row.area_x == nil and (row.area_type == nil or row.zone_points == nil) then
            return true
        end

        if not position then return true end

        local areaType = row.area_type or 'radius'

        if areaType == 'zone' and row.zone_points then
            local ok, pts = pcall(json.decode, row.zone_points)
            if ok and pointInZone(position.x, position.y, pts) then return true end
        elseif areaType == 'radius' and row.area_x ~= nil then
            local dx = position.x - row.area_x
            local dy = position.y - row.area_y
            local dz = position.z - row.area_z
            if math.sqrt(dx * dx + dy * dy + dz * dz) <= row.area_radius then return true end
        end
    end
    return false
end

-- ─── Payload builders & broadcast ────────────────────────────────────────────

function buildGroupStates()
    local states = {}
    for name, group in pairs(groups) do
        states[name] = group.enabled
    end
    return states
end

function buildPropList()
    local list = {}
    for groupName, group in pairs(groups) do
        for dbId, prop in pairs(group.props) do
            list[#list + 1] = {
                id             = dbId,
                model          = prop.model,
                position       = prop.position,
                quaternion     = prop.quat,
                group          = groupName,
                outlined       = false,
                renderDistance = prop.renderDistance or 200,
                expiresAt      = prop.expiresAt,
            }
        end
    end
    return list
end

function buildSyncPayload()
    return { props = buildPropList(), groupStates = buildGroupStates() }
end

function buildPropEntry(id, prop, groupName)
    return {
        id             = id,
        model          = prop.model,
        position       = prop.position,
        quaternion     = prop.quat,
        group          = groupName,
        outlined       = false,
        renderDistance = prop.renderDistance or 200,
        expiresAt      = prop.expiresAt,
    }
end

function broadcastPropAdded(id, prop, groupName)
    TriggerClientEvent('ar_propmanager:propAdded', -1, buildPropEntry(id, prop, groupName))
end

function broadcastPropUpdated(id, prop, groupName)
    TriggerClientEvent('ar_propmanager:propUpdated', -1, buildPropEntry(id, prop, groupName))
end

function broadcastPropsRemoved(ids)
    TriggerClientEvent('ar_propmanager:propsRemoved', -1, ids)
end

function broadcastGroupStates()
    TriggerClientEvent('ar_propmanager:groupStatesChanged', -1, buildGroupStates())
end

-- ─── Schema ──────────────────────────────────────────────────────────────────

local function createTables()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `ar_props` (
            `id`              INT         NOT NULL AUTO_INCREMENT,
            `model`           VARCHAR(64) NOT NULL,
            `pos_x`           FLOAT       NOT NULL,
            `pos_y`           FLOAT       NOT NULL,
            `pos_z`           FLOAT       NOT NULL,
            `quat_x`          FLOAT       NOT NULL DEFAULT 0,
            `quat_y`          FLOAT       NOT NULL DEFAULT 0,
            `quat_z`          FLOAT       NOT NULL DEFAULT 0,
            `quat_w`          FLOAT       NOT NULL DEFAULT 1,
            `group_name`      VARCHAR(64) NOT NULL,
            `render_distance` FLOAT       NOT NULL DEFAULT 200,
            `expires_at`      BIGINT      NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_group` (`group_name`)
        )
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `ar_prop_groups` (
            `group_name` VARCHAR(64) NOT NULL,
            `enabled`    TINYINT     NOT NULL DEFAULT 1,
            PRIMARY KEY (`group_name`)
        )
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `ar_player_access` (
            `id`          INT                   NOT NULL AUTO_INCREMENT,
            `identifier`  VARCHAR(64)           NOT NULL,
            `name`        VARCHAR(64)           NOT NULL,
            `groups`      JSON                  NOT NULL,
            `area_type`   ENUM('radius','zone') NULL DEFAULT NULL,
            `area_x`      FLOAT                 NULL,
            `area_y`      FLOAT                 NULL,
            `area_z`      FLOAT                 NULL,
            `area_radius` FLOAT                 NULL,
            `zone_points` JSON                  NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_identifier` (`identifier`)
        )
    ]])
end

-- ─── Startup ─────────────────────────────────────────────────────────────────

local function loadData()
    local groupRows = MySQL.query.await('SELECT * FROM `ar_prop_groups`')
    for _, row in ipairs(groupRows or {}) do
        getOrCreateGroup(row.group_name, row.enabled == 1)
    end

    local propRows = MySQL.query.await('SELECT * FROM `ar_props`')
    for _, row in ipairs(propRows or {}) do
        local group = getOrCreateGroup(row.group_name)
        group.props[row.id] = {
            model          = row.model,
            position       = { x = row.pos_x, y = row.pos_y, z = row.pos_z },
            quat           = { x = row.quat_x, y = row.quat_y, z = row.quat_z, w = row.quat_w },
            renderDistance = row.render_distance or 200,
            expiresAt      = row.expires_at,
        }
    end

    print(('[ar_propmanager] Loaded %d prop(s)'):format(#(propRows or {})))
end

MySQL.ready(function()
    createTables()
    CreateThread(function()
        Wait(200)
        loadData()
    end)
end)
