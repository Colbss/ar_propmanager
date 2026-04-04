local config = require 'config'

-- ─── Group toggle ─────────────────────────────────────────────────────────────

function setGroupEnabled(groupName, enabled)
    local group = groups[groupName]
    if not group or group.enabled == enabled then return end

    group.enabled = enabled

    MySQL.query(
        'INSERT INTO `ar_prop_groups` (group_name, enabled) VALUES (?, ?) ON DUPLICATE KEY UPDATE enabled = ?',
        { groupName, enabled and 1 or 0, enabled and 1 or 0 }
    )

    broadcastGroupStates()
end

--- data: { group = string, enabled = bool }
RegisterNetEvent('ar_propmanager:toggleGroup', function(data)
    if getPlayerLevel(source) < 1 then return end
    setGroupEnabled(data.group, data.enabled)
end)

-- ─── Prop events ─────────────────────────────────────────────────────────────

--- data: { id?, model, position, quaternion, group, renderDistance?, expiresAt? }
RegisterNetEvent('ar_propmanager:saveProp', function(data)

    print('Saving prop')
    lib.print.info(data)

    local src  = source
    local pos  = data.position
    local quat = data.quaternion or { x = 0, y = 0, z = 0, w = 1 }

    if not hasPlayerAccess(src, data.group, pos) then
        print(('[ar_propmanager] saveProp denied — player %s, group: %s'):format(src, data.group))
        return
    end

    if data.id then
        -- ── Update existing prop transform ────────────────────────────────────
        local group = groups[data.group]
        if not group then return end
        local propData = group.props[data.id]
        if not propData then return end

        propData.position       = pos
        propData.quat           = quat
        propData.renderDistance = data.renderDistance or propData.renderDistance or 200
        propData.expiresAt      = data.expiresAt

        MySQL.query(
            'UPDATE `ar_props` SET pos_x=?,pos_y=?,pos_z=?,quat_x=?,quat_y=?,quat_z=?,quat_w=?,render_distance=?,expires_at=? WHERE id=?',
            { pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, propData.renderDistance, propData.expiresAt, data.id }
        )
        broadcastPropUpdated(data.id, propData, data.group)
    else
        -- ── New prop ──────────────────────────────────────────────────────────
        local group = getOrCreateGroup(data.group)

        local propData = {
            model          = data.model,
            position       = pos,
            quat           = quat,
            renderDistance = data.renderDistance or 200,
            expiresAt      = data.expiresAt,
        }

        MySQL.query(
            'INSERT IGNORE INTO `ar_prop_groups` (group_name, enabled) VALUES (?, 1)',
            { data.group }
        )
        local id = MySQL.insert.await(
            'INSERT INTO `ar_props` (model,pos_x,pos_y,pos_z,quat_x,quat_y,quat_z,quat_w,group_name,render_distance,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            { data.model, pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, data.group, propData.renderDistance, propData.expiresAt }
        )
        group.props[id] = propData
        broadcastPropAdded(id, propData, data.group)
    end
end)

--- data: { id }
RegisterNetEvent('ar_propmanager:deleteProp', function(data)
    local src = source

    local targetGroupName, propData
    for gName, group in pairs(groups) do
        if group.props[data.id] then
            targetGroupName = gName
            propData        = group.props[data.id]
            break
        end
    end
    if not propData then return end

    if not hasPlayerAccess(src, targetGroupName, propData.position) then
        print(('[ar_propmanager] deleteProp denied — player %s'):format(src))
        return
    end

    groups[targetGroupName].props[data.id] = nil

    MySQL.query('DELETE FROM `ar_props` WHERE id = ?', { data.id })
    broadcastPropsRemoved({ data.id })
end)

-- ─── Expiry cron ─────────────────────────────────────────────────────────────

local function checkExpiredProps()
    local now     = os.time()
    local expired = {}

    for groupName, group in pairs(groups) do
        for dbId, prop in pairs(group.props) do
            if prop.expiresAt and now >= prop.expiresAt then
                expired[#expired + 1] = { groupName = groupName, dbId = dbId, prop = prop }
            end
        end
    end

    if #expired == 0 then return end

    for _, entry in ipairs(expired) do
        groups[entry.groupName].props[entry.dbId] = nil
        print(('[ar_propmanager] Expired prop removed — id: %s, model: %s, group: %s')
            :format(entry.dbId, entry.prop.model, entry.groupName))
    end

    local ids = {}
    for _, entry in ipairs(expired) do ids[#ids + 1] = entry.dbId end
    local placeholders = string.rep('?,', #ids):sub(1, -2)
    MySQL.query('DELETE FROM `ar_props` WHERE id IN (' .. placeholders .. ')', ids)

    broadcastPropsRemoved(ids)
end

lib.cron.new(config.expiryCron, checkExpiredProps)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports('SetGroupEnabled', setGroupEnabled)
