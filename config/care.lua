-- Server policy only. No gameplay activation or existing-horse backfill.
StablesCareConfig={
    enabled=false,
    revision=1,
    newHorse={healthCore=100,staminaCore=100},
    feed={healthGain=20,staminaGain=20,durationMs=5000,maxDistance=2.5,observationTtlMs=1000,
        items={'consumable_haycube','consumable_carrots','consumable_apple'}},
}
