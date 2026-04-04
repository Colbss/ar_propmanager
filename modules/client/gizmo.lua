lib.locale()

-- ─── Keybinds ─────────────────────────────────────────────────────────────────

-- Courtesy of @MadsL
-- https://forum.cfx.re/t/help-how-to-get-the-current-keybind-of-a-registered-keymap/1847600/7

local specialkeyCodes = {
    ['b_100'] = 'LMB', ['b_101'] = 'RMB', ['b_102'] = 'MMB',
    ['b_103'] = 'Mouse.ExtraBtn1', ['b_104'] = 'Mouse.ExtraBtn2',
    ['b_105'] = 'Mouse.ExtraBtn3', ['b_106'] = 'Mouse.ExtraBtn4',
    ['b_107'] = 'Mouse.ExtraBtn5', ['b_108'] = 'Mouse.ExtraBtn6',
    ['b_109'] = 'Mouse.ExtraBtn7', ['b_110'] = 'Mouse.ExtraBtn8',
    ['b_115'] = 'MouseWheel.Up',   ['b_116'] = 'MouseWheel.Down',
    ['b_130'] = 'NumSubstract',    ['b_131'] = 'NumAdd',
    ['b_134'] = 'Num Multiplication', ['b_135'] = 'Num Enter',
    ['b_137'] = 'Num1', ['b_138'] = 'Num2', ['b_139'] = 'Num3',
    ['b_140'] = 'Num4', ['b_141'] = 'Num5', ['b_142'] = 'Num6',
    ['b_143'] = 'Num7', ['b_144'] = 'Num8', ['b_145'] = 'Num9',
    ['b_170'] = 'F1',  ['b_171'] = 'F2',  ['b_172'] = 'F3',  ['b_173'] = 'F4',
    ['b_174'] = 'F5',  ['b_175'] = 'F6',  ['b_176'] = 'F7',  ['b_177'] = 'F8',
    ['b_178'] = 'F9',  ['b_179'] = 'F10', ['b_180'] = 'F11', ['b_181'] = 'F12',
    ['b_182'] = 'F13', ['b_183'] = 'F14', ['b_184'] = 'F15', ['b_185'] = 'F16',
    ['b_186'] = 'F17', ['b_187'] = 'F18', ['b_188'] = 'F19', ['b_189'] = 'F20',
    ['b_190'] = 'F21', ['b_191'] = 'F22', ['b_192'] = 'F23', ['b_193'] = 'F24',
    ['b_194'] = 'Arrow Up',    ['b_195'] = 'Arrow Down',
    ['b_196'] = 'Arrow Left',  ['b_197'] = 'Arrow Right',
    ['b_198'] = 'Delete',      ['b_199'] = 'Escape',
    ['b_200'] = 'Insert',      ['b_201'] = 'End',
    ['b_210'] = 'Delete',      ['b_211'] = 'Insert',      ['b_212'] = 'End',
    ['b_1000'] = 'Shift',      ['b_1002'] = 'Tab',        ['b_1003'] = 'Enter',
    ['b_1004'] = 'Backspace',  ['b_1008'] = 'Home',       ['b_1009'] = 'PageUp',
    ['b_1010'] = 'PageDown',   ['b_1012'] = 'CapsLock',   ['b_1013'] = 'Control',
    ['b_1014'] = 'Right Control', ['b_1015'] = 'Alt',
    ['b_1055'] = 'Home',       ['b_1056'] = 'PageUp',     ['b_2000'] = 'Space',
}

local function GetKeyLabel(commandHash)
    local key = GetControlInstructionalButton(0, commandHash | 0x80000000, true)
    if string.find(key, 't_') then
        local label, _count = string.gsub(key, 't_', '')
        return label
    end
    return specialkeyCodes[key] or 'unknown'
end

local CloseGizmo -- forward declaration (keybind callbacks reference it before definition)

keybinds = {}

