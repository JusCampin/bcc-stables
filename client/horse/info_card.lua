-- Credit: cfx discord user notdeadjustexpired (aka: i just stole a kia) for original file
-- Edits by BCC
local ANIMAL_INFO_UIAPP_HASH <const> = joaat('SHOP_BROWSING')
local GAME_EVENT_TRIGGER_HASH <const> = joaat('EVENT_PLAYER_PROMPT_TRIGGERED')
local GET_EVENT_DATA_NATIVE <const> = 0x57EC5FA4D4D6AFCA
local INFO_PROMPT_TYPE <const> = 35
local INFO_PROMPT_ACTION <const> = 16
local INFO_EVENT_DATA_SIZE <const> = 10
local HORSE_UI_ENTRY <const> = -649639953
local ANIMAL_UI_ENTRY <const> = -1645363952
local STAT_MIN <const> = 0
local STAT_MAX <const> = 10

-- Data for the info card UI ("m_" just for intellisense sake to make my life a bit easier).
local m_InfoCardData = {
	-- If we're showing an info card currently
	bShowing = false,
	-- Which entity we're showing the info card currently for
	iEntity = 0,
	-- Model of the entity.
	hEntityModel = 0,
	-- Data binding containers stored so we can remove them later on cleanup.
	tDataBinding = {}
}

---Listens for a game event
---@param iEventGroup integer Which group/channel of events we should listen to
---@param hWhichEvent integer Hash of the event we are specifically looking for
---@param iEventDataSize integer Data size of the event. See the github link above.
---@return integer|nil promptType
---@return integer|nil promptAction
---@return integer|nil targetEntity
---@return integer|nil promptState
local function ListenForPromptEvent(iEventGroup, hWhichEvent, iEventDataSize)
	local iNumEvents = GetNumberOfEvents(iEventGroup)
	if iNumEvents > 0 then
		for i = 0, iNumEvents - 1 do
			local hEventName = GetEventAtIndex(iEventGroup, i)

			if hEventName == hWhichEvent then
				local EventDataStruct = CreateEventDataBuffer(iEventDataSize * 8)

				local bDataExists = Citizen.InvokeNative(GET_EVENT_DATA_NATIVE, iEventGroup, i, EventDataStruct:Buffer(), iEventDataSize)
				if bDataExists then
					return EventDataStruct:GetInt32(0),      -- Prompt type
						EventDataStruct:GetInt32(8),          -- Prompt action
						EventDataStruct:GetInt32(16),         -- Target entity
						EventDataStruct:GetInt32(24)          -- Prompt state
				else
					DBG:Warning('Unable to read animal info prompt event data.')
					return nil
				end
			end
		end
	end

	return nil
end

AddTextEntry('COAT_NONE', _U('other'))

