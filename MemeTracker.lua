local RAID_CHANNEL				= "RAID"
local WARN_CHANNEL				= "RAID_WARNING"
local OFFICER_CHANNEL			= "OFFICER"

MemeTracker_Title = "MemeTracker"
MemeTracker_Version = "3.2.2"

MemeTracker_RecipientTable = {}
MemeTracker_LootHistoryTable = {}
MemeTracker_LootHistoryTable_Filtered = {}
MemeTracker_VoteTable = {}
MemeTracker_OverviewTable = {}
MemeTracker_LootHistoryTable_Temp = {}
my_vote = nil

sort_direction = "ascending"
recipient_sort_field = "player_name"
recipient_sort_id = 1

loot_sort_direction = "ascending"
loot_sort_field = "time_stamp";

version_request_in_progress = false

debug_enabled = false

local session_queue = {}
local MT_MESSAGE_PREFIX		= "MemeTracker"

MemeTracker_color_common = "ffffffff"
MemeTracker_color_uncommon = "ff1eff00"
MemeTracker_color_rare = "ff0070dd"
MemeTracker_color_epic = "ffa335ee"
MemeTracker_color_legendary = "ffff8000"

local default_rgb = {["r"]=0.83, ["g"]=0.83, ["b"]=0.83}
local LootHistoryEditorEntry = {}

local DE_BANK = "DE-Bank"

local playerClassSlotNames = {
	{slot = "???", 				    name = "???"},
	{slot = "Druid",				name = "druid"},
	{slot = "Hunter", 				name = "hunter"},
	{slot = "Mage", 				name = "mage"},
	{slot = "Paladin", 				name = "paladin"},
	{slot = "Priest", 				name = "priest"},
	{slot = "Rogue", 				name = "rogue"},
	{slot = "Warlock", 				name = "warlock"},
	{slot = "Warrior", 				name = "warrior"},
}

local lootHistoryUseCase = {
	[1] = "MS",
	[2] = "OS",
	[3] = "RES",
	[4] = DE_BANK
}

local class_colors = {
	["Hunter"] =  {["r"] = 0.67, ["g"] = 0.83, ["b"] = 0.45},
	["Mage"] =    {["r"] = 0.41, ["g"] = 0.80, ["b"] = 0.94},
	["Paladin"] = {["r"] = 0.96, ["g"] = 0.55, ["b"] = 0.73},
	["Priest"] =  {["r"] = 1.00, ["g"] = 1.00, ["b"] = 1.00},
	["Rogue"] =   {["r"] = 1.00, ["g"] = 0.96, ["b"] = 0.41},
	["Shaman"] =  {["r"] = 0.00, ["g"] = 0.44, ["b"] = 0.80},
	["Warlock"] = {["r"] = 0.58, ["g"] = 0.51, ["b"] = 0.79},
	["Warrior"] = {["r"] = 0.78, ["g"] = 0.61, ["b"] = 0.43},
	["Druid"] =	  {["r"] = 1.00, ["g"] = 0.49, ["b"] = 0.04},
	["Unknown"] = {["r"] = 0.83, ["g"] = 0.68, ["b"] = 0.04},
	["???"] =     {["r"] = 0.83, ["g"] = 0.68, ["b"] = 0.04},
	[""] =        {["r"] = 0.83, ["g"] = 0.68, ["b"] = 0.04}
}
local class_default_color

local DEFAULT_VOTES_NEEDED = 5


local string_gmatch = lua51 and string.gmatch or string.gfind

local function echo(tag, msg)
	if msg then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffa335ee<MemeTracker> |r"..tag.." : "..msg));
	else
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffa335ee<MemeTracker> |r"..tag));
	end
end

local function debug(tag, msg)
	if debug_enabled then
		if msg then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffEE3580<MemeTracker Debug> |r"..tag.." : "..msg));
		else
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffEE3580<MemeTracker Debug> |r"..tag));
		end
	end
end

TimeSinceLastUpdate=0
TimeSinceLastSessionStart = 0
local version_request_time_limit = 2;
function MemeTracker_OnUpdate(elapsed)
	TimeSinceLastUpdate = TimeSinceLastUpdate + elapsed;
	TimeSinceLastSessionStart = TimeSinceLastSessionStart + elapsed

	if version_request_in_progress then
		--debug("TimeSinceLastUpdate", TimeSinceLastUpdate)
  		if (TimeSinceLastUpdate > version_request_time_limit) then
  			MemeTracker_Version_End();
   			TimeSinceLastUpdate = 0;
   		end
	else
  		TimeSinceLastUpdate = 0;
	end

	if not MemeTracker_OverviewTable.in_session and getn(session_queue) > 0 then
		if TimeSinceLastSessionStart > 1 then
				item_link = table.remove(session_queue, 1)
				MemeTracker_Broadcast_Session_Start(item_link)
				TimeSinceLastSessionStart = 0
		end
	else
		TimeSinceLastSessionStart = 0
	end
end

local function isLeader()
	local lootmethod, masterlooterPartyID, _ = GetLootMethod()
	if lootmethod == "master" then
		return masterlooterPartyID == 0
	else 
		return IsRaidLeader()
	end 
end

local function getPlayerGuildRank(player_name)
	local guild_rank_name = nil
	local guild_rank_rank_id = -1
	local entry_key = 1
	while guild_rank_name == nil do
		name, rank, rank_id, _ = GetGuildRosterInfo(entry_key);
		if name == player_name then
			guild_rank_name = rank
			guild_rank_rank_id = rank_rank_id

		elseif name == nil then
			guild_rank_name = "Unknown"
			guild_rank_id = 100
		end

		entry_key = entry_key + 1
	end

	local dict = {}
	dict["name"] = guild_rank_name
	dict["id"] = guild_rank_rank_id
	return dict
end

local function getPlayerClass(player_name)

	if player_name == DE_BANK then
		return ""
	end

	for raid_id = 1,40 do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(raid_id)
		if name == player_name then
			return class
		end
	end

	return "???"
end

local function isOfficer()
	local guild_name, guild_rank, _ = GetGuildInfo("player")
	if isLeader() then
		return true
	elseif guild_name == "meme team" and (guild_rank == "Class Oracle" or guild_rank == "Officer" or guild_rank == "Suprememe Leadr" or guild_rank == "Loot Council") then
		return true
	else
		return false
	end
end

-- echo 

local function echo_leader(tag, msg)
	if isLeader() then
		if msg then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffa335ee<MemeTracker> |r"..tag.." : "..msg));
		else
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffa335ee<MemeTracker> |r"..tag));
		end
	end
end



local function addonEcho(msg)
	SendAddonMessage(MT_MESSAGE_PREFIX, msg, "RAID")
end

local function addonEcho_leader(msg)
	if isLeader() then
		addonEcho(msg)
	end
end

local function rwEcho(msg)
	SendChatMessage(msg, WARN_CHANNEL);
end

local function raidEcho(msg)
	SendChatMessage(msg, RAID_CHANNEL);
end

local function officerEcho(msg)
	SendChatMessage(msg, OFFICER_CHANNEL)
end

local function leaderRaidEcho(msg)
	if isLeader() then
		raidEcho(msg)
	end
end

-- String/List helpers

local function getKeysSortedByKey(tbl)
	a = {}
    for n in pairs(tbl) do table.insert(a, n) end
    table.sort(a)
    return a
end

local function getKeysSortedByValue(tbl, sortFunction)
  local keys = {}
  for key in pairs(tbl) do
    table.insert(keys, key)
  end

  table.sort(keys, function(a, b)
    return sortFunction(tbl[a], tbl[b])
  end)

  return keys
end

local function firstToUpper(name)
	if name then
		return string.gsub(name, "^%l",string.upper)
	else 
		return ""
	end
end

local function String_Contains(full_string, partical_string)
 	local _,_,res = string.find(string.lower(full_string) , ".*(" .. string.lower(partical_string) .. ").*")
 	return res ~= nil
end 

local function String_Starts_With(full_string, partical_string)
   return string.sub(string.lower(full_string),1,string.len(partical_string))==string.lower(partical_string)
end

local function Parse_String_List(string_list)
	local list = {}
	for name in string_gmatch(string_list, "[^,%s]+") do
		table.insert(list, name)
	end
	return list
end

local function getItemLinkQuality(item_color) 
	if item_color == MemeTracker_color_common then
		item_quality = "common"
	elseif item_color == MemeTracker_color_uncommon then
		item_quality = "uncommon"
	elseif item_color == MemeTracker_color_rare then
		item_quality = "rare"
	elseif item_color == MemeTracker_color_epic then
		item_quality = "epic"
	elseif item_color == MemeTracker_color_legendary then
		item_quality = "legendary"
	else
		item_quality = "common"
	end
	return item_quality
end

local function getItemLinkColor(item_quality)
	if item_quality == "common" then
		item_color = MemeTracker_color_common
	elseif item_quality == "uncommon" then
		item_color = MemeTracker_color_uncommon
	elseif item_quality == "rare" then
		item_color = MemeTracker_color_rare
	elseif item_quality == "epic" then
		item_color = MemeTracker_color_epic
	elseif item_quality == "legendary" then
		item_color = MemeTracker_color_legendary
	else 
		item_color = MemeTracker_color_common
	end
	return item_color
end

