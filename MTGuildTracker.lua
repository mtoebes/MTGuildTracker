local MTGuildTracker_Version = "4.2.1"

local GUILD_NAME, _, _ = GetGuildInfo("player")

local SLASH_COMMAND_SHORT = "ft"
local SLASH_COMMAND_LONG = "FearlessTracker"
local MT_MESSAGE_PREFIX = "FearlessTracker"
local MTGuildTracker_Title = "FearlessTracker"

local DEFAULT_VOTES_NEEDED = 5

MTGuildTracker_RecipientTable = {}
MTGuildTracker_LootHistoryTable = {}
MTGuildTracker_LootHistoryTable_Filtered = {}
MTGuildTracker_VoteTable = {}
MTGuildTracker_OverviewTable = {}
MTGuildTracker_LootHistoryTable_Temp = {}
my_vote = nil

last_sync_time = ""

sort_direction = "ascending"
recipient_sort_field = "player_name"
recipient_sort_id = 1

loot_sort_direction = "ascending"
loot_sort_field = "time_stamp";

version_request_in_progress = false
sync_time_request_in_progress = false 
debug_enabled = false

local session_queue = {}
local LootHistoryEditorEntry = {}

MTGuildTracker_color_prefix = "ffa335ee"
MTGuildTracker_color_help_command = "ffffff00"
MTGuildTracker_color_common = "ffffffff"
MTGuildTracker_color_uncommon = "ff1eff00"
MTGuildTracker_color_rare = "ff0070dd"
MTGuildTracker_color_epic = "ffa335ee"
MTGuildTracker_color_legendary = "ffff8000"

local default_rgb = {["r"]=0.83, ["g"]=0.83, ["b"]=0.83}

local DE_BANK = "DE-Bank"

local HISTORY_DELETED = "Deleted"

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
	[4] = DE_BANK,
	[5] = HISTORY_DELETED
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

local GUILD_RANK_INDEX = 5

local string_gmatch = lua51 and string.gmatch or string.gfind

local function echo(tag, msg)
	if msg then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|c"..MTGuildTracker_color_prefix.."<"..MT_MESSAGE_PREFIX.."> |r"..tag.." : "..msg));
	else
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|c"..MTGuildTracker_color_prefix.."<"..MT_MESSAGE_PREFIX.."> |r"..tag));
	end
end

local function debug(tag, msg)
	if debug_enabled then
		if msg then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|c"..MTGuildTracker_color_prefix.."<"..MT_MESSAGE_PREFIX.." Debug> |r"..tag.." : "..msg));
		else
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|c"..MTGuildTracker_color_prefix.."<"..MT_MESSAGE_PREFIX.." Debug> |r"..tag));
		end
	end
end

local function get_server_time()
	hour, minutes = GetGameTime();
	time_string = string.format("%s:%s", hour, minutes)
	debug(time_string)
	return time_string
end

TimeSinceLastSyncRequestStart=0
TimeSinceVersionRequestStart=0
TimeSinceLastSessionStart = 0
local version_request_time_limit = 2;
local sync_request_time_limit = 2;

function MTGuildTracker_OnUpdate(elapsed)
	TimeSinceVersionRequestStart = TimeSinceVersionRequestStart + elapsed;
	TimeSinceLastSessionStart = TimeSinceLastSessionStart + elapsed
	TimeSinceLastSyncRequestStart = TimeSinceLastSyncRequestStart + elapsed

	if version_request_in_progress then
  		if (TimeSinceVersionRequestStart > version_request_time_limit) then
  			MTGuildTracker_Version_End();
   			TimeSinceVersionRequestStart = 0;
   		end
	else
  		TimeSinceVersionRequestStart = 0;
	end

	if sync_time_request_in_progress then
		if (TimeSinceLastSyncRequestStart > sync_request_time_limit) then
			MTGuildTracker_Sync_Time_End()
			TimeSinceLastSyncRequestStart = 0;
		end
	else
		TimeSinceLastSyncRequestStart = 0
	end

	if not MTGuildTracker_OverviewTable.in_session and getn(session_queue) > 0 then
		if TimeSinceLastSessionStart > 1 then
			item_link = table.remove(session_queue, 1)
			MTGuildTracker_Broadcast_Session_Start(item_link)
			TimeSinceLastSessionStart = 0
		end
	else
		TimeSinceLastSessionStart = 0
	end
end

local function getGuildName()
	local guild_name, _, _ = GetGuildInfo("player")
	return guild_name
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

	if player_name == DE_BANK or player_name == HISTORY_DELETED then
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
	local guild_name, guild_rank, rank_index = GetGuildInfo("player")
	if isLeader() then
		return true
	elseif rank_index < GUILD_RANK_INDEX then
		return true
	else
		return false
	end
end

-- echo 

local function echo_leader(tag, msg)
	if isLeader() then
		if msg then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|c"..MTGuildTracker_color_prefix.."<"..MT_MESSAGE_PREFIX.."> |r"..tag.." : "..msg));
		else
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|c"..MTGuildTracker_color_prefix.."<"..MT_MESSAGE_PREFIX.."> |r"..tag));
		end
	end
end



local function addonEcho(tag, msg)
	encodedMsg = tag.."#"..getGuildName().."#"..msg.."#"
	SendAddonMessage(MT_MESSAGE_PREFIX, encodedMsg, "RAID")
end

local function addonEcho_leader(tag, msg)
	if isLeader() then
		addonEcho(tag, msg)
	end
end

local function rwEcho(msg)
	SendChatMessage(msg, "RAID_WARNING");
end

local function raidEcho(msg)
	SendChatMessage(msg, "RAID");
end

local function leaderRaidEcho(msg)
	if isLeader() then
		raidEcho(msg)
	end
end

local function leaderRaidWarnEcho(msg)
	if isLeader() then
		rwEcho(msg)
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
	if item_color == MTGuildTracker_color_common then
		item_quality = "common"
	elseif item_color == MTGuildTracker_color_uncommon then
		item_quality = "uncommon"
	elseif item_color == MTGuildTracker_color_rare then
		item_quality = "rare"
	elseif item_color == MTGuildTracker_color_epic then
		item_quality = "epic"
	elseif item_color == MTGuildTracker_color_legendary then
		item_quality = "legendary"
	else
		item_quality = "common"
	end
	return item_quality
end

local function getItemLinkColor(item_quality)
	if item_quality == "common" then
		item_color = MTGuildTracker_color_common
	elseif item_quality == "uncommon" then
		item_color = MTGuildTracker_color_uncommon
	elseif item_quality == "rare" then
		item_color = MTGuildTracker_color_rare
	elseif item_quality == "epic" then
		item_color = MTGuildTracker_color_epic
	elseif item_quality == "legendary" then
		item_color = MTGuildTracker_color_legendary
	else 
		item_color = MTGuildTracker_color_common
	end
	return item_color
end

local function parseItemLink(item_link)

	local _,_, find_item_link, item_color, item_id, item_name = string.find(item_link , "(|c(%w+).*item:(%d+):.*%[(.*)%]|h|r)")
	local item_quality = getItemLinkQuality(item_color)
	if find_item_link then
		return find_item_link, item_quality, item_id, item_name, item_color
	else
		return nil, MTGuildTracker_color_common, nil, item_link
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
	MTGuildTracker_RecipientTable = {}
	MTGuildTracker_VoteTable = {}

	FauxScrollFrame_SetOffset(MTGuildTracker_RecipientListScrollFrame, 0);
	getglobal("MTGuildTracker_RecipientListScrollFrameScrollBar"):SetValue(0);


	MTGuildTracker_RecipientListScrollFrame_Update()
end

local function VoteTable_Tally()
	local tally_table = {}

	for sender, player_name in MTGuildTracker_VoteTable do
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
	MTGuildTracker_VoteTable[sender] = player_name
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
	for i,n in pairs(MTGuildTracker_LootHistoryTable) do
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
	local is_auto_close = (getglobal("MTGuildTracker_SessionAutoEndCheckButton"):GetChecked() == 1)
	if MTGuildTracker_OverviewTable.in_session == true and is_auto_close then
		vote_total = {}
		votes = 0

		for entry_key, entry in MTGuildTracker_RecipientTable do
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

		if (votes >= MTGuildTracker_OverviewTable.votes_needed) then
			if runner_up_votes == max_votes then
				echo("Session cannot end while tied!")
				return false
			else
				return true
			end
		elseif(max_votes > MTGuildTracker_OverviewTable.votes_needed/2) then
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
	table.sort(MTGuildTracker_RecipientTable, function(a,b) return RecipientTable_Sort_Function(sort_direction, recipient_sort_field, a, b) end)
