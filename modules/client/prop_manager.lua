-- ─── Prop Manager ─────────────────────────────────────────────────────────────

local outlinedProps = {} -- prop IDs currently outlined in-game

--- Open the prop manager window.
--- @param payload table  { level, props, groupStates, ... }
function OpenPropManager(payload)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openPropManager', data = payload })
end

local function ClosePropManager()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePropManager', data = {} })
end

RegisterNUICallback('ClosePropManager', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- ─── Prop NUI callbacks ───────────────────────────────────────────────────────

RegisterNUICallback('PlaceProp', function(data, cb)
    local model = data.model
    if not model or model == '' then cb('error') return end

    local modelHash = GetHashKey(model)

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then
        SetModelAsNoLongerNeeded(modelHash)
        cb({ error = 'invalid_model' })
        return
    end

    local ped     = PlayerPedId()
    local pos     = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local prop = CreateObjectNoOffset(
        modelHash,
        pos.x + math.sin(math.rad(-heading)) * 3.0,
        pos.y + math.cos(math.rad(-heading)) * 3.0,
        pos.z,
        false, false, false
    )

    SetModelAsNoLongerNeeded(modelHash)
    FreezeEntityPosition(prop, true)
    SetEntityCollision(prop, false, false)

    local propMeta = {
        model          = model,
        group          = data.group or 'default',
        renderDistance = data.renderDistance or 200,
        expiresAt      = data.expiresAt,
    }

    ClosePropManager()
    OpenGizmo(prop, {}, function(position, quaternion)
        TriggerServerEvent('ar_propmanager:saveProp', {
            model          = propMeta.model,
            position       = position,
            quaternion     = quaternion,
            group          = propMeta.group,
            renderDistance = propMeta.renderDistance,
            expiresAt      = propMeta.expiresAt,
        })
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end, function(entity)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end)

    cb('ok')
end)

RegisterNUICallback('EditProp', function(data, cb)
    lib.callback('ar_propmanager:canInteractWithProp', false, function(allowed)
        if not allowed then cb('denied') return end
        local id   = data.id
        local prop = propCache[id]
        if not prop then cb('error') return end

        local pos = prop.position
        if #(vector3(pos.x, pos.y, pos.z) - GetEntityCoords(PlayerPedId())) > 50.0 then
            cb('too_far')
            return
        end

        local attempts = 0
        while not spawnedProps[id] and attempts < 20 do
            Wait(100)
            attempts = attempts + 1
        end

        local entity = spawnedProps[id]
        if not entity or not DoesEntityExist(entity) then cb('error') return end

        local propMeta = {
            dbId           = id,
            model          = prop.model,
            group          = prop.group,
            renderDistance = prop.renderDistance or 200,
            expiresAt      = prop.expiresAt,
        }

        local origPos             = GetEntityCoords(entity)
        local oqx, oqy, oqz, oqw = GetEntityQuaternion(entity)

        SetEntityCollision(entity, false, false)

        ClosePropManager()
        OpenGizmo(entity, {}, function(position, quaternion)
            TriggerServerEvent('ar_propmanager:saveProp', {
                id             = propMeta.dbId,
                model          = propMeta.model,
                position       = position,
                quaternion     = quaternion,
                group          = propMeta.group,
                renderDistance = propMeta.renderDistance,
                expiresAt      = propMeta.expiresAt,
            })
        end, function(e)
            if DoesEntityExist(e) then
                SetEntityCoords(e, origPos.x, origPos.y, origPos.z, false, false, false, false)
                SetEntityQuaternion(e, oqx, oqy, oqz, oqw)
                FreezeEntityPosition(e, true)
                SetEntityCollision(e, true, true)
            end
        end, function(e)
            if DoesEntityExist(e) then 
                SetEntityCollision(e, true, true)
            end
        end)

        cb('ok')
    end, data.id)
end)

RegisterNUICallback('TeleportToProp', function(data, cb)
    lib.callback('ar_propmanager:canInteractWithProp', false, function(allowed)
        if not allowed then cb('denied') return end
        local prop = propCache[data.id]
        if not prop then cb('error') return end
        local pos = prop.position
        SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z + 1.0, false, false, false, false)
        cb('ok')
    end, data.id)
end)

