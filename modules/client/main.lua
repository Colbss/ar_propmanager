local config = require 'config'
LocalState = LocalPlayer.state

local gizmoActive = false
local currentGizmoEntity = nil
local currentGizmoOptions = nil
local originalCoords = nil
local originalQuat = nil

--- Open the gizmo for the given entity handle.
--- @param entity  number  Entity handle
--- @param options table   Optional: { restrictRotationAxes, attachingProp, simpleOverlay, group, dbId, model }
function common.OpenGizmo(entity, options)
    assert(DoesEntityExist(entity), 'ar_propmanager2: entity does not exist')
    options = options or {}
    currentGizmoOptions = options

    currentGizmoEntity = entity

    local pos = GetEntityCoords(entity)
    local qx, qy, qz, qw = GetEntityQuaternion(entity)

    -- Snapshot for cancel restore
    originalCoords = pos
    originalQuat = { x = qx, y = qy, z = qz, w = qw }

    keybinds.mode:disable(false)
    keybinds.focus:disable(false)
    keybinds.finish:disable(false)
    keybinds.cancel:disable(false)

    SetNuiFocus(true, true)

    SendNUIMessage({ action = 'show', data = {} })

    SendNUIMessage({
        action = 'setGizmoEntity',
        data = {
            handle               = entity,
            position             = { x = pos.x, y = pos.y, z = pos.z },
            quaternion           = { x = qx, y = qy, z = qz, w = qw },
            keybinds             = keybinds.GetKeybinds(),
            restrictRotationAxes = options.restrictRotationAxes or false,
            attachingProp        = options.attachingProp or false,
            simpleOverlay        = options.simpleOverlay or false,
        }
    })

    gizmoActive = true

    -- Send camera transform to NUI every frame while the gizmo is open
    CreateThread(function()
        while gizmoActive do
            local camPos = GetGameplayCamCoords()
            local camRot = GetGameplayCamRot(2)
            local camFov = GetGameplayCamFov()

            SendNUIMessage({
                action = 'setCameraPosition',
                data = {
                    position = { x = camPos.x, y = camPos.y, z = camPos.z },
                    rotation = { x = camRot.x, y = camRot.y, z = camRot.z },
                    fov      = camFov,
                }
            })

            Wait(0)
        end
    end)
end

--- Close the active gizmo session.
--- @param save boolean  true = keep final transform, false = revert to original
function common.CloseGizmo(save)
    if not gizmoActive then return end
    gizmoActive = false

    keybinds.mode:disable(true)
    keybinds.focus:disable(true)
    keybinds.finish:disable(true)
    keybinds.cancel:disable(true)

    if not save and currentGizmoEntity and DoesEntityExist(currentGizmoEntity) then
        if originalCoords then
            SetEntityCoords(currentGizmoEntity, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
        end
        if originalQuat then
            SetEntityQuaternion(currentGizmoEntity, originalQuat.x, originalQuat.y, originalQuat.z, originalQuat.w)
        end
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeGizmo', data = {} })
    SendNUIMessage({ action = 'hide', data = {} })

    currentGizmoEntity = nil
    currentGizmoOptions = nil
    originalCoords = nil
    originalQuat = nil
end

-- ─── NUI Callbacks ────────────────────────────────────────────────────────────

RegisterNUICallback('MoveEntity', function(data, cb)
    local entity = data.handle
    if not entity or not DoesEntityExist(entity) then cb('error') return end

    SetEntityCoords(entity, data.position.x, data.position.y, data.position.z, false, false, false, false)

    if data.quaternion then
        SetEntityQuaternion(entity, data.quaternion.x, data.quaternion.y, data.quaternion.z, data.quaternion.w)
    elseif data.rotation then
        SetEntityRotation(entity, data.rotation.x, data.rotation.y, data.rotation.z, 2, false)
    end

    cb('ok')
end)

RegisterNUICallback('SnapToGround', function(_, cb)
    if not currentGizmoEntity or not DoesEntityExist(currentGizmoEntity) then cb('error') return end

    local pos = GetEntityCoords(currentGizmoEntity)
    -- Cast slightly above current Z so we don't miss ground directly underfoot
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)

    if found then
        SetEntityCoords(currentGizmoEntity, pos.x, pos.y, groundZ, false, false, false, false)

        local qx, qy, qz, qw = GetEntityQuaternion(currentGizmoEntity)
        SendNUIMessage({
            action = 'updateGizmoTransform',
            data = {
                handle     = currentGizmoEntity,
                position   = { x = pos.x, y = pos.y, z = groundZ },
                quaternion = { x = qx, y = qy, z = qz, w = qw },
            }
        })
    end

    cb('ok')
end)