end

local function RecipientTable_UpdateVotes()

	local tally_table = VoteTable_Tally()
	local vote_total = {}
	local total_votes = 0
	for entry_key, entry in MTGuildTracker_RecipientTable do
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
	for sender, player in MTGuildTracker_VoteTable do
		table.insert(all_voters, sender)
		end

	MTGuildTracker_OverviewTable.votes = getn(all_voters)
	MTGuildTracker_OverviewTable.voters = all_voters

	if Session_CanEnd() and isLeader() and (MTGuildTracker_OverviewTable.in_session == true) then
		MTGuildTracker_Broadcast_Session_End()
	end
end

local function RecipientTable_GetPlayerentry_key(player_name)
	local entry_key = 1;
	while MTGuildTracker_RecipientTable[entry_key] do
		if player_name == MTGuildTracker_RecipientTable[entry_key].player_name then
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
		entry_key = getn(MTGuildTracker_RecipientTable) + 1
		MTGuildTracker_RecipientTable[entry_key] = {}
		MTGuildTracker_RecipientTable[entry_key].voters = {}
	end

	debug("RecipientTable_Add entry_key", entry_key)

	local guild_rank = getPlayerGuildRank(player_name)
	local _, _, item_id, item_name = parseItemLink(item_link)
	MTGuildTracker_RecipientTable[entry_key].player_class = getPlayerClass(player_name)
	MTGuildTracker_RecipientTable[entry_key].player_guild_rank = guild_rank.name
	MTGuildTracker_RecipientTable[entry_key].player_guild_rank_id = guild_rank.entry_key
	MTGuildTracker_RecipientTable[entry_key].player_name = player_name
	MTGuildTracker_RecipientTable[entry_key].item_id = item_id
	MTGuildTracker_RecipientTable[entry_key].item_link = item_link
	MTGuildTracker_RecipientTable[entry_key].item_name = item_name

	MTGuildTracker_RecipientTable[entry_key].loot_count_table = GetPlayerLootCount(player_name)

 	local attendance = MTGuildTracker_Attendance[player_name]

	if attendance then
		last_8_weeks = tonumber(MTGuildTracker_Attendance[player_name].last_8_weeks)
		last_4_weeks = tonumber(MTGuildTracker_Attendance[player_name].last_4_weeks)
		last_2_weeks = tonumber(MTGuildTracker_Attendance[player_name].last_2_weeks)
	else
		last_8_weeks = 0
		last_4_weeks = 0
		last_2_weeks = 0
	end

	MTGuildTracker_RecipientTable[entry_key].attendance_last_8_weeks = last_8_weeks
	MTGuildTracker_RecipientTable[entry_key].attendance_last_4_weeks = last_4_weeks
	MTGuildTracker_RecipientTable[entry_key].attendance_last_2_weeks = last_2_weeks

	MTGuildTracker_RecipientListScrollFrame_Update()
end

function MTGuildTracker_RecipientListScrollFrame_Update()
	if not MTGuildTracker_RecipientTable then
		MTGuildTracker_RecipientTable = {}
	end

	RecipientTable_UpdateVotes()
	RecipientTable_Sort()

	getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetText(MTGuildTracker_OverviewTable.item_link)

	if isOfficer() or isLeader() then
		getglobal("MTGuildTracker_OverviewButtonTextVotes"):Show()
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):Show()

		if MTGuildTracker_OverviewTable.votes and MTGuildTracker_OverviewTable.votes_needed then
			getglobal("MTGuildTracker_OverviewButtonTextVotes"):SetText(MTGuildTracker_OverviewTable.votes .. "/" .. MTGuildTracker_OverviewTable.votes_needed)
		end
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):SetText(table.concat(MTGuildTracker_OverviewTable.voters, ", "))
	else
		getglobal("MTGuildTracker_OverviewButtonTextVotes"):Hide()
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):Hide()
	end

	if (MTGuildTracker_OverviewTable.in_session == true) then
		getglobal("MTGuildTracker_SessionEndButton"):Enable()
		getglobal("MTGuildTracker_SessionDEButton"):Enable()
		getglobal("MTGuildTracker_SessionCancelButton"):Enable()

		getglobal("MTGuildTracker_OverviewButtonTextVotes"):SetTextColor(.83,.68,.04,1)
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):SetTextColor(.83,.68,.04,1)
		getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetTextColor(.83,.68,.04,1)
	else
		getglobal("MTGuildTracker_SessionEndButton"):Disable()
		getglobal("MTGuildTracker_SessionDEButton"):Disable()
		getglobal("MTGuildTracker_SessionCancelButton"):Disable()

		getglobal("MTGuildTracker_OverviewButtonTextVotes"):SetTextColor(.5,.5,.5,1)
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):SetTextColor(.5,.5,.5,1)
		getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetTextColor(.5,.5,.5,1)
	end

	local max_lines = getn(MTGuildTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MTGuildTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MTGuildTracker_RecipientListScrollFrame, max_lines, 15, 25)
	for line = 1,15 do

		local entry_key = line + offset

		if entry_key <= max_lines then
			local recipient = MTGuildTracker_RecipientTable[entry_key]

			if MTGuildTracker_OverviewTable.in_session then
				rgb = class_colors[recipient.player_class]
				if not rgb then
					rgb = default_rgb
				end
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerName"):SetTextColor(rgb.r,rgb.g,rgb.b,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerGuildRank"):SetTextColor(.83,.68,.04,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetTextColor(.83,.68,.04,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast8Weeks"):SetTextColor(.83,.68,.04,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):SetTextColor(.83,.68,.04,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):SetTextColor(.83,.68,.04,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):SetTextColor(.83,.68,.04,1)
				for i,n in ipairs(recipient.loot_count_table) do
					getglobal("MTGuildTracker_RecipientListItem"..line.."TextLootCount"..i):SetTextColor(.83,.68,.04,1)
				end
			else
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerName"):SetTextColor(.5,.5,.5,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerGuildRank"):SetTextColor(.5,.5,.5,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetTextColor(.5,.5,.5,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast8Weeks"):SetTextColor(.5,.5,.5,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):SetTextColor(.5,.5,.5,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):SetTextColor(.5,.5,.5,1)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):SetTextColor(.5,.5,.5,1)
				for i,n in ipairs(recipient.loot_count_table) do
					getglobal("MTGuildTracker_RecipientListItem"..line.."TextLootCount"..i):SetTextColor(.5,.5,.5,1)
				end
			end

			getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerName"):SetText(recipient.player_name)
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerGuildRank"):SetText(recipient.player_guild_rank)
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetText(recipient.item_link)

			getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast8Weeks"):SetText(recipient.attendance_last_8_weeks .. "%")
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):SetText(recipient.attendance_last_4_weeks .. "%")

			for i,n in ipairs(recipient.loot_count_table) do
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextLootCount"..i):SetText(n)
			end

			if isOfficer() or isLeader() then
				getglobal("MTGuildTracker_RecipientListVoteBox"..line):Show()
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):Show()
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):Show()

				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):SetText(recipient.votes)
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):SetText(recipient.voters_text)

			else
				getglobal("MTGuildTracker_RecipientListVoteBox"..line):Hide()
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):Hide()
				getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):Hide()
			end

			if my_vote ~= nil and my_vote == recipient.player_name then
				getglobal("MTGuildTracker_RecipientListVoteBox"..line):SetChecked(true)
			else
				getglobal("MTGuildTracker_RecipientListVoteBox"..line):SetChecked(false)
			end

			getglobal("MTGuildTracker_RecipientListItem"..line):Show()

			if (MTGuildTracker_OverviewTable.in_session == true) then
				getglobal("MTGuildTracker_RecipientListVoteBox"..line):Enable()
			else
				getglobal("MTGuildTracker_RecipientListVoteBox"..line):Disable()
			end

		 else
			getglobal("MTGuildTracker_RecipientListItem"..line):Hide()
			getglobal("MTGuildTracker_RecipientListVoteBox"..line):Hide()
		 end
	end

	MTGuildTracker_Mode_Update()
end

-- Attendance Table

function AttendanceTable_Build()
	if not MTGuildTracker_Attendance then
		MTGuildTracker_Attendance = {}
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
	table.sort(MTGuildTracker_LootHistoryTable_Filtered, function(a,b) return LootHistory_Sort_Function(loot_sort_direction, loot_sort_field, a, b) end)
