StablesConfig = {
    -- Bounded readiness wait per dependency. Owned schema initializes at startup.
    startupTimeoutMs = 30000,
    -- Capacity used only by the internal reservation repository; no purchase RPC.
    ownedHorseLimit = 3,
    -- Temporary console-only SQL acceptance fixture; keep false outside testing.
    repositoryProof = false,
    -- Console-only quote -> durable unpaid reservation acceptance proof.
    quoteIntentProof = false,
    -- Experimental player RPC: unpaid capacity holds only; never submits payment.
    purchaseAdmission = false,
    -- Charges the saved admission price when explicitly enabled; no fulfillment yet.
    purchasePayments = false,
    -- Registers a canonical horse for a verified paid intent; no gameplay spawn.
    purchaseRegistration = false,
    -- Atomic stored horse/history/outbox commit; no physical horse or dispatch.
    purchaseFulfillment = false,
    -- One persisted selection per character; selecting never spawns a horse.
    horseSelection = false,
    -- Durable pre-spawn generation only; native creation remains disabled.
    callPreparation = false,
    -- Controlled native call/bind/store bridge; keep false until explicitly tested.
    nativeCalls = false,
    -- After verified binding, enable basic riding/companion whistles automatically.
    -- Still controlled/invincible; full gameplay remains unavailable.
    nativeBehavior = false,
    -- Manual publication first; automatic polling is independently opt-in.
    outbox = { enabled = false, automatic = false },
    -- Console-only canonical Assets fixture; creates a durable test asset/audit.
    assetProof = false,
    -- Charges ONE dollars base unit, then explicitly refunds through a durable fence.
    paymentProof = false,
    -- One-unit real payment + Assets registration/link + fenced retirement/refund.
    paidLinkProof = false,
    -- Disposable Phase 0 horse test. Console-only; keep false in production.
    entityProof = {
        enabled = false,
        -- Explicit experiment selection; never auto-fallback after a timeout.
        spawnMode = 'client_lease', -- 'client_lease' or 'server_rpc'
    },
}
