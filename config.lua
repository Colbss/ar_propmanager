return {
    -- ─── Admin ace permissions ─────────────────────────────────────────────────
    -- Grant these in server.cfg or your ACL file, e.g.:
    --   add_ace group.admin ar_propmanager2.manage       allow
    --   add_ace group.admin ar_propmanager2.toggleGroups allow
    --   add_ace group.admin ar_propmanager2.playerAccess allow
    --
    -- Each key maps to a specific capability so you can grant them independently:
    --   manage       – place, move and delete props; open the prop manager
    --   toggleGroups – enable / disable a prop group (spawns or despawns all props in it)
    --   playerAccess – view and edit the player access list (who can place in which group)
    ace = {
        manage       = 'ar_propmanager2.manage',
        toggleGroups = 'ar_propmanager2.toggleGroups',
        playerAccess = 'ar_propmanager2.playerAccess',
    },
}
