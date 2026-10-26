local HORSE_AGING_POLICY <const> = {
    -- Keep recorded age, while guaranteeing a minimum amount of remaining life.
    GRACE_PERIOD = 'grace_period',

    -- Treat every existing horse as newly born when aging is first enabled.
    RESET_AGE = 'reset_age',

    -- Keep recorded ages without protection. Over-age horses may die immediately.
    NATURAL_AGE = 'natural_age',

    -- Apply aging only to horses created after the aging system is enabled.
    EXCLUDE_EXISTING = 'exclude_existing',
}

Config.aging = {
    -- Master switch for natural horse aging and age-related death.
    enabled = true,

    -- Number of real-world days represented by one horse year.
    daysPerYear = 7,

    -- Each horse receives a random natural lifespan within this range.
    lifespan = {
        minimumYears = 18, -- Youngest possible natural-death age.
        maximumYears = 28, -- Oldest possible natural-death age.
    },

    -- Controls how horses already in the database are handled when aging is enabled.
    existingHorses = {
        policy = HORSE_AGING_POLICY.GRACE_PERIOD,

        -- Used only by GRACE_PERIOD to prevent existing horses from dying immediately.
        minimumRemainingYears = 2,
    },

    -- Age, in horse years, at which each life-stage label begins.
    lifeStages = {
        adult = 2,   -- Age when Young changes to Adult.
        senior = 3,  -- Age when Senior begins and penalties start.
        elderly = 5, -- Age when Senior changes to Elderly.
    },

    -- Gradually reduces selected performance stats after a horse becomes a senior.
    seniorEffects = {
        enabled = true, -- Apply performance penalties to senior horses.

        -- Decimal reduction applied for every year beyond the senior threshold.
        speedPenaltyPerYear = 0.02,        -- Speed lost per senior year; 0.02 is 2 percent.
        accelerationPenaltyPerYear = 0.02, -- Acceleration lost per senior year.
        staminaPenaltyPerYear = 0.03,      -- Stamina lost per senior year.

        -- Caps the combined reduction at 30 percent of the original value.
        maximumPenalty = 0.30,
    },

    -- How often the server checks active records for life-stage changes and death.
    checkIntervalMinutes = 15,
}