local function parseItemLink(item_link)

	local _,_, find_item_link, item_color, item_id, item_name = string.find(item_link , "(|c(%w+).*item:(%d+):.*%[(.*)%]|h|r)")
	local item_quality = getItemLinkQuality(item_color)
	if find_item_link then
		return find_item_link, item_quality, item_id, item_name, item_color
	else
		return nil, MemeTracker_color_common, nil, item_link
	end
end

local function buildItemLink(item_id, item_name, item_color, item_quality)
	if item_color == nil then
		item_color = getItemLinkColor(item_quality)
	end

	local item_link = "|c" .. item_color .. "|Hitem:" .. item_id .. ":0:0:0|h[" .. item_name .. "]|h|r"

	return item_link
end

local function List_Contains(list, target_value, starts_with)
	for entry_key, value in ipairs(list) do
		local start, _ = string.find(target_value, value )
		if starts_with then
			if String_Starts_With(target_value, value) then
				return true
			end
		else
			if String_Contains(target_value, value) then
				return true
			end
		end
	end
	return false
end

-- Session functions

local function Session_Clear()
	my_vote = nil
	MemeTracker_RecipientTable = {}
	MemeTracker_VoteTable = {}

	FauxScrollFrame_SetOffset(MemeTracker_RecipientListScrollFrame, 0);
	getglobal("MemeTracker_RecipientListScrollFrameScrollBar"):SetValue(0);


	MemeTracker_RecipientListScrollFrame_Update()
end

local function VoteTable_Tally()
	local tally_table = {}

	for sender, player_name in MemeTracker_VoteTable do
		local voters = tally_table[player_name]
		if (voters == nil) then
			voters = {}
		end
		table.insert(voters, sender)
		tally_table[player_name] = voters
	end

	return tally_table
end

local function VoteTable_Add(player_name, sender)
	MemeTracker_VoteTable[sender] = player_name
end

-- Recipient Table


function GetTargetDate(start_time, days_ago)
	if start_time == nil then
		start_time = time()
	end

	local last_time = 1483228800

	if days_ago ~= 0 then
		last_time = start_time - (days_ago * 86400)	
	end

	local last_date = date( "%y-%m-%d", last_time )
	return last_date
end

function GetPlayerLootCount_DaysAgo(player_name, start_date, days_ago)
	local loot_count = 0
	local target_date = GetTargetDate(start_date, days_ago)
	for i,n in pairs(MemeTracker_LootHistoryTable) do
		if (n.player_name == player_name) and (n.date >= target_date) then
			loot_count = loot_count + 1
		end
	end

	return loot_count
end

local week_list = {
	[1] = 1,
	[2] = 2,
	[3] = 4,
	[4] = 6,
	[5] = 0
}

function GetPlayerLootCount(player_name)
	start_date = time()

	loot_count_table = {}
	for i,n in ipairs(week_list) do
		loot_count_table[i] = GetPlayerLootCount_DaysAgo(player_name, start_date, 7*n)
	end

	return loot_count_table
end

local function Session_CanEnd()
	local is_auto_close = (getglobal("MemeTracker_SessionAutoEndCheckButton"):GetChecked() == 1)
	if MemeTracker_OverviewTable.in_session == true and is_auto_close then
		vote_total = {}
		votes = 0

		for entry_key, entry in MemeTracker_RecipientTable do
			if entry.votes > 0 then
				votes = votes +  entry.votes
				vote_total[entry.player_name] = entry.votes
			end
		end
		local sortedKeys = getKeysSortedByValue(vote_total, function(a, b) return a > b end)

		if getn(sortedKeys) >= 1 then
			max_votes = vote_total[sortedKeys[1]]
		else
			max_votes = 0
		end

		if getn(sortedKeys) >= 2 then
			runner_up_votes = vote_total[sortedKeys[2]]
		else
			runner_up_votes = 0
		end

		if (votes >= MemeTracker_OverviewTable.votes_needed) then
			if runner_up_votes == max_votes then
				echo("Session cannot end while tied!")
				return false
			else
				return true
			end
		elseif(max_votes > MemeTracker_OverviewTable.votes_needed/2) then
			return true
		else
			return false
		end
	else
		return false
	end
end

local function RecipientTable_Sort_Function_LootCount(sort_direction, start_id, a, b)
	if  a.loot_count_table[recipient_sort_id] ~= b.loot_count_table[recipient_sort_id] then
		if sort_direction == "ascending" then
			return a.loot_count_table[recipient_sort_id] < b.loot_count_table[recipient_sort_id]
		else
			return a.loot_count_table[recipient_sort_id] > b.loot_count_table[recipient_sort_id]
		end
	else
		for entry_key = 1,5 do 
			if  a.loot_count_table[entry_key] ~= b.loot_count_table[entry_key] then
				if sort_direction == "ascending" then
					return a.loot_count_table[entry_key] < b.loot_count_table[entry_key]
				else
					return a.loot_count_table[entry_key] > b.loot_count_table[entry_key]
				end
			end
		end
	end

	if sort_direction == "ascending" then
		return a.player_name < b.player_name 
	else
		return a.player_name > b.player_name 
	end
end

local function RecipientTable_Sort_Function(sort_direction, recipient_sort_field, a, b)
	if recipient_sort_field then
		if sort_direction == "ascending" then
			if recipient_sort_field == "loot_count_table" then
				return RecipientTable_Sort_Function_LootCount(sort_direction, recipient_sort_id, a, b)
			else
				if ( a[recipient_sort_field] == b[recipient_sort_field]) then
					return a.player_name < b.player_name
				else
					return a[recipient_sort_field] < b[recipient_sort_field]
				end
			end
		else
			if recipient_sort_field == "loot_count_table" then
				return RecipientTable_Sort_Function_LootCount(sort_direction, recipient_sort_id, a, b)
			else
				if ( a[recipient_sort_field] == b[recipient_sort_field]) then
					return a.player_name > b.player_name
				else
					return a[recipient_sort_field] > b[recipient_sort_field]
				end
			end
		end
	else
		return a.player_name < b.player_name
	end
end

local function RecipientTable_Sort()
	table.sort(MemeTracker_RecipientTable, function(a,b) return RecipientTable_Sort_Function(sort_direction, recipient_sort_field, a, b) end)
end

local function RecipientTable_UpdateVotes()

	local tally_table = VoteTable_Tally()
	local vote_total = {}
	local total_votes = 0
	for entry_key, entry in MemeTracker_RecipientTable do
		local voters = tally_table[entry.player_name]
		local votes = 0;
		local voters_text = "";
		if voters ~= nil then
			votes = getn(voters);
			voters_text = table.concat(voters, ", ");
		end
		total_votes = total_votes + votes
		entry.votes = votes
		entry.voters_text = voters_text
	end

	local all_voters = {}
	for sender, player in MemeTracker_VoteTable do
		table.insert(all_voters, sender)
		end

	MemeTracker_OverviewTable.votes = getn(all_voters)
	MemeTracker_OverviewTable.voters = all_voters

	if Session_CanEnd() and isLeader() and (MemeTracker_OverviewTable.in_session == true) then
		MemeTracker_Broadcast_Session_End()
	end
end

local function RecipientTable_GetPlayerentry_key(player_name)
	local entry_key = 1;
	while MemeTracker_RecipientTable[entry_key] do
		if player_name == MemeTracker_RecipientTable[entry_key].player_name then
			return entry_key;
		end
		entry_key = entry_key + 1;
	end
	return nil;
end

local function RecipientTable_Add(player_name, item_link)
	local entry_key = RecipientTable_GetPlayerentry_key(player_name)
	local player_name = firstToUpper(player_name)

	if (entry_key == nil) then
		debug("RecipientTable_Add entry_key nil")
		entry_key = getn(MemeTracker_RecipientTable) + 1
		MemeTracker_RecipientTable[entry_key] = {}
		MemeTracker_RecipientTable[entry_key].voters = {}
	end

	debug("RecipientTable_Add entry_key", entry_key)

	local guild_rank = getPlayerGuildRank(player_name)
	local _, _, item_id, item_name = parseItemLink(item_link)
	MemeTracker_RecipientTable[entry_key].player_class = getPlayerClass(player_name)
	MemeTracker_RecipientTable[entry_key].player_guild_rank = guild_rank.name
	MemeTracker_RecipientTable[entry_key].player_guild_rank_id = guild_rank.entry_key
	MemeTracker_RecipientTable[entry_key].player_name = player_name
	MemeTracker_RecipientTable[entry_key].item_id = item_id
	MemeTracker_RecipientTable[entry_key].item_link = item_link
	MemeTracker_RecipientTable[entry_key].item_name = item_name

	MemeTracker_RecipientTable[entry_key].loot_count_table = GetPlayerLootCount(player_name)

 	local attendance = MemeTracker_Attendance[player_name]

	if attendance then
		last_4_weeks = tonumber(MemeTracker_Attendance[player_name].last_4_weeks)
		last_2_weeks = tonumber(MemeTracker_Attendance[player_name].last_2_weeks)
	else
		last_4_weeks = 0
		last_2_weeks = 0
	end

	MemeTracker_RecipientTable[entry_key].attendance_last_4_weeks = last_4_weeks
	MemeTracker_RecipientTable[entry_key].attendance_last_2_weeks = last_2_weeks

	MemeTracker_RecipientListScrollFrame_Update()
end