RegisterNUICallback('OutlineProp', function(data, cb)
    local id     = data.id
    local handle = spawnedProps[id]
    if not handle or not DoesEntityExist(handle) then cb('error') return end

    local enabled = not outlinedProps[id]
    SetEntityDrawOutline(handle, enabled)
    if enabled then SetEntityDrawOutlineColor(48, 111, 178, 255) end
    outlinedProps[id] = enabled or nil

    cb('ok')
end)

RegisterNUICallback('OutlineAllProps', function(data, cb)
    local enabled = data.outlined
    for id, handle in pairs(spawnedProps) do
        if DoesEntityExist(handle) then
            SetEntityDrawOutline(handle, enabled)
            if enabled then SetEntityDrawOutlineColor(48, 111, 178, 255) end
            outlinedProps[id] = enabled or nil
        end
    end
    cb('ok')
end)

RegisterNUICallback('DeleteProp', function(data, cb)
    TriggerServerEvent('ar_propmanager:deleteProp', { id = data.id })
    cb('ok')
end)

RegisterNUICallback('ToggleGroup', function(data, cb)
    TriggerServerEvent('ar_propmanager:toggleGroup', { group = data.group, enabled = data.enabled })
    cb('ok')
end)

RegisterNUICallback('GetPlayerPosition', function(_, cb)
    local pos = GetEntityCoords(PlayerPedId())
    cb({ x = pos.x, y = pos.y, z = pos.z })
end)

-- ─── Player access NUI callbacks ──────────────────────────────────────────────

RegisterNUICallback('GetOnlinePlayers', function(_, cb)
    lib.callback('ar_propmanager:getOnlinePlayers', false, function(players)
        cb(players or {})
    end)
end)

RegisterNUICallback('AddPlayerAccess', function(data, cb)
    TriggerServerEvent('ar_propmanager:addPlayerAccess', data)
    cb('ok')
end)

RegisterNUICallback('UpdatePlayerAccess', function(data, cb)
    TriggerServerEvent('ar_propmanager:updatePlayerAccess', data)
    cb('ok')
end)

RegisterNUICallback('DeletePlayerAccess', function(data, cb)
    TriggerServerEvent('ar_propmanager:deletePlayerAccess', data.id)
    cb('ok')
end)

-- ─── Server → client events ───────────────────────────────────────────────────

RegisterNetEvent('ar_propmanager:propAdded', function(prop)
    if groupEnabled[prop.group] == nil then groupEnabled[prop.group] = true end
    propCache[prop.id] = {
        model          = prop.model,
        position       = prop.position,
        quaternion     = prop.quaternion,
        renderDistance = prop.renderDistance or 200,
        group          = prop.group,
        expiresAt      = prop.expiresAt,
    }
    SendNUIMessage({ action = 'addProp', data = prop })
end)

RegisterNetEvent('ar_propmanager:propUpdated', function(prop)
    local cached = propCache[prop.id]
    propCache[prop.id] = {
        model          = prop.model,
        position       = prop.position,
        quaternion     = prop.quaternion,
        renderDistance = prop.renderDistance or 200,
        group          = prop.group,
        expiresAt      = prop.expiresAt,
    }
    if cached and spawnedProps[prop.id] and DoesEntityExist(spawnedProps[prop.id]) then
        local e = spawnedProps[prop.id]
        local q = prop.quaternion or { x = 0, y = 0, z = 0, w = 1 }
        SetEntityCoords(e, prop.position.x, prop.position.y, prop.position.z, false, false, false, false)
        SetEntityQuaternion(e, q.x, q.y, q.z, q.w)
    end
    SendNUIMessage({ action = 'updateProp', data = prop })
end)

