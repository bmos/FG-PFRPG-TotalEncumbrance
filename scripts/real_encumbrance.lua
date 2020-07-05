--
--	Please see the LICENSE.md file included with this distribution for attribution and copyright information.
--

function onInit()
	if User.isHost() then
		DB.addHandler(DB.getPath('charsheet.*.inventorylist.*.carried'), 'onUpdate', applyPenalties)
		DB.addHandler(DB.getPath('charsheet.*.inventorylist.*.weight'), 'onUpdate', applyPenalties)
		DB.addHandler(DB.getPath('charsheet.*.inventorylist.*.cost'), 'onUpdate', applyPenalties)
		DB.addHandler(DB.getPath('charsheet.*.inventorylist.*.count'), 'onUpdate', applyPenalties)
		DB.addHandler(DB.getPath('charsheet.*.inventorylist.*.isidentified'), 'onUpdate', applyPenalties)
		DB.addHandler(DB.getPath('charsheet.*.inventorylist'), 'onChildDeleted', applyPenalties)
		DB.addHandler(DB.getPath('charsheet.*.hp'), 'onChildUpdate', applyPenalties)
		DB.addHandler(DB.getPath('combattracker.list.*.effects.*.label'), 'onUpdate', applyPenalties)
		DB.addHandler(DB.getPath('combattracker.list.*.effects.*.isactive'), 'onUpdate', applyPenalties)
	end
end

--	Summary: Handles arguments of applyPenalties()
--	Argument: potentially nil node representing carried databasenode on newly carried / equipped / dropped item
--	Return: appropriate object databasenode - should represent node of PC
local function handleApplyPenaltiesArgs(node)
	local nodeChar
	local rActor

	if node.getParent().getName() == 'charsheet' then
		nodeChar = node
	elseif node.getName() == 'inventorylist' then
		nodeChar = node.getParent()
	elseif node.getChild( '...' ).getName() == 'inventorylist' then
		nodeChar = node.getChild( '....' )
	elseif node.getParent().getName() == 'inventorylist' then
		nodeChar = node.getChild( '...' )
	elseif node.getName() == 'hp' then
		nodeChar = node.getParent()
	elseif node.getName() == 'effects' then
		rActor = ActorManager.getActor('ct', node.getParent())
		nodeChar = DB.findNode(rActor['sCreatureNode'])
	end

	if not rActor then
		rActor = ActorManager.getActor('pc', nodeChar)
	end

	return nodeChar, rActor
end

--	Summary: Determine the total bonus to character's speed from effects
--	Argument: rActor containing the PC's charsheet and combattracker nodes
--	Return: total bonus to speed from effects formatted as 'SPEED: n' in the combat tracker
local function getSpeedEffects(nodeChar, rActor)
	if not rActor then
		return 0, false
	end

	local bSpeedHalved = false
	local bSpeedZero = false

	if
		EffectManagerTE.hasEffectCondition(rActor, 'Exhausted')
		or EffectManagerTE.hasEffectCondition(rActor, 'Entangled')
	then
		bSpeedHalved = true
	end

	if
		EffectManagerTE.hasEffectCondition(rActor, 'Grappled')
		or EffectManagerTE.hasEffectCondition(rActor, 'Paralyzed')
		or EffectManagerTE.hasEffectCondition(rActor, 'Petrified')
		or EffectManagerTE.hasEffectCondition(rActor, 'Pinned')
	then
		bSpeedZero = true
	end

	--	Check if the character is disabled (at zero remaining hp)
	if DB.getValue(nodeChar, 'hp.total', 0) == DB.getValue(nodeChar, 'hp.wounds', 0) then
		bSpeedHalved = true
	end

	local nSpeedAdjFromEffects = EffectManagerTE.getEffectsBonus(rActor, 'SPEED', true)

	return nSpeedAdjFromEffects, bSpeedHalved, bSpeedZero
end

