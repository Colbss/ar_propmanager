return {
    -- ─── Permission levels ────────────────────────────────────────────────────
    -- Levels are cumulative — each level includes all levels below it.
    --   1 (toggleGroups) – enable / disable prop groups
    --   2 (manage)       – add, move and delete props; view the map
    --   3 (playerAccess) – view and edit the player access list
    --
    -- Grant in server.cfg, e.g.:
    --   add_ace group.admin       ar_propmanager.level2 allow
    --   add_ace group.superadmin  ar_propmanager.level3 allow

    -- ─── Expiry cron ─────────────────────────────────────────────────────────
    -- How often to check for and remove expired props.
    -- Uses standard cron syntax (powered by ox_lib's lib.cron).
    -- Examples: '*/5 * * * *' = every 5 minutes, '*/1 * * * *' = every minute
    expiryCron = '*/5 * * * *',

    ace = {
        [1] = 'ar_propmanager.level1',
        [2] = 'ar_propmanager.level2',
        [3] = 'ar_propmanager.level3',
    },
}
