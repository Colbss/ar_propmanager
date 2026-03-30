local config = require 'config'

-- ─── Utilities ────────────────────────────────────────────────────────────────

--- Returns the player's permission level (0 = none, 1 = toggleGroups, 2 = manage, 3 = playerAccess).
--- Levels are cumulative — level 3 implies levels 1 and 2.
local function getPlayerLevel(source)
    if IsPlayerAceAllowed(source, config.ace[3]) then return 3 end
    if IsPlayerAceAllowed(source, config.ace[2]) then return 2 end
    if IsPlayerAceAllowed(source, config.ace[1]) then return 1 end
    return 0
end

local function getIdentifier(source)
    return GetPlayerIdentifierByType(source, 'license')
end

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

local groups = {}

local function getOrCreateGroup(name, enabled)
    if not groups[name] then
        groups[name] = { enabled = (enabled ~= false), props = {} }
    end
    return groups[name]
end

-- ─── Player access check ──────────────────────────────────────────────────────
-- Checks whether a non-admin player has been granted access to a group via the
-- player access list (ar_player_access table).
-- Players with the `manage` ace bypass this check entirely.

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

local function hasPlayerAccess(source, group, position)
    if getPlayerLevel(source) >= 2 then return true end

    local identifier = getIdentifier(source)
    if not identifier then return false end

    local rows = MySQL.query.await(
        'SELECT * FROM `ar_player_access` WHERE identifier = ? AND JSON_CONTAINS(`groups`, JSON_QUOTE(?))',
        { identifier, group }
    )
    if not rows or #rows == 0 then return false end

    for _, row in ipairs(rows) do
        -- No area restriction → access granted
        if row.area_x == nil and (row.area_type == nil or row.zone_points == nil) then
            return true
        end

        if not position then return true end

        local areaType = row.area_type or 'radius'

        if areaType == 'zone' and row.zone_points then
            local ok, pts = pcall(json.decode, row.zone_points)
            if ok and pointInZone(position.x, position.y, pts) then
                return true
            end
        elseif areaType == 'radius' and row.area_x ~= nil then
            local dx = position.x - row.area_x
            local dy = position.y - row.area_y
            local dz = position.z - row.area_z
            if math.sqrt(dx * dx + dy * dy + dz * dz) <= row.area_radius then
                return true
            end
        end
    end
    return false
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

-- ─── Payload builders ─────────────────────────────────────────────────────────

local function buildGroupStates()
    local states = {}
    for name, group in pairs(groups) do
        states[name] = group.enabled
    end
    return states
end

local function buildPropList()
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

local function buildSyncPayload()
    return { props = buildPropList(), groupStates = buildGroupStates() }
end

local function buildPropEntry(id, prop, groupName)
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

local function broadcastPropAdded(id, prop, groupName)
    TriggerClientEvent('ar_propmanager:propAdded', -1, buildPropEntry(id, prop, groupName))
end

local function broadcastPropUpdated(id, prop, groupName)
    TriggerClientEvent('ar_propmanager:propUpdated', -1, buildPropEntry(id, prop, groupName))
end

local function broadcastPropsRemoved(ids)
    TriggerClientEvent('ar_propmanager:propsRemoved', -1, ids)
end

local function broadcastGroupStates()
    TriggerClientEvent('ar_propmanager:groupStatesChanged', -1, buildGroupStates())
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

-- ─── Group toggle ─────────────────────────────────────────────────────────────

local function setGroupEnabled(groupName, enabled)
    local group = groups[groupName]
    if not group or group.enabled == enabled then return end

    group.enabled = enabled

    MySQL.query(
        'INSERT INTO `ar_prop_groups` (group_name, enabled) VALUES (?, ?) ON DUPLICATE KEY UPDATE enabled = ?',
        { groupName, enabled and 1 or 0, enabled and 1 or 0 }
    )

    broadcastGroupStates()
end

--- data: { group = string, enabled = bool }
RegisterNetEvent('ar_propmanager:toggleGroup', function(data)
    if getPlayerLevel(source) < 1 then return end
    setGroupEnabled(data.group, data.enabled)
end)

-- ─── Prop events ─────────────────────────────────────────────────────────────