end

local function LootHistoryTable_Build()
	MTGuildTracker_LootHistoryTable = {}

	if not MTGuildTrackerDB then
		MTGuildTrackerDB = {}
	end

	for entry_key in MTGuildTrackerDB do
		MTGuildTracker_LootHistoryTable[entry_key] = {}
		local item_link = MTGuildTrackerDB[entry_key].item_link
		local item_name =  MTGuildTrackerDB[entry_key].item_name
		local item_quality = MTGuildTrackerDB[entry_key].item_quality
		local item_color = MTGuildTrackerDB[entry_key].item_color
		local item_id = MTGuildTrackerDB[entry_key].item_id


		if item_link == nil then
			item_link = buildItemLink(item_id,  item_name, item_color, item_quality)
		end

		MTGuildTracker_LootHistoryTable[entry_key].entry_key    = entry_key
		MTGuildTracker_LootHistoryTable[entry_key].time_stamp   = MTGuildTrackerDB[entry_key].time_stamp
		MTGuildTracker_LootHistoryTable[entry_key].date         = MTGuildTrackerDB[entry_key].date
		MTGuildTracker_LootHistoryTable[entry_key].use_case     = MTGuildTrackerDB[entry_key].use_case
		MTGuildTracker_LootHistoryTable[entry_key].raid_name    = MTGuildTrackerDB[entry_key].raid_name
		MTGuildTracker_LootHistoryTable[entry_key].item_name    = item_name
		MTGuildTracker_LootHistoryTable[entry_key].item_id      = item_id
		MTGuildTracker_LootHistoryTable[entry_key].item_quality = item_quality
		MTGuildTracker_LootHistoryTable[entry_key].item_link    = item_link
		MTGuildTracker_LootHistoryTable[entry_key].player_name  = firstToUpper(MTGuildTrackerDB[entry_key].player_name)
		MTGuildTracker_LootHistoryTable[entry_key].player_class = firstToUpper(MTGuildTrackerDB[entry_key].player_class)
	end

	MTGuildTracker_LootHistoryScrollFrame_Update();
end

local function LootHistoryTable_UpdateEntry(entry)
	if not entry then
		debug("null entry update")
		return
	end

	entry_key = entry["entry_key"]

	if MTGuildTrackerDB[entry_key] == nil then
		MTGuildTrackerDB[entry_key] = {}
	end

	MTGuildTrackerDB[entry_key] = entry
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
	MTGuildTracker_LootHistoryTable_Filtered = {}
	for k,v in pairs(MTGuildTracker_LootHistoryTable) do
		
		if searchString and searchString == HISTORY_DELETED then
			if v.use_case == HISTORY_DELETED then
				table.insert(MTGuildTracker_LootHistoryTable_Filtered, v)
			end
		elseif searchString and searchString ~= "" then
			local search_list = Parse_String_List(searchString)
			if (List_Contains(search_list, v.player_name, true) == true) or 
				(List_Contains(search_list, v.player_class, true) == true) or 
				(List_Contains(search_list, v.item_name, false) == true) then
				table.insert(MTGuildTracker_LootHistoryTable_Filtered, v)
			end
		else
			if v.use_case ~= HISTORY_DELETED then
				table.insert(MTGuildTracker_LootHistoryTable_Filtered, v)
			end
		end
	end
end

function MTGuildTracker_LootHistoryScrollFrame_Update()

	if not MTGuildTracker_LootHistoryTable then
		MTGuildTracker_LootHistoryTable = {};
	end

	LootHistory_Filter()
	LootHistory_Sort()

	local maxlines = getn(MTGuildTracker_LootHistoryTable_Filtered)
	local offset = FauxScrollFrame_GetOffset(MTGuildTracker_LootHistoryScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MTGuildTracker_LootHistoryScrollFrame, maxlines, 15, 25)

	for line=1,15 do
		 lineplusoffset = line + offset
		 if lineplusoffset <= maxlines then
		 	local player_class =  MTGuildTracker_LootHistoryTable_Filtered[lineplusoffset].player_class

		 	if player_class == nil then
		 		player_class = ""
		 	end

		 	local rgb = class_colors[player_class]
		 	if not rgb then
				rgb = default_rgb
			end
			getglobal("MTGuildTracker_LootHistoryListItem"..line.."TextPlayerName"):SetTextColor(rgb.r,rgb.g,rgb.b,1)
			getglobal("MTGuildTracker_LootHistoryListItem"..line.."TextPlayerName"):SetText(MTGuildTracker_LootHistoryTable_Filtered[lineplusoffset].player_name)
			getglobal("MTGuildTracker_LootHistoryListItem"..line.."TextItemName"):SetText(MTGuildTracker_LootHistoryTable_Filtered[lineplusoffset].item_link)
			getglobal("MTGuildTracker_LootHistoryListItem"..line.."TextRaidName"):SetText(MTGuildTracker_LootHistoryTable_Filtered[lineplusoffset].raid_name)
			getglobal("MTGuildTracker_LootHistoryListItem"..line.."TextDate"):SetText(MTGuildTracker_LootHistoryTable_Filtered[lineplusoffset].date)
			getglobal("MTGuildTracker_LootHistoryListItem"..line.."TextUseCase"):SetText(MTGuildTracker_LootHistoryTable_Filtered[lineplusoffset].use_case)
			getglobal("MTGuildTracker_LootHistoryListItem"..line):Show()
		 else
			getglobal("MTGuildTracker_LootHistoryListItem"..line):Hide()
		 end
	end
end

-- Session Commands

function MTGuildTracker_Session_List()
	for k,v in pairs(session_queue) do
		echo(k, v)
	end
	-- body
end

function MTGuildTracker_Session_Queue(item_link)

	if not session_queue then
		session_queue = {}
	end

	if item_link == nil or item_link=="" then
		echo("Cannot start a session without loot")
	elseif not (MTGuildTracker_OverviewTable.in_session==true) and getn(session_queue) == 0 then
		MTGuildTracker_Broadcast_Session_Start(item_link)
	else
		echo("A session for "..item_link.." has been queued")
		table.insert(session_queue, item_link)
	end
end

function MTGuildTracker_Session_Dequeue(entry_key)

	if not session_queue or not entry_key or tonumber(entry_key) < 1 or tonumber(entry_key) > getn(session_queue) then
		echo("Please provide a valid queue list entry_key")
	else
		item_link = table.remove(session_queue, entry_key)
		echo("Removed queued session for ", item_link)
	end
	-- body
end

function MTGuildTracker_Broadcast_Message_Echo(message)
	if message then
		addonEcho_leader("TX_MESSAGE_ECHO", message);
	end
end

function MTGuildTracker_Handle_Message_Echo(message, sender)
	echo(message)
end

-- Recipient Broadcast

function MTGuildTracker_Broadcast_RecipientTable_Add(player_name, item_link)
	if MTGuildTracker_OverviewTable.in_session == true then
		local player_name = firstToUpper(player_name)
		local player_class = getPlayerClass(player_name)

		if player_class == "???" then
			--echo("Error adding player " .. player_name .. ". Player must be in the raid.")
			--return
		end

		addonEcho_leader("TX_ENTRY_ADD", string.format("%s/%s", player_name, item_link));
	else
		echo_leader("No session in progress")
	end
end

function MTGuildTracker_Handle_RecipientTable_Add(message, sender)
	local _, _, player_name, item_link = string.find(message, "([^/]*)/(.*)")

	RecipientTable_Add(player_name, item_link)
end

-- Vote Broadcast

function MTGuildTracker_Broadcast_VoteTable_Add(player_name)
	if MTGuildTracker_OverviewTable.in_session == true then
		if player_name then
			addonEcho("TX_VOTE_ADD", string.format("%s", player_name));
		else
			addonEcho("TX_VOTE_ADD", "");
		end
	else
		echo("No session in progress")
	end
end

function MTGuildTracker_Handle_VoteTable_Add(message, sender)
	local _, _, player_name = string.find(message, "([^/]+)")

	VoteTable_Add(player_name, sender)
	MTGuildTracker_RecipientListScrollFrame_Update()
end

-- Session Start Broadcast

function MTGuildTracker_Broadcast_Session_Start(item_link)
	if MTGuildTracker_OverviewTable.in_session == true then
		echo_leader("A session for "..MTGuildTracker_OverviewTable.item_link.." is in progress")
	elseif item_link == nil or item_link=="" then
		echo_leader("Cannot start a session without loot")
	else
		MTGuildTracker_Sync_Time_Start()
		addonEcho_leader("TX_SESSION_START", item_link);
	end
