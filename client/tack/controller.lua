HorseAppearance = HorseAppearance or {}
local appliedByEntity = {}

local function updateVariation(entity)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, entity, false, true, true, true, false)
end

function HorseAppearance.removeSlot(entity, slotId, deferUpdate)
    local slot = Tack.GetSlot(slotId)
    if not slot or not DoesEntityExist(entity) then return false end
    Citizen.InvokeNative(0xD710A5007C2AC539, entity, slot.category, 0)
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
    for _, slot in ipairs(Tack.Slots) do
        local equipped = type(loadout) == 'table' and loadout[slot.id]
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