RegisterNetEvent('ar_propmanager:propsRemoved', function(ids)
    for _, id in ipairs(ids) do
        despawnProp(id)
        propCache[id]    = nil
        outlinedProps[id] = nil
    end
    SendNUIMessage({ action = 'removeProps', data = { ids = ids } })
end)

RegisterNetEvent('ar_propmanager:groupStatesChanged', function(groupStates)
    for name, enabled in pairs(groupStates) do
        groupEnabled[name] = enabled
    end
    SendNUIMessage({ action = 'updateGroupStates', data = groupStates })
end)

--- Triggered by the server export OpenPropManagerForPlayer.
RegisterNetEvent('ar_propmanager:openPropManagerFromServer', function(payload)
    OpenPropManager(payload)
end)

--- Server confirms a newly added player access entry with its real DB id.
RegisterNetEvent('ar_propmanager:playerAccessSaved', function(entry)
    SendNUIMessage({ action = 'playerAccessSaved', data = entry })
end)

-- ─── Commands ─────────────────────────────────────────────────────────────────

RegisterCommand('test_prop_manager', function()
    local ped       = PlayerPedId()
    local origin    = GetEntityCoords(ped)
    local propList  = {}
    local mockGroups   = { 'Street Furniture', 'Vehicles', 'Nature' }
    local now          = os.time()
    local mockExpiries = { nil, now + 3600, now + 86400, now - 60 }

    local count = 0
    for _, obj in ipairs(GetGamePool('CObject')) do
        if #(GetEntityCoords(obj) - origin) < 30.0 then
            local pos = GetEntityCoords(obj)
            count     = count + 1
            propList[#propList + 1] = {
                id             = obj,
                model          = tostring(GetEntityModel(obj)),
                position       = { x = pos.x, y = pos.y, z = pos.z },
                group          = mockGroups[(count % #mockGroups) + 1],
                outlined       = false,
                renderDistance = 200,
                expiresAt      = mockExpiries[(count % #mockExpiries) + 1],
            }
            if count >= 20 then break end
        end
    end

    local groupStates = {}
    for _, g in ipairs(mockGroups) do groupStates[g] = true end

    OpenPropManager({ props = propList, groupStates = groupStates })
end, false)

local function buildPropEntryFromCache(id, prop)
    return {
        id             = id,
        model          = prop.model,
        position       = prop.position,
        quaternion     = prop.quaternion,
        group          = prop.group,
        outlined       = outlinedProps[id] == true,
        renderDistance = prop.renderDistance or 200,
        expiresAt      = prop.expiresAt,
    }
end

RegisterCommand('manage_props', function()
    lib.callback('ar_propmanager:getOpenData', false, function(openData)
        if not openData then return end

        local props       = {}
        local groupStates = {}

        if openData.level == 0 then
            -- Restricted player: only show props from their allowed groups
            local allowed = {}
            for _, entry in ipairs(openData.playerAccess or {}) do
                for _, g in ipairs(entry.groups or {}) do allowed[g] = true end
            end
            for id, prop in pairs(propCache) do
                if allowed[prop.group] then
                    props[#props + 1]       = buildPropEntryFromCache(id, prop)
                    groupStates[prop.group] = groupEnabled[prop.group]
                end
            end
        else
            for id, prop in pairs(propCache) do
                props[#props + 1] = buildPropEntryFromCache(id, prop)
            end
            for name, enabled in pairs(groupEnabled) do
                groupStates[name] = enabled
            end
        end

        local payload = {
            level       = openData.level,
            props       = props,
            groupStates = groupStates,
        }
        if openData.playerAccess then payload.playerAccess = openData.playerAccess end
        if openData.groups       then payload.groups       = openData.groups end

        OpenPropManager(payload)
    end)
end, false)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('OpenPropManager', function(payload)
    OpenPropManager(payload)
end)