local HORSE_COAT_BY_MODEL <const> = {
		[`A_C_HORSE_AMERICANPAINT_GREYOVERO`]                 = 'COAT_GREYOVERO',
        [`A_C_HORSE_AMERICANPAINT_OVERO`]                     = 'COAT_OVERO',
        [`A_C_HORSE_AMERICANPAINT_SPLASHEDWHITE`]             = 'COAT_SPLASHWHITE',
        [`A_C_HORSE_AMERICANPAINT_TOBIANO`]                   = 'COAT_TOB',
		[`A_C_HORSE_AMERICANSTANDARDBRED_BLACK`]              = 'COAT_BLACK',
		[`A_C_HORSE_AMERICANSTANDARDBRED_BUCKSKIN`]           = 'COAT_BUCKSKIN',
        [`A_C_HORSE_AMERICANSTANDARDBRED_LIGHTBUCKSKIN`]      = 'COAT_LIGHTBUCKSKIN',
		[`A_C_HORSE_AMERICANSTANDARDBRED_PALOMINODAPPLE`]     = 'COAT_PALDAP',
		[`A_C_HORSE_AMERICANSTANDARDBRED_SILVERTAILBUCKSKIN`] = 'COAT_SILVERTAILBUCKSKIN',
		[`A_C_HORSE_ANDALUSIAN_DARKBAY`]                      = 'COAT_DARKBAY',
        [`A_C_HORSE_ANDALUSIAN_PERLINO`]                      = 'COAT_PERLINO',
		[`A_C_HORSE_ANDALUSIAN_ROSEGRAY`]                     = 'COAT_ROSEGREY',
        [`A_C_HORSE_APPALOOSA_BLACKSNOWFLAKE`]                = 'COAT_BLACKSNO',
		[`A_C_HORSE_APPALOOSA_BLANKET`]                       = 'COAT_BLANKET',
        [`A_C_HORSE_APPALOOSA_BROWNLEOPARD`]                  = 'COAT_BRLEOP',
        [`A_C_HORSE_APPALOOSA_FEWSPOTTED_PC`]                 = 'COAT_FEWSPOTTED',
        [`A_C_HORSE_APPALOOSA_LEOPARD`]                       = 'COAT_LEOP',
		[`A_C_HORSE_APPALOOSA_LEOPARDBLANKET`]                = 'COAT_LEOPBLANKET',
		[`A_C_HORSE_ARABIAN_BLACK`]                           = 'COAT_BLACK',
        [`A_C_HORSE_ARABIAN_GREY`]                            = 'COAT_GREY',
        [`A_C_HORSE_ARABIAN_REDCHESTNUT`]                     = 'COAT_REDCH',
		[`A_C_HORSE_ARABIAN_REDCHESTNUT_PC`]                  = 'COAT_REDCH',
		[`A_C_HORSE_ARABIAN_ROSEGREYBAY`]                     = 'COAT_ROSEGREYBAY',
		[`A_C_HORSE_ARABIAN_WARPEDBRINDLE_PC`]                = 'COAT_WARPEDBRINDLE',
		[`A_C_HORSE_ARABIAN_WHITE`]                           = 'COAT_WHITE',
		[`A_C_HORSE_ARDENNES_BAYROAN`]                        = 'COAT_BAYR',
        [`A_C_HORSE_ARDENNES_IRONGREYROAN`]                   = 'COAT_IRONGREYR',
		[`A_C_HORSE_ARDENNES_STRAWBERRYROAN`]                 = 'COAT_STRAWR',
		[`A_C_HORSE_BELGIAN_BLONDCHESTNUT`]                   = 'COAT_BLONDCH',
		[`A_C_HORSE_BELGIAN_MEALYCHESTNUT`]                   = 'COAT_MEALYCH',
        [`A_C_HORSE_BRETON_GRULLODUN`]                        = 'COAT_GRULDUN',
        [`A_C_HORSE_BRETON_MEALYDAPPLEBAY`]                   = 'COAT_MEALYDAPBAY',
        [`A_C_HORSE_BRETON_REDROAN`]                          = 'COAT_REDR',
        [`A_C_HORSE_BRETON_SEALBROWN`]                        = 'COAT_SEALBR',
        [`A_C_HORSE_BRETON_SORREL`]                           = 'COAT_SORREL',
        [`A_C_HORSE_BRETON_STEELGREY`]                        = 'COAT_STEELGREY',
        [`A_C_HORSE_CRIOLLO_BLUEROANOVERO`]                   = 'COAT_BLUEROANOVERO',
        [`A_C_HORSE_CRIOLLO_DUN`]                             = 'COAT_DUN',
        [`A_C_HORSE_CRIOLLO_BAYBRINDLE`]                      = 'COAT_BAYBRINDLE',
        [`A_C_HORSE_CRIOLLO_SORRELOVERO`]                     = 'COAT_SORRELOVERO',
        [`A_C_HORSE_CRIOLLO_MARBLESABINO`]                    = 'COAT_MARBLESABINO',
        [`A_C_HORSE_CRIOLLO_BAYFRAMEOVERO`]                   = 'COAT_BAYFRAMEOVERO',
        [`A_C_HORSE_DUTCHWARMBLOOD_CHOCOLATEROAN`]            = 'COAT_CHOCR',
		[`A_C_HORSE_DUTCHWARMBLOOD_SEALBROWN`]                = 'COAT_SEALBR',
		[`A_C_HORSE_DUTCHWARMBLOOD_SOOTYBUCKSKIN`]            = 'COAT_SOOTYBUCKSKIN',
        [`A_C_HORSE_GYPSYCOB_PALOMINOBLAGDON`]                = 'COAT_PALBLAG',
        [`A_C_HORSE_GYPSYCOB_PIEBALD`]                        = 'COAT_PIE',
        [`A_C_HORSE_GYPSYCOB_SKEWBALD`]                       = 'COAT_SKEWBALD',
        [`A_C_HORSE_GYPSYCOB_SPLASHEDBAY`]                    = 'COAT_SPLASHBAY',
        [`A_C_HORSE_GYPSYCOB_SPLASHEDPIEBALD`]                = 'COAT_SPLASHPIE',
        [`A_C_HORSE_GYPSYCOB_WHITEBLAGDON`]                   = 'COAT_WHITEBLAG',
        [`A_C_HORSE_HUNGARIANHALFBRED_DARKDAPPLEGREY`]        = 'COAT_DAPDARKGREY',
		[`A_C_HORSE_HUNGARIANHALFBRED_FLAXENCHESTNUT`]        = 'COAT_FLAXCH',
        [`A_C_HORSE_HUNGARIANHALFBRED_LIVERCHESTNUT`]         = 'COAT_LIVERCH',
		[`A_C_HORSE_HUNGARIANHALFBRED_PIEBALDTOBIANO`]        = 'COAT_PIETOB',
		[`A_C_HORSE_KENTUCKYSADDLE_BLACK`]                    = 'COAT_BLACK',
		[`A_C_HORSE_KENTUCKYSADDLE_BUTTERMILKBUCKSKIN_PC`]    = 'COAT_BUTTERMILKBUCKSKIN',
		[`A_C_HORSE_KENTUCKYSADDLE_CHESTNUTPINTO`]            = 'COAT_CHPIN',
		[`A_C_HORSE_KENTUCKYSADDLE_GREY`]                     = 'COAT_GREY',
		[`A_C_HORSE_KENTUCKYSADDLE_SILVERBAY`]                = 'COAT_SILVERBAY',
        [`A_C_HORSE_KLADRUBER_BLACK`]                         = 'COAT_BLACK',
        [`A_C_HORSE_KLADRUBER_CREMELLO`]                      = 'COAT_CREM',
        [`A_C_HORSE_KLADRUBER_DAPPLEROSEGREY`]                = 'COAT_DAPROSEGREY',
        [`A_C_HORSE_KLADRUBER_GREY`]                          = 'COAT_GREY',
        [`A_C_HORSE_KLADRUBER_SILVER`]                        = 'COAT_SILVER',
        [`A_C_HORSE_KLADRUBER_WHITE`]                         = 'COAT_WHITE',
		[`A_C_HORSE_MISSOURIFOXTROTTER_AMBERCHAMPAGNE`]       = 'COAT_AMBCHA',
        [`A_C_HORSE_MISSOURIFOXTROTTER_BLACKTOVERO`]          = 'COAT_BLACKTOVERO',
        [`A_C_HORSE_MISSOURIFOXTROTTER_BLUEROAN`]             = 'COAT_BLUER',
        [`A_C_HORSE_MISSOURIFOXTROTTER_BUCKSKINBRINDLE`]      = 'COAT_BUCKSKINBRINDLE',
        [`A_C_HORSE_MISSOURIFOXTROTTER_DAPPLEGREY`]           = 'COAT_DAPGREY',
        [`A_C_HORSE_MISSOURIFOXTROTTER_SABLECHAMPAGNE`]       = 'COAT_SABLECHAMP',
		[`A_C_HORSE_MISSOURIFOXTROTTER_SILVERDAPPLEPINTO`]    = 'COAT_SILVERDAPPINT',
		[`A_C_HORSE_MORGAN_BAY`]                              = 'COAT_BAY',
		[`A_C_HORSE_MORGAN_BAYROAN`]                          = 'COAT_BAYR',
		[`A_C_HORSE_MORGAN_FLAXENCHESTNUT`]                   = 'COAT_FLAXCH',
		[`A_C_HORSE_MORGAN_LIVERCHESTNUT_PC`]                 = 'COAT_LIVERCH',
		[`A_C_HORSE_MORGAN_PALOMINO`]                         = 'COAT_PAL',
        [`A_C_HORSE_MUSTANG_BLACKOVERO`]                      = 'COAT_BLACKOVERO',
        [`A_C_HORSE_MUSTANG_BUCKSKIN`]                        = 'COAT_BUCKSKIN',
        [`A_C_HORSE_MUSTANG_CHESTNUTTOVERO`]                  = 'COAT_CHTOVERO',
        [`A_C_HORSE_MUSTANG_GOLDENDUN`]                       = 'COAT_GOLDENDUN',
		[`A_C_HORSE_MUSTANG_GRULLODUN`]                       = 'COAT_GRULDUN',
        [`A_C_HORSE_MUSTANG_REDDUNOVERO`]                     = 'COAT_REDDUNOVERO',
        [`A_C_HORSE_MUSTANG_TIGERSTRIPEDBAY`]                 = 'COAT_TIGSTRBAY',
		[`A_C_HORSE_MUSTANG_WILDBAY`]                         = 'COAT_WILDBAY',
		[`A_C_HORSE_NOKOTA_BLUEROAN`]                         = 'COAT_BLUER',
        [`A_C_HORSE_NOKOTA_REVERSEDAPPLEROAN`]                = 'COAT_REVDAPR',
		[`A_C_HORSE_NOKOTA_WHITEROAN`]                        = 'COAT_WHITER',
        [`A_C_HORSE_NORFOLKROADSTER_BLACK`]                   = 'COAT_BLACK',
        [`A_C_HORSE_NORFOLKROADSTER_DAPPLEDBUCKSKIN`]         = 'COAT_DAPBUCKSKIN',
        [`A_C_HORSE_NORFOLKROADSTER_PIEBALDROAN`]             = 'COAT_PIEBALDROAN',
        [`A_C_HORSE_NORFOLKROADSTER_ROSEGREY`]                = 'COAT_ROSEGREY',
        [`A_C_HORSE_NORFOLKROADSTER_SPECKLEDGREY`]            = 'COAT_SPECKLEDGREY',
        [`A_C_HORSE_NORFOLKROADSTER_SPOTTEDTRICOLOR`]         = 'COAT_SPOTTEDTRICOLOR',
		[`A_C_HORSE_SHIRE_DARKBAY`]                           = 'COAT_DARKBAY',
		[`A_C_HORSE_SHIRE_LIGHTGREY`]                         = 'COAT_LGREY',
        [`A_C_HORSE_SHIRE_RAVENBLACK`]                        = 'COAT_RAVBLACK',
        [`A_C_HORSE_SUFFOLKPUNCH_REDCHESTNUT`]                = 'coat_redch',
		[`A_C_HORSE_SUFFOLKPUNCH_SORREL`]                     = 'COAT_SORREL',
		[`A_C_HORSE_TENNESSEEWALKER_BLACKRABICANO`]           = 'COAT_BLACKRAB',
		[`A_C_HORSE_TENNESSEEWALKER_CHESTNUT`]                = 'COAT_CH',
		[`A_C_HORSE_TENNESSEEWALKER_DAPPLEBAY`]               = 'COAT_DAPBAY',
        [`A_C_HORSE_TENNESSEEWALKER_FLAXENROAN`]              = 'COAT_FLAXR',
		[`A_C_HORSE_TENNESSEEWALKER_GOLDPALOMINO_PC`]         = 'COAT_GOLDPALOMINO',
        [`A_C_HORSE_TENNESSEEWALKER_MAHOGANYBAY`]             = 'COAT_MAHBAY',
		[`A_C_HORSE_TENNESSEEWALKER_REDROAN`]                 = 'COAT_REDR',
		[`A_C_HORSE_THOROUGHBRED_BLACKCHESTNUT`]              = 'COAT_BLACKCH',
		[`A_C_HORSE_THOROUGHBRED_BLOODBAY`]                   = 'COAT_BLBAY',
		[`A_C_HORSE_THOROUGHBRED_BRINDLE`]                    = 'COAT_BRINDLE',
		[`A_C_HORSE_THOROUGHBRED_DAPPLEGREY`]                 = 'COAT_DAPGREY',
		[`A_C_HORSE_THOROUGHBRED_REVERSEDAPPLEBLACK`]         = 'COAT_REVDAPBLACK',
        [`A_C_HORSE_TURKOMAN_BLACK`]                          = 'COAT_BLACK',
        [`A_C_HORSE_TURKOMAN_CHESTNUT`]                       = 'COAT_CH',
		[`A_C_HORSE_TURKOMAN_DARKBAY`]                        = 'COAT_DARKBAY',
		[`A_C_HORSE_TURKOMAN_GOLD`]                           = 'COAT_GOLD',
        [`A_C_HORSE_TURKOMAN_GREY`]                           = 'COAT_GREY',
        [`A_C_HORSE_TURKOMAN_PERLINO`]                        = 'COAT_PERLINO',
		[`A_C_HORSE_TURKOMAN_SILVER`]                         = 'COAT_SILVER',
        [`A_C_HORSE_BUELL_WARVETS`]                           = 'COAT_CHEMGOLD',
        [`A_C_HORSE_EAGLEFLIES`]                              = 'COAT_SPLASHWHITE',
        [`A_C_HORSE_GANG_BILL`]                               = 'COAT_BROWNR',
        [`A_C_HORSE_GANG_CHARLES`]                            = 'COAT_GREYSNOWCAPSPOTTED',
        [`A_C_HORSE_GANG_CHARLES_ENDLESSSUMMER`]              = 'COAT_GREYROANSABINO',
        [`A_C_HORSE_GANG_DUTCH`]                              = 'COAT_ALBINO',
		[`A_C_HORSE_GANG_HOSEA`]                              = 'COAT_SILVER',
        [`A_C_HORSE_GANG_JAVIER`]                             = 'COAT_GREYOVERO',
        [`A_C_HORSE_GANG_JOHN`]                               = 'COAT_SILVERDARKBAY',
        [`A_C_HORSE_GANG_KAREN`]                              = 'COAT_SMOKYBLACK',
        [`A_C_HORSE_GANG_KIERAN`]                             = 'COAT_FLAXR',
        [`A_C_HORSE_GANG_LENNY`]                              = 'COAT_LIGHTPALOMINO',
        [`A_C_HORSE_GANG_MICAH`]                              = 'COAT_BLACK',
        [`A_C_HORSE_GANG_SADIE`]                              = 'COAT_GOLDDAP',
        [`A_C_HORSE_GANG_SADIE_ENDLESSSUMMER`]                = 'COAT_DARKBAYROAN',
        [`A_C_HORSE_GANG_SEAN`]                               = 'COAT_SILVERTAILBUCKSKIN',
        [`A_C_HORSE_GANG_TRELAWNEY`]                          = 'COAT_BRLEOP',
        [`A_C_HORSE_GANG_UNCLE`]                              = 'COAT_SABINO',
        [`A_C_HORSE_GANG_UNCLE_ENDLESSSUMMER`]                = 'COAT_FEWSPOTBUCKSKIN',
        [`A_C_HORSE_JOHN_ENDLESSSUMMER`]                      = 'COAT_SEALBR',
        [`A_C_HORSE_WINTER02_01`]                             = 'COAT_SILVERBAY',
        [`A_C_DONKEY_01`]                                     = 'BREED_DONKEY',
        [`A_C_HORSE_MP_MANGY_BACKUP`]                         = 'COAT_MANGY', -- or COAT_NONE ? In latest game builds
		[`A_C_HORSEMULE_01`]                                  = 'BREED_MULE',
		[`A_C_HORSEMULEPAINTED_01`]                           = 'BREED_MULE_PAINTED',
		[`A_C_HORSE_MURFREEBROOD_MANGE_03`]                   = 'COAT_BLACKRAB',
		[`A_C_HORSE_MURFREEBROOD_MANGE_02`]                   = 'COAT_BLUER',
		[`A_C_HORSE_MURFREEBROOD_MANGE_01`]                   = 'COAT_BLANKET',
}

