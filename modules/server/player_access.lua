lib.locale()

--- Decode the JSON zones column from a player-access DB row into a Lua table.
--- Returns an empty table if the column is absent or malformed.
--- @param  row  { zones: string|nil }  Raw MySQL row from ar_props_player_access
--- @return { x: number, y: number }[][]  Array of zone polygons (each polygon is an array of points)
local function rowToZones(row)
    if not row.zones then return {} end
    local ok, zones = pcall(json.decode, row.zones)
    if ok and zones then return zones end
    return {}
end

--- Build the prop-manager open payload tailored to a specific player's access level.
--- Returns nil when a level-0 player has no access entries.
--- @param  source  integer   Player server ID
--- @return { level: integer, props: table[], groupStates: table<string, boolean>, playerAccess: table[]|nil, groups: string[]|nil }|nil
local function buildPlayerPayload(source)
    local level = getPlayerLevel(source)

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

-- ██████ ██  ██ ██████ ███  ██ ██████ ▄█████ 
-- ██▄▄   ██▄▄██ ██▄▄   ██ ▀▄██   ██   ▀▀▀▄▄▄ 
-- ██▄▄▄▄  ▀██▀  ██▄▄▄▄ ██   ██   ██   █████▀ 

RegisterNetEvent('ar_propmanager:addPlayerAccess', function(data)
    local src = source
    if getPlayerLevel(src) < 3 then return end

    local existing = MySQL.query.await(
        'SELECT id FROM `ar_props_player_access` WHERE identifier = ? LIMIT 1',
        { data.identifier }
    )
    if existing and #existing > 0 then return end

    local id = MySQL.insert.await(
        'INSERT INTO `ar_props_player_access` (identifier,name,groups,zones) VALUES (?,?,?,?)',
        { data.identifier, data.name, json.encode(data.groups or {}), json.encode(data.zones or {}) }
    )

    TriggerClientEvent('ar_propmanager:playerAccessSaved', src, {
        id         = id,
        identifier = data.identifier,
        name       = data.name,
        groups     = data.groups or {},
        zones      = data.zones or {},
    })

    CreateLog(src, locale('logs_add_player_access_title'), locale('logs_add_player_access_description'), {
        id         = id,
        identifier = data.identifier,
        name       = data.name,
        groups     = data.groups or {},
    })
end)

RegisterNetEvent('ar_propmanager:updatePlayerAccess', function(data)
    local src = source
    if getPlayerLevel(src) < 3 then return end

    MySQL.query(
        'UPDATE `ar_props_player_access` SET identifier=?,name=?,groups=?,zones=? WHERE id=?',
        { data.identifier, data.name, json.encode(data.groups or {}), json.encode(data.zones or {}), data.id }
    )

    CreateLog(src, locale('logs_update_player_access_title'), locale('logs_update_player_access_description'), {
        id         = data.id,
        identifier = data.identifier,
        name       = data.name,
        groups     = data.groups or {},
    })
end)

RegisterNetEvent('ar_propmanager:deletePlayerAccess', function(id)
    local src = source
    if getPlayerLevel(src) < 3 then return end

    local row = MySQL.query.await('SELECT identifier, name FROM `ar_props_player_access` WHERE id = ? LIMIT 1', { id })
    MySQL.query('DELETE FROM `ar_props_player_access` WHERE id = ?', { id })

    CreateLog(src, locale('logs_delete_player_access_title'), locale('logs_delete_player_access_description'), {
        id         = id,
        identifier = row and row[1] and row[1].identifier or 'unknown',
        name       = row and row[1] and row[1].name       or 'unknown',
    })
end)

-- ▄█████ ▄████▄ ██     ██     █████▄ ▄████▄ ▄█████ ██ ▄█▀ ▄█████ 
-- ██     ██▄▄██ ██     ██     ██▄▄██ ██▄▄██ ██     ████   ▀▀▀▄▄▄ 
-- ▀█████ ██  ██ ██████ ██████ ██▄▄█▀ ██  ██ ▀█████ ██ ▀█▄ █████▀ 

lib.callback.register('ar_propmanager:getOnlinePlayers', function(source)
    if getPlayerLevel(source) < 3 then return {} end

    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        if tonumber(playerId) == source then
            goto continue
        end
        local identifier = getIdentifier(tonumber(playerId))
        if identifier then
            players[#players + 1] = {
                name       = GetPlayerName(playerId),
                identifier = identifier,
            }
        end
        ::continue::
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

lib.callback.register('ar_propmanager:getProps', function(source)
    return buildPlayerPayload(source)
end)

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

lib.callback.register('ar_propmanager:getSpawnData', function()
    return buildSyncPayload()
end)