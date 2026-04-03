-- ─── Player access events ─────────────────────────────────────────────────────

--- Decodes the zones JSON column into a Lua table (array of zone point arrays).
local function rowToZones(row)
    if not row.zones then return {} end
    local ok, zones = pcall(json.decode, row.zones)
    if ok and zones then return zones end
    return {}
end

--- data: { identifier, name, groups, zones? }
RegisterNetEvent('ar_propmanager:addPlayerAccess', function(data)
    if getPlayerLevel(source) < 3 then return end

    local existing = MySQL.query.await(
        'SELECT id FROM `ar_props_player_access` WHERE identifier = ? LIMIT 1',
        { data.identifier }
    )
    if existing and #existing > 0 then return end

    local id = MySQL.insert.await(
        'INSERT INTO `ar_props_player_access` (identifier,name,groups,zones) VALUES (?,?,?,?)',
        { data.identifier, data.name, json.encode(data.groups or {}), json.encode(data.zones or {}) }
    )

    -- Return confirmed record so UI can swap the optimistic temp id
    TriggerClientEvent('ar_propmanager:playerAccessSaved', source, {
        id         = id,
        identifier = data.identifier,
        name       = data.name,
        groups     = data.groups or {},
        zones      = data.zones or {},
    })
end)

--- data: { id, identifier, name, groups, zones? }
RegisterNetEvent('ar_propmanager:updatePlayerAccess', function(data)
    if getPlayerLevel(source) < 3 then return end

    MySQL.query(
        'UPDATE `ar_props_player_access` SET identifier=?,name=?,groups=?,zones=? WHERE id=?',
        { data.identifier, data.name, json.encode(data.groups or {}), json.encode(data.zones or {}), data.id }
    )
end)

RegisterNetEvent('ar_propmanager:deletePlayerAccess', function(id)
    if getPlayerLevel(source) < 3 then return end
    MySQL.query('DELETE FROM `ar_props_player_access` WHERE id = ?', { id })
end)

-- ─── Server callbacks ─────────────────────────────────────────────────────────

lib.callback.register('ar_propmanager:getOnlinePlayers', function(source)
    if getPlayerLevel(source) < 3 then return {} end

    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        local identifier = getIdentifier(tonumber(playerId))
        if identifier then
            players[#players + 1] = {
                name       = GetPlayerName(playerId),
                identifier = identifier,
            }
        end
    end
    return players
end)

lib.callback.register('ar_propmanager:canInteractWithProp', function(source, propId)
    for gName, group in pairs(groups) do
        if group.props[propId] then
            return hasPlayerAccess(source, gName, group.props[propId].position)
        end
    end
    return getPlayerLevel(source) >= 2
end)

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
        local rows    = MySQL.query.await('SELECT * FROM `ar_props_player_access`')
        local entries = {}
        for _, row in ipairs(rows or {}) do
            local ok, groupList = pcall(json.decode, row.groups)
            entries[#entries + 1] = {
                id         = row.id,
                identifier = row.identifier,
                name       = row.name,
                groups     = (ok and groupList) or {},
                zones      = rowToZones(row),
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
                zones      = rowToZones(row),
                maxExpiry  = row.max_expiry,
            }
        end
        if not anyGroup then return nil end

        return { level = 0, playerAccess = entries }
    end

    local payload = { level = level }

    if level >= 3 then
        local rows    = MySQL.query.await('SELECT * FROM `ar_props_player_access`')
        local entries = {}
        for _, row in ipairs(rows or {}) do
            local ok, groupList = pcall(json.decode, row.groups)
            entries[#entries + 1] = {
                id         = row.id,
                identifier = row.identifier,
                name       = row.name,
                groups     = (ok and groupList) or {},
                zones      = rowToZones(row),
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