RegisterNUICallback('ResetRotation', function(_, cb)
    if not currentGizmoEntity or not DoesEntityExist(currentGizmoEntity) then cb('error') return end

    SetEntityQuaternion(currentGizmoEntity, 0.0, 0.0, 0.0, 1.0)

    local pos = GetEntityCoords(currentGizmoEntity)
    SendNUIMessage({
        action = 'updateGizmoTransform',
        data = {
            handle     = currentGizmoEntity,
            position   = { x = pos.x, y = pos.y, z = pos.z },
            quaternion = { x = 0.0, y = 0.0, z = 0.0, w = 1.0 },
        }
    })

    cb('ok')
end)

RegisterNUICallback('Finish', function(_, cb)
    if currentGizmoEntity and DoesEntityExist(currentGizmoEntity) then
        local pos             = GetEntityCoords(currentGizmoEntity)
        local qx, qy, qz, qw = GetEntityQuaternion(currentGizmoEntity)
        local opts            = currentGizmoOptions or {}

        TriggerServerEvent('ar_propmanager2:saveProp', {
            id             = opts.dbId,
            netId          = NetworkGetNetworkIdFromEntity(currentGizmoEntity),
            model          = opts.model or tostring(GetEntityModel(currentGizmoEntity)),
            position       = { x = pos.x, y = pos.y, z = pos.z },
            quaternion     = { x = qx, y = qy, z = qz, w = qw },
            group          = opts.group or 'default',
            renderDistance = opts.renderDistance or 200,
            expiresAt      = opts.expiresAt,
        })
    end
    common.CloseGizmo(true)
    cb('ok')
end)

RegisterNUICallback('Cancel', function(_, cb)
    common.CloseGizmo(false)
    cb('ok')
end)

-- ─── Test command ─────────────────────────────────────────────────────────────

RegisterCommand('test_gizmo', function(source, args, rawCommand)
    local model = args[1] or 'prop_bench_01a'
    local modelHash = GetHashKey(model)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Spawn 3m in front of the player
    local prop = CreateObject(
        modelHash,
        pos.x + math.sin(math.rad(-heading)) * 3.0,
        pos.y + math.cos(math.rad(-heading)) * 3.0,
        pos.z,
        true, true, false
    )

    SetModelAsNoLongerNeeded(modelHash)
    common.OpenGizmo(prop)
end, false)

-- ─── Add Prop NUI Callbacks ───────────────────────────────────────────────────

RegisterNUICallback('GetPropList', function(_, cb)
    local propList = require 'config/props'
    cb(propList)
end)

RegisterNUICallback('PlaceProp', function(data, cb)
    local model = data.model
    if not model or model == '' then cb('error') return end

    local modelHash = GetHashKey(model)

    -- Validate model by attempting to load it
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

    local prop = CreateObject(
        modelHash,
        pos.x + math.sin(math.rad(-heading)) * 3.0,
        pos.y + math.cos(math.rad(-heading)) * 3.0,
        pos.z,
        true, true, false
    )

    SetModelAsNoLongerNeeded(modelHash)

    common.OpenGizmo(prop, {
        model          = model,
        group          = data.group or 'default',
        renderDistance = data.renderDistance or 200,
        expiresAt      = data.expiresAt,
        attachingProp  = true,
    })

    cb('ok')
end)

-- ─── Prop Manager NUI Callbacks ──────────────────────────────────────────────

RegisterNUICallback('TeleportToProp', function(data, cb)
    lib.callback('ar_propmanager2:canInteractWithProp', false, function(allowed)
        if not allowed then cb('denied') return end
        local entity = NetworkGetEntityFromNetworkId(data.netId or data.id) or data.handle
        if not entity or not DoesEntityExist(entity) then cb('error') return end
        local pos = GetEntityCoords(entity)
        SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z + 1.0, false, false, false, false)
        cb('ok')
    end, data.id)
end)

RegisterNUICallback('OutlineProp', function(data, cb)
    -- Outlined state is tracked in the UI; the server/manager is responsible for
    -- applying SetEntityDrawOutline if needed via a networked event.
    cb('ok')
end)

RegisterNUICallback('OutlineAllProps', function(data, cb)
    -- Bulk outline toggle — same as OutlineProp but for all props.
    -- Actual visual effect can be applied here once the outline system is wired up.
    cb('ok')
end)

RegisterNUICallback('DeleteProp', function(data, cb)
    TriggerServerEvent('ar_propmanager2:deleteProp', { id = data.id })
    cb('ok')
end)

RegisterNUICallback('ToggleGroup', function(data, cb)
    TriggerServerEvent('ar_propmanager2:toggleGroup', { group = data.group, enabled = data.enabled })
    cb('ok')
end)

