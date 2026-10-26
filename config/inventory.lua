Config.inventory = {
    requireSaddlebags = true, -- Require equipped saddlebags to open horse inventory.
    shared = false,           -- Allows other players to loot horse inventories when true.

    weapons = {
        enabled = true,       -- Allow weapons to be stored on horses.
        useAllowList = false, -- Restrict weapons to the entries below.
        allowList = {
            -- name: weapon identifier; limit: maximum stored quantity.
            -- { name = 'WEAPON_MELEE_TORCH', limit = 1 },
        },
    },

    items = {
        ignoreStackLimit = true, -- Ignore normal item stack limits in horse inventory.
        useAllowList = false,    -- Restrict items to the entries below.
        allowList = {
            -- name: item identifier; limit: maximum stored quantity.
            -- { name = 'diamond', limit = 10 },
        },
        useBlockList = false, -- Prevent storage of the items listed below.
        blockList = {
            -- Add inventory item identifiers as strings.
            -- 'food_delivery1',
        },
    },

    permissions = {
        enabled = false, -- Restrict inventory transfers by job and grade.
        allowedJobsTakeFrom = {
            -- Jobs allowed to remove items from horse inventory.
            -- { name = 'police', grade = 0 },
        },
        allowedJobsMoveTo = {
            -- Jobs allowed to place items into horse inventory.
            -- { name = 'police', grade = 0 },
        },
    },
}