end

function MTGuildTracker_Handle_Session_Start(message, sender)
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

	MTGuildTracker_OverviewTable = {}
	MTGuildTracker_OverviewTable.in_session = true
	MTGuildTracker_OverviewTable.item_id = item_id
	MTGuildTracker_OverviewTable.item_link = item_message
	MTGuildTracker_OverviewTable.item_name = item_name
	MTGuildTracker_OverviewTable.votes_needed = votes_needed
	MTGuildTracker_OverviewTable.votes = 0
	MTGuildTracker_OverviewTable.voters = ""

	Session_Clear()

	echo("Session started : ".. item_message)

	local sample_itemlink = buildItemLink(8952, "Your Current Item", MTGuildTracker_color_common, nil) 

	leaderRaidWarnEcho("Session started : ".. item_message)
	leaderRaidEcho("To be considered for the item type in raid chat \""..SLASH_COMMAND_SHORT.." "..sample_itemlink.."\"")
end

-- Session End Broadcast

function MTGuildTracker_Broadcast_Session_DE()
	MTGuildTracker_Broadcast_Session_Finish(DE_BANK);
end

function MTGuildTracker_Broadcast_Session_End()
	MTGuildTracker_Broadcast_Session_Finish("end");
end

function MTGuildTracker_Broadcast_Session_Cancel()
	MTGuildTracker_Broadcast_Session_Finish("cancel");
end

function MTGuildTracker_Broadcast_Session_ForceCancel()
	addonEcho("TX_SESSION_FINISH","force_cancel");
end

function MTGuildTracker_Broadcast_Session_Finish(mode)

	if MTGuildTracker_OverviewTable.in_session then
		debug("MTGuildTracker_Broadcast_Session_Finish mode", mode)

		MTGuildTracker_OverviewTable.in_session = false

		local vote_total = {}
		local votes = 0

		for entry_key, recipient in MTGuildTracker_RecipientTable do
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
			end_announcement = "Session canceled : ".. MTGuildTracker_OverviewTable.item_link
		elseif mode == DE_BANK then
 			end_type = 'ended'
		 	end_announcement = "Session ended : ".. MTGuildTracker_OverviewTable.item_link.." - Item will be Disenchanted or sent to the Bank"
		else
		 	end_type = 'ended'
		 	end_announcement = "Session ended : ".. MTGuildTracker_OverviewTable.item_link.." - Congratulations "..sortedKeys[1].."!"
		end

		MTGuildTracker_Broadcast_Message_Echo("Session " .. end_type .. " : ".. MTGuildTracker_OverviewTable.item_link.." - ("..MTGuildTracker_OverviewTable.votes.."/"
		..MTGuildTracker_OverviewTable.votes_needed..") "..table.concat( MTGuildTracker_OverviewTable.voters, ", " ))

		if getn(stringList) > 0 then
			local summary_string = table.concat(stringList, ", ")
			MTGuildTracker_Broadcast_Message_Echo(summary_string)
		end

		leaderRaidWarnEcho(end_announcement)

		addonEcho("TX_SESSION_FINISH",mode);

		if mode == "end" or mode == DE_BANK then
			local player_name;
			if mode == DE_BANK then
				player_name = DE_BANK
			else 
				player_name = sortedKeys[1]
			end

			if MTGuildTracker_OverviewTable.item_link then
				local entry = LootHistoryTable_AddEntry(MTGuildTracker_OverviewTable.item_link, player_name)
				MTGuildTracker_Broadcast_Sync_Start();
				local sync_string = MTGuildTracker_SendSync_String("loothistory", entry)
				MTGuildTracker_Broadcast_Sync_Add("loothistory", sync_string)
				MTGuildTracker_Broadcast_Sync_End(false);

			end
		end

		MTGuildTracker_RecipientListScrollFrame_Update()
	else
		echo("No Session in progress")
	end
end

function MTGuildTracker_Handle_Session_Finish(message)
	local mode = message;
	debug("MTGuildTracker_Handle_Session_Finish mode", mode)
	if MTGuildTracker_OverviewTable.in_session then
		if mode == "force_cancel" then
			echo("Session canceled: Error with syncing")
		end
		MTGuildTracker_OverviewTable.in_session = false
		MTGuildTracker_RecipientListScrollFrame_Update()
	end
end

-- AutoEnd UI Broadcast

function MTGuildTracker_Broadcast_AutoEnd(autoclose)
	if autoclose then
		addonEcho("TX_SESSION_AUTOCLOSE", "1");
	else
		addonEcho("TX_SESSION_AUTOCLOSE", "0");
	end
end

function MTGuildTracker_Handle_AutoClose(message, sender)
	local _, _, state = string.find(message, "(.*)");

	if state == "1" then
		getglobal("MTGuildTracker_SessionAutoEndCheckButton"):SetChecked(true)
	else
		getglobal("MTGuildTracker_SessionAutoEndCheckButton"):SetChecked(false)
	end
end

-- TODO

function MTGuildTracker_SendSync_String(table_name, entry, key)

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

function MTGuildTracker_ReadSync_Entry(table_name, fields_string)

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
			browse_rarityhexlink = MTGuildTracker_color_common
		elseif item_quality == "uncommon" then
			browse_rarityhexlink = MTGuildTracker_color_uncommon
		elseif item_quality == "rare" then
			browse_rarityhexlink = MTGuildTracker_color_rare
		elseif item_quality == "epic" then
			browse_rarityhexlink = MTGuildTracker_color_epic
		elseif item_quality == "legendary" then
			browse_rarityhexlink = MTGuildTracker_color_legendary
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

function MTGuildTracker_Send_Sync()
	for k,v in pairs(MTGuildTracker_LootHistoryTable) do
		local sync_string = MTGuildTracker_SendSync_String("loothistory", v)
		MTGuildTracker_Broadcast_Sync_Add("loothistory", sync_string)
	end
	for k,v in pairs(MTGuildTracker_Attendance) do
		local sync_string = MTGuildTracker_SendSync_String("attendance", v)
		MTGuildTracker_Broadcast_Sync_Add("attendance", sync_string)
	end
end

function MTGuildTracker_Save_Sync(clear_table)

	last_sync_time = get_server_time()

	-- Loot History Table
	if clear_table and getn(MTGuildTracker_LootHistoryTable_Temp) > 0 then
		MTGuildTrackerDB = {}
	end

	for k,v in pairs(MTGuildTracker_LootHistoryTable_Temp) do
		LootHistoryTable_UpdateEntry(v)
	end

	MTGuildTracker_LootHistoryTable_Temp = {}

	-- Attendance Table
	if clear_table and getn(MTGuildTracker_Attendance_Temp) > 0 then
		MTGuildTracker_Attendance = {}
	end

	for k,v in pairs(MTGuildTracker_Attendance_Temp) do
		MTGuildTracker_Attendance[k] = v
	end

	local time_stamp = date("%y-%m-%d %H:%M:%S")
	MTGuildTracker_LastUpdate = {}
	MTGuildTracker_LastUpdate["time_stamp"] = time_stamp

	-- Refresh View
	LootHistoryTable_Build()
	MTGuildTracker_RecipientListScrollFrame_Update();
end

-- Version Broadcast

function MTGuildTracker_Broadcast_PerformSync_Request() 
	addonEcho("TX_PERFORM_SYNC_REQUEST", "");
end

function MTGuildTracker_Handle_PerformSync_Request()
	if isLeader() and not version_request_in_progress then
		MTGuildTracker_Version_Start()
	end
end

function MTGuildTracker_Version_Start()
	if isLeader() and not version_request_in_progress then
		getglobal("MTGuildTracker_LootHistorySyncButton"):Disable()
		version_request_in_progress = true
		response_versions = {}
		MTGuildTracker_Broadcast_Version_Request()
	end
end

function MTGuildTracker_Broadcast_Version_Request()
	if isLeader() then
		debug("MTGuildTracker_Broadcast_Version_Request")
		addonEcho("TX_VERSION_REQUEST", "");
	end
end

function MTGuildTracker_Handle_Version_Request(message, sender)
	debug("MTGuildTracker_Handle_Version_Request")
	echo("Syncing Loot History")
	MTGuildTracker_Broadcast_Version_Response()
end

function MTGuildTracker_Broadcast_Version_Response()
	if MTGuildTracker_LastUpdate ~= nil and MTGuildTracker_LastUpdate["time_stamp"] ~= nil then
		debug("MTGuildTracker_Broadcast_Version_Response")
		addonEcho("TX_VERSION_RESPONSE", MTGuildTracker_LastUpdate["time_stamp"]);
	end
