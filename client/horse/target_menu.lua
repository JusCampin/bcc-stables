-- Native target-menu actions use completed prompt events, not raw key presses.
-- One nearby-horse reader handles Cargo and Flee.
local C,H=Stables.Client,Stables.Horse
local function yes(v) return v==true or v==1 end
CreateThread(function()
    local cargoEnabled=Config.saddlebags and Config.saddlebags.enabled==true
    local fleeEnabled=Config.stable and Config.stable.fleeEnabled==true
    if not cargoEnabled and not fleeEnabled then return end
    local buffer=CreateEventDataBuffer(80) -- ten eight-byte event fields
    local promptEvent=GetHashKey('EVENT_PLAYER_PROMPT_TRIGGERED')
    local interaction=GetHashKey('Interaction_LootSaddleBags')
    while true do
        local sleep=500
        local r=H.GetActive();local ped=PlayerPedId()
        if r and not yes(IsEntityDead(ped)) and yes(IsPedOnFoot(ped)) and not IsNuiFocused() then
            local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
            if (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=9 then
                sleep=0
                for index=0,GetNumberOfEvents(0)-1 do
                    if Citizen.InvokeNative(0xA85E614430EFF816,0,index)==promptEvent
                        and yes(Citizen.InvokeNative(0x57EC5FA4D4D6AFCA,0,index,buffer:Buffer(),10))
                        and buffer:GetInt32(16)==r.entity then
                        local kind=buffer:GetInt32(0)
                        if kind==33 and fleeEnabled then -- PP_HORSE_FLEE
                            H.Flee(r.generationId)
                            sleep=500;break
                        end
                        if kind==28 and cargoEnabled and r.saddlebag then -- PP_HORSE_ITEMS
                            local result=C.Rpc('saddlebags',{})
                            if not result.ok then C.Message(C.Text('menu_saddlebagsUnavailable'))
                            else
                                local current=H.GetActive()
                                if current and current.entity==r.entity and current.generationId==r.generationId
                                    and PlayerPedId()==ped and yes(IsPedOnFoot(ped)) then
                                    Citizen.InvokeNative(0xCD181A959CFDD7F4,ped,r.entity,interaction,0,true)
                                end
                            end
                            sleep=500;break
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
