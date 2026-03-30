local config = require 'config'
lib.locale()

-- ─── Spawn state ─────────────────────────────────────────────────────────────
--
-- propCache    : [id] = { model, position, quaternion, renderDistance, group, expiresAt }
-- groupEnabled : [groupName] = bool
-- spawnedProps : [id] = entity handle
-- pendingSpawn : [id] = bool  (model loading, not yet spawned)

propCache    = {}
groupEnabled = {}
spawnedProps = {}
pendingSpawn = {}

function despawnPropLocal(id)
    pendingSpawn[id] = nil
    local entity = spawnedProps[id]
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
    spawnedProps[id] = nil
end

local function applySpawnPayload(payload)
    if payload.groupStates then
        for name, enabled in pairs(payload.groupStates) do
            groupEnabled[name] = enabled
        end
    end

    local newIds = {}
    for _, prop in ipairs(payload.props or {}) do
        newIds[prop.id] = true
        local existing = propCache[prop.id]
        propCache[prop.id] = {
            model          = prop.model,
            position       = prop.position,
            quaternion     = prop.quaternion,
            renderDistance = prop.renderDistance or 200,
            group          = prop.group,
            expiresAt      = prop.expiresAt,
        }
        -- Update coords of already-spawned entities in-place
        if existing and spawnedProps[prop.id] and DoesEntityExist(spawnedProps[prop.id]) then
            local e = spawnedProps[prop.id]
            local q = prop.quaternion or { x = 0, y = 0, z = 0, w = 1 }
            SetEntityCoords(e, prop.position.x, prop.position.y, prop.position.z, false, false, false, false)
            SetEntityQuaternion(e, q.x, q.y, q.z, q.w)
        end
    end

    for id in pairs(propCache) do
        if not newIds[id] then
            despawnPropLocal(id)
            propCache[id] = nil
        end
    end
end

-- ─── Spawn management thread ──────────────────────────────────────────────────

-- Spawns/despawns props based on player distance and group enabled state.
CreateThread(function()
    while true do
        Wait(1000)
        local playerPos = GetEntityCoords(PlayerPedId())

        for id, prop in pairs(propCache) do
            local dist        = #(vector3(prop.position.x, prop.position.y, prop.position.z) - playerPos)
            local shouldSpawn = dist <= (prop.renderDistance or 200) and (groupEnabled[prop.group] ~= false)

            if shouldSpawn and not spawnedProps[id] and not pendingSpawn[id] then
                pendingSpawn[id] = true
                local capturedId   = id
                local capturedProp = prop
                CreateThread(function()
                    local hash = GetHashKey(capturedProp.model)
                    RequestModel(hash)
                    local t = 0
                    while not HasModelLoaded(hash) and t < 100 do Wait(10); t = t + 1 end
                    if HasModelLoaded(hash) and propCache[capturedId] and pendingSpawn[capturedId] then
                        local q      = capturedProp.quaternion or { x = 0, y = 0, z = 0, w = 1 }
                        local entity = CreateObjectNoOffset(
                            hash,
                            capturedProp.position.x, capturedProp.position.y, capturedProp.position.z,
                            false, false, false
                        )
                        SetEntityQuaternion(entity, q.x, q.y, q.z, q.w)
                        FreezeEntityPosition(entity, true)
                        SetModelAsNoLongerNeeded(hash)
                        spawnedProps[capturedId] = entity
                    end
                    pendingSpawn[capturedId] = nil
                end)
            elseif not shouldSpawn and spawnedProps[id] then
                despawnPropLocal(id)
            end
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    lib.callback('ar_propmanager:getSpawnData', false, function(payload)
        if payload then applySpawnPayload(payload) end
    end)
end)
