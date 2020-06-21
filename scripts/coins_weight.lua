--
-- Please see the license.html file included with this distribution for attribution and copyright information.
--

-- Initialization
function onInit()
	if User.isHost() then
		Comm.registerSlashHandler("ccweight", computeCoinsWeight)
	end
end

-- This function recomputes the total weight field
function recomputeTotalWeight(nodeWin)
	local rActor = ActorManager.getActor("pc", nodeWin)
	local nodePC = DB.findNode(rActor['sCreatureNode'])

	local treasure = DB.getValue(nodePC.getPath() .. '.encumbrance.treasure')
	local eqload = DB.getValue(nodePC.getPath() .. '.encumbrance.load')
	
	DB.setValue(nodePC.getPath() .. '.encumbrance.total', 'number', treasure+eqload)
end

-- This function is manualy called with the command /ccweight (DM only)
function computeCoinsWeight(command, parameters)
	if User.isHost() then
		for _,v in pairs(DB.getChildren("partysheet.partyinformation")) do
			local sClass, sRecord = DB.getValue(v, "link")
			Debug.chat( sRecord );
			if sClass == "charsheet" and sRecord then
				local nodePC = DB.findNode(sRecord)
				if nodePC then
					computePCCoinsWeigh(nodePC)
				end
			end
		end
	end
end

-- This function is called when a coin field is called
function onCoinsValueChanged(nodeWin)
	local rActor = ActorManager.getActor("pc", nodeWin )
	local nodePC = DB.findNode(rActor['sCreatureNode'])
	CoinsWeight.computePCCoinsWeigh(nodePC)
end

-- This function really compute the weight of the coins
function computePCCoinsWeigh(nodePC)
	local totalcoins = 0;
	for _,coin in pairs(DB.getChildren(nodePC, "coins")) do
		totalcoins = totalcoins + DB.getValue(coin, "amount", 0)
	end

	if OptionsManager.isOption('COIN_WEIGHT', 'on') then -- if coin weight calculation is enabled
		totalcoins = math.floor(totalcoins / TEGlobals.coinsperunit)
	else
		totalcoins = 0
	end

	DB.setValue(nodePC.getPath() .. '.encumbrance.treasure', 'number', totalcoins)
end