---Returns a text label representing a horse's coat
---@param hModel integer Model hash of the horse
---@return string Coat
local function GetHorseCoatFromModel(hModel)
	return HORSE_COAT_BY_MODEL[hModel] or ''
end

local function ClampValue(value, min, max)
    return math.max(min, math.min(value, max))
end

local function AddStatBindings(infoBox, prefix, baseRank, bonusRank, capacityBonus)
	DatabindingAddDataInt(infoBox, prefix .. 'Value', baseRank)
	DatabindingAddDataInt(infoBox, prefix .. 'MinValue', STAT_MIN)
	DatabindingAddDataInt(infoBox, prefix .. 'MaxValue', STAT_MAX)
	DatabindingAddDataInt(infoBox, prefix .. 'EquipmentValue', ClampValue(baseRank + bonusRank, STAT_MIN, STAT_MAX))
	DatabindingAddDataInt(infoBox, prefix .. 'EquipmentMinValue', STAT_MIN)
	DatabindingAddDataInt(infoBox, prefix .. 'EquipmentMaxValue', STAT_MAX)
	DatabindingAddDataInt(infoBox, prefix .. 'CapacityValue', ClampValue(baseRank + capacityBonus, STAT_MIN, STAT_MAX))
	DatabindingAddDataInt(infoBox, prefix .. 'CapacityMinValue', STAT_MIN)
	DatabindingAddDataInt(infoBox, prefix .. 'CapacityMaxValue', STAT_MAX)
