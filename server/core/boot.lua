-- Consume the existing Feather schema; never run the VORP baseline SQL here.
local F=Stables.Feather
local health={state='starting',schemaVersion=11,features={call=false,whistle=false,care=false,commerce=false,menus=false}}
local checksums={
    ['001_purchase_foundation']='fnv1a32:9472f124',
    ['002_asset_registration']='fnv1a32:1c0b2c99',
    ['003_call_generations']='fnv1a32:34c7cb42',
    ['004_call_bindings']='fnv1a32:7b75a419',
    ['005_call_process_epochs']='fnv1a32:568acc4d',
    ['006_call_recoveries']='fnv1a32:b50d161a',
    ['007_horse_runtime_projection']='fnv1a32:f07263eb',
    ['008_call_horse_state_index']='fnv1a32:cc1af751',
    ['009_horse_care_foundation']='fnv1a32:185c1b14',
    ['010_active_care_targets']='fnv1a32:00e0cc8f',
    ['011_care_projection_dispatches']='fnv1a32:d793ddb4'
}
local function start()
    for _,resource in ipairs({'feather-core','feather-assets'}) do
        local ready=F.Call(resource,'AwaitReady',15000); if not ready.ok then return ready end
        local caps=F.Call(resource,'GetCapabilities')
        if not caps.ok then return caps end
        if type(caps.value)~='table' or caps.value.contract~=1 or caps.value.state~='ready' then
            return F.Error('unsupported_contract',resource..' Contract 1 is required.')
        end
    end
    if Stables.Checkout and Stables.Checkout.Enabled() then
        local ready=F.Call('feather-economy','AwaitReady',15000);if not ready.ok then return ready end
        for _,code in ipairs({'dollars','gold'}) do
            local currency=F.Call('feather-economy','GetCurrency',code)
            if not currency.ok then return currency end
            if currency.value.precision~=2 then return F.Error('unsupported_currency','Checkout requires precision 2.') end
        end
    end
    if not DB.awaitReady(15000) then return F.Error('database_unavailable','Feather MySQL is not ready.') end
    local rows=DB.query('SELECT id,checksum,state FROM fs_schema_migrations')
    if type(rows)~='table' or #rows~=11 then return F.Error('schema_incompatible','Existing Feather Stables schema 11 is required; no migration was attempted.') end
    local seen={}
    for _,row in ipairs(rows) do
        if seen[row.id] or checksums[row.id]~=row.checksum or row.state~='applied' then
            return F.Error('schema_incompatible','Migration evidence disagrees: '..tostring(row.id)..'; database left unchanged.')
        end
        seen[row.id]=true
    end
    local installed=Stables.HorseController.Install()
    if not installed.ok then return installed end
    if Stables.Checkout then Stables.Checkout.Start() end
    if Stables.StableMenu then return Stables.StableMenu.Install() end
    return installed
end
exports('GetHealth',function()
    return F.Ok({state=health.state,code=health.code,schemaVersion=health.schemaVersion,
        features={call=health.features.call,whistle=health.features.whistle,care=false,commerce=health.features.commerce,menus=health.features.menus}})
end)
RegisterCommand('BccStablesStatus',function(source)
    if source~=0 then return end
    print('[bcc-stables] '..json.encode({state=health.state,code=health.code,
        schemaVersion=health.schemaVersion,features=health.features,calls=Stables.HorseController.Status(),purchases=Stables.Checkout and Stables.Checkout.Status() or nil}))
end,true)
CreateThread(function()
    local called,result=pcall(start)
    if not called then result=F.Error('startup_failed','Provider or schema startup failed; no new calls are enabled.') end
    if not result.ok then
        health.state,health.code='failed',result.code
        print('[bcc-stables] startup failed ['..result.code..']: '..result.message)
        return
    end
    health.state,health.features.call,health.features.whistle='ready',true,true
    health.features.menus=Stables.StableMenu~=nil
    health.features.commerce=Stables.Checkout and Stables.Checkout.Enabled() or false
    print('[bcc-stables] Feather horse lifecycle/whistle ready; stable roster ready; purchase checkout follows Config.commerce; care remains disabled.')
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() or resource=='feather-core' or resource=='feather-mysql' or resource=='feather-assets' then
        health.state,health.features.call,health.features.whistle='stopped',false,false
    end
end)