---	Convert everything to main currency and drop any non-numerical characters. ('300gp' -> 300) ('30pp' -> 300) ('3sp' -> .3).
local function processItemCost(nodeChar, sItemCost, sItemName)
	if string.match(sItemCost, '%-') then
		local nAnnounce = DB.getValue(nodeChar, 'coins.costerrorannouncer', 1)

		if (OptionsManager.isOption('WARN_COST', 'subtle') or OptionsManager.isOption('WARN_COST', 'on')) and nAnnounce == 1 then
			local sHoldingPc = DB.getValue(nodeChar, 'name', 'unknown player')

			ChatManager.SystemMessage(sHoldingPc..': "' .. sItemName .. '" has an improper value.')
		end

		return 0
	end

	local sTrimmedItemCost = sItemCost:gsub('[^0-9.-]', '')

	if sTrimmedItemCost then
		nTrimmedItemCost = tonumber(sTrimmedItemCost)
		for k,v in pairs(TEGlobals.tDenominations) do
			if string.match(sItemCost, k) then
				return nTrimmedItemCost * v
			end
		end
	end

	return 0
end

---	Returns a string formatted with commas inserted every three digits from the left side of the decimal place
--	@param n The number to be reformatted.
local function formatCurrency(n)
	local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')

	return left..(num:reverse():gsub('(%d%d%d)',TEGlobals.sDigitDivider):reverse())..right
end

---	Calculate total value of all coins, standardized to gp
--	@param nodeChar databasenode of PC within charsheet
--	@return 10 a temporary number to debug with
local function getTotalCoinWealth(nodeChar)
	return 0
end