--- data: { id?, model, position, quaternion, group }
RegisterNetEvent('ar_propmanager:saveProp', function(data)
    local src  = source
    local pos  = data.position
    local quat = data.quaternion or { x = 0, y = 0, z = 0, w = 1 }

    if not hasPlayerAccess(src, data.group, pos) then
        print(('[ar_propmanager] saveProp denied — player %s, group: %s'):format(src, data.group))
        return
    end

    if data.id then
        -- ── Update existing prop transform ────────────────────────────────────
        local group = groups[data.group]
        if not group then return end
        local propData = group.props[data.id]
        if not propData then return end

        propData.position       = pos
        propData.quat           = quat
        propData.renderDistance = data.renderDistance or propData.renderDistance or 200
        propData.expiresAt      = data.expiresAt

        MySQL.query(
            'UPDATE `ar_props` SET pos_x=?,pos_y=?,pos_z=?,quat_x=?,quat_y=?,quat_z=?,quat_w=?,render_distance=?,expires_at=? WHERE id=?',
            { pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, propData.renderDistance, propData.expiresAt, data.id }
        )
        broadcastPropUpdated(data.id, propData, data.group)
    else
        -- ── New prop ──────────────────────────────────────────────────────────
        local group = getOrCreateGroup(data.group)

        local propData = {
            model          = data.model,
            position       = pos,
            quat           = quat,
            renderDistance = data.renderDistance or 200,
            expiresAt      = data.expiresAt,
        }

        MySQL.query(
            'INSERT IGNORE INTO `ar_prop_groups` (group_name, enabled) VALUES (?, 1)',
            { data.group }
        )
        local id = MySQL.insert.await(
            'INSERT INTO `ar_props` (model,pos_x,pos_y,pos_z,quat_x,quat_y,quat_z,quat_w,group_name,render_distance,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            { data.model, pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, data.group, propData.renderDistance, propData.expiresAt }
        )
        group.props[id] = propData
        broadcastPropAdded(id, propData, data.group)
    end
end)

--- data: { id }
RegisterNetEvent('ar_propmanager:deleteProp', function(data)
    local src = source

    local targetGroupName, propData
    for gName, group in pairs(groups) do
        if group.props[data.id] then
            targetGroupName = gName
            propData        = group.props[data.id]
            break
        end
    end
    if not propData then return end

    if not hasPlayerAccess(src, targetGroupName, propData.position) then
        print(('[ar_propmanager] deleteProp denied — player %s'):format(src))
        return
    end

    groups[targetGroupName].props[data.id] = nil

    MySQL.query('DELETE FROM `ar_props` WHERE id = ?', { data.id })
    broadcastPropsRemoved({ data.id })
end)

-- ─── Expiry cron ─────────────────────────────────────────────────────────────

