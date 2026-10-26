Config.care = {
    -- Core restoration is additive on the 0-100 core scale. Use 0 to disable a value.
    boosts = {
        -- Health and stamina restored by one brush action.
        brush = { health = 10, stamina = 10 },
        -- Health and stamina restored by feeding or grazing.
        feed = { health = 20, stamina = 20 },
        drink = {
            health = 20,          -- Health restored after drinking.
            stamina = 20,         -- Stamina restored after drinking.
            durationSeconds = 15, -- Natural-water drinking animation length.
        },
        rest = {
            health = 5,              -- Health restored on each rest tick.
            stamina = 5,             -- Stamina restored on each rest tick.
            tickIntervalSeconds = 5, -- Seconds between rest restoration ticks.
        },
        sleep = {
            health = 10,             -- Health restored on each sleep tick.
            stamina = 10,            -- Stamina restored on each sleep tick.
            tickIntervalSeconds = 5, -- Seconds between sleep restoration ticks.
        },
    },

    -- Bonding level 1 and above multiplies brush, feed, graze, and drink restoration.
    bondedRestorationMultiplier = 1.25,

    -- Save active horse cores on this interval. Use 0 to disable periodic saves.
    saveIntervalMinutes = 2,

    -- Play a core-restoration sound on every rest and sleep regeneration tick.
    playPassiveRegenSound = false,

    waterCleaning = {
        enabled = true, -- Clean the active horse after it enters sufficiently deep water.
        minimumSubmergedLevel = 0.35, -- Required submerged fraction; shallow puddles are ignored.
        checkIntervalMs = 500, -- How often to check the horse's water depth.
    },

    -- Supported water troughs and hay props. Add profiles for custom map props as needed.
    world = {
        enabled = true,               -- Enable drinking from troughs and eating world hay.
        scanRadius = 3.0,             -- Distance around the horse searched for supported props.
        scanIntervalMs = 500,         -- Delay between nearby-prop searches.
        approachTimeoutMs = 6000,     -- Time allowed for the horse to reach the prop.
        reservationTimeoutMs = 45000, -- Time one horse reserves a prop interaction point.
        troughs = {
            durationSeconds = 15,     -- Time spent drinking before rewards are applied.
            -- Animation played while lowering the horse's head.
            enterAnimation = {
                dict = 'amb_creature_mammal@prop_horse_drink_trough@stand_enter', -- Animation dictionary.
                name = 'enter',                                                   -- Animation clip name.
            },
            -- Loop played while the horse drinks.
            animation = {
                dict = 'amb_creature_mammal@prop_horse_drink_trough@idle0',
                name = 'idle_a',
            },
            -- Animation played while the horse stands again.
            exitAnimation = {
                dict = 'amb_creature_mammal@prop_horse_drink_trough@stand_exit',
                name = 'exit',
            },
            -- model: supported prop; distance: horse stopping distance from it.
            profiles = {
                { model = 'p_watertrough01x', distance = 1.05 },
                { model = 'p_watertrough02x', distance = 1.05 },
                { model = 'p_watertrough03x', distance = 1.05 },
            },
        },
        hay = {
            durationSeconds = 10, -- Time spent grazing before rewards are applied.
            -- Animation played while lowering the horse's head.
            enterAnimation = {
                dict = 'amb_creature_mammal@world_horse_grazing@stand_enter',
                name = 'enter',
            },
            -- Loop played while the horse grazes.
            animation = {
                dict = 'amb_creature_mammal@world_horse_grazing@idle',
                name = 'idle_a',
            },
            -- Animation played while the horse stands again.
            exitAnimation = {
                dict = 'amb_creature_mammal@world_horse_grazing@stand_exit',
                name = 'exit',
            },
            -- model: supported prop; distance: horse stopping distance from it.
            profiles = {
                { model = 'p_haybale01x', distance = 1.75 },
                { model = 'p_haybale02x', distance = 1.75 },
                { model = 'p_haybale03x', distance = 1.75 },
                { model = 'p_haypile01x', distance = 1.0 },
                { model = 'p_haypile02x', distance = 1.0 },
            },
        },
    },
}
