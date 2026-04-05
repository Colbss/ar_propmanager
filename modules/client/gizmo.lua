lib.locale()

-- ██ ▄█▀ ██████ ██  ██ █████▄ ██ ███  ██ ████▄  ▄█████ 
-- ████   ██▄▄    ▀██▀  ██▄▄██ ██ ██ ▀▄██ ██  ██ ▀▀▀▄▄▄ 
-- ██ ▀█▄ ██▄▄▄▄   ██   ██▄▄█▀ ██ ██   ██ ████▀  █████▀ 

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
                           
--  ▄████  ██ ██████ ██▄  ▄██ ▄████▄ 
-- ██  ▄▄▄ ██  ▄▄▀▀  ██ ▀▀ ██ ██  ██ 
--  ▀███▀  ██ ██████ ██    ██ ▀████▀                               

local gizmoActive        = false
local currentGizmoEntity = nil
local hasFocus           = false
local gizmoOnFinish      = nil
local gizmoOnCancel      = nil

local disabledControls = {
    23,     -- Enter
    25,     -- Aim
    44,     -- Cover
    140,    -- MeleeAttackLight
    141,    -- MeleeAttackHeavy
    142,    -- MeleeAttackAlternate
    143,    -- MeleeAttack
    263     -- MeleeAttackAlt
}

--- Toggle NUI focus for the gizmo, optionally overriding the current state.
--- @param  override boolean|nil  true = focused, false = unfocused, nil = toggle
--- @return nil
function ToggleFocus(override)
    if override ~= nil then
        hasFocus = override
    else
        hasFocus = not hasFocus
    end
    SetNuiFocus(hasFocus, hasFocus)
    SetNuiFocusKeepInput(hasFocus)
    if hasFocus then
        lib.disableControls:Add({1,2})
    else
        lib.disableControls:Remove({1,2})
    end
end

--- Open the gizmo for the given entity.
--- @param  entity   number                                                                                                                         Entity handle to manipulate
--- @param  options  { restrictRotationAxes?: boolean }|nil                                                                                        Gizmo options
--- @param  onFinish fun(position: { x: number, y: number, z: number }, quaternion: { x: number, y: number, z: number, w: number })|nil            Called when the player confirms placement
--- @param  onCancel fun(entity: number)|nil                                                                                                        Called when the player cancels
--- @return nil
function OpenGizmo(entity, options, onFinish, onCancel)
    
    if not DoesEntityExist(entity) then
        lib.notify({
            description = locale('gizmo_invalid_entity'),
            type = 'error'
        })
        onCancel()
        return
    end

    options = options or {}

    currentGizmoEntity = entity
    gizmoOnFinish      = onFinish
    gizmoOnCancel      = onCancel

    local pos             = GetEntityCoords(entity)
    local qx, qy, qz, qw = GetEntityQuaternion(entity)

    keybinds.mode:disable(false)
    keybinds.focus:disable(false)
    keybinds.finish:disable(false)
    keybinds.cancel:disable(false)

    ToggleFocus(false)
    SendNUIMessage({
        action = 'initGizmo',
        data   = {
            position             = { x = pos.x, y = pos.y, z = pos.z },
            quaternion           = { x = qx, y = qy, z = qz, w = qw },
            restrictRotationAxes = options.restrictRotationAxes or false,
            locales              = BuildUILocales(),
        },
    })

    gizmoActive = true

    if cache.vehicle then
        lib.notify({
            description = locale('gizmo_vehicle_warning'),
            type = 'error'
        })
        CloseGizmo(false)
        return
    end

    CreateThread(function()
        lib.disableControls:Add(disabledControls)
        while gizmoActive do
            lib.disableControls()
            local camPos = GetGameplayCamCoords()
            local camRot = GetGameplayCamRot(2)
            SendNUIMessage({
                action = 'setCameraPosition',
                data   = {
                    position = { x = camPos.x, y = camPos.y, z = camPos.z },
                    rotation = { x = camRot.x, y = camRot.y, z = camRot.z },
                },
            })
            Wait(0)
        end
        lib.disableControls:Remove(disabledControls)
    end)
