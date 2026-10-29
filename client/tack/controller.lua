HorseAppearance = HorseAppearance or {}
local appliedByEntity = {}

local function updateVariation(entity)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, entity, false, true, true, true, false)
end

function HorseAppearance.removeSlot(entity, slotId, deferUpdate)
    local slot = Tack.GetSlot(slotId)
    if not slot or not DoesEntityExist(entity) then return false end
    Citizen.InvokeNative(0xD710A5007C2AC539, entity, slot.category, 0)
    -- Saddle presets can add these categories without separate loadout entries.
    -- Remove them when swapping/removing a saddle; applyLoadout reapplies any
    -- explicitly chosen horn/stirrups afterward in the normal slot order.
    if slotId == 'saddle' then
        for _, dependent in ipairs({'saddle_horn', 'stirrups'}) do
            Citizen.InvokeNative(0xD710A5007C2AC539, entity, Tack.GetSlot(dependent).category, 0)
        end
    end
    if not deferUpdate then updateVariation(entity) end
    return true
end

function HorseAppearance.applyItem(entity, catalogId, deferUpdate)
    local item = Tack.GetItem(catalogId)
    if not item or not DoesEntityExist(entity) then return false end

    HorseAppearance.removeSlot(entity, item.slot, true)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, entity, item.hash, true, true, true)
    if not deferUpdate then updateVariation(entity) end
    return true
end

function HorseAppearance.applyLoadout(entity, loadout)
    if not DoesEntityExist(entity) then return false end

    local previous = appliedByEntity[entity] or {}
    for _, slot in ipairs(Tack.Slots) do
        if previous[slot.id] or (type(loadout) == 'table' and loadout[slot.id]) then
            HorseAppearance.removeSlot(entity, slot.id, true)
        end
    end

    local applied = {}
    local saddle = type(loadout) == 'table' and loadout.saddle
    local saddleItem = saddle and Tack.GetItem(saddle.catalogId)
    for _, slot in ipairs(Tack.Slots) do
        local equipped = type(loadout) == 'table' and loadout[slot.id]
        local policy = Tack.PieceSlots and Tack.PieceSlots[slot.id]
        if policy and (policy.requiresSaddle or policy.needsSaddle) and not loadout.saddle then equipped = nil end
        if not equipped and saddleItem and Tack.SaddleDefaults and Tack.SaddleDefaults[slot.id] then
            equipped = {catalogId=Tack.SaddleDefaults[slot.id]}
        end
        if equipped and equipped.catalogId then
            local item = Tack.GetItem(equipped.catalogId)
            if item then
                Citizen.InvokeNative(0xD3A7B003ED343FD9, entity, item.hash, true, true, true)
                applied[slot.id] = item.id
            end
        end
    end
    appliedByEntity[entity] = applied
    updateVariation(entity)
    return true
end

function HorseAppearance.resetTracking(entity)
    appliedByEntity[entity] = nil
end

-- Kept as the general native component helper used by non-tack features such as lanterns.
function SetComponent(entity, hash)
    if not DoesEntityExist(entity) then return false end
    local component = tonumber(hash)
    if not component or component == 0 then return false end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, entity, component, true, true, true)
    updateVariation(entity)
    return true
end