function MemeTracker_RecipientListScrollFrame_Update()
	if not MemeTracker_RecipientTable then
		MemeTracker_RecipientTable = {}
	end

	RecipientTable_UpdateVotes()
	RecipientTable_Sort()

	getglobal("MemeTracker_OverviewButtonTextItemName"):SetText(MemeTracker_OverviewTable.item_link)

	if isOfficer() or isLeader() then
		getglobal("MemeTracker_OverviewButtonTextVotes"):Show()
		getglobal("MemeTracker_OverviewButtonTextVoters"):Show()

		if MemeTracker_OverviewTable.votes and MemeTracker_OverviewTable.votes_needed then
			getglobal("MemeTracker_OverviewButtonTextVotes"):SetText(MemeTracker_OverviewTable.votes .. "/" .. MemeTracker_OverviewTable.votes_needed)
		end
		getglobal("MemeTracker_OverviewButtonTextVoters"):SetText(table.concat(MemeTracker_OverviewTable.voters, ", "))
	else
		getglobal("MemeTracker_OverviewButtonTextVotes"):Hide()
		getglobal("MemeTracker_OverviewButtonTextVoters"):Hide()
	end

	if (MemeTracker_OverviewTable.in_session == true) then
		getglobal("MemeTracker_SessionEndButton"):Enable()
		getglobal("MemeTracker_SessionDEButton"):Enable()
		getglobal("MemeTracker_SessionCancelButton"):Enable()

		getglobal("MemeTracker_OverviewButtonTextVotes"):SetTextColor(.83,.68,.04,1)
		getglobal("MemeTracker_OverviewButtonTextVoters"):SetTextColor(.83,.68,.04,1)
		getglobal("MemeTracker_OverviewButtonTextItemName"):SetTextColor(.83,.68,.04,1)
	else
		getglobal("MemeTracker_SessionEndButton"):Disable()
		getglobal("MemeTracker_SessionDEButton"):Disable()
		getglobal("MemeTracker_SessionCancelButton"):Disable()

		getglobal("MemeTracker_OverviewButtonTextVotes"):SetTextColor(.5,.5,.5,1)
		getglobal("MemeTracker_OverviewButtonTextVoters"):SetTextColor(.5,.5,.5,1)
		getglobal("MemeTracker_OverviewButtonTextItemName"):SetTextColor(.5,.5,.5,1)
	end

	local max_lines = getn(MemeTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MemeTracker_RecipientListScrollFrame, max_lines, 15, 25)
	for line = 1,15 do

		local entry_key = line + offset

		if entry_key <= max_lines then
			local recipient = MemeTracker_RecipientTable[entry_key]

			if MemeTracker_OverviewTable.in_session then
				rgb = class_colors[recipient.player_class]
				if not rgb then
					rgb = default_rgb
				end
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerName"):SetTextColor(rgb.r,rgb.g,rgb.b,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerGuildRank"):SetTextColor(.83,.68,.04,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetTextColor(.83,.68,.04,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):SetTextColor(.83,.68,.04,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast2Weeks"):SetTextColor(.83,.68,.04,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):SetTextColor(.83,.68,.04,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):SetTextColor(.83,.68,.04,1)
				for i,n in ipairs(recipient.loot_count_table) do
					getglobal("MemeTracker_RecipientListItem"..line.."TextLootCount"..i):SetTextColor(.83,.68,.04,1)
				end
			else
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerName"):SetTextColor(.5,.5,.5,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerGuildRank"):SetTextColor(.5,.5,.5,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetTextColor(.5,.5,.5,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):SetTextColor(.5,.5,.5,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast2Weeks"):SetTextColor(.5,.5,.5,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):SetTextColor(.5,.5,.5,1)
				getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):SetTextColor(.5,.5,.5,1)
				for i,n in ipairs(recipient.loot_count_table) do
					getglobal("MemeTracker_RecipientListItem"..line.."TextLootCount"..i):SetTextColor(.5,.5,.5,1)
				end
			end

			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerName"):SetText(recipient.player_name)
			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerGuildRank"):SetText(recipient.player_guild_rank)
			getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetText(recipient.item_link)

			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):SetText(recipient.attendance_last_4_weeks .. "%")
			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast2Weeks"):SetText(recipient.attendance_last_2_weeks .. "%")

			for i,n in ipairs(recipient.loot_count_table) do
				getglobal("MemeTracker_RecipientListItem"..line.."TextLootCount"..i):SetText(n)
			end

			if isOfficer() or isLeader() then
				getglobal("MemeTracker_RecipientListVoteBox"..line):Show()
				getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):Show()
				getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):Show()

				getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):SetText(recipient.votes)
				getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):SetText(recipient.voters_text)

			else
				getglobal("MemeTracker_RecipientListVoteBox"..line):Hide()
				getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):Hide()
				getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):Hide()
			end

			if my_vote ~= nil and my_vote == recipient.player_name then
				getglobal("MemeTracker_RecipientListVoteBox"..line):SetChecked(true)
			else
				getglobal("MemeTracker_RecipientListVoteBox"..line):SetChecked(false)
			end

			getglobal("MemeTracker_RecipientListItem"..line):Show()

			if (MemeTracker_OverviewTable.in_session == true) then
				getglobal("MemeTracker_RecipientListVoteBox"..line):Enable()
			else
				getglobal("MemeTracker_RecipientListVoteBox"..line):Disable()
			end

		 else
			getglobal("MemeTracker_RecipientListItem"..line):Hide()
			getglobal("MemeTracker_RecipientListVoteBox"..line):Hide()
		 end
	end

	MemeTracker_Mode_Update()
end

-- Attendance Table

function AttendanceTable_Build()
	if not MemeTracker_Attendance then
		MemeTracker_Attendance = {}
	end
end
-- Loot History

local function LootHistory_Sort_Function(loot_sort_direction, loot_sort_field, a, b)

	if loot_sort_field then

		if ( a[loot_sort_field] == b[loot_sort_field]) then
			if loot_sort_field ~= "time_stamp"  then
				if loot_sort_field ~= "player_name" then
					return LootHistory_Sort_Function(loot_sort_direction, "player_name", a, b)
				else
					return LootHistory_Sort_Function(loot_sort_direction, "time_stamp", a, b)          
				end
			end
		end

		if loot_sort_direction == "ascending" then
			return a[loot_sort_field] < b[loot_sort_field]
		else
			return a[loot_sort_field] > b[loot_sort_field]
		end
	else
		return a.time_stamp < b.time_stamp
	end
end

local function LootHistory_Sort()
	table.sort(MemeTracker_LootHistoryTable_Filtered, function(a,b) return LootHistory_Sort_Function(loot_sort_direction, loot_sort_field, a, b) end)
end

local function LootHistoryTable_Build()
	MemeTracker_LootHistoryTable = {}

	if not MemeTrackerDB then
		MemeTrackerDB = {}
	end

	for entry_key in MemeTrackerDB do
		MemeTracker_LootHistoryTable[entry_key] = {}
		local item_link = MemeTrackerDB[entry_key].item_link
		local item_name =  MemeTrackerDB[entry_key].item_name
		local item_quality = MemeTrackerDB[entry_key].item_quality
		local item_color = MemeTrackerDB[entry_key].item_color
		local item_id = MemeTrackerDB[entry_key].item_id


		if item_link == nil then
			item_link = buildItemLink(item_id,  item_name, item_color, item_quality)
		end

		MemeTracker_LootHistoryTable[entry_key].entry_key    = entry_key
		MemeTracker_LootHistoryTable[entry_key].time_stamp   = MemeTrackerDB[entry_key].time_stamp
		MemeTracker_LootHistoryTable[entry_key].date         = MemeTrackerDB[entry_key].date
		MemeTracker_LootHistoryTable[entry_key].use_case     = MemeTrackerDB[entry_key].use_case
		MemeTracker_LootHistoryTable[entry_key].raid_name    = MemeTrackerDB[entry_key].raid_name
		MemeTracker_LootHistoryTable[entry_key].item_name    = item_name
		MemeTracker_LootHistoryTable[entry_key].item_id      = item_id
		MemeTracker_LootHistoryTable[entry_key].item_quality = item_quality
		MemeTracker_LootHistoryTable[entry_key].item_link    = item_link
		MemeTracker_LootHistoryTable[entry_key].player_name  = firstToUpper(MemeTrackerDB[entry_key].player_name)
		MemeTracker_LootHistoryTable[entry_key].player_class = firstToUpper(MemeTrackerDB[entry_key].player_class)
	end

	MemeTracker_LootHistoryScrollFrame_Update();
end

local function LootHistoryTable_UpdateEntry(entry)
	if not entry then
		debug("null entry update")
		return
	end

	entry_key = entry["entry_key"]

	if MemeTrackerDB[entry_key] == nil then
		MemeTrackerDB[entry_key] = {}
	end

	MemeTrackerDB[entry_key] = entry
end

local function LootHistoryTable_BuildEntry(item_link, player_name)
	local time_stamp = date("%y-%m-%d %H:%M:%S")
	local date = date("%y-%m-%d")
	local item_link, item_quality, item_id, item_name = parseItemLink(item_link)

	if item_link == nil then
		debug("cant parse this link")
		return
	end

	local localized_class, _, _ = getPlayerClass(player_name);
	local zone_name = GetRealZoneText();

	entry = {}
	entry["player_name"] = player_name
	entry["date"] = date
	entry["use_case"] = lootHistoryUseCase[1]
	entry["raid_name"] = zone_name
	entry["time_stamp"] = time_stamp
	entry["player_class"] = localized_class
	entry["item_quality"] = item_quality
	entry["item_link"] = item_link
	entry["item_name"] = item_name
	entry["item_id"] = item_id

	entry["entry_key"] = string.format("%s_%s",time(), item_id)

	return entry