keybinds.mode = lib.addKeybind({
    name        = 'gizmo_mode',
    description = string.format('~b~%s~w~', locale('keybind_mode')),
    defaultKey  = 'R',
    onPressed   = function() SendNUIMessage({ action = 'toggleMode', data = {} }) end,
})
keybinds.mode:disable(true)

keybinds.focus = lib.addKeybind({
    name        = 'gizmo_focus',
    description = string.format('~b~%s~w~', locale('keybind_focus')),
    defaultKey  = 'F',
    onPressed   = function() ToggleFocus() end,
})
keybinds.focus:disable(true)

keybinds.finish = lib.addKeybind({
    name        = 'gizmo_finish',
    description = string.format('~b~%s~w~', locale('keybind_finish')),
    defaultKey  = 'E',
    onPressed   = function() if CloseGizmo then CloseGizmo(true) end end,
})
keybinds.finish:disable(true)

keybinds.cancel = lib.addKeybind({
    name        = 'gizmo_cancel',
    description = string.format('~b~%s~w~', locale('keybind_cancel')),
    defaultKey  = 'Back',
    onPressed   = function() if CloseGizmo then CloseGizmo(false) end end,
})
keybinds.cancel:disable(true)

function keybinds.GetKeybinds()
    return {
        mode   = { key = GetKeyLabel(keybinds.mode.hash),   description = locale('keybind_mode') },
        focus  = { key = GetKeyLabel(keybinds.focus.hash),  description = locale('keybind_focus') },
        finish = { key = GetKeyLabel(keybinds.finish.hash), description = locale('keybind_finish') },
        cancel = { key = GetKeyLabel(keybinds.cancel.hash), description = locale('keybind_cancel') },
    }
end

-- ─── Gizmo state ─────────────────────────────────────────────────────────────

local gizmoActive         = false
local currentGizmoEntity  = nil
local currentGizmoOptions = nil
local originalCoords      = nil
local originalQuat        = nil
local hasFocus            = false

-- ─── Gizmo ────────────────────────────────────────────────────────────────────

--- Toggle NUI focus for the gizmo, optionally overriding the current state.
--- @param override boolean|nil  Optional explicit focus state (true = focused, false = unfocused, nil = toggle)
function ToggleFocus(override)
    if override ~= nil then
        hasFocus = override
    else
        hasFocus = not hasFocus
    end
    SetNuiFocus(hasFocus, hasFocus)
    SetNuiFocusKeepInput(hasFocus)
end