end

local function GetHandlingLabel(entity)
	local handlingRank = GetAttributeRank(entity, 4)

	if handlingRank >= 6 then
		return 'HORSE_HANDLING_ELITE'
	elseif handlingRank >= 4 then
		return 'HORSE_HANDLING_RACE'
	elseif handlingRank >= 2 then
		return 'HORSE_HANDLING_STANDARD'
	end

	return 'HORSE_HANDLING_HEAVY'
end

---Launches the horse details UI app if the entity is a horse
---@param iEntity integer ID of the horse entity
---@param hModel integer Model hash of the horse entity
local function ShowHorseDetailsOnCard(iEntity, hModel)
	local iInfoBox = DatabindingAddDataContainerFromPath('', 'InfoBox') -- Add the info box container
	m_InfoCardData.tDataBinding.iInfoBox = iInfoBox -- Save data for the info box container for future use. This data is deleted on cleanup.

	DatabindingAddDataString(iInfoBox, 'itemLabel', GetStringFromHashKey(GetDiscoverableNameHashAndTypeForEntity(iEntity))) -- Sets the title of the card.

	DatabindingAddDataBool(iInfoBox, 'showHorseStats', true)
	DatabindingAddDataBool(iInfoBox, 'isVisible', true)

	DatabindingAddDataString(iInfoBox, 'HorseCoat', GetHorseCoatFromModel(hModel))

	local speedBaseRank = GetAttributeBaseRank(iEntity, 5) + 1
	AddStatBindings(iInfoBox, 'HorseSpeed', speedBaseRank, GetAttributeBonusRank(iEntity, 5), 3)

	local accelerationBaseRank = GetAttributeBaseRank(iEntity, 6) + 1
	AddStatBindings(iInfoBox, 'HorseAcc', accelerationBaseRank, GetAttributeBonusRank(iEntity, 6), 2)

	DatabindingAddDataString(iInfoBox, 'HorseHandling', GetHandlingLabel(iEntity))