local function checkExpiredProps()
    local now = os.time()
    local expired = {}

    for groupName, group in pairs(groups) do
        for dbId, prop in pairs(group.props) do
            if prop.expiresAt and now >= prop.expiresAt then
                expired[#expired + 1] = { groupName = groupName, dbId = dbId, prop = prop }
            end
        end
    end

    if #expired == 0 then return end

    for _, entry in ipairs(expired) do
        groups[entry.groupName].props[entry.dbId] = nil
        print(('[ar_propmanager] Expired prop removed — id: %s, model: %s, group: %s')
            :format(entry.dbId, entry.prop.model, entry.groupName))
    end

    -- Batch delete from DB
    local ids = {}
    for _, entry in ipairs(expired) do ids[#ids + 1] = entry.dbId end
    local placeholders = string.rep('?,', #ids):sub(1, -2)
    MySQL.query('DELETE FROM `ar_props` WHERE id IN (' .. placeholders .. ')', ids)

    broadcastPropsRemoved(ids)
end

lib.cron.new(config.expiryCron, checkExpiredProps)

-- ─── Player access events ─────────────────────────────────────────────────────

--- Builds the flat DB column values from the area object sent by the UI.
--- Returns: areaType, ax, ay, az, aRadius, zoneJson
local function decomposeArea(area)
    if not area then
        return nil, nil, nil, nil, nil, nil
    end
    if area.type == 'zone' then
        local zoneJson = area.points and json.encode(area.points) or nil
        return 'zone', nil, nil, nil, nil, zoneJson
    end
    -- radius (default)
    local c = area.center or {}
    return 'radius', c.x, c.y, c.z, area.radius, nil
end

--- data: { identifier, name, groups, area? }
RegisterNetEvent('ar_propmanager:addPlayerAccess', function(data)
    if getPlayerLevel(source) < 3 then return end

    local areaType, ax, ay, az, aRadius, zoneJson = decomposeArea(data.area)

    local id = MySQL.insert.await(
        'INSERT INTO `ar_player_access` (identifier,name,groups,area_type,area_x,area_y,area_z,area_radius,zone_points) VALUES (?,?,?,?,?,?,?,?,?)',
        { data.identifier, data.name, json.encode(data.groups or {}), areaType, ax, ay, az, aRadius, zoneJson }
    )

    -- Return confirmed record so UI can swap the optimistic temp id
    TriggerClientEvent('ar_propmanager:playerAccessSaved', source, {
        id         = id,
        identifier = data.identifier,
        name       = data.name,
        groups     = data.groups or {},
        area       = data.area,
    })
end)

--- data: { id, identifier, name, groups, area? }
RegisterNetEvent('ar_propmanager:updatePlayerAccess', function(data)
    if getPlayerLevel(source) < 3 then return end

    local areaType, ax, ay, az, aRadius, zoneJson = decomposeArea(data.area)
    MySQL.query(
        'UPDATE `ar_player_access` SET identifier=?,name=?,groups=?,area_type=?,area_x=?,area_y=?,area_z=?,area_radius=?,zone_points=? WHERE id=?',
        { data.identifier, data.name, json.encode(data.groups or {}), areaType, ax, ay, az, aRadius, zoneJson, data.id }
    )
end)

--- Receives the string id directly
RegisterNetEvent('ar_propmanager:deletePlayerAccess', function(id)
    if getPlayerLevel(source) < 3 then return end
    MySQL.query('DELETE FROM `ar_player_access` WHERE id = ?', { id })
end)

-- ─── Server callbacks ─────────────────────────────────────────────────────────

lib.callback.register('ar_propmanager:canInteractWithProp', function(source, propId)
    for gName, group in pairs(groups) do
        if group.props[propId] then
            return hasPlayerAccess(source, gName, group.props[propId].position)
        end
    end
    return getPlayerLevel(source) >= 2
end)

--- Converts a DB row's area columns into the AreaRestriction shape expected by the UI.
local function rowToArea(row)
    local areaType = row.area_type
    if areaType == 'zone' and row.zone_points then
        local ok, pts = pcall(json.decode, row.zone_points)
        if ok then return { type = 'zone', points = pts } end
    elseif areaType == 'radius' and row.area_x ~= nil then
        return {
            type   = 'radius',
            center = { x = row.area_x, y = row.area_y, z = row.area_z },
            radius = row.area_radius,
        }
    end
    return nil
end

--- Returns the full prop-manager payload, filtered by the caller's aces.
--- Includes permissions flags, props/groups (if canManage or canToggleGroups),
--- and player access entries (if canManage or canPlayerAccess).
--- Builds a prop-manager payload for `source`.
--- Returns nil if the player has no access at all.
local function buildPlayerPayload(source)
    local level = getPlayerLevel(source)

    -- No ace — check if they have explicit player-access rows
    if level == 0 then
        local identifier = getIdentifier(source)
        if not identifier then return nil end

        local accessRows = MySQL.query.await(
            'SELECT `groups` FROM `ar_player_access` WHERE identifier = ?',
            { identifier }
        )
        if not accessRows or #accessRows == 0 then return nil end

        -- Collect every group across all rows for this player
        local allowed = {}
        for _, row in ipairs(accessRows) do
            local ok, groupList = pcall(json.decode, row.groups)
            if ok and groupList then
                for _, g in ipairs(groupList) do allowed[g] = true end
            end
        end
        if not next(allowed) then return nil end

        local propList  = {}
        local stateSubset = {}
        for gName, group in pairs(groups) do
            if allowed[gName] then
                stateSubset[gName] = group.enabled
                for dbId, prop in pairs(group.props) do
                    propList[#propList + 1] = {
                        id             = dbId,
                        model          = prop.model,
                        position       = prop.position,
                        quaternion     = prop.quat,
                        group          = gName,
                        outlined       = false,
                        renderDistance = prop.renderDistance or 200,
                        expiresAt      = prop.expiresAt,
                    }
                end
            end
        end

        return { level = 2, props = propList, groupStates = stateSubset }
    end

    local payload = { level = level, props = {}, groupStates = {} }

    if level >= 1 then
        local sync = buildSyncPayload()
        payload.props       = sync.props
        payload.groupStates = sync.groupStates
    end

    if level >= 3 then
        local rows = MySQL.query.await('SELECT * FROM `ar_player_access`')
        local entries = {}
        for _, row in ipairs(rows or {}) do
            local ok, groupList = pcall(json.decode, row.groups)
            entries[#entries + 1] = {
                id         = row.id,
                identifier = row.identifier,
                name       = row.name,
                groups     = (ok and groupList) or {},
                area       = rowToArea(row),
            }
        end
        payload.playerAccess = entries

        local groupNames = {}
        for name in pairs(groups) do groupNames[#groupNames + 1] = name end
        payload.groups = groupNames
    end

    return payload
end

lib.callback.register('ar_propmanager:getProps', function(source)
    return buildPlayerPayload(source)
end)

--- Returns the full spawn payload (all props + group states) for client-side rendering.
--- No access filtering — props are world objects visible to everyone.
lib.callback.register('ar_propmanager:getSpawnData', function()
    return buildSyncPayload()
end)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('GetProps',         buildPropList)
exports('GetGroupStates',  buildGroupStates)
exports('SetGroupEnabled', setGroupEnabled)
exports('HasPlayerAccess', hasPlayerAccess)
exports('GetPlayerLevel',  getPlayerLevel)

exports('OpenPropManagerForPlayer', function(playerId)
    local payload = buildPlayerPayload(playerId)
    if not payload then return end
    TriggerClientEvent('ar_propmanager:openPropManagerFromServer', playerId, payload)
end)