---	Compile penalties from armor worn by character related to nodeChar
--	This function fills max stat and check penalty tables with appropriate nonzero values from any child items in the inventorylist node
--	@param nodeChar databasenode for the PC within charsheet
--	@param tMaxStat an empty table to be filled with max stat penalties from worn armor and shields
--	@param tEqCheckPenalty an empty table to be filled with check penalties from worn armor and shields
--	@param tSpellFailure an empty table to be filled with spell failure penalties from worn armor and shields
--	@param tSpeed20 an empty table to be filled with the 20-foot speeds of any worn armor and shields
--	@param tSpeed30 an empty table to be filled with the 30-foot speeds of any worn armor and shields
local function rawArmorPenalties(nodeChar, tMaxStat, tEqCheckPenalty, tSpellFailure, tSpeed20, tSpeed30)
	local nItemCarried
	local nItemMaxStat
	local nItemCheckPenalty
	local nItemSpellFailure
	local nItemSpeed20
	local nItemSpeed30
	local nItemIDed
	local nItemCount
	local sItemName
	local sItemType
	local sItemSubtype
	local sItemCost

	local tLtArmor = {}
	local tMedArmor = {}
	local tHeavyArmor = {}
	local tShield = {}

	local nTotalInvVal = 0

	local bClumsyArmor = false

	for _,v in pairs(DB.getChildren(nodeChar, 'inventorylist')) do
		nItemCarried = DB.getValue(v, 'carried', 0)
		nItemMaxStat = DB.getValue(v, 'maxstatbonus', 0)
		nItemCheckPenalty = DB.getValue(v, 'checkpenalty', 0)
		nItemSpellFailure = DB.getValue(v, 'spellfailure', 0)
		nItemSpeed20 = DB.getValue(v, 'speed20', 0)
		nItemSpeed30 = DB.getValue(v, 'speed30', 0)
		nItemIDed = DB.getValue(v, 'isidentified', 1)
		nItemCount = DB.getValue(v, 'count', 1)
		sItemName = string.lower(DB.getValue(v, 'name', ''))
		sItemType = string.lower(DB.getValue(v, 'type', ''))
		sItemSubtype = string.lower(DB.getValue(v, 'subtype', ''))
		sItemCost = string.lower(DB.getValue(v, 'cost', '0 gp'))

		if nItemIDed ~= 0 and sItemCost then
			nItemCost = processItemCost(nodeChar, sItemCost, sItemName)
			nTotalInvVal = nTotalInvVal + (nItemCount * nItemCost)
		end

		if nItemCarried == 2 then
			for _,v in pairs(TEGlobals.tClumsyArmorTypes) do
				if string.find(sItemName, string.lower(v)) then
					bClumsyArmor = true
					break
				end
			end

			if
				nItemMaxStat ~= 0
				or bClumsyArmor
			then
				table.insert(tMaxStat, nItemMaxStat)
			end

			if nItemCheckPenalty ~= 0 then
				table.insert(tEqCheckPenalty, nItemCheckPenalty)
			end

			if nItemSpellFailure ~= 0 then
				table.insert(tSpellFailure, nItemSpellFailure)
			end

			if nItemSpeed20 ~= 0 then
				table.insert(tSpeed20, nItemSpeed20)
			end

			if nItemSpeed30 ~= 0 then
				table.insert(tSpeed30, nItemSpeed30)
			end

			if sItemType == 'armor' then
				if sItemSubtype == 'light' then
					table.insert(tLtArmor, '1')
				elseif sItemSubtype == 'medium' then
					table.insert(tMedArmor, '2')
				elseif sItemSubtype == 'heavy' then
					table.insert(tHeavyArmor, '3')
				end

				if sItemName == 'tower' then
					table.insert(tHeavyArmor, '3')
				elseif
					sItemSubtype == 'shield'
					or sItemSubtype == 'magic shield'
				then
					table.insert(tShield, 'i like turtles')
				end
			end
		end
	end

	DB.setValue(nodeChar, 'coins.costerrorannouncer', 'number', 0)

	if OptionsManager.isOption('CALCULATE_INVENTORY_VALUE', 'on') then
		local sWealthVal = formatCurrency(nTotalInvVal + getTotalCoinWealth(nodeChar))
		local sTotalInvVal = formatCurrency(nTotalInvVal)
		DB.setValue(nodeChar, 'coins.wealthtotal', 'string', 'Wealth Total: '..sWealthVal..' gp')
		DB.setValue(nodeChar, 'coins.inventorytotal', 'string', 'Item Total: '..sTotalInvVal..' gp')
	else
		DB.setValue(nodeChar, 'coins.inventorytotal', 'string', '')
	end

	local nMaxStatFromArmor = -1
	local nCheckPenaltyFromArmor = 0
	local nSpeed20FromArmor = 0
	local nSpeed30FromArmor = 0

	if table.getn(tMaxStat) ~= 0 then
		nMaxStatFromArmor = math.min(unpack(tMaxStat)) -- this would pick the lowest max dex if there is multi-equipped armor
	end

	DB.setValue(nodeChar, 'encumbrance.maxstatbonusfromarmor', 'number', nMaxStatFromArmor ~= nil and nMaxStatFromArmor or -1)

	if table.getn(tEqCheckPenalty) ~= 0 then
		nCheckPenaltyFromArmor = LibTotalEncumbrance.tableSum(tEqCheckPenalty) -- this would sum penalties on multi-equipped armor
	end

	DB.setValue(nodeChar, 'encumbrance.checkpenaltyfromarmor', 'number', nCheckPenaltyFromArmor ~= nil and nCheckPenaltyFromArmor or 0)

	if table.getn(tSpeed20) ~= 0 then
		nSpeed20FromArmor = math.min(unpack(tSpeed20)) -- this gets min speed from multi-equipped armor
	end

	if table.getn(tSpeed30) ~= 0 then
		nSpeed30FromArmor = math.min(unpack(tSpeed30)) -- this gets min speed from multi-equipped armor
	end

	DB.setValue(nodeChar, 'encumbrance.speed20fromarmor', 'number', nSpeed20FromArmor ~= nil and nSpeed20FromArmor or 0)
	DB.setValue(nodeChar, 'encumbrance.speed30fromarmor', 'number', nSpeed30FromArmor ~= nil and nSpeed30FromArmor or 0)

	local nHeavyArmorCount = table.getn(tHeavyArmor)
	local nMedArmorCount = table.getn(tMedArmor)
	local nLtArmorCount = table.getn(tLtArmor)
	local nShieldCount = table.getn(tShield)

	if
		nHeavyArmorCount ~= 0
		and nHeavyArmorCount ~= nil
	then
		DB.setValue(nodeChar, 'encumbrance.armorcategory', 'number', 3)
	elseif
			nMedArmorCount ~= 0
			and nMedArmorCount ~= nil
	then
		DB.setValue(nodeChar, 'encumbrance.armorcategory', 'number', 2)
	elseif
		nLtArmorCount ~= 0
		and nLtArmorCount ~= nil
	then
		DB.setValue(nodeChar, 'encumbrance.armorcategory', 'number', 1)
	else
		DB.setValue(nodeChar, 'encumbrance.armorcategory', 'number', 0)
	end

	if
		nShieldCount ~= 0
		and nShieldCount ~= nil
	then
		DB.setValue(nodeChar, 'encumbrance.shieldequipped', 'number', 1)
	else
		DB.setValue(nodeChar, 'encumbrance.shieldequipped', 'number', 0)
	end