end

local function LootHistoryTable_AddEntry(item_link, player_name)
	entry = LootHistoryTable_BuildEntry(item_link, player_name)
	LootHistoryTable_UpdateEntry(entry)
	LootHistoryTable_Build()
	return entry
end

local function LootHistory_Filter()
	MemeTracker_LootHistoryTable_Filtered = {}
	for k,v in pairs(MemeTracker_LootHistoryTable) do
		if searchString and searchString ~= "" then
			local search_list = Parse_String_List(searchString)
			if (List_Contains(search_list, v.player_name, true) == true) or (List_Contains(search_list, v.player_class, true) == true) or (List_Contains(search_list, v.item_name, false) == true)then
				table.insert(MemeTracker_LootHistoryTable_Filtered, v)
			end
		else
			table.insert(MemeTracker_LootHistoryTable_Filtered, v)
		end
	end
end

function MemeTracker_LootHistoryScrollFrame_Update()

	if not MemeTracker_LootHistoryTable then
		MemeTracker_LootHistoryTable = {};
	end

	LootHistory_Filter()
	LootHistory_Sort()

	local maxlines = getn(MemeTracker_LootHistoryTable_Filtered)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_LootHistoryScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MemeTracker_LootHistoryScrollFrame, maxlines, 15, 25)

	for line=1,15 do
		 lineplusoffset = line + offset
		 if lineplusoffset <= maxlines then
		 	local player_class =  MemeTracker_LootHistoryTable_Filtered[lineplusoffset].player_class

		 	if player_class == nil then
		 		player_class = ""
		 	end

		 	local rgb = class_colors[player_class]
		 	if not rgb then
				rgb = default_rgb
			end
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextPlayerName"):SetTextColor(rgb.r,rgb.g,rgb.b,1)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextPlayerName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].player_name)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextItemName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].item_link)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextRaidName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].raid_name)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextDate"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].date)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextUseCase"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].use_case)
			getglobal("MemeTracker_LootHistoryListItem"..line):Show()
		 else
			getglobal("MemeTracker_LootHistoryListItem"..line):Hide()
		 end
	end
end

-- Session Commands

function MemeTracker_Session_List()
	for k,v in pairs(session_queue) do
		echo(k, v)
	end
	-- body
end

function MemeTracker_Session_Queue(item_link)

	if not session_queue then
		session_queue = {}
	end

	if item_link == nil or item_link=="" then
		echo("Cannot start a session without loot")
	elseif not (MemeTracker_OverviewTable.in_session==true) and getn(session_queue) == 0 then
		MemeTracker_Broadcast_Session_Start(item_link)
	else
		echo("A session for "..item_link.." has been queued")
		table.insert(session_queue, item_link)
	end
end

function MemeTracker_Session_Dequeue(entry_key)

	if not session_queue or not entry_key or tonumber(entry_key) < 1 or tonumber(entry_key) > getn(session_queue) then
		echo("Please provide a valid queue list entry_key")
	else
		item_link = table.remove(session_queue, entry_key)
		echo("Removed queued session for ", item_link)
	end
	-- body
end

function MemeTracker_Broadcast_Message_Echo(message)
	if message then
		addonEcho_leader("TX_MESSAGE_ECHO#".. message .."#");
	end
end

function MemeTracker_Handle_Message_Echo(message, sender)
	echo(message)
end

-- Recipient Broadcast

function MemeTracker_Broadcast_RecipientTable_Add(player_name, item_link)
	if MemeTracker_OverviewTable.in_session == true then
		local player_name = firstToUpper(player_name)
		local player_class = getPlayerClass(player_name)

		if player_class == "???" then
			--echo("Error adding player " .. player_name .. ". Player must be in the raid.")
			--return
		end

		addonEcho_leader("TX_ENTRY_ADD#".. string.format("%s/%s", player_name, item_link) .."#");
	else
		echo_leader("No session in progress")
	end
end

function MemeTracker_Handle_RecipientTable_Add(message, sender)
	local _, _, player_name, item_link = string.find(message, "([^/]*)/(.*)")

	RecipientTable_Add(player_name, item_link)
end

-- Vote Broadcast

function MemeTracker_Broadcast_VoteTable_Add(player_name)
	if MemeTracker_OverviewTable.in_session == true then
		if player_name then
			addonEcho("TX_VOTE_ADD#".. string.format("%s", player_name) .."#");
		else
			addonEcho("TX_VOTE_ADD#".. "#");
		end
	else
		echo("No session in progress")
	end
end

function MemeTracker_Handle_VoteTable_Add(message, sender)
	local _, _, player_name = string.find(message, "([^/]+)")

	VoteTable_Add(player_name, sender)
	MemeTracker_RecipientListScrollFrame_Update()
end

-- Session Start Broadcast

function MemeTracker_Broadcast_Session_Start(item_link)
	if MemeTracker_OverviewTable.in_session == true then
		echo_leader("A session for "..MemeTracker_OverviewTable.item_link.." is in progress")
	elseif item_link == nil or item_link=="" then
		echo_leader("Cannot start a session without loot")
	else
		addonEcho_leader("TX_SESSION_START#"..item_link.."#");
	end
end

function MemeTracker_Handle_Session_Start(message, sender)
	local _, _, item_link, votes_needed = string.find(message, "([^/]+%]|h|r)%s*(.*)")

	local _, _, item_message, votes_needed = string.find(message, "(.*)%s+(%d+)")
	if item_message == nil then
		item_message = message
		votes_needed = DEFAULT_VOTES_NEEDED
	else
		votes_needed = tonumber(votes_needed)
	end

	local _, _, item_link, notes = string.find(item_message, "([^/]+%]|h|r)%s*(.*)")
	if item_link == nil then
		item_link = item_message
	end

	local item_link, _, item_id, item_name = parseItemLink(item_message)

	MemeTracker_OverviewTable = {}
	MemeTracker_OverviewTable.in_session = true
	MemeTracker_OverviewTable.item_id = item_id
	MemeTracker_OverviewTable.item_link = item_message
	MemeTracker_OverviewTable.item_name = item_name
	MemeTracker_OverviewTable.votes_needed = votes_needed
	MemeTracker_OverviewTable.votes = 0
	MemeTracker_OverviewTable.voters = ""

	Session_Clear()

	echo("Session started : ".. item_message)

	local sample_itemlink = buildItemLink(8952, "Your Current Item", MemeTracker_color_common, nil) 

	leaderRaidEcho("Session started : ".. item_message)
	leaderRaidEcho("To be considered for the item type in raid chat \"mt "..sample_itemlink.."\"")
end

-- Session End Broadcast

function MemeTracker_Broadcast_Session_DE()
	MemeTracker_Broadcast_Session_Finish(DE_BANK);
end

function MemeTracker_Broadcast_Session_End()
	MemeTracker_Broadcast_Session_Finish("end");
end

function MemeTracker_Broadcast_Session_Cancel()
	MemeTracker_Broadcast_Session_Finish("cancel");
end

function MemeTracker_Broadcast_Session_ForceCancel()
	addonEcho("TX_SESSION_FINISH#".."force_cancel".."#");
end

function MemeTracker_Broadcast_Session_Finish(mode)

	if MemeTracker_OverviewTable.in_session then
		debug("MemeTracker_Broadcast_Session_Finish mode", mode)

		MemeTracker_OverviewTable.in_session = false

		local vote_total = {}
		local votes = 0

		for entry_key, recipient in MemeTracker_RecipientTable do
			if recipient.votes and (recipient.votes > 0) then
				votes = votes +  recipient.votes
				vote_total[recipient.player_name] = recipient.votes
			end
		end

		local sortedKeys = getKeysSortedByValue(vote_total, function(a, b) return a > b end)
		local stringList = {}
		for i,n in ipairs(sortedKeys) do table.insert(stringList, "#"..i.." ("..vote_total[n]..")"..": "..n) end

		local end_type;
		local end_announcement

		if (mode == 'end') and (getn(stringList) == 0) then
			mode = "cancel"
		end

		if mode == "cancel" then
			end_type = 'canceled'
			end_announcement = "Session canceled : ".. MemeTracker_OverviewTable.item_link
		elseif mode == DE_BANK then
 			end_type = 'ended'
		 	end_announcement = "Session ended : ".. MemeTracker_OverviewTable.item_link.." - Item will be Disenchanted or sent to the Bank"
		else
		 	end_type = 'ended'
		 	end_announcement = "Session ended : ".. MemeTracker_OverviewTable.item_link.." - Congratulations "..sortedKeys[1].."!"
		end

		MemeTracker_Broadcast_Message_Echo("Session " .. end_type .. " : ".. MemeTracker_OverviewTable.item_link.." - ("..MemeTracker_OverviewTable.votes.."/"
		..MemeTracker_OverviewTable.votes_needed..") "..table.concat( MemeTracker_OverviewTable.voters, ", " ))

		if getn(stringList) > 0 then
			local summary_string = table.concat(stringList, ", ")
			MemeTracker_Broadcast_Message_Echo(summary_string)
		end

		leaderRaidEcho(end_announcement)

		addonEcho("TX_SESSION_FINISH#"..mode.."#");

		if mode == "end" or mode == DE_BANK then
			local player_name;
			if mode == DE_BANK then
				player_name = DE_BANK
			else 
				player_name = sortedKeys[1]
			end

			if MemeTracker_OverviewTable.item_link then
				local entry = LootHistoryTable_AddEntry(MemeTracker_OverviewTable.item_link, player_name)
				MemeTracker_Broadcast_Sync_Start();
				local sync_string = MemeTracker_SendSync_String("loothistory", entry)
				MemeTracker_Broadcast_Sync_Add("loothistory", sync_string)
				MemeTracker_Broadcast_Sync_End(false);

			end
		end

		MemeTracker_RecipientListScrollFrame_Update()
	else
		echo("No Session in progress")
	end
