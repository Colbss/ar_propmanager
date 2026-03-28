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

-- ─── Export ───────────────────────────────────────────────────────────────────

exports('OpenGizmo', function(entity, options)
    common.OpenGizmo(entity, options)
end)
