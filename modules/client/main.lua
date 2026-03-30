local config = require 'config'
LocalState = LocalPlayer.state
lib.locale()

-- ─── Keybinds ─────────────────────────────────────────────────────────────────

-- Courtesy of @MadsL
-- https://forum.cfx.re/t/help-how-to-get-the-current-keybind-of-a-registered-keymap/1847600/7

local specialkeyCodes = {
    ['b_100'] = 'LMB', -- Left Mouse Button
    ['b_101'] = 'RMB', -- Right Mouse Button
    ['b_102'] = 'MMB', -- Middle Mouse Button
    ['b_103'] = 'Mouse.ExtraBtn1',
    ['b_104'] = 'Mouse.ExtraBtn2',
    ['b_105'] = 'Mouse.ExtraBtn3',
    ['b_106'] = 'Mouse.ExtraBtn4',
    ['b_107'] = 'Mouse.ExtraBtn5',
    ['b_108'] = 'Mouse.ExtraBtn6',
    ['b_109'] = 'Mouse.ExtraBtn7',
    ['b_110'] = 'Mouse.ExtraBtn8',
    ['b_115'] = 'MouseWheel.Up',
    ['b_116'] = 'MouseWheel.Down',
    ['b_130'] = 'NumSubstract',
    ['b_131'] = 'NumAdd',
    ['b_134'] = 'Num Multiplication',
    ['b_135'] = 'Num Enter',
    ['b_137'] = 'Num1',
    ['b_138'] = 'Num2',
    ['b_139'] = 'Num3',
    ['b_140'] = 'Num4',
    ['b_141'] = 'Num5',
    ['b_142'] = 'Num6',
    ['b_143'] = 'Num7',
    ['b_144'] = 'Num8',
    ['b_145'] = 'Num9',
    ['b_170'] = 'F1',
    ['b_171'] = 'F2',
    ['b_172'] = 'F3',
    ['b_173'] = 'F4',
    ['b_174'] = 'F5',
    ['b_175'] = 'F6',
    ['b_176'] = 'F7',
    ['b_177'] = 'F8',
    ['b_178'] = 'F9',
    ['b_179'] = 'F10',
    ['b_180'] = 'F11',
    ['b_181'] = 'F12',
    ['b_182'] = 'F13',
    ['b_183'] = 'F14',
    ['b_184'] = 'F15',
    ['b_185'] = 'F16',
    ['b_186'] = 'F17',
    ['b_187'] = 'F18',
    ['b_188'] = 'F19',
    ['b_189'] = 'F20',
    ['b_190'] = 'F21',
    ['b_191'] = 'F22',
    ['b_192'] = 'F23',
    ['b_193'] = 'F24',
    ['b_194'] = 'Arrow Up',
    ['b_195'] = 'Arrow Down',
    ['b_196'] = 'Arrow Left',
    ['b_197'] = 'Arrow Right',
    ['b_198'] = 'Delete',
    ['b_199'] = 'Escape',
    ['b_200'] = 'Insert',
    ['b_201'] = 'End',
    ['b_210'] = 'Delete',
    ['b_211'] = 'Insert',
    ['b_212'] = 'End',
    ['b_1000'] = 'Shift',
    ['b_1002'] = 'Tab',
    ['b_1003'] = 'Enter',
    ['b_1004'] = 'Backspace',
    ['b_1009'] = 'PageUp',
    ['b_1008'] = 'Home',
    ['b_1010'] = 'PageDown',
    ['b_1012'] = 'CapsLock',
    ['b_1013'] = 'Control',
    ['b_1014'] = 'Right Control',
    ['b_1015'] = 'Alt',
    ['b_1055'] = 'Home',
    ['b_1056'] = 'PageUp',
    ['b_2000'] = 'Space'
}

local function GetKeyLabel(commandHash)
    local key = GetControlInstructionalButton(0, commandHash | 0x80000000, true)
    if string.find(key, "t_") then
        local label, _count = string.gsub(key, "t_", "")
        return label
    else
        return specialkeyCodes[key] or "unknown"
    end
end

local CloseGizmo -- forward declaration (keybind callbacks reference it before definition)

keybinds = {}

keybinds.mode = lib.addKeybind({
    name = 'gizmo_mode',
    description = string.format('~b~%s~w~', locale('keybind_mode')),
    defaultKey = 'R',
    onPressed = function(self)
        SendNUIMessage({ action = 'toggleMode', data = {} })
    end
})
keybinds.mode:disable(true)

keybinds.focus = lib.addKeybind({
    name = 'gizmo_focus',
    description = string.format('~b~%s~w~', locale('keybind_focus')),
    defaultKey = 'F',
    onPressed = function(self)
        -- Focus camera handled server-side or via cam natives if needed
    end
})
keybinds.focus:disable(true)

