-- ─── Prop Manager ─────────────────────────────────────────────────────────────

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

    OpenGizmo(prop, {
        model          = model,
        group          = data.group or 'default',
        renderDistance = data.renderDistance or 200,
        expiresAt      = data.expiresAt,
        attachingProp  = true,
    })

    cb('ok')
end)

RegisterNUICallback('EditProp', function(data, cb)
    lib.callback('ar_propmanager:canInteractWithProp', false, function(allowed)
        if not allowed then cb('denied') return end
        local id   = data.id
        local prop = propCache[id]
        if not prop then cb('error') return end

        local pos = prop.position
        SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z + 1.0, false, false, false, false)

        local attempts = 0
        while not spawnedProps[id] and attempts < 20 do
            Wait(100)
            attempts = attempts + 1
        end

        local entity = spawnedProps[id]
        if not entity or not DoesEntityExist(entity) then cb('error') return end

        ClosePropManager()
        OpenGizmo(entity, {
            dbId           = id,
            model          = prop.model,
            group          = prop.group,
            renderDistance = prop.renderDistance or 200,
            expiresAt      = prop.expiresAt,
        })

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

RegisterNUICallback('OutlineProp', function(_, cb)
    cb('ok')
end)

RegisterNUICallback('OutlineAllProps', function(_, cb)
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
        despawnPropLocal(id)
        propCache[id] = nil
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

RegisterCommand('manage_props', function()
    lib.callback('ar_propmanager:getProps', false, function(payload)
        if payload then OpenPropManager(payload) end
    end)
end, false)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('OpenPropManager', function(payload)
    OpenPropManager(payload)
end)
