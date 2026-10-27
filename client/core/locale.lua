local english=Locales.en_lang
local extra={
    catalog='Horse Catalog',browseCatalog='Browse Horses',catalogEmpty='No horses are available to browse.',
    coatPosition='%d of %d',catalogPrice='Catalog Price',cashPrice='$%.2f',goldPrice='%.2f gold',priceChoice='%s or %s',free='Free',
    browsingOnly='Browsing only. Purchases are currently unavailable.',previewUnavailable='This horse preview could not be loaded.',
    purchase='Purchase Horse',reviewPurchase='Review Purchase',confirmPurchase='Confirm Purchase',purchasing='Processing…',
    sex='Sex',male='Male',female='Female',currency='Currency',cash='Cash',gold='Gold',cancel='Cancel',
    purchaseSummary='Buy %s (%s - %s, %s) for %s?',
    purchaseFunds='Insufficient funds. No purchase was completed.',purchaseLimit='Your stable is full.',
    purchaseExpired='The quote expired or changed. Refresh to review the price again.',
    purchaseRestricted='This horse or stable is not available for public purchase.',purchaseDisabled='Purchasing is disabled.',
    purchasePending='Your purchase is still processing. Retry Confirm with this purchase; do not start another.',
    purchaseFailed='The outcome could not be confirmed. Retry this purchase or reopen your stable to check ownership.',
    purchaseComplete='Horse purchased. It is ready in My Horses.',
    title='My Horses',selected='Selected',stored='Stored',active='Active',
    empty='No horses on this page.',refresh='Refresh',close='Close',
    takeOut='Take Out',select='Select Horse',back='Back',next='Next Page',
    unavailableStatus='Unavailable',
    details='Stats & Details',breed='Breed',coat='Coat',ownership='Ownership',owned='Owned by you',
    selection='Selection',notSelected='Not selected',status='Status',
    savedCondition='Saved Condition',savedHealth='Health Core',savedStamina='Stamina Core',
    notRecorded='Not recorded',baseStats='Catalog Base Performance',unknown='Unknown',
    speed='Speed',acceleration='Acceleration',handling='Handling',health='Health',stamina='Stamina',
    rename='Rename Horse',horseName='Horse Name',namePlaceholder='Enter a name',saveName='Save Name',savingName='Saving…',
    nameHelp='Use 1–100 characters. Names cannot contain control characters, <, > or ~.',
    nameInvalid='Enter a valid horse name.',
    horseActions='Horse Actions',horseInformation='Horse Information',
    nameConflict='This horse changed. Refresh before saving again.',
    nameDenied='Renaming is not permitted by the server.',
    nameFailed='The name could not be confirmed. Refresh to check the saved name before retrying.',
    nameSaved='Horse renamed.',
    rotateLeft='Rotate Left',rotateRight='Rotate Right',
    opening='Preparing your stable; any active horse must be safely stored first.',
    unavailable='Stable action unavailable: %s',
}
for key,value in pairs(extra) do english['menu_'..key]=value end
local codes={en_lang='en_us',fr_lang='fr_fr',it_lang='it',pl_lang='pl',pt_lang='pt',ro_lang='ro',th_lang='th'}
local function register()
    for key,locale in pairs(codes) do
        local translations={}
        for name,value in pairs(Locales[key] or {}) do translations['stables_'..name]=value end
        exports['feather-core']:RegisterLocale(locale,translations)
    end
end
register()
function Stables.Client.Text(key,...)
    local args=table.pack(...)
    local ok,result=pcall(function()
        return exports['feather-core']:TranslateLocale(0,'stables_'..key,table.unpack(args,1,args.n))
    end)
    -- Missing files/keys are text errors inside Core's successful envelope.
    if ok and type(result)=='table' and result.ok and type(result.value)=='string'
        and not result.value:match('^Translation %[') and not result.value:match('^Locale %[') then return result.value end
    return string.format(english[key] or key,table.unpack(args,1,args.n))
end
AddEventHandler('onClientResourceStart',function(resource) if resource=='feather-core' then register() end end)