end

---Sets information for an animal that is not a horse
---@param iEntity integer
local function ShowAnimalDetailsOnCard(iEntity)
	local iInfoBox = DatabindingAddDataContainerFromPath('', 'InfoBox') -- Add info box container
	m_InfoCardData.tDataBinding.iInfoBox = iInfoBox -- Store in memory for cleanup/later usage
	DatabindingAddDataBool(iInfoBox, 'isVisible', true) -- Make box visible
	-- Set title. Ideally this would be done with VarString but i couldn't get it to work for some reason.
	DatabindingAddDataString(iInfoBox, 'itemLabel', GetStringFromHashKey(GetDiscoverableNameHashAndTypeForEntity(iEntity)))
	DatabindingAddDataHash(iInfoBox, 'itemDescription', CompendiumGetShortDescriptionFromPed(iEntity)) -- Set description
end

---Activates an info card for an animal. Do note that the animal must be focused with rightclick or binoculars!
---@param b boolean true activates the card and false clears it
---@param iEntity integer ID of the entity.
local function SetAnimalInfoCardActive(b, iEntity)
	if b and not m_InfoCardData.bShowing then
		if not DoesEntityExist(iEntity) or not IsEntityAPed(iEntity) then -- Check if the entity is valid
			DBG:Warning('Unable to show animal info card for an invalid entity.')
			return
		end

		local hModel = GetEntityModel(iEntity)
		local bHorse = IsThisModelAHorse(hModel) == 1
		local iEntry = bHorse and HORSE_UI_ENTRY or ANIMAL_UI_ENTRY

		-- Ensure no UI is active.
		if CanLaunchUiappByHashWithEntry(ANIMAL_INFO_UIAPP_HASH, iEntry) ~= 1 then
			DBG:Warning('Unable to launch animal info card while another UI app is active.')
			if IsUiappActiveByHash(ANIMAL_INFO_UIAPP_HASH) ~= 1 then
				return
			end
		end

		-- If Animal Info uiapp isn't active, launch it
		if IsUiappActiveByHash(ANIMAL_INFO_UIAPP_HASH) ~= 1 then
			LaunchUiappByHashWithEntry(ANIMAL_INFO_UIAPP_HASH, iEntry)
		end

		-- If this is a horse, show horse details, if not then show animal details
		if bHorse then
			ShowHorseDetailsOnCard(iEntity, hModel)
		else
			ShowAnimalDetailsOnCard(iEntity)
		end

		SetShowInfoCard(PlayerId(), true) -- Changes Show Info prompt to Hide Info
		-- Set some script data.
		m_InfoCardData.iEntity = iEntity
		m_InfoCardData.bShowing = true
		m_InfoCardData.hEntityModel = hModel
	elseif not b and m_InfoCardData.bShowing then
		-- Release the data binding from memory.
		for _, v in pairs(m_InfoCardData.tDataBinding) do
			DatabindingRemoveDataEntry(v)
		end
		m_InfoCardData.tDataBinding = {}

		m_InfoCardData.bShowing = false

		if IsUiappActiveByHash(ANIMAL_INFO_UIAPP_HASH) == 1 then
			CloseUiappByHash(ANIMAL_INFO_UIAPP_HASH)
		end

		SetShowInfoCard(PlayerId(), false) -- Changes Hide Info prompt to Show Info
		m_InfoCardData.iEntity = 0
		m_InfoCardData.hEntityModel = 0
	end