end

function MTGuildTracker_Handle_Version_Response(message, sender)
	if isLeader() then
		debug("MTGuildTracker_Handle_Version_Response")
		response_versions[sender] = message
	end
end

function MTGuildTracker_Version_End()
	debug("MTGuildTracker_Version_End")
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
		debug("MTGuildTracker_Version_End", max_sender.." is master");
	else
		debug("MTGuildTracker_Version_End", "I am master");
	end
	MTGuildTracker_Broadcast_Sync_Request(max_sender)

end

-- Upload Sync

function MTGuildTracker_Broadcast_Sync_Request(player_name)
	if isLeader() and not sync_in_progress then
		debug("MTGuildTracker_Broadcast_Sync_Request")
		addonEcho("TX_SYNC_REQUEST", player_name);
	end
end

function MTGuildTracker_Handle_Sync_Request(message, sender)
	local player_name = message
	if UnitName("player") == player_name then
		debug("MTGuildTracker_Handle_Sync_Request");
		MTGuildTracker_Broadcast_Message_Echo("Sync Started")
		MTGuildTracker_Broadcast_Sync_Start();
		MTGuildTracker_Send_Sync();
		MTGuildTracker_Broadcast_Sync_End(true);
		MTGuildTracker_Broadcast_Message_Echo("Sync Completed")
	end
end

function MTGuildTracker_Broadcast_Sync_Start()
	debug("MTGuildTracker_Broadcast_Sync_Start");
	addonEcho("TX_SYNC_START", "");
end

function MTGuildTracker_Handle_Sync_Start(message, sender)
	getglobal("MTGuildTracker_LootHistorySyncButton"):Disable()

	if not sync_in_progress then
		sync_in_progress = true
		MTGuildTracker_Attendance_Temp = {}
		MTGuildTracker_LootHistoryTable_Temp = {}
		debug("MTGuildTracker_Handle_Sync_Start");
	end
end

function MTGuildTracker_Broadcast_Sync_Add(table_name, sync_string)
	addonEcho("TX_SYNC_ADD", sync_string);
end

function MTGuildTracker_Handle_Sync_Add(message, sender)
	if sync_in_progress then
		local _, _, table_name, fields_string = string.find(message, "([^/]*)/(.*)");

		entry = MTGuildTracker_ReadSync_Entry(table_name, fields_string)

		if table_name == "loothistory" then
			table.insert(MTGuildTracker_LootHistoryTable_Temp, entry)
		elseif table_name == "attendance" then
			MTGuildTracker_Attendance_Temp[entry["player_name"]] = entry
		end
	end
end

function MTGuildTracker_Broadcast_Sync_End(clear_table)
	debug("MTGuildTracker_Broadcast_Sync_End");

	if clear_table then
		addonEcho("TX_SYNC_END","1");
	else
		addonEcho("TX_SYNC_END","0");
	end
end

function MTGuildTracker_Handle_Sync_End(message, sender)
	local clear_table = message
	if sync_in_progress then
		sync_in_progress = false

		debug("MTGuildTracker_Handle_Sync_End clear_table", clear_table)
		getglobal("MTGuildTracker_LootHistorySyncButton"):Enable()

		MTGuildTracker_Save_Sync(clear_table == "1")
	end
end

function MTGuildTracker_Sync_Time_Start()
	debug("MTGuildTracker_Sync_Time_Start")
	if isLeader() and not sync_time_request_in_progress then
		sync_time_request_in_progress = true
		response_sync_times = {}
		MTGuildTracker_Broadcast_Sync_Time_Request()
	end
end

function MTGuildTracker_Sync_Time_End()
	debug("MTGuildTracker_Sync_Time_End")
	sync_time_request_in_progress = false

	max_sender = UnitName("player")
	max_time_stamp = response_sync_times[UnitName("player")]
	
	update_needed = false

	for sender,time_stamp in pairs(response_sync_times) do
		debug("time_stamp", time_stamp)
		if time_stamp == "" then
			update_needed = true
		elseif time_stamp ~= nill and (time_stamp ~= max_time_stamp) then
			update_needed = true
		end
	end

	if update_needed then
		debug("MTGuildTracker_Sync_Time_End", " update needed");
		MTGuildTracker_Broadcast_Sync_Request(max_sender)
	else
		debug("MTGuildTracker_Sync_Time_End", "no update needed");	
	end
end

function MTGuildTracker_Broadcast_Sync_Time_Request()
	if isLeader() and not sync_in_progress then
		debug("MTGuildTracker_Broadcast_Get_Last_Sync_Time");
		addonEcho("TX_SYNC_TIME_REQUEST","");
	end
end

function MTGuildTracker_Handle_Sync_Time_Request(message, sender)
	debug("MTGuildTracker_Handle_Sync_Time_Request")
	MTGuildTracker_Broadcast_Sync_Time_Response()
end

function MTGuildTracker_Broadcast_Sync_Time_Response()
	debug("MTGuildTracker_Broadcast_Sync_Time_Response")
	addonEcho("TX_SYNC_TIME_RESPONSE",last_sync_time);
end

function MTGuildTracker_Handle_Sync_Time_Response(message, sender)
	if isLeader() then
		debug("MTGuildTracker_Handle_Sync_Time_Response")
		response_sync_times[sender] = message
	end
end

-- UI LINK

function MTGuildTracker_ChatLink(button, link)
	 if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			ChatFrameEditBox:Insert(link)
		end
	end
end

function MTGuildTracker_RecipientButton_OnClick(button, entry_key)
	local link = MTGuildTracker_RecipientTable[entry_key].item_link
	MTGuildTracker_ChatLink(button, link)
end

function MTGuildTracker_LootHistoryEditorSaveButton_OnClick()
	getglobal("MTGuildTracker_LootHistoryEditorFrame"):Hide()
	local name_box_text = MTGuildTracker_LootHistoryEditor_NameBox:GetText()

	if name_box_text4 ~= "" then
		LootHistoryEditorEntry.player_name = name_box_text

		if LootHistoryEditorEntry["use_case"] == DE_BANK or  LootHistoryEditorEntry["use_case"] == HISTORY_DELETED then
			LootHistoryEditorEntry.player_class = ""
		end

		MTGuildTracker_Broadcast_Sync_Start();
		local sync_string = MTGuildTracker_SendSync_String("loothistory", LootHistoryEditorEntry)
		MTGuildTracker_Broadcast_Sync_Add("loothistory", sync_string)
		MTGuildTracker_Broadcast_Sync_End(false);
		MTGuildTracker_LootHistoryScrollFrame_Update()
	end
end

function LootTracker_OptionCheckButton_Check(id)

	for index = 1,getn(lootHistoryUseCase),1  do
		getglobal("MTGuildTracker_LootHistoryEditor_UseCase"..index):SetChecked(id==index)
	end

	if id == 4 then
		player_name= DE_BANK
		use_index = 1
	elseif id == 5 then
		player_name= HISTORY_DELETED
		use_index = 1
	else
		player_name = LootHistoryEditorEntry.player_name
		use_index = GetPlayerClassDropDownIndex(LootHistoryEditorEntry.player_class)
	end

	getglobal("MTGuildTracker_LootHistoryEditor_NameBox"):SetText(player_name)
	UIDropDownMenu_SetSelectedID(MTGuildTracker_LootHistoryEditor_ClassDropDown,use_index)
	LootHistoryEditorEntry["use_case"] = lootHistoryUseCase[id]
end

function MTGuildTracker_LootHistoryEditor_UseCaseButton_OnClick(id)
	local useCase = lootHistoryUseCase[id]

	if getglobal("MTGuildTracker_LootHistoryEditor_UseCase"..id):GetChecked() then
		LootTracker_OptionCheckButton_Check(id)
	else
		LootTracker_OptionCheckButton_Check(1)
	end
end

function MTGuildTracker_LootHistoryEditor_ClassDropDown_OnClick()
	local id = this:GetID();
	UIDropDownMenu_SetSelectedID(MTGuildTracker_LootHistoryEditor_ClassDropDown, id);
	
	if( id > 1) then
		searchSlot = playerClassSlotNames[id-1].name;
	else
		searchSlot = nil;
	end	

	LootHistoryEditorEntry.player_class = playerClassSlotNames[id].slot
end

