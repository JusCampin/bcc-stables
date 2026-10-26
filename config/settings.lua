Config = {
    -- Language file used for player-facing text.
    locale = 'en_lang',
    -----------------------------------------------------

    development = {
        -- Enables debug logs and test commands. Disable on live servers.
        enabled = true,
    },
    -----------------------------------------------------

    integrations = {
        discord = {
            enabled = false,       -- Send configured stable events to Discord.
            webhookUrl = '',       -- Discord webhook URL. Keep blank when disabled.
            title = 'BCC-Stables', -- Name shown above Discord log messages.
            avatarUrl = '',        -- Optional image URL used as the webhook avatar.
        },
    },
    -----------------------------------------------------

    -- Keyboard controls use RedM input hashes.
    controls = {
        openStable = 0x80F28E95,   -- L: open the stable menu.
        stableAction = 0x27D1C284, -- R: call or return a horse at a stable.
        -- Context-sensitive horse care prompt: drink from natural water or a trough, or eat nearby hay.
        drink = 0xD8F73058,        -- U
        rest = 0x620A6C5E,         -- V: make the horse rest.
        sleep = 0x43CDA5B0,        -- Z: make the horse sleep.
        wallow = 0x9959A6F0,       -- C: make the horse wallow.
        standOrWake = 0x760A9C6F,  -- G: end rest, sleep, or wallowing.
        lootHorse = 0x27D1C284,    -- R: open an allowed horse inventory.
    },
    -----------------------------------------------------

    preview = {
        -- Each player receives a private routing bucket while viewing stable horses.
        bucketBase = 7000,

        -- Default preview framing. Individual stables may override these values.
        camera = {
            referenceFov = 42.0,       -- Baseline field of view used for automatic scaling.
            referenceDistance = 4.75,  -- Distance paired with the baseline field of view.
            distance = 3.25,           -- Default camera distance from the preview horse.
            minimumFov = 30.0,         -- Narrowest field of view automatic scaling may use.
            maximumFov = 65.0,         -- Widest field of view automatic scaling may use.
            horizontalOffset = 0.85,   -- Positive values move the horse right on screen.
            cameraHeightOffset = 0.20, -- Raises or lowers the camera from the stable camera point.
            targetHeightOffset = 0.05, -- Raises or lowers where the camera aims on the horse.
        },
    },
    -----------------------------------------------------

    commands = {
        respawnHorse = 'horseRespawn',  -- Respawn the selected horse without a distance check.
        setHorseWild = 'horseSetWild',  -- Development only.
        setHorseWrithe = 'horseWrithe', -- Development only.
        horseInfo = 'horseInfo',        -- Open detailed information for the active horse.
    },
    -----------------------------------------------------

    horseLimits = {
        player = 5,   -- Maximum horses owned by a normal player.
        trainer = 10, -- Maximum horses owned by a configured trainer.
    },
    -----------------------------------------------------

    stable = {
        -- Allow the normal whistle to spawn a selected horse away from a stable.
        whistleAnywhere = true,

        -- Allow players to dismiss their horse through the Flee prompt.
        fleeEnabled = true,

        -- Actions that remain available while a stable is closed.
        whileClosed = {
            callHorse = true,   -- Allow calling a horse while the stable is closed.
            returnHorse = true, -- Allow returning a horse while the stable is closed.
        },

        -- Return a horse to the stable when it becomes too far from its owner.
        autoReturn = {
            enabled = true,          -- Despawn horses left too far from their owner.
            maximumDistance = 100.0, -- Maximum owner distance before auto-return.
        },

        -- Controls queued delivery from a stable spawn point to its delivery point.
        delivery = {
            reservationTimeoutMs = 15000, -- Maximum time one delivery reserves a spawn point.
            spawnClearance = 4.0,         -- Distance required before the next horse may spawn.
            walkSpeed = 1.25,             -- Speed used while walking to the delivery point.
            arrivalDistance = 2.5,        -- Distance from the destination considered delivered.
        },
    },
    -----------------------------------------------------

    items = {
        brush = {
            name = 'horsebrush',         -- Inventory item used to brush horses.
            durabilityEnabled = true,    -- Consume brush durability when used.
            maximumDurability = 100,     -- Durability assigned to a new brush.
            durabilityUsedPerAction = 1, -- Durability consumed per brushing.
        },
        lantern = {
            name = 'oil_lantern',        -- Inventory item attached as a horse lantern.
            durabilityEnabled = true,    -- Consume lantern durability while used.
            maximumDurability = 100,     -- Durability assigned to a new lantern.
            durabilityUsedPerAction = 1, -- Durability consumed per lantern use.
        },
        food = {                         -- Inventory items that can feed a horse.
            'consumable_haycube',
            'consumable_carrots',
            'consumable_apple',
        },
        reviver = 'consumable_horse_reviver', -- Item used to revive a writhing horse.
    },
    -----------------------------------------------------

    death = {
        writheEnabled = true,    -- Down horses before death so they can be revived.
        persistentWrithe = true, -- Save the downed state through reconnects and restarts.
        deselectOnDeath = false, -- Require selecting another horse after death.
        permanentDeath = false,  -- Permanently mark killed horses as dead.
    },
    -----------------------------------------------------

    sales = {
        -- Percentage of the catalog price returned when selling a purchased horse.
        purchasedHorsePriceMultiplier = 0.70,
    },
    -----------------------------------------------------

    horseBehavior = {
        disableKick = false, -- Prevent owned horses from kicking nearby players.
    },
    -----------------------------------------------------

    display = {
        horseTag = {
            enabled = true,           -- Show the active horse's name above it.
            distance = 15.0,          -- Maximum distance at which the name is visible.
        },
        showMountedHorseBreed = true, -- Show the breed while the player is mounted.
    },
}
