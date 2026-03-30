return {
    -- ─── Admin ace permissions ─────────────────────────────────────────────────
    -- Grant these in server.cfg or your ACL file, e.g.:
    --   add_ace group.admin ar_propmanager.manage       allow
    --   add_ace group.admin ar_propmanager.toggleGroups allow
    --   add_ace group.admin ar_propmanager.playerAccess allow
    --
    -- Each key maps to a specific capability so you can grant them independently:
    --   manage       – place, move and delete props; open the prop manager
    --   toggleGroups – enable / disable a prop group (spawns or despawns all props in it)
    --   playerAccess – view and edit the player access list (who can place in which group)
    -- ─── Expiry cron ──────────────────────────────────────────────────────────────
    -- How often to check for and remove expired props.
    -- Uses standard cron syntax (powered by ox_lib's lib.cron).
    -- Examples: '*/5 * * * *' = every 5 minutes, '*/1 * * * *' = every minute
    expiryCron = '*/5 * * * *',

    ace = {
        manage       = 'ar_propmanager.manage',
        toggleGroups = 'ar_propmanager.toggleGroups',
        playerAccess = 'ar_propmanager.playerAccess',
    },
}