end

function MemeTracker_Handle_Session_Finish(message)
	local mode = message;
	debug("MemeTracker_Handle_Session_Finish mode", mode)
	if MemeTracker_OverviewTable.in_session then
		if mode == "force_cancel" then
			echo("Session canceled: Error with syncing")
		end
		MemeTracker_OverviewTable.in_session = false
		MemeTracker_RecipientListScrollFrame_Update()
	end
end

-- AutoEnd UI Broadcast

function MemeTracker_Broadcast_AutoEnd(autoclose)
	if autoclose then
		addonEcho("TX_SESSION_AUTOCLOSE#".."1".."#");
	else
		addonEcho("TX_SESSION_AUTOCLOSE#".."0".."#");
	end
end

function MemeTracker_Handle_AutoClose(message, sender)
	local _, _, state = string.find(message, "(.*)");

	if state == "1" then
		getglobal("MemeTracker_SessionAutoEndCheckButton"):SetChecked(true)
	else
		getglobal("MemeTracker_SessionAutoEndCheckButton"):SetChecked(false)
	end
end

-- TODO

function MemeTracker_SendSync_String(table_name, entry, key)

	sync_string = "";

	if entry and table_name == "loothistory" then
		sync_string = string.format("%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s",
			table_name,
			entry.entry_key,
			entry.date,
			entry.time_stamp,
			entry.raid_name,
			entry.use_case,
			entry.item_name,
			entry.item_id,
			entry.item_quality,
			entry.player_name,
			entry.player_class)
	elseif entry and table_name == "attendance" then
		sync_string = string.format("%s/%s/%s/%s/%s",
			table_name,
			entry.player_name,
			entry.player_class,
			entry.last_4_weeks,
			entry.last_2_weeks)
	elseif entry and table_name == "time_stamp" then
		sync_string = string.format("%s/%s",
			table_name,
			entry.time_stamp)
	end

	return sync_string;
end

function MemeTracker_ReadSync_Entry(table_name, fields_string)

	entry = {}
	if table_name == "loothistory" then
		local _, _, entry_key, date, time_stamp, raid_name, use_case, item_name, item_id, item_quality,  player_name, player_class =
		string.find(fields_string, "(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)");

		entry["entry_key"] = entry_key
		entry["date"] = date
		entry["time_stamp"] = time_stamp
		entry["raid_name"] = raid_name
		entry["use_case"] = use_case
		entry["item_name"] = item_name
		entry["item_id"] = item_id
		entry["item_quality"] = item_quality
		entry["player_name"] = player_name
		entry["player_class"] = player_class

		if item_quality == "common" then
			browse_rarityhexlink = MemeTracker_color_common
		elseif item_quality == "uncommon" then
			browse_rarityhexlink = MemeTracker_color_uncommon
		elseif item_quality == "rare" then
			browse_rarityhexlink = MemeTracker_color_rare
		elseif item_quality == "epic" then
			browse_rarityhexlink = MemeTracker_color_epic
		elseif item_quality == "legendary" then
			browse_rarityhexlink = MemeTracker_color_legendary
		end
		--building the itemlink
		local item_link = "|c" .. browse_rarityhexlink .. "|Hitem:" .. item_id .. ":0:0:0|h[" .. item_name .. "]|h|r"

		entry["item_link"] = item_link
	elseif table_name == "attendance" then
		local _,_, player_name, player_class, last_4_weeks, last_2_weeks = string.find(fields_string, "(.*)/(.*)/(.*)/(.*)");
		entry["player_name"] = player_name
		entry["player_class"] = player_class
		entry["last_4_weeks"] = last_4_weeks
		entry["last_2_weeks"] = last_2_weeks
	elseif table_name == "time_stamp" then
		time_stamp = fields_string
		entry["time_stamp"] = time_stamp
	end
	return entry
end

function MemeTracker_Send_Sync()
	for k,v in pairs(MemeTracker_LootHistoryTable) do
		local sync_string = MemeTracker_SendSync_String("loothistory", v)
		MemeTracker_Broadcast_Sync_Add("loothistory", sync_string)
	end
	for k,v in pairs(MemeTracker_Attendance) do
		local sync_string = MemeTracker_SendSync_String("attendance", v)
		MemeTracker_Broadcast_Sync_Add("attendance", sync_string)
	end
end

function MemeTracker_Save_Sync(clear_table)

	-- Loot History Table
	if clear_table and getn(MemeTracker_LootHistoryTable_Temp) > 0 then
		MemeTrackerDB = {}
	end

	for k,v in pairs(MemeTracker_LootHistoryTable_Temp) do
		LootHistoryTable_UpdateEntry(v)
	end

	MemeTracker_LootHistoryTable_Temp = {}

	-- Attendance Table
	if clear_table and getn(MemeTracker_Attendance_Temp) > 0 then
		MemeTracker_Attendance = {}
	end

	for k,v in pairs(MemeTracker_Attendance_Temp) do
		MemeTracker_Attendance[k] = v
	end

	local time_stamp = date("%y-%m-%d %H:%M:%S")
	MemeTracker_LastUpdate = {}
	MemeTracker_LastUpdate["time_stamp"] = time_stamp

	-- Refresh View
	LootHistoryTable_Build()
	MemeTracker_RecipientListScrollFrame_Update();
end

-- Version Broadcast

function MemeTracker_Broadcast_PerformSync_Request() 
	addonEcho("TX_PERFORM_SYNC_REQUEST#".."#");
end

function MemeTracker_Handle_PerformSync_Request()
	if isLeader() and not version_request_in_progress then
		MemeTracker_Version_Start()
	end
end

function MemeTracker_Version_Start()
	if isLeader() and not version_request_in_progress then
		getglobal("MemeTracker_LootHistorySyncButton"):Disable()
		version_request_in_progress = true
		response_versions = {}
		MemeTracker_Broadcast_Version_Request()
	end
end

function MemeTracker_Broadcast_Version_Request()
	if isLeader() then
		debug("MemeTracker_Broadcast_Version_Request")
		addonEcho("TX_VERSION_REQUEST#".."#");
	end
end

function MemeTracker_Handle_Version_Request(message, sender)
	debug("MemeTracker_Handle_Version_Request")
	echo("Syncing Loot History")
	MemeTracker_Broadcast_Version_Response()
end

function MemeTracker_Broadcast_Version_Response()
	if MemeTracker_LastUpdate ~= nil and MemeTracker_LastUpdate["time_stamp"] ~= nil then
		debug("MemeTracker_Broadcast_Version_Response")
		addonEcho("TX_VERSION_RESPONSE#"..MemeTracker_LastUpdate["time_stamp"].."#");
	end
end

function MemeTracker_Handle_Version_Response(message, sender)
	if isLeader() then
		debug("MemeTracker_Handle_Version_Response")
		response_versions[sender] = message
	end
end

function MemeTracker_Version_End()
	debug("MemeTracker_Version_End")
	version_request_in_progress = false

	max_sender = UnitName("player")
	max_time_stamp = response_versions[UnitName("player")]
	for sender,time_stamp in pairs(response_versions) do
		if time_stamp ~= nill and (max_time_stamp == nil or time_stamp > max_time_stamp) then
			max_time_stamp = time_stamp
			max_sender = sender
		end
	end

	if max_sender ~= UnitName("player") then
		debug("MemeTracker_Version_End", max_sender.." is master");
	else
		debug("MemeTracker_Version_End", "I am master");
	end
	MemeTracker_Broadcast_Sync_Request(max_sender)

end

-- Upload Sync

function MemeTracker_Broadcast_Sync_Request(player_name)
	if isLeader() and not sync_in_progress then
		debug("MemeTracker_Broadcast_Sync_Request")
		addonEcho("TX_Sync_REQUEST#"..player_name.."#");
	end
end

function MemeTracker_Handle_Sync_Request(message, sender)
	local player_name = message
	if UnitName("player") == player_name then
		debug("MemeTracker_Handle_Sync_Request");
		MemeTracker_Broadcast_Sync_Start();
		MemeTracker_Send_Sync();
		MemeTracker_Broadcast_Sync_End(true);
		MemeTracker_Broadcast_Message_Echo("Sync Completed")

	end
end

function MemeTracker_Broadcast_Sync_Start()
	debug("MemeTracker_Broadcast_Sync_Start");
	addonEcho("TX_Sync_START#".."#");
end

function MemeTracker_Handle_Sync_Start(message, sender)
	getglobal("MemeTracker_LootHistorySyncButton"):Disable()

	if not sync_in_progress then
		sync_in_progress = true
		MemeTracker_Attendance_Temp = {}
		MemeTracker_LootHistoryTable_Temp = {}
		debug("MemeTracker_Handle_Sync_Start");
	end
end

function MemeTracker_Broadcast_Sync_Add(table_name, sync_string)
	addonEcho("TX_Sync_ADD#".. sync_string .."#");
end