end

--- Close the active gizmo session.
--- @param  save    boolean  true = confirm placement and fire onFinish, false = cancel and fire onCancel
--- @return nil
function CloseGizmo(save)
    if not gizmoActive then return end
    gizmoActive = false

    keybinds.mode:disable(true)
    keybinds.focus:disable(true)
    keybinds.finish:disable(true)
    keybinds.cancel:disable(true)

    ToggleFocus(false)
    SendNUIMessage({ action = 'closeGizmo', data = {} })

    -- Capture and clear state before firing callbacks
    local entity   = currentGizmoEntity
    local onFinish = gizmoOnFinish
    local onCancel = gizmoOnCancel

    currentGizmoEntity = nil
    gizmoOnFinish      = nil
    gizmoOnCancel      = nil

    if save then
        if entity and DoesEntityExist(entity) then
            local pos             = GetEntityCoords(entity)
            local qx, qy, qz, qw = GetEntityQuaternion(entity)
            if onFinish then
                onFinish(
                    { x = pos.x, y = pos.y, z = pos.z },
                    { x = qx, y = qy, z = qz, w = qw }
                )
            end
        end
    else
        if onCancel then onCancel(entity) end
    end
end

lib.onCache('vehicle', function(value)
    if value then
        CloseGizmo(false)
        lib.notify({
            description = locale('gizmo_vehicle_warning'),
            type = 'error'
        })
    end
end)
             
-- ███  ██ ██  ██ ██ 
-- ██ ▀▄██ ██  ██ ██ 
-- ██   ██ ▀████▀ ██ 

RegisterNUICallback('TransformEntity', function(data, cb)
    if not currentGizmoEntity or not DoesEntityExist(currentGizmoEntity) then cb('error') return end

    SetEntityCoords(currentGizmoEntity, data.position.x, data.position.y, data.position.z, false, false, false, false)

    if data.quaternion then
        SetEntityQuaternion(currentGizmoEntity, data.quaternion.x, data.quaternion.y, data.quaternion.z, data.quaternion.w)
    elseif data.rotation then
        SetEntityRotation(currentGizmoEntity, data.rotation.x, data.rotation.y, data.rotation.z, 2, false)
    end

    FreezeEntityPosition(currentGizmoEntity, true)
    cb('ok')
end)

RegisterNUICallback('SnapToGround', function(_, cb)
    if not currentGizmoEntity or not DoesEntityExist(currentGizmoEntity) then cb('error') return end

    local pos            = GetEntityCoords(currentGizmoEntity)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, false)

    if not found or (pos.z - groundZ) > 50.0 then cb('error') return end

    local placed = PlaceObjectOnGroundProperly(currentGizmoEntity)

    if placed then
        local newPos          = GetEntityCoords(currentGizmoEntity)
        local qx, qy, qz, qw = GetEntityQuaternion(currentGizmoEntity)
        SendNUIMessage({
            action = 'updateGizmoTransform',
            data   = {
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
            position   = { x = pos.x, y = pos.y, z = pos.z },
            quaternion = { x = 0.0, y = 0.0, z = 0.0, w = 1.0 },
        },
    })

    cb('ok')
end)

RegisterNUICallback('Finish', function(_, cb)
    CloseGizmo(true)
    cb('ok')
end)

RegisterNUICallback('Cancel', function(_, cb)
    CloseGizmo(false)
    cb('ok')
end)
                                            
-- ██████ ██  ██ █████▄ ▄████▄ █████▄  ██████ ▄█████ 
-- ██▄▄    ████  ██▄▄█▀ ██  ██ ██▄▄██▄   ██   ▀▀▀▄▄▄ 
-- ██▄▄▄▄ ██  ██ ██     ▀████▀ ██   ██   ██   █████▀ 

exports('OpenGizmo', function(entity, options, onFinish, onCancel)
    OpenGizmo(entity, options, onFinish, onCancel)
end)