end

---Should be called once the resource stops.
function CleanupAnimalInfoHud()
	SetAnimalInfoCardActive(false, 0)
end

---Should be called every frame.
function UpdateAnimalInfoThisFrame()
	local iPlayerID = PlayerId() -- Our player ID

	if m_InfoCardData.bShowing then -- If the card UI is showing
		-- This code block handles changing animals with binoculars
		local _, iEntity  = GetPlayerTargetEntity(iPlayerID)
		local hEntityModel = DoesEntityExist(iEntity) and GetEntityModel(iEntity) or 0
		local bIsModelDifferent = hEntityModel ~= m_InfoCardData.hEntityModel

		-- We looked at a different entity
		if m_InfoCardData.iEntity ~= iEntity then
			if bIsModelDifferent then -- We're looking at a different animal, so let's close the card
				SetAnimalInfoCardActive(false, iEntity)
			elseif not bIsModelDifferent then -- The animal is the same, let's just update the entity in the card data table
				m_InfoCardData.iEntity = iEntity
				m_InfoCardData.hEntityModel = hEntityModel
			end
		end
	end

	-- Returns if this ui prompt is active https://i.imgur.com/z4qY6XT.png
	-- We check if this is 1 because the native returns 0 if this is false and lua thinks that 'not 0' is false
	if GetIsPlayerUiPromptActive(iPlayerID, INFO_PROMPT_TYPE) == 1 then
		local promptType, promptAction, entity, promptState = ListenForPromptEvent(
			0,
			GAME_EVENT_TRIGGER_HASH,
			INFO_EVENT_DATA_SIZE
		)

		if promptType == INFO_PROMPT_TYPE
			and promptAction == INFO_PROMPT_ACTION
			and promptState == 0
			and type(entity) == 'number'
		then
			SetAnimalInfoCardActive(not m_InfoCardData.bShowing, entity)
		end
	else
		if m_InfoCardData.bShowing then
			SetAnimalInfoCardActive(false, 0) -- close the card when we stop focusing on an entity
		end
	end
end

CreateThread(function()
	while true do
		Wait(0)
		UpdateAnimalInfoThisFrame()
	end
end)
