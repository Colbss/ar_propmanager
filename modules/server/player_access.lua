-- ─── Player access events ─────────────────────────────────────────────────────

--- Builds flat DB column values from the area object sent by the UI.
--- Returns: areaType, ax, ay, az, aRadius, zoneJson
local function decomposeArea(area)
    if not area then return nil, nil, nil, nil, nil, nil end
    if area.type == 'zone' then
        return 'zone', nil, nil, nil, nil, area.points and json.encode(area.points) or nil
    end
    local c = area.center or {}
    return 'radius', c.x, c.y, c.z, area.radius, nil
end

--- data: { identifier, name, groups, area? }
RegisterNetEvent('ar_propmanager:addPlayerAccess', function(data)
    if getPlayerLevel(source) < 3 then return end

    local areaType, ax, ay, az, aRadius, zoneJson = decomposeArea(data.area)

    local id = MySQL.insert.await(
        'INSERT INTO `ar_props_player_access` (identifier,name,groups,area_type,area_x,area_y,area_z,area_radius,zone_points) VALUES (?,?,?,?,?,?,?,?,?)',
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
        'UPDATE `ar_props_player_access` SET identifier=?,name=?,groups=?,area_type=?,area_x=?,area_y=?,area_z=?,area_radius=?,zone_points=? WHERE id=?',
        { data.identifier, data.name, json.encode(data.groups or {}), areaType, ax, ay, az, aRadius, zoneJson, data.id }
    )
end)

RegisterNetEvent('ar_propmanager:deletePlayerAccess', function(id)
    if getPlayerLevel(source) < 3 then return end
    MySQL.query('DELETE FROM `ar_props_player_access` WHERE id = ?', { id })
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
    if row.area_type == 'zone' and row.zone_points then
        local ok, pts = pcall(json.decode, row.zone_points)
        if ok then return { type = 'zone', points = pts } end
    elseif row.area_type == 'radius' and row.area_x ~= nil then
        return {
            type   = 'radius',
            center = { x = row.area_x, y = row.area_y, z = row.area_z },
            radius = row.area_radius,
        }
    end
    return nil
end

--- Builds a prop-manager payload for `source`. Returns nil if the player has no access.
local function buildPlayerPayload(source)
    local level = getPlayerLevel(source)

    print(('Player %d has access level %d'):format(source, level))

    -- No ace — check if they have explicit player-access rows
    if level == 0 then
        local identifier = getIdentifier(source)
        if not identifier then return nil end

        local accessRows = MySQL.query.await(
            'SELECT `groups` FROM `ar_props_player_access` WHERE identifier = ?',
            { identifier }
        )
        if not accessRows or #accessRows == 0 then return nil end

        local allowed = {}
        for _, row in ipairs(accessRows) do
            local ok, groupList = pcall(json.decode, row.groups)
            if ok and groupList then
                for _, g in ipairs(groupList) do allowed[g] = true end
            end
        end
        if not next(allowed) then return nil end

        local propList    = {}
        local stateSubset = {}
        for gName, group in pairs(groups) do
            if allowed[gName] then
                stateSubset[gName] = group.enabled
                for dbId, prop in pairs(group.props) do
                    propList[#propList + 1] = buildPropEntry(dbId, prop, gName)
                end
            end
        end

        return { level = 2, props = propList, groupStates = stateSubset }
    end

    local payload = { level = level, props = {}, groupStates = {} }

    if level >= 1 then
        local sync      = buildSyncPayload()
        payload.props       = sync.props
        payload.groupStates = sync.groupStates
    end

    if level >= 3 then
        local rows   = MySQL.query.await('SELECT * FROM `ar_props_player_access`')
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

--- Lightweight callback — returns only what the client can't derive locally:
--- level, and for level 0: their access entries; for level 3: all entries + group names.
--- The client builds props/groupStates itself from propCache/groupEnabled.
lib.callback.register('ar_propmanager:getOpenData', function(source)
    local level = getPlayerLevel(source)

    if level == 0 then
        local identifier = getIdentifier(source)
        if not identifier then return nil end

        local rows = MySQL.query.await(
            'SELECT * FROM `ar_props_player_access` WHERE identifier = ?',
            { identifier }
        )
        if not rows or #rows == 0 then return nil end

        local entries  = {}
        local anyGroup = false
        for _, row in ipairs(rows) do
            local ok, groupList = pcall(json.decode, row.groups)
            local groupArr = (ok and groupList) or {}
            if #groupArr > 0 then anyGroup = true end
            entries[#entries + 1] = {
                id         = row.id,
                identifier = row.identifier,
                name       = row.name,
                groups     = groupArr,
                area       = rowToArea(row),
                maxExpiry  = row.max_expiry,
            }
        end
        if not anyGroup then return nil end

        return { level = 0, playerAccess = entries }
    end

    local payload = { level = level }

    if level >= 3 then
        local rows   = MySQL.query.await('SELECT * FROM `ar_props_player_access`')
        local entries = {}
        for _, row in ipairs(rows or {}) do
            local ok, groupList = pcall(json.decode, row.groups)
            entries[#entries + 1] = {
                id         = row.id,
                identifier = row.identifier,
                name       = row.name,
                groups     = (ok and groupList) or {},
                area       = rowToArea(row),
                maxExpiry  = row.max_expiry,
            }
        end
        payload.playerAccess = entries

        local groupNames = {}
        for name in pairs(groups) do groupNames[#groupNames + 1] = name end
        payload.groups = groupNames
    end

    return payload
end)

--- Returns the full spawn payload for client-side rendering (no access filtering).
lib.callback.register('ar_propmanager:getSpawnData', function()
    return buildSyncPayload()
end)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('GetProps',        buildPropList)
exports('GetGroupStates',  buildGroupStates)
exports('HasPlayerAccess', hasPlayerAccess)
exports('GetPlayerLevel',  getPlayerLevel)

exports('OpenPropManagerForPlayer', function(playerId)
    local payload = buildPlayerPayload(playerId)
    if not payload then return end
    TriggerClientEvent('ar_propmanager:openPropManagerFromServer', playerId, payload)
end)
