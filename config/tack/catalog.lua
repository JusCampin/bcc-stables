TackCurrency = {
    CASH = 1,   -- Tack can only be purchased with cash.
    GOLD = 2,   -- Tack can only be purchased with gold.
    EITHER = 3, -- Player chooses cash or gold at checkout.
    FREE = 4,   -- Tack has no purchase cost.
}

TackConfig = {
    -- Currency policy applied to every tack component.
    currency = TackCurrency.EITHER,
}

-- Category files add their component lists to this table.
HorseComp = {}
