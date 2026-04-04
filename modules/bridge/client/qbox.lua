if GetResourceState('qbx_core') ~= 'started' then return end

Framework = {}
Framework.Name = 'QBox'

function Framework.IsLoaded()
    return LocalPlayer.state.isLoggedIn
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() 
    Framework.OnLoaded()
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function() 
    Framework.OnUnloaded()
end)