function MemeTracker_Handle_Sync_Add(message, sender)
	if sync_in_progress then
		local _, _, table_name, fields_string = string.find(message, "([^/]*)/(.*)");

		entry = MemeTracker_ReadSync_Entry(table_name, fields_string)

		if table_name == "loothistory" then
			table.insert(MemeTracker_LootHistoryTable_Temp, entry)
		elseif table_name == "attendance" then
			MemeTracker_Attendance_Temp[entry["player_name"]] = entry
		end
	end
end

function MemeTracker_Broadcast_Sync_End(clear_table)
	debug("MemeTracker_Broadcast_Sync_End");

	if clear_table then
		addonEcho("TX_Sync_END#".."1".."#");
	else
		addonEcho("TX_Sync_END#".."0".."#");
	end
end

function MemeTracker_Handle_Sync_End(message, sender)
	local clear_table = message
	if sync_in_progress then
		sync_in_progress = false

		debug("MemeTracker_Handle_Sync_End clear_table", clear_table)
		getglobal("MemeTracker_LootHistorySyncButton"):Enable()

		MemeTracker_Save_Sync(clear_table == "1")
	end
end

-- UI LINK

function MemeTracker_ChatLink(button, link)
	 if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			ChatFrameEditBox:Insert(link)
		end
	end
end

function MemeTracker_RecipientButton_OnClick(button, entry_key)
	local link = MemeTracker_RecipientTable[entry_key].item_link
	MemeTracker_ChatLink(button, link)
end

function MemeTracker_LootHistoryEditorSaveButton_OnClick()
	getglobal("MemeTracker_LootHistoryEditorFrame"):Hide()
	local name_box_text = MemeTracker_LootHistoryEditor_NameBox:GetText()

	if name_box_text4 ~= "" then
		LootHistoryEditorEntry.player_name = name_box_text

		if LootHistoryEditorEntry["use_case"] == DE_BANK then
			LootHistoryEditorEntry.player_class = ""
		end

		MemeTracker_Broadcast_Sync_Start();
		local sync_string = MemeTracker_SendSync_String("loothistory", LootHistoryEditorEntry)
		MemeTracker_Broadcast_Sync_Add("loothistory", sync_string)
		MemeTracker_Broadcast_Sync_End(false);
	end
end

function LootTracker_OptionCheckButton_Check(id)

	for index = 1,getn(lootHistoryUseCase),1  do
		getglobal("MemeTracker_LootHistoryEditor_UseCase"..index):SetChecked(id==index)
	end

	if id == 4 then
		player_name= DE_BANK
		use_index = 1
	else
		player_name = LootHistoryEditorEntry.player_name
		use_index = GetPlayerClassDropDownIndex(LootHistoryEditorEntry.player_class)
	end

	getglobal("MemeTracker_LootHistoryEditor_NameBox"):SetText(player_name)
	UIDropDownMenu_SetSelectedID(MemeTracker_LootHistoryEditor_ClassDropDown,use_index)
	LootHistoryEditorEntry["use_case"] = lootHistoryUseCase[id]
end

function MemeTracker_LootHistoryEditor_UseCaseButton_OnClick(id)
	local useCase = lootHistoryUseCase[id]

	if getglobal("MemeTracker_LootHistoryEditor_UseCase"..id):GetChecked() then
		LootTracker_OptionCheckButton_Check(id)
	else
		LootTracker_OptionCheckButton_Check(1)
	end
end

function MemeTracker_LootHistoryEditor_ClassDropDown_OnClick()
	local id = this:GetID();
	UIDropDownMenu_SetSelectedID(MemeTracker_LootHistoryEditor_ClassDropDown, id);
	
	if( id > 1) then
		searchSlot = playerClassSlotNames[id-1].name;
	else
		searchSlot = nil;
	end	

	LootHistoryEditorEntry.player_class = playerClassSlotNames[id].slot
end

function MemeTracker_LootHistoryEditor_ClassDropDown_Initialize()
	local info;

	for i = 1, getn(playerClassSlotNames), 1 do
		info = { };
		info.text = playerClassSlotNames[i].slot;
		info.func = MemeTracker_LootHistoryEditor_ClassDropDown_OnClick;
		UIDropDownMenu_AddButton(info);
	end
end

function MemeTracker_LootHistoryEditor_ClassDropDown_OnShow()
     UIDropDownMenu_Initialize(this, MemeTracker_LootHistoryEditor_ClassDropDown_Initialize);
     UIDropDownMenu_SetWidth(90);
end

function GetPlayerClassDropDownIndex(player_class)
	local player_class_index = 1
	for index, slot in ipairs(playerClassSlotNames) do
		if slot.slot == player_class then
			player_class_index = index
		end
	end

	return player_class_index
end

function GetUseCaseDropDownIndex(player_name, use_case)
	local use_case_index = 1

	if player_name == DE_BANK then
		use_case_index = 4
	end

	for index, name in ipairs(lootHistoryUseCase) do
		if LootHistoryEditorEntry["use_case"] == name then
			use_case_index = index
		end
	end

	return use_case_index
end

function MemeTracker_LootHistoryEditor_Open(index)
	ShowUIPanel(MemeTracker_LootHistoryEditorFrame, 1)

	LootHistoryEditorEntry =  MemeTracker_LootHistoryTable_Filtered[index]

	local player_class = LootHistoryEditorEntry.player_class
	local player_name = LootHistoryEditorEntry.player_name

	local player_class_index = GetPlayerClassDropDownIndex(player_class)

	local use_case_index = GetUseCaseDropDownIndex(player_name, LootHistoryEditorEntry["use_case"])

	LootTracker_OptionCheckButton_Check(use_case_index)
	UIDropDownMenu_SetSelectedID(MemeTracker_LootHistoryEditor_ClassDropDown,LootHistoryEditorEntry.player_class_index)

	getglobal("MemeTracker_LootHistoryEditor_TextItemName"):SetText(LootHistoryEditorEntry.item_link)
	getglobal("MemeTracker_LootHistoryEditor_NameBox"):SetText(LootHistoryEditorEntry.player_name)
end


function MemeTracker_LootHistoryEditorFrame_OnShow()
	
end

function MemeTracker_LootHistoryButton_OnClick(button, entry_key)
	if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			local link = MemeTracker_LootHistoryTable_Filtered[entry_key].item_link
			MemeTracker_ChatLink(button, link)
		end
	elseif button == "RightButton" and (isOfficer() or isLeader()) then
		MemeTracker_LootHistoryEditor_Open(entry_key)
	end
end

function MemeTracker_OverviewButton_OnClick(button)
	local link = MemeTracker_OverviewTable.item_link
	MemeTracker_ChatLink(button, link)
end

-- UI Drag

function MemeTracker_Main_OnMouseDown(button)
	if (button == "LeftButton") then
		this:StartMoving();
	end
end

function MemeTracker_Main_OnMouseUp(button)
	if (button == "LeftButton") then
		this:StopMovingOrSizing()

	end
end

-- UI Tooltip

function MemeTracker_Tooltip_Show(item_id)
	if item_id then
		MemeTracker_Tooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
		MemeTracker_Tooltip:SetHyperlink("item:" .. item_id .. ":0:0:0")
		MemeTracker_Tooltip:Show()
	end
end

function MemeTracker_Tooltip_Hide()
	MemeTracker_Tooltip:Hide()
end

function MemeTracker_RecipientButton_OnEnter(entry_key)
	local item_id = MemeTracker_RecipientTable[entry_key].item_id
	MemeTracker_Tooltip_Show(item_id)
end

function MemeTracker_RecipientButton_OnLeave()
	MemeTracker_Tooltip_Hide()
end

function MemeTracker_OverviewButton_OnEnter()
	local item_id = MemeTracker_OverviewTable.item_id
	MemeTracker_Tooltip_Show(item_id)
end

function MemeTracker_OverviewButton_OnLeave()
	MemeTracker_Tooltip_Hide()
end

function MemeTracker_LootHistoryButton_OnEnter(entry_key)
	local item_id = MemeTracker_LootHistoryTable_Filtered[entry_key].item_id
	MemeTracker_Tooltip_Show(item_id)
end

function MemeTracker_LootHistoryButton_OnLeave()
	MemeTracker_Tooltip_Hide()
end

function MemeTracker_LootHistoryEditor_ItemNameButton_OnClick(button)
	local link = LootHistoryEditorEntry.item_link
	MemeTracker_ChatLink(button, link)
end 

function MemeTracker_LootHistoryEditor_ItemNameButton_OnEnter()
	local item_id = LootHistoryEditorEntry.item_id
	MemeTracker_Tooltip_Show(item_id)
end

function MemeTracker_LootHistoryEditor_ItemNameButton_OnLeave()
	MemeTracker_Tooltip_Hide()
end
-- Session UI


function MemeTracker_Mode_Update()
	if is_min_mode then
		getglobal("MemeTracker_SessionMinButton"):SetText("Max")
		MemeTracker_SessionMinMode()
	else
		getglobal("MemeTracker_SessionMinButton"):SetText("Min")
		MemeTracker_SessionMaxMode()
	end
end

function MemeTracker_SessionMinButton_OnClick()
	is_min_mode = not is_min_mode
	MemeTracker_Mode_Update()
end