end

--	Summary: Finds the max stat and check penalty penalties based on medium and heavy encumbrance thresholds based on current total encumbrance
--	Argument: number light is medium encumbrance threshold for PC
--	Argument: number medium is heavy encumbrance threshold for PC
--	Argument: number total is current total encumbrance for PC
--	Return: number for max stat penalty based solely on encumbrance (max stat, check penalty, spell failure chance)
--	Return: number for check penalty penalty based solely on encumbrance (max stat, check penalty, spell failure chance)
--	Return: number for spell failure chance based solely on encumbrance (max stat, check penalty, spell failure chance)
local function encumbrancePenalties(nodeChar)
	local nUnit = LibTotalEncumbrance.getEncWeightUnit()
	local light = DB.getValue(nodeChar, 'encumbrance.lightload', 0)
	local medium = DB.getValue(nodeChar, 'encumbrance.mediumload', 0)
	local total = DB.getValue(nodeChar, 'encumbrance.total', 0)

	if total > medium then -- heavy load
		DB.setValue(nodeChar, 'encumbrance.encumbrancelevel', 'number', 3)
		return TEGlobals.nHeavyMaxStat, TEGlobals.nHeavyCheckPenalty, nil
	elseif total > light then -- medium load
		DB.setValue(nodeChar, 'encumbrance.encumbrancelevel', 'number', 2)
		return TEGlobals.nMediumMaxStat, TEGlobals.nMediumCheckPenalty, nil
	else -- light load
		DB.setValue(nodeChar, 'encumbrance.encumbrancelevel', 'number', 1)
		return nil, nil, nil
	end
end

--	Summary: Appends encumbrance-based penalties to respective penalty tables
--	Argument: databasenode nodeChar is the PC node
--	Argument: table holding nonzero max stat penalties from armor / shields
--	Argument: table holding nonzero check penalty penalties from armor / shields
--	Argument: table holding nonzero spell failure penalties from armor / shields
--	Return: nil, however table arguments are directly updated
local function rawEncumbrancePenalties(nodeChar, tMaxStat, tCheckPenalty, tSpellFailure)
local nMaxStatFromEnc, nCheckPenaltyFromEnc, nSpellFailureFromEnc = encumbrancePenalties(nodeChar)

	DB.setValue(nodeChar, 'encumbrance.maxstatbonusfromenc', 'number', nMaxStatFromEnc ~= nil and nMaxStatFromEnc or -1)
	DB.setValue(nodeChar, 'encumbrance.checkpenaltyfromenc', 'number', nCheckPenaltyFromEnc ~= nil and nCheckPenaltyFromEnc or 0)

	if OptionsManager.isOption('WEIGHT_ENCUMBRANCE', 'on') then -- if weight encumbrance penalties are enabled in options
		if nMaxStatFromEnc ~= nil then
			table.insert(tMaxStat, nMaxStatFromEnc)
		end

		if nCheckPenaltyFromEnc ~= nil then
			table.insert(tCheckPenalty, nCheckPenaltyFromEnc)
		end
		--[[ I think we could support spell failure by encumbrance with this pending using a value of a setting in encumbrancePenalties.
		For now, it can be removed

		if nSpellFailureFromEnc ~= nil then
			table.insert(tSpellFailure, nSpellFailureFromEnc)
		end --]]
	end