keybinds.finish = lib.addKeybind({
    name = 'gizmo_finish',
    description = string.format('~b~%s~w~', locale('keybind_finish')),
    defaultKey = 'E',
    onPressed = function(self)
        if CloseGizmo then CloseGizmo(true) end
    end
})
keybinds.finish:disable(true)

keybinds.cancel = lib.addKeybind({
    name = 'gizmo_cancel',
    description = string.format('~b~%s~w~', locale('keybind_cancel')),
    defaultKey = 'Back',
    onPressed = function(self)
        if CloseGizmo then CloseGizmo(false) end
    end
})
keybinds.cancel:disable(true)

function keybinds.GetKeybinds()
    return {
        mode = {
            key = GetKeyLabel(keybinds.mode.hash),
            description = keybinds.mode.description,
        },
        focus = {
            key = GetKeyLabel(keybinds.focus.hash),
            description = keybinds.focus.description,
        },
        finish = {
            key = GetKeyLabel(keybinds.finish.hash),
            description = keybinds.finish.description,
        },
        cancel = {
            key = GetKeyLabel(keybinds.cancel.hash),
            description = keybinds.cancel.description,
        },
    }
end

-- ─── State ────────────────────────────────────────────────────────────────────

local gizmoActive = false
local currentGizmoEntity = nil
local currentGizmoOptions = nil
local originalCoords = nil
local originalQuat = nil

-- ─── Gizmo ────────────────────────────────────────────────────────────────────

--- Open the gizmo for the given entity handle.
--- @param entity  number  Entity handle
--- @param options table   Optional: { restrictRotationAxes, attachingProp, simpleOverlay, group, dbId, model }
local function OpenGizmo(entity, options)
    assert(DoesEntityExist(entity), 'ar_propmanager: entity does not exist')
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
CloseGizmo = function(save)
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

        TriggerServerEvent('ar_propmanager:saveProp', {
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
    CloseGizmo(true)
    cb('ok')
end)

RegisterNUICallback('Cancel', function(_, cb)
    CloseGizmo(false)
    cb('ok')
end)

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

    OpenGizmo(prop, {
        model          = model,
        group          = data.group or 'default',
        renderDistance = data.renderDistance or 200,
        expiresAt      = data.expiresAt,
        attachingProp  = true,
    })

    cb('ok')
end)

-- ─── Prop Manager ─────────────────────────────────────────────────────────────

--- Open the prop manager window.
--- @param payload table  { props = [...], groupStates = { [groupName] = bool } }
local function OpenPropManager(payload)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openPropManager', data = payload })
end

local function ClosePropManager()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePropManager', data = {} })
end

RegisterNUICallback('TeleportToProp', function(data, cb)
    lib.callback('ar_propmanager:canInteractWithProp', false, function(allowed)
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
    TriggerServerEvent('ar_propmanager:deleteProp', { id = data.id })
    cb('ok')
end)

RegisterNUICallback('ToggleGroup', function(data, cb)
    TriggerServerEvent('ar_propmanager:toggleGroup', { group = data.group, enabled = data.enabled })
    cb('ok')
end)

-- ─── Player Access ────────────────────────────────────────────────────────────

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

RegisterNUICallback('GetPlayerPosition', function(_, cb)
    local pos = GetEntityCoords(PlayerPedId())
    cb({ x = pos.x, y = pos.y, z = pos.z })
end)

-- ─── Commands ─────────────────────────────────────────────────────────────────

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
    OpenGizmo(prop)
end, false)

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

    OpenPropManager({ props = propList, groupStates = groupStates })
end, false)

RegisterCommand('manage_props', function()
    lib.callback('ar_propmanager:getProps', false, function(payload)
        if payload then
            OpenPropManager(payload)
        end
    end)
end, false)

-- ─── Exports ──────────────────────────────────────────────────────────────────

exports('OpenGizmo', function(entity, options)
    OpenGizmo(entity, options)
end)

exports('OpenPropManager', function(propList)
    OpenPropManager(propList)
end)

-- ─── Server → client events ───────────────────────────────────────────────────

--- Broadcast from server whenever the prop list or group states change.
--- Refreshes the UI if the prop manager window is currently open.
RegisterNetEvent('ar_propmanager:syncPropList', function(payload)
    SendNUIMessage({ action = 'updatePropList', data = payload })
end)

--- Server export OpenPropManagerForPlayer triggers this.
RegisterNetEvent('ar_propmanager:openPropManagerFromServer', function(payload)
    OpenPropManager(payload)
end)