function MemeTracker_SessionMinMode() 
	local max_lines = getn(MemeTracker_RecipientTable)

	local min_width = 272

	local min_height = 320

	getglobal("MemeTracker_OverviewButtonTextVoters"):Hide()
	
	getglobal("MemeTracker_OverviewButtonTextItemName"):SetWidth(125);
	getglobal("MemeTracker_OverviewButtonTextItemName"):SetPoint("LEFT", 5, 0);



	getglobal("MemeTracker_OverviewButtonTextVoters"):Hide()

	getglobal("MemeTracker_SessionEndButton"):Hide()
	getglobal("MemeTracker_SessionDEButton"):Hide()
	getglobal("MemeTracker_SessionCancelButton"):Hide()
	getglobal("MemeTracker_SessionAutoEndCheckButton"):Hide()

	getglobal("MemeTracker_LootHistoryTabButton"):Hide()

	getglobal("MemeTracker_RecipientListSortPlayerGuildRank"):Hide()

	for i,n in ipairs(week_list) do
		getglobal("MemeTracker_RecipientListSortLootCount"..i):Hide()
	end
	-- 320
	getglobal("MemeTracker_RecipientListSortLootCountTitle"):Hide()
	getglobal("MemeTracker_RecipientListSortPlayerAttendanceTitle"):Hide()
	getglobal("MemeTracker_RecipientListSortPlayerAttendanceLast4Weeks"):Hide()
	getglobal("MemeTracker_RecipientListSortPlayerAttendanceLast2Weeks"):Hide()

	getglobal("MemeTracker_BrowseFrame"):SetHeight(min_width+18)
	getglobal("MemeTracker_LootSessionFrame"):SetHeight(min_width)

	getglobal("MemeTracker_BrowseFrame"):SetWidth(min_width+18)
	getglobal("MemeTracker_RecipientListSortFrame"):SetWidth(min_width-7)
	getglobal("MemeTracker_LootSessionFrame"):SetWidth(min_width)
	--getglobal("MemeTracker_RecipientListSortFrame"):SetWidth(300)
	local max_lines = getn(MemeTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each linevmkm
	
	if max_lines < 15 then
		min_height = min_height - 16*(15 - max_lines)
	end

	getglobal("MemeTracker_BrowseFrame"):SetHeight(min_height + 11)
	getglobal("MemeTracker_LootSessionFrame"):SetHeight(min_height)

	for line = 1,15 do
		getglobal("MemeTracker_RecipientListItem"..line):SetWidth(min_width)
		getglobal("MemeTracker_RecipientListItem"..line.."HighlightTexture"):SetWidth(min_width)

		getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerGuildRank"):Hide()
		getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):Hide()
		getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast2Weeks"):Hide()
		getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):Hide()
		getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetWidth(125);
		getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetPoint("LEFT", getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerName"), "RIGHT", 5, 0);

		for i,n in ipairs(week_list) do
			getglobal("MemeTracker_RecipientListItem"..line.."TextLootCount"..i):Hide()
		end
	end
end

function MemeTracker_SessionMaxMode() 
	local max_width = 700
	getglobal("MemeTracker_OverviewButtonTextVoters"):Show()
	getglobal("MemeTracker_OverviewButtonTextItemName"):SetWidth(200);
	getglobal("MemeTracker_OverviewButtonTextItemName"):SetPoint("LEFT", 265, 0);


	getglobal("MemeTracker_LootHistoryTabButton"):Show()

	getglobal("MemeTracker_RecipientListSortPlayerGuildRank"):Show()

	getglobal("MemeTracker_RecipientListSortPlayerAttendanceTitle"):Show()
	getglobal("MemeTracker_RecipientListSortPlayerAttendanceLast4Weeks"):Show()
	getglobal("MemeTracker_RecipientListSortPlayerAttendanceLast2Weeks"):Show()

	getglobal("MemeTracker_BrowseFrame"):SetWidth(max_width+43)
	getglobal("MemeTracker_RecipientListSortFrame"):SetWidth(max_width+20)
	getglobal("MemeTracker_LootSessionFrame"):SetWidth(max_width)

	getglobal("MemeTracker_BrowseFrame"):SetHeight(320)
	getglobal("MemeTracker_LootSessionFrame"):SetHeight(287)

	for i,n in ipairs(week_list) do
		getglobal("MemeTracker_RecipientListSortLootCount"..i):Show()
	end

	if isOfficer() or isLeader() then
		getglobal("MemeTracker_OverviewButtonTextVotes"):Show()
		getglobal("MemeTracker_OverviewButtonTextVoters"):Show()
	else 
		getglobal("MemeTracker_OverviewButtonTextVotes"):Hide()
		getglobal("MemeTracker_OverviewButtonTextVoters"):Hide()
	end

	if isLeader() then
		getglobal("MemeTracker_SessionEndButton"):Show()
		getglobal("MemeTracker_SessionDEButton"):Show()
		getglobal("MemeTracker_SessionCancelButton"):Show()
	else 
		getglobal("MemeTracker_SessionEndButton"):Hide()
		getglobal("MemeTracker_SessionDEButton"):Hide()
		getglobal("MemeTracker_SessionCancelButton"):Hide()
	end
	getglobal("MemeTracker_RecipientListSortLootCountTitle"):Show()

	local max_lines = getn(MemeTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MemeTracker_RecipientListScrollFrame, max_lines, 15, 25)
	for line = 1,15 do
		getglobal("MemeTracker_RecipientListItem"..line):SetWidth(max_width)
		getglobal("MemeTracker_RecipientListItem"..line.."HighlightTexture"):SetWidth(max_width)
		getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerGuildRank"):Show()
		getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):Show()
		getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast2Weeks"):Show()
		getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetWidth(175);
		getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetPoint("LEFT", getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerGuildRank"), "RIGHT", 5, 0);

		for i,n in ipairs(week_list) do
			getglobal("MemeTracker_RecipientListItem"..line.."TextLootCount"..i):Show()
		end

		getglobal("MemeTracker_SessionAutoEndCheckButton"):Show()

		if isOfficer() or isLeader() then
			getglobal("MemeTracker_RecipientListVoteBox"..line):Show()
			getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):Show()
			getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):Show()

		else
			getglobal("MemeTracker_RecipientListVoteBox"..line):Hide()
			getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):Hide()
			getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):Hide()
		end
	end
end

function MemeTracker_VoteCheckButton_OnClick(line)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_RecipientListScrollFrame);
	local entry_key = line + offset
	local player_name = MemeTracker_RecipientTable[entry_key].player_name

	if getglobal("MemeTracker_RecipientListVoteBox"..line):GetChecked() then
		my_vote = player_name
	else
		my_vote = nil
	end

	for other_line = 1,15 do
		if other_line ~= line then
			getglobal("MemeTracker_RecipientListVoteBox"..line):SetChecked(false)
		end
	end

	MemeTracker_Broadcast_VoteTable_Add(my_vote)
end

function MemeTracker_SessionDEButton_OnClick()
	MemeTracker_Broadcast_Session_DE()
end

function MemeTracker_SessionEndButton_OnClick()
	MemeTracker_Broadcast_Session_End()
end

function MemeTracker_SessionCancelButton_OnClick()
	MemeTracker_Broadcast_Session_Cancel()
end

function MemeTracker_LootHistorySyncButton_OnClick()
	MemeTracker_Broadcast_PerformSync_Request()
end

function MemeTracker_LootHistory_Sort_OnClick(field)

	if loot_sort_field == field and field == "player_name" then
		field = "player_class"
	end

	if loot_sort_field == field and loot_sort_direction == "ascending" then
		loot_sort_direction = "descending"
	else
		loot_sort_direction = "ascending"
	end

	loot_sort_field = field
	MemeTracker_LootHistoryScrollFrame_Update()
end

function MemeTracker_CouncilSession_Sort_OnClick(field, id)

	if recipient_sort_field == field and field == "player_name" then
		field = "player_class"
	end

	if recipient_sort_field == field and sort_direction == "ascending" then
		sort_direction = "descending"
	else
		sort_direction = "ascending"
	end

	recipient_sort_field = field
	recipient_sort_id = id
	MemeTracker_RecipientListScrollFrame_Update()
end

function MemeTracker_LootHistoryTabButton_OnClick()
	local player_name_list = {}
	for entry_key, entry in MemeTracker_RecipientTable do
		table.insert(player_name_list, entry.player_name)
	end

	player_name_string = table.concat(player_name_list, ", ");
	if (getn(player_name_list) > 0) then
		MemeTracker_LootHistorySearchBox:SetText(player_name_string)
		MemeTracker_LootHistory_SearchUpdate()
	end
	MemeTracker_LootHistoryTable_Show()
end

function MemeTracker_LootSessionTabButton_OnClick()
	MemeTracker_RecipientTable_Show()
end

function MemeTracker_LootHistorySearchBox_OnEnterPressed()
	MemeTracker_LootHistory_SearchUpdate();
end

function MemeTracker_LootHistory_SearchUpdate()

	local msg = MemeTracker_LootHistorySearchBox:GetText();

	if( msg and msg ~= "" ) then
		searchString = string.lower(msg);
	else
		searchString = nil;
	end

	FauxScrollFrame_SetOffset(MemeTracker_LootHistoryScrollFrame, 0);
	getglobal("MemeTracker_LootHistoryScrollFrameScrollBar"):SetValue(0);

	MemeTracker_LootHistoryScrollFrame_Update()
end

function MemeTracker_SessionAutoEndCheckButton_OnEnter()
	if not isLeader() then
		getglobal("MemeTracker_SessionAutoEndCheckButton"):Disable()
	end
end