end

--	Summary: Finds max stat and check penalty based on current enc / armor / shield data
--	Argument: databasenode nodeChar is the PC node
--	Return: number holding armor max stat penalty
--	Return: number holding armor check penalty
--	Return: number holding armor spell failure penalty
local function computePenalties(nodeChar)
	local tMaxStat = {}
	local tEqCheckPenalty = {}
	local tCheckPenalty = {}
	local tSpellFailure = {}
	local tSpeed20 = {}
	local tSpeed30 = {}

	rawArmorPenalties(nodeChar, tMaxStat, tEqCheckPenalty, tSpellFailure, tSpeed20, tSpeed30)

	if table.getn(tEqCheckPenalty) ~= 0 then
		table.insert(tCheckPenalty, LibTotalEncumbrance.tableSum(tEqCheckPenalty)) -- add equipment total to overall table for comparison with encumbrance
	end

	rawEncumbrancePenalties(nodeChar, tMaxStat, tCheckPenalty, tSpellFailure)

	local nMaxStatToSet = -1
	local nCheckPenaltyToSet = 0
	local nSpellFailureToSet = 0
	local nSpeedPenalty20 = 0
	local nSpeedPenalty30 = 0

	if table.getn(tMaxStat) ~= 0 then
		 nMaxStatToSet = math.min(unpack(tMaxStat))
	end

	if table.getn(tCheckPenalty) ~= 0 then
		 nCheckPenaltyToSet = math.min(unpack(tCheckPenalty)) -- this would sum penalties on multi-equipped shields / armor & encumbrance
	end

	if table.getn(tSpellFailure) ~= 0 then
		 nSpellFailureToSet = LibTotalEncumbrance.tableSum(tSpellFailure) -- this would sum penalties on multi-equipped armor

		if nSpellFailureToSet > 100 then
			nSpellFailureToSet = 100
		end
	end

	if table.getn(tSpeed20) ~= 0 then
		 nSpeedPenalty20 = math.min(unpack(tSpeed20))
	end

	if table.getn(tSpeed30) ~= 0 then
		 nSpeedPenalty30 = math.min(unpack(tSpeed30))
	end

	--compute speed including total encumberance speed penalty
	local tEncumbranceSpeed = TEGlobals.tEncumbranceSpeed
	local nSpeedBase = DB.getValue(nodeChar, 'speed.base', 0)
	local nSpeedTableIndex = nSpeedBase / 5

	nSpeedTableIndex = nSpeedTableIndex + 0.5 - (nSpeedTableIndex + 0.5) % 1

	local nSpeedPenaltyFromEnc = 0

	if tEncumbranceSpeed[nSpeedTableIndex] ~= nil then
		nSpeedPenaltyFromEnc = tEncumbranceSpeed[nSpeedTableIndex] - nSpeedBase
	end

	DB.setValue(nodeChar, 'encumbrance.speedfromenc', 'number', nSpeedPenaltyFromEnc ~= nil and nSpeedPenaltyFromEnc or 0)

	local bApplySpeedPenalty = true

	if CharManager.hasTrait(nodeChar, 'Slow and Steady') then
		bApplySpeedPenalty = false
	end

	local nSpeedPenalty = 0

	if bApplySpeedPenalty then
		if
			nSpeedBase >= 30
			and nSpeedPenalty30 > 0
		then
			nSpeedPenalty = nSpeedPenalty30 - 30
		elseif
			nSpeedBase < 30
			and nSpeedPenalty20 > 0
		then
			nSpeedPenalty = nSpeedPenalty20 - 20
		end
	end

	local nEncumbranceLevel = DB.getValue(nodeChar, 'encumbrance.encumbrancelevel', 0)

	if -- if weight encumbrance penalties are enabled in options and player is encumbered
		OptionsManager.isOption('WEIGHT_ENCUMBRANCE', 'on')
		and nEncumbranceLevel > 1
	then
		if
			nSpeedPenalty ~= 0
			and nSpeedPenaltyFromEnc ~= 0
		then
			nSpeedPenalty = math.min(nSpeedPenaltyFromEnc, nSpeedPenalty)
		elseif nSpeedPenaltyFromEnc then
			nSpeedPenalty = nSpeedPenaltyFromEnc
		end
	end

	return nMaxStatToSet, nCheckPenaltyToSet, nSpellFailureToSet, nSpeedPenalty, nSpeedBase
