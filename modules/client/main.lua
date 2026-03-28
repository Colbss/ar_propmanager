local config = require 'config'
LocalState = LocalPlayer.state

local gizmoActive = false
local currentGizmoEntity = nil
local originalCoords = nil
local originalQuat = nil

--- Open the gizmo for the given entity handle.
--- @param entity number  Entity handle
--- @param options table  Optional: { restrictRotationAxes, attachingProp, simpleOverlay }
function common.OpenGizmo(entity, options)
    assert(DoesEntityExist(entity), 'ar_propmanager2: entity does not exist')
    options = options or {}

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

-- ─── Prop Manager NUI Callbacks ──────────────────────────────────────────────

RegisterNUICallback('TeleportToProp', function(data, cb)
    local entity = GetEntityFromNetworkId and GetEntityFromNetworkId(data.id) or data.handle
    if not entity or not DoesEntityExist(entity) then cb('error') return end

    local pos = GetEntityCoords(entity)
    SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z + 1.0, false, false, false, false)
    cb('ok')
end)

RegisterNUICallback('OutlineProp', function(data, cb)
    -- Outlined state is tracked in the UI; the server/manager is responsible for
    -- applying SetEntityDrawOutline if needed via a networked event.
    cb('ok')
end)

RegisterNUICallback('DeleteProp', function(data, cb)
    -- The caller is responsible for providing the entity handle or a lookup mechanism.
    -- This stub signals intent; extend with your persistence layer as needed.
    cb('ok')
end)

-- ─── Prop Manager helpers ─────────────────────────────────────────────────────

--- Open the prop manager window and populate it with a list of props.
--- @param propList table  Array of { id, handle, model, position={x,y,z}, group }
function common.OpenPropManager(propList)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openPropManager',
        data   = { props = propList }
    })
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
    local groups = { 'Street Furniture', 'Vehicles', 'Nature' }

    local nearby = GetGamePool('CObject')
    local count  = 0
    for _, obj in ipairs(nearby) do
        if #(GetEntityCoords(obj) - origin) < 30.0 then
            local pos = GetEntityCoords(obj)
            count = count + 1
            propList[#propList + 1] = {
                id       = tostring(obj),
                handle   = obj,
                model    = tostring(GetEntityModel(obj)),
                position = { x = pos.x, y = pos.y, z = pos.z },
                group    = groups[(count % #groups) + 1],
                outlined = false,
            }
            if count >= 20 then break end
        end
    end

    common.OpenPropManager(propList)
end, false)

-- ─── Permissions NUI Callbacks ───────────────────────────────────────────────

RegisterNUICallback('AddPermission', function(data, cb)
    -- Forward to server for persistence; stub for client-side acknowledgement
    TriggerServerEvent('ar_propmanager2:addPermission', data)
    cb('ok')
end)

RegisterNUICallback('UpdatePermission', function(data, cb)
    TriggerServerEvent('ar_propmanager2:updatePermission', data)
    cb('ok')
end)

RegisterNUICallback('DeletePermission', function(data, cb)
    TriggerServerEvent('ar_propmanager2:deletePermission', data.id)
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