function MTGuildTracker_LootHistoryEditor_ClassDropDown_Initialize()
	local info;

	for i = 1, getn(playerClassSlotNames), 1 do
		info = { };
		info.text = playerClassSlotNames[i].slot;
		info.func = MTGuildTracker_LootHistoryEditor_ClassDropDown_OnClick;
		UIDropDownMenu_AddButton(info);
	end
end

function MTGuildTracker_LootHistoryEditor_ClassDropDown_OnShow()
     UIDropDownMenu_Initialize(this, MTGuildTracker_LootHistoryEditor_ClassDropDown_Initialize);
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
	elseif player_name == HISTORY_DELETED then
		use_case_index = 5
	end

	for index, name in ipairs(lootHistoryUseCase) do
		if LootHistoryEditorEntry["use_case"] == name then
			use_case_index = index
		end
	end

	return use_case_index
end

function MTGuildTracker_LootHistoryEditor_Open(index)
	ShowUIPanel(MTGuildTracker_LootHistoryEditorFrame, 1)

	LootHistoryEditorEntry =  MTGuildTracker_LootHistoryTable_Filtered[index]

	local player_class = LootHistoryEditorEntry.player_class
	local player_name = LootHistoryEditorEntry.player_name

	local player_class_index = GetPlayerClassDropDownIndex(player_class)

	local use_case_index = GetUseCaseDropDownIndex(player_name, LootHistoryEditorEntry["use_case"])

	LootTracker_OptionCheckButton_Check(use_case_index)
	UIDropDownMenu_SetSelectedID(MTGuildTracker_LootHistoryEditor_ClassDropDown,LootHistoryEditorEntry.player_class_index)

	getglobal("MTGuildTracker_LootHistoryEditor_TextItemName"):SetText(LootHistoryEditorEntry.item_link)
	getglobal("MTGuildTracker_LootHistoryEditor_NameBox"):SetText(LootHistoryEditorEntry.player_name)
end

function MTGuildTracker_LootHistoryEditorFrame_OnShow()
	
end

function MTGuildTracker_LootHistoryButton_OnClick(button, entry_key)
	if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			local link = MTGuildTracker_LootHistoryTable_Filtered[entry_key].item_link
			MTGuildTracker_ChatLink(button, link)
		end
	elseif button == "RightButton" and (isOfficer() or isLeader()) then
		MTGuildTracker_LootHistoryEditor_Open(entry_key)
	end
end

function MTGuildTracker_OverviewButton_OnClick(button)
	local link = MTGuildTracker_OverviewTable.item_link
	MTGuildTracker_ChatLink(button, link)
end

-- UI Drag

function MTGuildTracker_Main_OnMouseDown(button)
	if (button == "LeftButton") then
		this:StartMoving();
	end
end

function MTGuildTracker_Main_OnMouseUp(button)
	if (button == "LeftButton") then
		this:StopMovingOrSizing()

	end
end

-- UI Tooltip

function MTGuildTracker_Tooltip_Show(item_id)
	if item_id then
		MTGuildTracker_Tooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
		MTGuildTracker_Tooltip:SetHyperlink("item:" .. item_id .. ":0:0:0")
		MTGuildTracker_Tooltip:Show()
	end
end

function MTGuildTracker_Tooltip_Hide()
	MTGuildTracker_Tooltip:Hide()
end

function MTGuildTracker_RecipientButton_OnEnter(entry_key)
	local item_id = MTGuildTracker_RecipientTable[entry_key].item_id
	MTGuildTracker_Tooltip_Show(item_id)
end

function MTGuildTracker_RecipientButton_OnLeave()
	MTGuildTracker_Tooltip_Hide()
end

function MTGuildTracker_OverviewButton_OnEnter()
	local item_id = MTGuildTracker_OverviewTable.item_id
	MTGuildTracker_Tooltip_Show(item_id)
end

function MTGuildTracker_OverviewButton_OnLeave()
	MTGuildTracker_Tooltip_Hide()
end

function MTGuildTracker_LootHistoryButton_OnEnter(entry_key)
	local item_id = MTGuildTracker_LootHistoryTable_Filtered[entry_key].item_id
	MTGuildTracker_Tooltip_Show(item_id)
end

function MTGuildTracker_LootHistoryButton_OnLeave()
	MTGuildTracker_Tooltip_Hide()
end

function MTGuildTracker_LootHistoryEditor_ItemNameButton_OnClick(button)
	local link = LootHistoryEditorEntry.item_link
	MTGuildTracker_ChatLink(button, link)
end 

function MTGuildTracker_LootHistoryEditor_ItemNameButton_OnEnter()
	local item_id = LootHistoryEditorEntry.item_id
	MTGuildTracker_Tooltip_Show(item_id)
end

function MTGuildTracker_LootHistoryEditor_ItemNameButton_OnLeave()
	MTGuildTracker_Tooltip_Hide()
end
-- Session UI


function MTGuildTracker_Mode_Update()
	if is_min_mode then
		getglobal("MTGuildTracker_SessionMinButton"):SetText("Max")
		MTGuildTracker_SessionMinMode()
	else
		getglobal("MTGuildTracker_SessionMinButton"):SetText("Min")
		MTGuildTracker_SessionMaxMode()
	end
end

function MTGuildTracker_SessionMinButton_OnClick()
	is_min_mode = not is_min_mode
	MTGuildTracker_Mode_Update()
end

function MTGuildTracker_SessionMinMode() 
	local max_lines = getn(MTGuildTracker_RecipientTable)

	local min_width = 272

	local min_height = 320

	getglobal("MTGuildTracker_OverviewButtonTextVoters"):Hide()
	
	getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetWidth(125);
	getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetPoint("LEFT", 5, 0);



	getglobal("MTGuildTracker_OverviewButtonTextVoters"):Hide()

	getglobal("MTGuildTracker_SessionEndButton"):Hide()
	getglobal("MTGuildTracker_SessionDEButton"):Hide()
	getglobal("MTGuildTracker_SessionCancelButton"):Hide()
	getglobal("MTGuildTracker_SessionAutoEndCheckButton"):Hide()

	getglobal("MTGuildTracker_LootHistoryTabButton"):Hide()

	getglobal("MTGuildTracker_RecipientListSortPlayerGuildRank"):Hide()

	for i,n in ipairs(week_list) do
		getglobal("MTGuildTracker_RecipientListSortLootCount"..i):Hide()
	end
	-- 320
	getglobal("MTGuildTracker_RecipientListSortLootCountTitle"):Hide()
	getglobal("MTGuildTracker_RecipientListSortPlayerAttendanceTitle"):Hide()
	getglobal("MTGuildTracker_RecipientListSortPlayerAttendanceLast8Weeks"):Hide()
	getglobal("MTGuildTracker_RecipientListSortPlayerAttendanceLast4Weeks"):Hide()

	getglobal("MTGuildTracker_BrowseFrame"):SetHeight(min_width+18)
	getglobal("MTGuildTracker_LootSessionFrame"):SetHeight(min_width)

	getglobal("MTGuildTracker_BrowseFrame"):SetWidth(min_width+18)
	getglobal("MTGuildTracker_RecipientListSortFrame"):SetWidth(min_width-7)
	getglobal("MTGuildTracker_LootSessionFrame"):SetWidth(min_width)
	--getglobal("MTGuildTracker_RecipientListSortFrame"):SetWidth(300)
	local max_lines = getn(MTGuildTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MTGuildTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each linevmkm
	
	if max_lines < 15 then
		min_height = min_height - 16*(15 - max_lines)
	end

	getglobal("MTGuildTracker_BrowseFrame"):SetHeight(min_height + 11)
	getglobal("MTGuildTracker_LootSessionFrame"):SetHeight(min_height)

	for line = 1,15 do
		getglobal("MTGuildTracker_RecipientListItem"..line):SetWidth(min_width)
		getglobal("MTGuildTracker_RecipientListItem"..line.."HighlightTexture"):SetWidth(min_width)

		getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerGuildRank"):Hide()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast8Weeks"):Hide()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):Hide()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):Hide()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetWidth(125);
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetPoint("LEFT", getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerName"), "RIGHT", 5, 0);

		for i,n in ipairs(week_list) do
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextLootCount"..i):Hide()
		end
	end
end

function MTGuildTracker_SessionMaxMode() 
	local max_width = 700
	getglobal("MTGuildTracker_OverviewButtonTextVoters"):Show()
	getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetWidth(200);
	getglobal("MTGuildTracker_OverviewButtonTextItemName"):SetPoint("LEFT", 265, 0);


	getglobal("MTGuildTracker_LootHistoryTabButton"):Show()

	getglobal("MTGuildTracker_RecipientListSortPlayerGuildRank"):Show()

	getglobal("MTGuildTracker_RecipientListSortPlayerAttendanceTitle"):Show()
	getglobal("MTGuildTracker_RecipientListSortPlayerAttendanceLast8Weeks"):Show()
	getglobal("MTGuildTracker_RecipientListSortPlayerAttendanceLast4Weeks"):Show()

	getglobal("MTGuildTracker_BrowseFrame"):SetWidth(max_width+43)
	getglobal("MTGuildTracker_RecipientListSortFrame"):SetWidth(max_width+20)
	getglobal("MTGuildTracker_LootSessionFrame"):SetWidth(max_width)

	getglobal("MTGuildTracker_BrowseFrame"):SetHeight(320)
	getglobal("MTGuildTracker_LootSessionFrame"):SetHeight(287)

	for i,n in ipairs(week_list) do
		getglobal("MTGuildTracker_RecipientListSortLootCount"..i):Show()
	end

	if isOfficer() or isLeader() then
		getglobal("MTGuildTracker_OverviewButtonTextVotes"):Show()
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):Show()
	else 
		getglobal("MTGuildTracker_OverviewButtonTextVotes"):Hide()
		getglobal("MTGuildTracker_OverviewButtonTextVoters"):Hide()
	end

	if isLeader() then
		getglobal("MTGuildTracker_SessionEndButton"):Show()
		getglobal("MTGuildTracker_SessionDEButton"):Show()
		getglobal("MTGuildTracker_SessionCancelButton"):Show()
	else 
		getglobal("MTGuildTracker_SessionEndButton"):Hide()
		getglobal("MTGuildTracker_SessionDEButton"):Hide()
		getglobal("MTGuildTracker_SessionCancelButton"):Hide()
	end
	getglobal("MTGuildTracker_RecipientListSortLootCountTitle"):Show()

	local max_lines = getn(MTGuildTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MTGuildTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MTGuildTracker_RecipientListScrollFrame, max_lines, 15, 25)
	for line = 1,15 do
		getglobal("MTGuildTracker_RecipientListItem"..line):SetWidth(max_width)
		getglobal("MTGuildTracker_RecipientListItem"..line.."HighlightTexture"):SetWidth(max_width)
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerGuildRank"):Show()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast8Weeks"):Show()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerAttendanceLast4Weeks"):Show()
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetWidth(175);
		getglobal("MTGuildTracker_RecipientListItem"..line.."TextItemName"):SetPoint("LEFT", getglobal("MTGuildTracker_RecipientListItem"..line.."TextPlayerGuildRank"), "RIGHT", 5, 0);

		for i,n in ipairs(week_list) do
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextLootCount"..i):Show()
		end

		getglobal("MTGuildTracker_SessionAutoEndCheckButton"):Show()

		if isOfficer() or isLeader() then
			getglobal("MTGuildTracker_RecipientListVoteBox"..line):Show()
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):Show()
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):Show()

		else
			getglobal("MTGuildTracker_RecipientListVoteBox"..line):Hide()
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextVotes"):Hide()
			getglobal("MTGuildTracker_RecipientListItem"..line.."TextVoters"):Hide()
		end
	end