end

--	Summary: Recomputes penalties and updates max stat and check penalty
--	Arguments: node - node of 'carried' when called from handler
function applyPenalties(node)
	local nodeChar, rActor = handleApplyPenaltiesArgs(node)

	local nMaxStatToSet, nCheckPenaltyToSet, nSpellFailureToSet, nSpeedPenalty, nSpeedBase = computePenalties(nodeChar)

	--	enable armor encumbrance when needed
	if
		nMaxStatToSet ~= -1
		or nCheckPenaltyToSet ~= 0
		or nSpellFailureToSet ~= 0
	then
		DB.setValue(nodeChar, 'encumbrance.armormaxstatbonusactive', 'number', 0)
		DB.setValue(nodeChar, 'encumbrance.armormaxstatbonusactive', 'number', 1)
	else
		DB.setValue(nodeChar, 'encumbrance.armormaxstatbonusactive', 'number', 1)
		DB.setValue(nodeChar, 'encumbrance.armormaxstatbonusactive', 'number', 0)
	end

	DB.setValue(nodeChar, 'encumbrance.armormaxstatbonus', 'number', nMaxStatToSet)
	DB.setValue(nodeChar, 'encumbrance.armorcheckpenalty', 'number', nCheckPenaltyToSet)
	DB.setValue(nodeChar, 'encumbrance.armorspellfailure', 'number', nSpellFailureToSet)

	DB.setValue(nodeChar, 'speed.armor', 'number', nSpeedPenalty)

	local nSpeedAdjFromEffects, bSpeedHalved, bSpeedZero = getSpeedEffects(nodeChar, rActor)

	--	recalculate total speed from all inputs
	local nSpeedToSet = nSpeedBase + nSpeedPenalty + nSpeedAdjFromEffects + DB.getValue(nodeChar, 'speed.misc', 0) + DB.getValue(nodeChar, 'speed.temporary', 0)

	--	round to nearest 5 (or 1 as specified in options list - SPEED_INCREMENT)
--	if OptionsManager.isOption('SPEED_INCREMENT', '5') then
		nSpeedToSet = ((nSpeedToSet / 5) + 0.5 - ((nSpeedToSet / 5) + 0.5) % 1) * 5
--	else
--		nSpeedToSet = nSpeedToSet + 0.5 - (nSpeedToSet + 0.5) % 1
--	end

	if bSpeedZero then
		nSpeedToSet = 0
	elseif bSpeedHalved then
		nSpeedToSet = nSpeedToSet / 2
	end

	DB.setValue(nodeChar, 'speed.final', 'number', nSpeedToSet)
	DB.setValue(nodeChar, 'speed.total', 'number', nSpeedToSet)
end
