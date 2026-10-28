local english=Locales.en_lang
local extra={
    tack='Horse Tack',saddles='Saddles',saddleNumber='Saddle %d',noSaddle='No Saddle',
    tackPreviewOnly='Preview only. Tack purchasing and saved equipment are not available yet.',
    tackUnavailable='Tack scripts are not loaded. Check the Stables manifest and tack files, then refresh and restart the resource.',
    tackSelectHorse='Select a stored horse in My Horses to preview its tack.',
    tackStorage='Your tack is stored at stables and is available at every stable.',
    tackAttached='Attached to saddle · Piece %d',tackDetach='Remove from Saddle',
    tackAssemblyHelp='Moving or unequipping this saddle keeps its fitted horn and stirrups together. Remove individual parts in their category.',
    tackCategory='Tack Category',saddlecloths='Saddlecloths',stirrups='Stirrups',saddleHorns='Saddle Horns',
    saddleclothNumber='Saddlecloth %d',stirrupNumber='Stirrups %d',saddleHornNumber='Saddle Horn %d',
    noSaddlecloth='No Saddlecloth',saddleDefault='Saddle Default',
    tackSaddleRequired='Equip a saddle on this horse before fitting stirrups or a saddle horn.',
    tackDependents='Unequip the separate stirrups and saddle horn before removing or moving their saddle.',
    tackCollection='Tack Collection',tackBrowse='Browse Tack',tackOwned='My Tack',
    tackOwned_saddle='My Saddles',tackOwned_saddlecloth='My Saddlecloths',
    tackOwned_stirrups='My Stirrups',tackOwned_saddle_horn='My Saddle Horns',
    tackBrowse_saddle='Browse Saddles',tackBrowse_saddlecloth='Browse Saddlecloths',
    tackBrowse_stirrups='Browse Stirrups',tackBrowse_saddle_horn='Browse Saddle Horns',
    tackEquip='Equip',tackUnequip='Unequip',tackBuy='Buy Tack',tackConfirm='Confirm Tack Purchase',
    tackEquip_saddle='Equip Saddle',tackUnequip_saddle='Unequip Saddle',
    tackEquip_saddlecloth='Equip Saddlecloth',tackUnequip_saddlecloth='Unequip Saddlecloth',
    tackEquip_stirrups='Equip Stirrups',tackUnequip_stirrups='Unequip Stirrups',
    tackEquip_saddle_horn='Equip Saddle Horn',tackUnequip_saddle_horn='Unequip Saddle Horn',
    tackBuy_saddle='Buy Saddle',tackConfirm_saddle='Confirm Saddle Purchase',
    tackBuy_saddlecloth='Buy Saddlecloth',tackConfirm_saddlecloth='Confirm Saddlecloth Purchase',
    tackBuy_stirrups='Buy Stirrups',tackConfirm_stirrups='Confirm Stirrup Purchase',
    tackBuy_saddle_horn='Buy Saddle Horn',tackConfirm_saddle_horn='Confirm Saddle Horn Purchase',
    tackOwnedPiece='%s · Piece %d',tackHere='Equipped on this horse',tackElsewhere='Equipped on another horse',
    tackCondition='Condition: %d/%d',tackEquipped='Tack assignment saved.',
    tackPurchased='Tack purchased. It is in My Tack; choose Equip to use it.',
    tackPending='Tack action is pending or changed. Refresh to check your collection; retry the same purchase if needed.',
    tackBuySummary='Buy %s for %s? This piece will belong to your character.',
    tackMoveSummary='Move this tack to %s? A saddle brings its fitted horn and stirrups; any replaced saddle stays in your collection with its parts.',
    tackConflict='Tack ownership or equipment changed. Refresh before trying again.',
    tackInventoryFull='Your stable tack collection is full. Make room before purchasing.',
    brushStay='Brushing your horse. Stay beside it for five seconds.',
    brushApplied='Your horse has been brushed.',brushCancelled='Brushing cancelled. No brush durability was used.',
    brushBroken='Your brush wore out.',brushDurability='Brush durability: %d/%d.',
    brushDismount='Stop leading your horse and have any other rider dismount before brushing.',
    brushUnavailable='The brush changed or is no longer usable. Check it in Inventory.',
    feedStay='Feeding your horse. Stay nearby for five seconds.',
    feedApplied='Food used. Your horse’s saved condition has improved.',feedCancelled='Feeding cancelled. No food was used.',
    feedFull='Your horse is already fully fed.',feedMissing='Carry suitable horse food.',
    feedBeside='Stay near your horse and stop leading or scripted movement before feeding.',feedDisabled='Feeding is disabled.',
    feedNotReady='Your horse is not ready for care. Wait for it to finish being called.',
    feedMoving='Stop following or approach movement before feeding your horse.',
    feedObservation='Your horse’s current state could not be verified. Try again.',
    feedLife='Both you and your horse must be alive for feeding.',
    feedOccupied='Stop leading your horse and have any other rider dismount before feeding.',
    feedTooFar='Your horse is %.1f metres away. Move within 2.5 metres to feed it.',
    feedUninitialized='This horse has no saved condition yet.',
    feedBusy='Horse care is already in progress. Wait for it to finish.',
    feedSaved='Saved condition: health %d, stamina %d (revision %d).',
    feedPending='Horse care is pending or unavailable. Do not use another item; recovery will check the original receipt.',
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
