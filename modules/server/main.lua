local config = require 'config'

-- ─── Utilities ────────────────────────────────────────────────────────────────

local function canManage(source)
    return IsPlayerAceAllowed(source, config.ace.manage)
end

local function canToggleGroups(source)
    return IsPlayerAceAllowed(source, config.ace.toggleGroups)
end

local function canManagePlayerAccess(source)
    return IsPlayerAceAllowed(source, config.ace.playerAccess)
end

local function getIdentifier(source)
    return GetPlayerIdentifierByType(source, 'license')
end

local function uuid()
    return ('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'):gsub('[xy]', function(c)
        local v = c == 'x' and math.random(0, 0xf) or math.random(8, 0xb)
        return ('%x'):format(v)
    end)
end

-- ─── Runtime state ───────────────────────────────────────────────────────────
--
-- All props are indexed by group for O(1) group-level operations (toggle).
--
--   groups[groupName] = {
--       enabled = bool,
--       props   = {
--           [dbId] = {
--               model    = string,
--               position = { x, y, z },
--               quat     = { x, y, z, w },
--               entity   = number | nil,   -- nil when group is disabled
--               netId    = number | nil,
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
    if canManage(source) then return true end

    local identifier = getIdentifier(source)
    if not identifier then return false end

    local rows = MySQL.query.await(
        'SELECT * FROM `ar_player_access` WHERE identifier = ? AND group_name = ?',
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
            `id`         VARCHAR(36) NOT NULL,
            `model`      VARCHAR(64) NOT NULL,
            `pos_x`      FLOAT       NOT NULL,
            `pos_y`      FLOAT       NOT NULL,
            `pos_z`      FLOAT       NOT NULL,
            `quat_x`     FLOAT       NOT NULL DEFAULT 0,
            `quat_y`     FLOAT       NOT NULL DEFAULT 0,
            `quat_z`     FLOAT       NOT NULL DEFAULT 0,
            `quat_w`     FLOAT       NOT NULL DEFAULT 1,
            `group_name`      VARCHAR(64) NOT NULL,
            `placed_by`       VARCHAR(64) NOT NULL,
            `placed_at`       TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `render_distance` FLOAT       NOT NULL DEFAULT 200,
            `expires_at`      BIGINT      NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_group` (`group_name`)
        )
    ]])

    -- Migration: add render_distance / expires_at to existing installs
    MySQL.query([[
        ALTER TABLE `ar_props`
            ADD COLUMN IF NOT EXISTS `render_distance` FLOAT     NOT NULL DEFAULT 200,
            ADD COLUMN IF NOT EXISTS `expires_at`      BIGINT    NULL
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
            `id`          VARCHAR(36)              NOT NULL,
            `identifier`  VARCHAR(64)              NOT NULL,
            `name`        VARCHAR(64)              NOT NULL,
            `group_name`  VARCHAR(64)              NOT NULL,
            `area_type`   ENUM('radius','zone')    NULL DEFAULT NULL,
            `area_x`      FLOAT                   NULL,
            `area_y`      FLOAT                   NULL,
            `area_z`      FLOAT                   NULL,
            `area_radius` FLOAT                   NULL,
            `zone_points` JSON                    NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_identifier` (`identifier`)
        )
    ]])

    -- Migration: add area_type / zone_points to existing installs
    MySQL.query([[
        ALTER TABLE `ar_player_access`
            ADD COLUMN IF NOT EXISTS `area_type`   ENUM('radius','zone') NULL DEFAULT NULL,
            ADD COLUMN IF NOT EXISTS `zone_points` JSON                  NULL
    ]])
end

-- ─── Entity helpers ───────────────────────────────────────────────────────────

local function spawnEntity(model, x, y, z, qx, qy, qz, qw)
    local entity = CreateObject(GetHashKey(model), x, y, z, true, true, false)
    if not entity or entity == 0 then return nil, nil end
    SetEntityQuaternion(entity, qx, qy, qz, qw)
    FreezeEntityPosition(entity, true)
    return entity, ObjToNet(entity)
end

local function despawnProp(propData)
    if propData.entity and DoesEntityExist(propData.entity) then
        DeleteEntity(propData.entity)
    end
    propData.entity = nil
    propData.netId  = nil
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
                netId          = prop.netId,
                handle         = prop.netId,
                model          = prop.model,
                position       = prop.position,
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

local function broadcastSync()
    TriggerClientEvent('ar_propmanager:syncPropList', -1, buildSyncPayload())
end

-- ─── Startup ─────────────────────────────────────────────────────────────────