--- Open the gizmo for the given entity handle.
--- @param entity  number  Entity handle
--- @param options table   Optional: { restrictRotationAxes, group, dbId, model }
function OpenGizmo(entity, options)
    assert(DoesEntityExist(entity), 'ar_propmanager: entity does not exist')
    options = options or {}
    currentGizmoOptions = options
    currentGizmoEntity  = entity

    local pos             = GetEntityCoords(entity)
    local qx, qy, qz, qw = GetEntityQuaternion(entity)

    originalCoords = pos
    originalQuat   = { x = qx, y = qy, z = qz, w = qw }

    keybinds.mode:disable(false)
    keybinds.focus:disable(false)
    keybinds.finish:disable(false)
    keybinds.cancel:disable(false)

    ToggleFocus(false)
    SendNUIMessage({ action = 'show', data = {} })
    SendNUIMessage({
        action = 'setGizmoEntity',
        data   = {
            handle               = entity,
            position             = { x = pos.x, y = pos.y, z = pos.z },
            quaternion           = { x = qx, y = qy, z = qz, w = qw },
            keybinds             = keybinds.GetKeybinds(),
            restrictRotationAxes = options.restrictRotationAxes or false,
        },
    })

    gizmoActive = true

    CreateThread(function()
        while gizmoActive do
            -- Prevent camera rotation from mouse movement
            if hasFocus then
                DisableControlAction(0, 1, true)   -- INPUT_LOOK_LR
                DisableControlAction(0, 2, true)   -- INPUT_LOOK_UD
            end

            -- Prevent combat actions
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 25, true)  -- Aim
            DisableControlAction(0, 140, true) -- MeleeAttackLight
            DisableControlAction(0, 141, true) -- MeleeAttackHeavy
            DisableControlAction(0, 142, true) -- MeleeAttackAlternate
            DisableControlAction(0, 143, true) -- MeleeAttack
            DisableControlAction(0, 263, true) -- MeleeAttackAlt

            local camPos = GetGameplayCamCoords()
            local camRot = GetGameplayCamRot(2)
            SendNUIMessage({
                action = 'setCameraPosition',
                data   = {
                    position = { x = camPos.x, y = camPos.y, z = camPos.z },
                    rotation = { x = camRot.x, y = camRot.y, z = camRot.z },
                    fov      = GetGameplayCamFov(),
                },
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
        DeleteEntity(currentGizmoEntity)
    end

    ToggleFocus(false)
    SendNUIMessage({ action = 'closeGizmo', data = {} })
    SendNUIMessage({ action = 'hide', data = {} })

    currentGizmoEntity  = nil
    currentGizmoOptions = nil
    originalCoords      = nil
    originalQuat        = nil
end

-- ─── Gizmo NUI callbacks ──────────────────────────────────────────────────────

RegisterNUICallback('MoveEntity', function(data, cb)
    local entity = data.handle
    if not entity or not DoesEntityExist(entity) then cb('error') return end

    SetEntityCoords(entity, data.position.x, data.position.y, data.position.z, false, false, false, false)

    if data.quaternion then
        SetEntityQuaternion(entity, data.quaternion.x, data.quaternion.y, data.quaternion.z, data.quaternion.w)
    elseif data.rotation then
        SetEntityRotation(entity, data.rotation.x, data.rotation.y, data.rotation.z, 2, false)
    end

    FreezeEntityPosition(entity, true)

    cb('ok')
end)

RegisterNUICallback('SnapToGround', function(_, cb)
    if not currentGizmoEntity or not DoesEntityExist(currentGizmoEntity) then cb('error') return end

    local pos            = GetEntityCoords(currentGizmoEntity)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, false)

    if not found or (pos.z - groundZ) > 50.0 then cb('error') return end

    local placed = PlaceObjectOnGroundProperly(currentGizmoEntity)

    if placed then
        local newPos = GetEntityCoords(currentGizmoEntity)
        local qx, qy, qz, qw = GetEntityQuaternion(currentGizmoEntity)
        SendNUIMessage({
            action = 'updateGizmoTransform',
            data   = {
                handle     = currentGizmoEntity,
                position   = { x = newPos.x, y = newPos.y, z = newPos.z },
                quaternion = { x = qx, y = qy, z = qz, w = qw },
            },
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
        data   = {
            handle     = currentGizmoEntity,
            position   = { x = pos.x, y = pos.y, z = pos.z },
            quaternion = { x = 0.0, y = 0.0, z = 0.0, w = 1.0 },
        },
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
            model          = opts.model or tostring(GetEntityModel(currentGizmoEntity)),
            position       = { x = pos.x, y = pos.y, z = pos.z },
            quaternion     = { x = qx, y = qy, z = qz, w = qw },
            group          = opts.group or 'default',
            renderDistance = opts.renderDistance or 200,
            expiresAt      = opts.expiresAt,
        })

        -- For new props, delete the temp entity — server broadcasts it back via propAdded
        if not opts.dbId then
            DeleteEntity(currentGizmoEntity)
            currentGizmoEntity = nil
        end
    end
    CloseGizmo(true)
    cb('ok')
end)

RegisterNUICallback('Cancel', function(_, cb)
    CloseGizmo(false)
    cb('ok')
end)

-- ─── Dev command ─────────────────────────────────────────────────────────────

RegisterCommand('test_gizmo', function(source, args)
    local model     = args[1] or 'prop_bench_01a'
    local modelHash = GetHashKey(model)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

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
    OpenGizmo(prop)
end, false)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('OpenGizmo', function(entity, options)
    OpenGizmo(entity, options)
end)