function MemeTracker_SessionAutoEndCheckButton_OnClick()
	if isLeader() then
		MemeTracker_Broadcast_AutoEnd(getglobal("MemeTracker_SessionAutoEndCheckButton"):GetChecked())
		if Session_CanEnd() then
			MemeTracker_Broadcast_Session_End()
		end
	end
end

function MemeTracker_RecipientTable_Show()
	MemeTracker_Mode_Update()
	if isLeader() then
		getglobal("MemeTracker_SessionAutoEndCheckButton"):Enable()
		getglobal("MemeTracker_SessionEndButton"):Show()
		getglobal("MemeTracker_SessionDEButton"):Show()
		getglobal("MemeTracker_SessionCancelButton"):Show()
	else
		getglobal("MemeTracker_SessionAutoEndCheckButton"):Disable()
		getglobal("MemeTracker_SessionEndButton"):Hide()
		getglobal("MemeTracker_SessionDEButton"):Hide()
		getglobal("MemeTracker_SessionCancelButton"):Hide()
	end

	MemeTracker_RecipientListScrollFrame_Update();
	MemeTracker_LootSessionFrame:Show();
	MemeTracker_LootHistoryFrame:Hide();
end

function MemeTracker_LootHistoryTable_Show()
	if isOfficer() then
		getglobal("MemeTracker_LootHistorySyncButton"):Show()
	else
		getglobal("MemeTracker_LootHistorySyncButton"):Hide()
	end

	MemeTracker_LootHistoryScrollFrame_Update();
	MemeTracker_LootSessionFrame:Hide();
	MemeTracker_LootHistoryFrame:Show();
end

-- Commands

function MemeTracker_OnChatMsgAddon(event, prefix, msg, channel, sender)
	if (prefix == MT_MESSAGE_PREFIX) then
			--	Split incoming message in Command, Payload (message) and Recipient
		local _, _, cmd, message, recipient = string.find(msg, "([^#]*)#(.*)#([^#]*)")

		if not cmd then
			return	-- cmd is mandatory, remaining parameters are optional.
		end

		if not message then
			message = ""
		end

		if cmd == "TX_ENTRY_ADD" then
			MemeTracker_Handle_RecipientTable_Add(message, sender)
		elseif cmd == "TX_ENTRY_REMOVE" then
			MemeTracker_Handle_RecipientTable_Remove(message, sender)
		elseif cmd == "TX_SESSION_START" then
			MemeTracker_Handle_Session_Start(message, sender)
		elseif cmd == "TX_SESSION_AUTOCLOSE" then
			MemeTracker_Handle_AutoClose(message, sender)
		elseif cmd == "TX_SESSION_FINISH" then
			MemeTracker_Handle_Session_Finish(message, sender)
		elseif cmd == "TX_Sync_REQUEST" then
			MemeTracker_Handle_Sync_Request(message, sender)
		elseif cmd == "TX_VERSION_REQUEST" then
			MemeTracker_Handle_Version_Request(message, sender)
		elseif cmd == "TX_Sync_START" then
			MemeTracker_Handle_Sync_Start(message, sender)
		elseif cmd == "TX_Sync_ADD" then
			MemeTracker_Handle_Sync_Add(message, sender)
		elseif cmd == "TX_Sync_END" then
			MemeTracker_Handle_Sync_End(message, sender)
		end

		if isLeader() or isOfficer() then
			if cmd == "TX_VOTE_ADD" then
				MemeTracker_Handle_VoteTable_Add(message, sender)
			elseif cmd == "TX_MESSAGE_ECHO" then
				MemeTracker_Handle_Message_Echo(message, sender)
			end
		end

		if isLeader() then
			if cmd == "TX_VERSION_RESPONSE" then
				MemeTracker_Handle_Version_Response(message, sender)
			elseif cmd == "TX_PERFORM_SYNC_REQUEST" then
				MemeTracker_Handle_PerformSync_Request(message, sender)
			end
		else
			
			
		end
	end
end

function MemeTracker_SlashCommand(msg)
	if msg =="" then
		if (MemeTracker_BrowseFrame:IsVisible()) then
			MemeTracker_BrowseFrame:Hide()
			MemeTracker_BrowseFrame:Hide()
		else
			MemeTracker_RecipientTable_Show()
			ShowUIPanel(MemeTracker_BrowseFrame, 1)
		end
	else
		_,_, cmd, cmd_msg = string.find(msg, "(%S+)%s+(.*)");
		if cmd == nil then
			cmd = msg
		end
		cmd = string.lower(cmd)
		if not cmd_msg then
			cmd_msg = ""
		end

		if isLeader() then
			if (cmd == "start") or (cmd == "queue") then
				_,_, item_link = string.find(cmd_msg, "(.*)");
				MemeTracker_Session_Queue(item_link)
			elseif (cmd == "list") then
				MemeTracker_Session_List()
			elseif (cmd == "dequeue") then
				MemeTracker_Session_Dequeue(cmd_msg)
				-- 	local _,_,item_quality, item_id, item_name= string.find(item_link , ".*c(%w+).*item:(.*):.*%[(.*)%]")
			elseif (cmd == "end") then
				MemeTracker_Broadcast_Session_End()
			elseif (cmd == "cancel") then
				MemeTracker_Broadcast_Session_Cancel()
			elseif (cmd == "force_cancel") then
				MemeTracker_Broadcast_Session_ForceCancel()
			elseif (cmd == "help") then
				echo("MemeTracker v"..MemeTracker_Version.." Commands")
				echo("Open MemeTracker:   /mt")
				echo("Start/Queue session:   /mt start [item link] OR /mt [item link] OR /mt queue [item link]")
				echo("End session:  /mt end")
				echo("List queued sessions:  /mt list")
				echo("Remove queued session:  /mt dequeue <entry_key>")
				echo("Manually add a raider to the current session:  /mt add <player_name> <entry_key>")
				echo("Cancel session:   /mt cancel")
				echo("Force cancel a bad session: /mt force_cancel")
				echo("Print help:   /mt help")
			 elseif cmd == "add" then
				local _,_, player_name, item_link = string.find(cmd_msg, "(%S+)%s*(.*)");
				MemeTracker_Broadcast_RecipientTable_Add(player_name, item_link)
			--elseif cmd == "vote" then
			--	_,_, sender, player_name = string.find(cmd_msg, "(%S+)%s+(.*)");
			--	VoteTable_Add(player_name, sender)
			--	MemeTracker_RecipientListScrollFrame_Update()
			else
				local _,_, item_link = string.find(msg , "(.*c%w+.*item:.*:.*%[.*%].*)")
				if item_link then
					MemeTracker_Session_Queue(item_link)
					echo("item_id", item_id)
				else
					echo("Unknown command "..msg.. ". Type /mt help to see a list of commands")
				end
			end
		else
			if isOfficer() and cmd == "force_cancel" then
				MemeTracker_Broadcast_Session_ForceCancel()
			elseif cmd == "help" then
				echo("MemeTracker v"..MemeTracker_Version.." Commands")
				echo("Open MemeTracker:   /mt")

				if isOfficer() then
					echo("Force cancel a bad session: /mt force_cancel")
				end

				echo("Print help:   /mt help")
			else
				echo("Unknown command "..cmd.. ". Type /mt help to see a list of commands")
			end
		end
	end
end

local function getCommand(message)
	_, _, cmd, arg = string.find(message, "(%S+)%s+(.*)");
	if (cmd ~= nil and (string.lower(cmd) == "memetracker" or string.lower(cmd)=="mt")) then
		return arg
	else
		return nil
	end
end

function MemeTracker_OnRaidChat(event, message, sender)
	if isLeader() then
		if not message then
			return
		end

		local cmd = getCommand(message)

		if cmd == nil then
			return
		end

		local _,_, item_link = string.find(cmd, "(.*)");

		if item_link then
			MemeTracker_Broadcast_RecipientTable_Add(sender, item_link)
		end
	end
end

function MemeTracker_OnEvent(event, arg1, arg2, arg3, arg4, arg5)
	if event == "VARIABLES_LOADED" then
		this:UnregisterEvent("VARIABLES_LOADED");
		MemeTracker_Initialize();
	elseif (event == "CHAT_MSG_ADDON") then
		MemeTracker_OnChatMsgAddon(event, arg1, arg2, arg3, arg4, arg5)
	elseif (event == "CHAT_MSG_RAID") then
		MemeTracker_OnRaidChat(event, arg1, arg2, arg3, arg4, arg5);
	elseif (event == "CHAT_MSG_RAID_LEADER") then
		MemeTracker_OnRaidChat(event, arg1, arg2, arg3, arg4, arg5);
	end
end

function MemeTracker_Main_OnShow()
	MemeTracker_FrameTitle:SetText(MemeTracker_Title .. " v" .. MemeTracker_Version);
end

function MemeTracker_OnLoad()
	echo("Type /mt or /memetracker for more info");
	this:RegisterEvent("VARIABLES_LOADED");
	this:RegisterEvent("CHAT_MSG_ADDON");
	this:RegisterEvent("CHAT_MSG_RAID");
	this:RegisterEvent("CHAT_MSG_RAID_LEADER");
	this:RegisterEvent("CHAT_MSG_OFFIER");
end

function MemeTracker_Initialize()
	LootHistoryTable_Build();
	AttendanceTable_Build();
end

SlashCmdList["MemeTracker"] = MemeTracker_SlashCommand;
SLASH_MemeTracker1 = "/memetracker";
SLASH_MemeTracker2 = "/mt";