end

function MTGuildTracker_VoteCheckButton_OnClick(line)
	local offset = FauxScrollFrame_GetOffset(MTGuildTracker_RecipientListScrollFrame);
	local entry_key = line + offset
	local player_name = MTGuildTracker_RecipientTable[entry_key].player_name

	if getglobal("MTGuildTracker_RecipientListVoteBox"..line):GetChecked() then
		my_vote = player_name
	else
		my_vote = nil
	end

	for other_line = 1,15 do
		if other_line ~= line then
			getglobal("MTGuildTracker_RecipientListVoteBox"..line):SetChecked(false)
		end
	end

	MTGuildTracker_Broadcast_VoteTable_Add(my_vote)
end

function MTGuildTracker_SessionDEButton_OnClick()
	MTGuildTracker_Broadcast_Session_DE()
end

function MTGuildTracker_SessionEndButton_OnClick()
	MTGuildTracker_Broadcast_Session_End()
end

function MTGuildTracker_SessionCancelButton_OnClick()
	MTGuildTracker_Broadcast_Session_Cancel()
end

function MTGuildTracker_LootHistorySyncButton_OnClick()
	MTGuildTracker_Broadcast_PerformSync_Request()
end

function MTGuildTracker_LootHistory_Sort_OnClick(field)

	if loot_sort_field == field and field == "player_name" then
		field = "player_class"
	end

	if loot_sort_field == field and loot_sort_direction == "ascending" then
		loot_sort_direction = "descending"
	else
		loot_sort_direction = "ascending"
	end

	loot_sort_field = field
	MTGuildTracker_LootHistoryScrollFrame_Update()
end

function MTGuildTracker_CouncilSession_Sort_OnClick(field, id)

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
	MTGuildTracker_RecipientListScrollFrame_Update()
end

function MTGuildTracker_LootHistoryTabButton_OnClick()
	local player_name_list = {}
	for entry_key, entry in MTGuildTracker_RecipientTable do
		table.insert(player_name_list, entry.player_name)
	end

	player_name_string = table.concat(player_name_list, ", ");
	if (getn(player_name_list) > 0) then
		MTGuildTracker_LootHistorySearchBox:SetText(player_name_string)
		MTGuildTracker_LootHistory_SearchUpdate()
	end
	MTGuildTracker_LootHistoryTable_Show()
end

function MTGuildTracker_LootSessionTabButton_OnClick()
	MTGuildTracker_RecipientTable_Show()
end

function MTGuildTracker_LootHistorySearchBox_OnEnterPressed()
	MTGuildTracker_LootHistory_SearchUpdate();
end

function MTGuildTracker_LootHistory_SearchUpdate()

	local msg = MTGuildTracker_LootHistorySearchBox:GetText();

	if( msg and msg ~= "" ) then
		searchString = string.lower(msg);
	else
		searchString = nil;
	end

	FauxScrollFrame_SetOffset(MTGuildTracker_LootHistoryScrollFrame, 0);
	getglobal("MTGuildTracker_LootHistoryScrollFrameScrollBar"):SetValue(0);

	MTGuildTracker_LootHistoryScrollFrame_Update()
end

function MTGuildTracker_SessionAutoEndCheckButton_OnEnter()
	if not isLeader() then
		getglobal("MTGuildTracker_SessionAutoEndCheckButton"):Disable()
	end
end

function MTGuildTracker_SessionAutoEndCheckButton_OnClick()
	if isLeader() then
		MTGuildTracker_Broadcast_AutoEnd(getglobal("MTGuildTracker_SessionAutoEndCheckButton"):GetChecked())
		if Session_CanEnd() then
			MTGuildTracker_Broadcast_Session_End()
		end
	end
end

function MTGuildTracker_RecipientTable_Show()
	MTGuildTracker_Mode_Update()
	if isLeader() then
		getglobal("MTGuildTracker_SessionAutoEndCheckButton"):Enable()
		getglobal("MTGuildTracker_SessionEndButton"):Show()
		getglobal("MTGuildTracker_SessionDEButton"):Show()
		getglobal("MTGuildTracker_SessionCancelButton"):Show()
	else
		getglobal("MTGuildTracker_SessionAutoEndCheckButton"):Disable()
		getglobal("MTGuildTracker_SessionEndButton"):Hide()
		getglobal("MTGuildTracker_SessionDEButton"):Hide()
		getglobal("MTGuildTracker_SessionCancelButton"):Hide()
	end

	MTGuildTracker_RecipientListScrollFrame_Update();
	MTGuildTracker_LootSessionFrame:Show();
	MTGuildTracker_LootHistoryFrame:Hide();
end

function MTGuildTracker_LootHistoryTable_Show()
	if isOfficer() then
		getglobal("MTGuildTracker_LootHistorySyncButton"):Show()
	else
		getglobal("MTGuildTracker_LootHistorySyncButton"):Hide()
	end

	MTGuildTracker_LootHistoryScrollFrame_Update();
	MTGuildTracker_LootSessionFrame:Hide();
	MTGuildTracker_LootHistoryFrame:Show();
end

-- Commands