-- ─── Prop Manager helpers ─────────────────────────────────────────────────────

--- Open the prop manager window.
--- @param payload table  { props = [...], groupStates = { [groupName] = bool } }
function common.OpenPropManager(payload)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openPropManager', data = payload })
end

function common.ClosePropManager()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePropManager', data = {} })
end

RegisterCommand('test_prop_manager', function()
    -- Build a fake list from nearby objects for quick testing
    local ped    = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local propList = {}
    local mockGroups = { 'Street Furniture', 'Vehicles', 'Nature' }

    local now = os.time()
    -- Expiry patterns cycled across props: none, future (+1 h), future (+24 h), already expired
    local mockExpiries = {
        nil,
        now + 3600,       -- expires in 1 hour
        now + 86400,      -- expires in 24 hours
        now - 60,         -- already expired (1 min ago)
    }

    local nearby = GetGamePool('CObject')
    local count  = 0
    for _, obj in ipairs(nearby) do
        if #(GetEntityCoords(obj) - origin) < 30.0 then
            local pos = GetEntityCoords(obj)
            count = count + 1
            propList[#propList + 1] = {
                id             = tostring(obj),
                handle         = obj,
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

    -- Build mock group states (all enabled)
    local groupStates = {}
    for _, g in ipairs(mockGroups) do groupStates[g] = true end

    common.OpenPropManager({ props = propList, groupStates = groupStates })
end, false)

-- ─── Player access NUI Callbacks ─────────────────────────────────────────────

RegisterNUICallback('AddPlayerAccess', function(data, cb)
    TriggerServerEvent('ar_propmanager2:addPlayerAccess', data)
    cb('ok')
end)

RegisterNUICallback('UpdatePlayerAccess', function(data, cb)
    TriggerServerEvent('ar_propmanager2:updatePlayerAccess', data)
    cb('ok')
end)

RegisterNUICallback('DeletePlayerAccess', function(data, cb)
    TriggerServerEvent('ar_propmanager2:deletePlayerAccess', data.id)
    cb('ok')
end)

RegisterNUICallback('GetPlayerPosition', function(_, cb)
    local pos = GetEntityCoords(PlayerPedId())
    cb({ x = pos.x, y = pos.y, z = pos.z })
end)

--- Open the permissions manager window.
--- @param permissionList table  Array of { id, identifier, name, group, area }
--- @param groups         table  Array of group name strings
function common.OpenPermissions(permissionList, groups)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openPermissions',
        data   = { permissions = permissionList, groups = groups }
    })
end

function common.ClosePermissions()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePermissions', data = {} })
end

RegisterCommand('test_permissions', function()
    local groups = { 'Street Furniture', 'Nature', 'Vehicles' }
    local permissions = {
        {
            id         = 'perm_1',
            identifier = 'license:a1b2c3d4e5f6a1b2c3d4e5f6',
            name       = 'John Doe',
            group      = 'Street Furniture',
            area       = nil,
        },
        {
            id         = 'perm_2',
            identifier = 'license:f6e5d4c3b2a1f6e5d4c3b2a1',
            name       = 'Jane Smith',
            group      = 'Nature',
            area       = {
                center = { x = 215.4, y = -810.2, z = 29.7 },
                radius = 100,
            },
        },
    }
    common.OpenPermissions(permissions, groups)
end, false)

-- ─── Exports ──────────────────────────────────────────────────────────────────

exports('OpenGizmo', function(entity, options)
    common.OpenGizmo(entity, options)
end)

exports('OpenPropManager', function(propList)
    common.OpenPropManager(propList)
end)

-- ─── Server → client events ───────────────────────────────────────────────────

--- Broadcast from server whenever the prop list or group states change.
--- Refreshes the UI if the prop manager window is currently open.
RegisterNetEvent('ar_propmanager2:syncPropList', function(payload)
    SendNUIMessage({ action = 'updatePropList', data = payload })
end)

--- Server export OpenPropManagerForPlayer triggers this.
RegisterNetEvent('ar_propmanager2:openPropManagerFromServer', function(propList)
    common.OpenPropManager(propList)
end)

--- Server export OpenPermissionsForPlayer triggers this.
RegisterNetEvent('ar_propmanager2:openPlayerAccessFromServer', function(permList, groups)
    common.OpenPermissions(permList, groups)
end)

-- ─── Real prop manager command ────────────────────────────────────────────────

--- Fetches the prop list from the server and opens the manager.
--- Non-admins only see props in groups they have permission for.
RegisterCommand('manage_props', function()
    lib.callback('ar_propmanager2:getProps', false, function(propList)
        if propList then
            common.OpenPropManager(propList)
        end
    end)
end, false)
