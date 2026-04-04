
if GetResourceState('qbx_core') ~= 'started' then return end

Framework = {}
Framework.Name = 'QBox'

function Framework.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end
