local paymentSetup=assert(loadfile('tests/fixtures/payment_services.lua'))()
local MODEL='a_c_horse_morgan_bay'
local function setup(unlinked,quoteSnapshot)
    local m=paymentSetup(quoteSnapshot); assert(m.pay().ok)
    local S=m.S
    local function external(name) assert(not m.inTx); m.calls[#m.calls+1]=name end
    S.Assets={
        FindRegistration=function(key)
            external('asset_find'); if m.onAssetFind then m.onAssetFind() end
            if m.assetReadError then return S.Err('assets_unavailable','Offline.') end
            local retire=key:find('stables.retire:',1,true)==1
            local receipt=retire and m.retirement or (not retire and m.registration)
            if not receipt then return S.Ok({found=false}) end
            return S.Ok({found=true,operation=retire and (m.retirementOperation or 'asset.retire') or 'asset.register',result=S.Copy(receipt)})
        end,
        RegisterHorse=function(request)
            external('register'); m.registerCalls=(m.registerCalls or 0)+1
            if not m.registration then
                m.registration={assetId='90000000-0000-4000-8000-000000000009',assetType='horse',modelKey=MODEL,status='active',
                    managerResource='bcc-stables',provenanceType=request.provenanceType,provenanceId=request.provenanceId,
                    metadataVersion=1,metadata=S.Copy(request.metadata),revision=1,
                    owner={interestId='a0000000-0000-4000-8000-00000000000a',holderType='character',holderId=m.t.characterId}}
                m.asset=S.Copy(m.registration)
            end
            if m.lostRegistration then return S.Err('transaction_failed','Registration reply lost.') end
            return S.Ok(S.Copy(m.registration))
        end,
        ReadHorse=function(id)
            external('asset_get'); assert(id==m.asset.assetId)
            if m.onAssetRead then m.onAssetRead() end
            return S.Ok(S.Copy(m.asset))
        end,
        RetireProof=function(request)
            external('retire'); m.retireCalls=(m.retireCalls or 0)+1; m.retireRequest=S.Copy(request)
            local record=m.r.Get(m.t.operationId,m.t.characterId).value
            assert(record.state=='compensation_pending' and record.registrationFence=='linked_retirement_v1')
            if m.retireError then return S.Err(m.retireError,'Retirement refused.') end
            if m.onRetire then m.onRetire() end
            if request.expectedRevision~=m.asset.revision then return S.Err('revision_conflict','Asset changed.') end
            m.asset.status,m.asset.owner,m.asset.revision='retired',nil,m.asset.revision+1
            m.retirement=S.Copy(m.asset)
            if m.lostRetirement then return S.Err('transaction_failed','Retirement committed reply lost.') end
            return S.Ok(S.Copy(m.retirement))
        end,
    }
    local reverse=S.Economy.Reverse
    S.Economy.Reverse=function(id)
        assert(m.asset.status=='retired' and m.retirement and m.retirement.assetId==m.asset.assetId,'refund before exact retirement')
        return reverse(id)
    end
    m.loadLinked=function()
        assert(loadfile('server/asset_registration.lua','t',m.env))()
        assert(loadfile('server/linked_cleanup.lua','t',m.env))()
        m.g,m.l=S.AssetRegistration,S.LinkedCleanup
    end
    m.loadLinked()
    if not unlinked then assert(m.g.Run(m.t.operationId,m.t.characterId,MODEL).ok) end
    m.cleanup=function() return m.l.Refund(m.t.operationId,m.t.characterId) end
    return m
end
return setup