local function loadData()
    local groupRows = MySQL.query.await('SELECT * FROM `ar_prop_groups`')
    for _, row in ipairs(groupRows or {}) do
        getOrCreateGroup(row.group_name, row.enabled == 1)
    end

    local propRows  = MySQL.query.await('SELECT * FROM `ar_props`')
    local spawned, skipped = 0, 0

    for _, row in ipairs(propRows or {}) do
        local group    = getOrCreateGroup(row.group_name)
        local propData = {
            model          = row.model,
            position       = { x = row.pos_x, y = row.pos_y, z = row.pos_z },
            quat           = { x = row.quat_x, y = row.quat_y, z = row.quat_z, w = row.quat_w },
            renderDistance = row.render_distance or 200,
            expiresAt      = row.expires_at,
            entity         = nil,
            netId          = nil,
        }

        if group.enabled then
            local entity, netId = spawnEntity(
                row.model,
                row.pos_x, row.pos_y, row.pos_z,
                row.quat_x, row.quat_y, row.quat_z, row.quat_w
            )
            if entity then
                propData.entity = entity
                propData.netId  = netId
                spawned = spawned + 1
            end
        else
            skipped = skipped + 1
        end

        group.props[row.id] = propData
    end

    print(('[ar_propmanager] Loaded %d prop(s) — %d spawned, %d in disabled groups')
        :format(#(propRows or {}), spawned, skipped))
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

    for _, propData in pairs(group.props) do
        if enabled then
            local pos  = propData.position
            local quat = propData.quat
            local entity, netId = spawnEntity(
                propData.model,
                pos.x, pos.y, pos.z,
                quat.x, quat.y, quat.z, quat.w
            )
            if entity then
                propData.entity = entity
                propData.netId  = netId
            end
        else
            despawnProp(propData)
        end
    end

    MySQL.query(
        'INSERT INTO `ar_prop_groups` (group_name, enabled) VALUES (?, ?) ON DUPLICATE KEY UPDATE enabled = ?',
        { groupName, enabled and 1 or 0, enabled and 1 or 0 }
    )

    broadcastSync()
end

--- data: { group = string, enabled = bool }
RegisterNetEvent('ar_propmanager:toggleGroup', function(data)
    if not canToggleGroups(source) then return end
    setGroupEnabled(data.group, data.enabled)
end)

-- ─── Prop events ─────────────────────────────────────────────────────────────

--- data: { id?, netId, model, position, quaternion, group }
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

        if propData.entity and DoesEntityExist(propData.entity) then
            SetEntityCoords(propData.entity, pos.x, pos.y, pos.z, false, false, false, false)
            SetEntityQuaternion(propData.entity, quat.x, quat.y, quat.z, quat.w)
        end

        MySQL.query(
            'UPDATE `ar_props` SET pos_x=?,pos_y=?,pos_z=?,quat_x=?,quat_y=?,quat_z=?,quat_w=?,render_distance=?,expires_at=? WHERE id=?',
            { pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, propData.renderDistance, propData.expiresAt, data.id }
        )
    else
        -- ── New prop ──────────────────────────────────────────────────────────
        local id         = uuid()
        local identifier = getIdentifier(src) or tostring(src)
        local group      = getOrCreateGroup(data.group)

        local propData = {
            model          = data.model,
            position       = pos,
            quat           = quat,
            renderDistance = data.renderDistance or 200,
            expiresAt      = data.expiresAt,
            entity         = nil,
            netId          = nil,
        }

        if data.netId then
            local entity = NetworkGetEntityFromNetworkId(data.netId)
            if entity and entity ~= 0 then
                propData.entity = entity
                propData.netId  = data.netId
                FreezeEntityPosition(entity, true)
            end
        elseif group.enabled then
            local entity, netId = spawnEntity(
                data.model,
                pos.x, pos.y, pos.z,
                quat.x, quat.y, quat.z, quat.w
            )
            if entity then
                propData.entity = entity
                propData.netId  = netId
            end
        end

        group.props[id] = propData

        MySQL.query(
            'INSERT IGNORE INTO `ar_prop_groups` (group_name, enabled) VALUES (?, 1)',
            { data.group }
        )
        MySQL.query(
            'INSERT INTO `ar_props` (id,model,pos_x,pos_y,pos_z,quat_x,quat_y,quat_z,quat_w,group_name,placed_by,render_distance,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
            { id, data.model, pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, data.group, identifier, propData.renderDistance, propData.expiresAt }
        )
    end

    broadcastSync()
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

    despawnProp(propData)
    groups[targetGroupName].props[data.id] = nil

    MySQL.query('DELETE FROM `ar_props` WHERE id = ?', { data.id })

    broadcastSync()
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
        despawnProp(entry.prop)
        groups[entry.groupName].props[entry.dbId] = nil
        print(('[ar_propmanager] Expired prop removed — id: %s, model: %s, group: %s')
            :format(entry.dbId, entry.prop.model, entry.groupName))
    end

    -- Batch delete from DB
    local ids = {}
    for _, entry in ipairs(expired) do ids[#ids + 1] = entry.dbId end
    local placeholders = string.rep('?,', #ids):sub(1, -2)
    MySQL.query('DELETE FROM `ar_props` WHERE id IN (' .. placeholders .. ')', ids)

    broadcastSync()
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

--- data: { identifier, name, group, area? }
RegisterNetEvent('ar_propmanager:addPlayerAccess', function(data)
    if not canManagePlayerAccess(source) then return end

    local id = uuid()
    local areaType, ax, ay, az, aRadius, zoneJson = decomposeArea(data.area)

    MySQL.query(
        'INSERT INTO `ar_player_access` (id,identifier,name,group_name,area_type,area_x,area_y,area_z,area_radius,zone_points) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { id, data.identifier, data.name, data.group, areaType, ax, ay, az, aRadius, zoneJson }
    )

    -- Return confirmed record so UI can swap the optimistic temp id
    TriggerClientEvent('ar_propmanager:playerAccessSaved', source, {
        id         = id,
        identifier = data.identifier,
        name       = data.name,
        group      = data.group,
        area       = data.area,
    })
end)

--- data: { id, identifier, name, group, area? }
RegisterNetEvent('ar_propmanager:updatePlayerAccess', function(data)
    if not canManagePlayerAccess(source) then return end

    local areaType, ax, ay, az, aRadius, zoneJson = decomposeArea(data.area)
    MySQL.query(
        'UPDATE `ar_player_access` SET identifier=?,name=?,group_name=?,area_type=?,area_x=?,area_y=?,area_z=?,area_radius=?,zone_points=? WHERE id=?',
        { data.identifier, data.name, data.group, areaType, ax, ay, az, aRadius, zoneJson, data.id }
    )
end)

--- Receives the string id directly
RegisterNetEvent('ar_propmanager:deletePlayerAccess', function(id)
    if not canManagePlayerAccess(source) then return end
    MySQL.query('DELETE FROM `ar_player_access` WHERE id = ?', { id })
end)

-- ─── Server callbacks ─────────────────────────────────────────────────────────

lib.callback.register('ar_propmanager:canInteractWithProp', function(source, propId)
    for gName, group in pairs(groups) do
        if group.props[propId] then
            return hasPlayerAccess(source, gName, group.props[propId].position)
        end
    end
    return canManage(source)
end)

--- Returns { props, groupStates } — filtered to accessible groups for non-admins.
lib.callback.register('ar_propmanager:getProps', function(source)
    if canManage(source) then
        return buildSyncPayload()
    end

    local identifier = getIdentifier(source)
    if not identifier then return { props = {}, groupStates = {} } end

    local accessRows = MySQL.query.await(
        'SELECT DISTINCT group_name FROM `ar_player_access` WHERE identifier = ?',
        { identifier }
    )

    local allowed = {}
    for _, row in ipairs(accessRows or {}) do allowed[row.group_name] = true end

    local propList    = {}
    local stateSubset = {}

    for gName, group in pairs(groups) do
        if allowed[gName] then
            stateSubset[gName] = group.enabled
            for dbId, prop in pairs(group.props) do
                propList[#propList + 1] = {
                    id             = dbId,
                    netId          = prop.netId,
                    handle         = prop.netId,
                    model          = prop.model,
                    position       = prop.position,
                    group          = gName,
                    outlined       = false,
                    renderDistance = prop.renderDistance or 200,
                    expiresAt      = prop.expiresAt,
                }
            end
        end
    end

    return { props = propList, groupStates = stateSubset }
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

--- Returns all player access entries. Requires playerAccess ace.
lib.callback.register('ar_propmanager:getPlayerAccess', function(source)
    if not canManagePlayerAccess(source) then return nil end

    local rows = MySQL.query.await('SELECT * FROM `ar_player_access`')
    local result = {}
    for _, row in ipairs(rows or {}) do
        result[#result + 1] = {
            id         = row.id,
            identifier = row.identifier,
            name       = row.name,
            group      = row.group_name,
            area       = rowToArea(row),
        }
    end
    return result
end)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('GetProps',        buildPropList)
exports('GetGroupStates',  buildGroupStates)
exports('SetGroupEnabled', setGroupEnabled)
exports('HasPlayerAccess', hasPlayerAccess)

exports('OpenPropManagerForPlayer', function(playerId)
    local payload = canManage(playerId) and buildSyncPayload() or { props = {}, groupStates = {} }
    TriggerClientEvent('ar_propmanager:openPropManagerFromServer', playerId, payload)
end)

exports('OpenPlayerAccessForPlayer', function(playerId, groupList)
    if not canManagePlayerAccess(playerId) then return end
    local rows = MySQL.query.await('SELECT * FROM `ar_player_access`')
    local result = {}
    for _, row in ipairs(rows or {}) do
        result[#result + 1] = {
            id         = row.id,
            identifier = row.identifier,
            name       = row.name,
            group      = row.group_name,
            area       = rowToArea(row),
        }
    end
    TriggerClientEvent('ar_propmanager:openPlayerAccessFromServer', playerId, result, groupList or {})
end)