function MTGuildTracker_OnChatMsgAddon(event, prefix, msg, channel, sender)
	if (prefix == MT_MESSAGE_PREFIX) then
			--	Split incoming message in Command, Payload (message) and Recipient
		local _, _, cmd, guild, message, recipient = string.find(msg, "([^#]*)#(.*)#(.*)#([^#]*)")

		if not cmd then
			return	-- cmd is mandatory, remaining parameters are optional.
		end

		if not guild or guild ~= getGuildName() then
			return
		end

		if not message then
			message = ""
		end

		if cmd == "TX_ENTRY_ADD" then
			MTGuildTracker_Handle_RecipientTable_Add(message, sender)
		elseif cmd == "TX_ENTRY_REMOVE" then
			MTGuildTracker_Handle_RecipientTable_Remove(message, sender)
		elseif cmd == "TX_SESSION_START" then
			MTGuildTracker_Handle_Session_Start(message, sender)
		elseif cmd == "TX_SESSION_AUTOCLOSE" then
			MTGuildTracker_Handle_AutoClose(message, sender)
		elseif cmd == "TX_SESSION_FINISH" then
			MTGuildTracker_Handle_Session_Finish(message, sender)
		elseif cmd == "TX_SYNC_REQUEST" then
			MTGuildTracker_Handle_Sync_Request(message, sender)
		elseif cmd == "TX_VERSION_REQUEST" then
			MTGuildTracker_Handle_Version_Request(message, sender)
		elseif cmd == "TX_SYNC_START" then
			MTGuildTracker_Handle_Sync_Start(message, sender)
		elseif cmd == "TX_SYNC_ADD" then
			MTGuildTracker_Handle_Sync_Add(message, sender)
		elseif cmd == "TX_SYNC_END" then
			MTGuildTracker_Handle_Sync_End(message, sender)
		elseif cmd == "TX_SYNC_TIME_REQUEST" then
			MTGuildTracker_Handle_Sync_Time_Request(message, sender)
		end

		if isLeader() or isOfficer() then
			if cmd == "TX_VOTE_ADD" then
				MTGuildTracker_Handle_VoteTable_Add(message, sender)
			elseif cmd == "TX_MESSAGE_ECHO" then
				MTGuildTracker_Handle_Message_Echo(message, sender)
			end
		end

		if isLeader() then
			if cmd == "TX_VERSION_RESPONSE" then
				MTGuildTracker_Handle_Version_Response(message, sender)
			elseif cmd == "TX_SYNC_TIME_RESPONSE" then
				MTGuildTracker_Handle_Sync_Time_Response(message, sender)
			elseif cmd == "TX_PERFORM_SYNC_REQUEST" then
				MTGuildTracker_Handle_PerformSync_Request(message, sender)
			end
		else
			
			
		end
	end
end

function MTGuildTracker_SlashCommand(msg)
	if msg =="" then
		if (MTGuildTracker_BrowseFrame:IsVisible()) then
			MTGuildTracker_BrowseFrame:Hide()
			MTGuildTracker_BrowseFrame:Hide()
		else
			MTGuildTracker_RecipientTable_Show()
			ShowUIPanel(MTGuildTracker_BrowseFrame, 1)
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

			if cmd == 'gettime' then
				MTGuildTracker_Sync_Time_Start()
			elseif (cmd == "start") or (cmd == "queue") then
				_,_, item_link = string.find(cmd_msg, "(.*)");
				MTGuildTracker_Session_Queue(item_link)
			elseif (cmd == "list") then
				MTGuildTracker_Session_List()
			elseif (cmd == "dequeue") then
				MTGuildTracker_Session_Dequeue(cmd_msg)
				-- 	local _,_,item_quality, item_id, item_name= string.find(item_link , ".*c(%w+).*item:(.*):.*%[(.*)%]")
			elseif (cmd == "end") then
				MTGuildTracker_Broadcast_Session_End()
			elseif (cmd == "cancel") then
				MTGuildTracker_Broadcast_Session_Cancel()
			elseif (cmd == "force_cancel") then
				MTGuildTracker_Broadcast_Session_ForceCancel()
			elseif (cmd == "help") then
				echo(MTGuildTracker_Title.." v"..MTGuildTracker_Version.." Commands")
				echo("Open MTGuildTracker: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.."|r") 
				echo("Start/Queue session: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." start [item link]|r OR |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." [item link]|r OR |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." queue [item link]|r")
				echo("End session: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." end|r")
				echo("List queued sessions: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." list|r")
				echo("Remove queued session: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." dequeue <entry_key>|r")
				echo("Manually add a raider to the current session: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." add <player_name> [current item link]|r")
				echo("Cancel session: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." cancel|r")
				echo("Force cancel a bad session: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." force_cancel|r")
				echo("Print help: |c"..MTGuildTracker_color_help_command.."/"..SLASH_COMMAND_SHORT.." help|r")
			 elseif cmd == "add" then
				local _,_, player_name, item_link = string.find(cmd_msg, "(%S+)%s*(.*)");
				MTGuildTracker_Broadcast_RecipientTable_Add(player_name, item_link)
			--elseif cmd == "vote" then
			--	_,_, sender, player_name = string.find(cmd_msg, "(%S+)%s+(.*)");
			--	VoteTable_Add(player_name, sender)
			--	MTGuildTracker_RecipientListScrollFrame_Update()
			else
				local _,_, item_link = string.find(msg , "(.*c%w+.*item:.*:.*%[.*%].*)")
				if item_link then
					MTGuildTracker_Session_Queue(item_link)
					echo("item_id", item_id)
				else
					echo("Unknown command "..msg.. ". Type /"..SLASH_COMMAND_SHORT.." help to see a list of commands")
				end
			end
		else
			if isOfficer() and cmd == "force_cancel" then
				MTGuildTracker_Broadcast_Session_ForceCancel()
			elseif cmd == "help" then
				echo(MT_MESSAGE_PREFIX.." v"..MTGuildTracker_Version.." Commands")
				echo("Open "..MT_MESSAGE_PREFIX..":   /"..SLASH_COMMAND_SHORT.."")

				if isOfficer() then
					echo("Force cancel a bad session: /"..SLASH_COMMAND_SHORT.." force_cancel")
				end

				echo("Print help:   /"..SLASH_COMMAND_SHORT.." help")
			else
				echo("Unknown command "..cmd.. ". Type /"..SLASH_COMMAND_SHORT.." help to see a list of commands")
			end
		end
	end
end

local function getCommand(message)
	_, _, cmd, arg = string.find(message, "(%S+)%s+(.*)");
	if (cmd ~= nil and (string.lower(cmd) == SLASH_COMMAND_LONG or string.lower(cmd)==SLASH_COMMAND_SHORT)) then
		return arg
	else
		return nil
	end
end

function MTGuildTracker_OnRaidChat(event, message, sender)
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
			MTGuildTracker_Broadcast_RecipientTable_Add(sender, item_link)
		end
	end
end

function MTGuildTracker_OnEvent(event, arg1, arg2, arg3, arg4, arg5)
	if event == "VARIABLES_LOADED" then
		this:UnregisterEvent("VARIABLES_LOADED");
		MTGuildTracker_Initialize();
	elseif (event == "CHAT_MSG_ADDON") then
		MTGuildTracker_OnChatMsgAddon(event, arg1, arg2, arg3, arg4, arg5)
	elseif (event == "CHAT_MSG_RAID") then
		MTGuildTracker_OnRaidChat(event, arg1, arg2, arg3, arg4, arg5);
	elseif (event == "CHAT_MSG_RAID_LEADER") then
		MTGuildTracker_OnRaidChat(event, arg1, arg2, arg3, arg4, arg5);
	end
end

function MTGuildTracker_Main_OnShow()
	MTGuildTracker_FrameTitle:SetText(MTGuildTracker_Title .. " v" .. MTGuildTracker_Version);
end

function MTGuildTracker_OnLoad()
	echo("Type /"..SLASH_COMMAND_SHORT.." or /"..SLASH_COMMAND_LONG.." for more info");
	this:RegisterEvent("VARIABLES_LOADED");
	this:RegisterEvent("CHAT_MSG_ADDON");
	this:RegisterEvent("CHAT_MSG_RAID");
	this:RegisterEvent("CHAT_MSG_RAID_LEADER");
	this:RegisterEvent("CHAT_MSG_OFFIER");
end

function MTGuildTracker_Initialize()
	LootHistoryTable_Build();
	AttendanceTable_Build();
end

SlashCmdList["MTGuildTracker"] = MTGuildTracker_SlashCommand;
SLASH_MTGuildTracker1 = "/"..SLASH_COMMAND_LONG;
SLASH_MTGuildTracker2 = "/"..SLASH_COMMAND_SHORT;