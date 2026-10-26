Config.training = {
    -- Restrict leveling and shops to configured trainer jobs.
    trainerOnly = false,

    -- Restrict wild-horse registration and sales to configured trainer jobs.
    tamingTrainerOnly = false,

    trainerJobs = {
        trainer = {
            minimumGrade = 0,       -- Lowest job grade allowed to train professionally.
            xpMultiplier = 1.5,     -- Horse XP earned while working as this job.
            cooldownMultiplier = 0.75, -- Reduces the delay between repeat training actions.
        },
    },

    xpRewards = {
        brush = 1,   -- XP awarded after brushing.
        pat = 1,     -- XP awarded after patting.
        feed = 1,    -- XP awarded after feeding or grazing.
        drink = 1,   -- XP awarded after drinking.
        riding = 5,  -- XP awarded at each riding milestone.
        leading = 5, -- XP awarded at each leading milestone.
    },

    xpPerLevel = 1000,         -- XP required for each training level.
    showXpMessage = true,      -- Notify the player when XP is awarded.
    showLevelUpMessage = true, -- Notify the player when a level is gained.
}

Config.taming = {
    registration = {
        enabled = true,       -- Allow captured horses to be registered.
        currency = 'cash',    -- Supported values: 'cash' or 'gold'.
        price = 25,           -- Registration cost in the selected currency.
        cooldownMinutes = 15, -- Delay before another horse can be registered.
    },
    sale = {
        enabled = true,         -- Allow captured horses to be sold.
        currency = 'cash',      -- Supported values: 'cash' or 'gold'.
        priceMultiplier = 0.25, -- Portion of the catalog price paid to the player.
        cooldownMinutes = 15,   -- Delay before another captured horse can be sold.
    },
}
