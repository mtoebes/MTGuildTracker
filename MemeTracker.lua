local RAID_CHANNEL				= "RAID"
local WARN_CHANNEL				= "RAID_WARNING"
local OFFICER_CHANNEL			= "OFFICER"

MemeTracker_Title = "MemeTracker"
MemeTracker_Version = "2.1.0"

MemeTracker_RecipientTable = {}
MemeTracker_LootHistoryTable = {}
MemeTracker_LootHistoryTable_Filtered = {}
MemeTracker_VoteTable = {}
MemeTracker_OverviewTable = {}
MemeTracker_LootHistoryTable_Temp = {}
my_vote = nil

sort_direction = "descending"
sort_field = "player_name"

loot_sort_direction = "descending"
loot_sort_field = "time_stamp";

version_request_in_progress = false

debug_enabled = true

local session_queue = {}
local MT_MESSAGE_PREFIX		= "MemeTracker"

MemeTracker_color_common = "ffffffff"
MemeTracker_color_uncommon = "ff1eff00"
MemeTracker_color_rare = "ff0070dd"
MemeTracker_color_epic = "ffa335ee"
MemeTracker_color_legendary = "ffff8000"
	
local DEFAULT_VOTES_NEEDED = 5

local string_gmatch = lua51 and string.gmatch or string.gfind

local function isLeader() 
 	return IsRaidLeader() 
end 

local function getKeysSortedByKey(tbl)
	a = {}
    for n in pairs(tbl) do table.insert(a, n) end
    table.sort(a)
    return a
end

function getPlayerClass(player_name)

	for raid_index = 1,40 do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(raid_index)
		if name == player_name then
			return class
		end
	end

	return "???"
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
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffa335ee<MemeTracker> |r"..tag.." : "..msg));
		else
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffa335ee<MemeTracker> |r"..tag));
		end
	end
end

local function is_officer()
	guild_name, guild_rank, _ = GetGuildInfo("player")
	if guild_name == "meme team" and (guild_rank == "Class Oracle" or guild_rank == "Officer" or guild_rank == "Suprememe Leadr" or guild_rank == "Loot Council") then
		return true
	else 
		return true
	end
end

local function addonEcho(msg)
	SendAddonMessage(MT_MESSAGE_PREFIX, msg, "RAID")
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

-- TODO 

local function firstToUpper(name)
    return string.gsub(name, "^%l",string.upper)
end

local function RecipientTable_GetPlayerIndex(player_name)
   local index = 1;
   while MemeTracker_RecipientTable[index] do
           if ( player_name == MemeTracker_RecipientTable[index].player_name ) then
                   return index;
           end
           index = index + 1;
   end
   return nil;
end

local function MemeTracker_ParseItemLink(item_link)
	local _,_,item_quality, item_id, item_name= string.find(item_link , ".*c(%w+).*item:(.*):.*%[(.*)%]")
	return item_link, item_quality, item_id, item_name
end

local function RecipientTable_Clear()
	MemeTracker_RecipientTable = {}
end

local function VoteTable_Clear()
	my_vote = nil
	MemeTracker_VoteTable = {}
end

local function Session_Clear()
	RecipientTable_Clear()
	VoteTable_Clear()
end

local function RecipientTable_Add(player_name, item_link)
	local index = RecipientTable_GetPlayerIndex(player_name)
	player_name = firstToUpper(player_name)

	if (index == nil) then
		index = getn(MemeTracker_RecipientTable) + 1
		MemeTracker_RecipientTable[index] = {}
		MemeTracker_RecipientTable[index].voters = {}
	end

	local item_link, item_quality, item_id, item_name = MemeTracker_ParseItemLink(item_link)
	MemeTracker_RecipientTable[index].player_class = getPlayerClass(player_name)
	MemeTracker_RecipientTable[index].player_name = player_name
	MemeTracker_RecipientTable[index].item_id = item_id
	MemeTracker_RecipientTable[index].item_link = item_link
	MemeTracker_RecipientTable[index].item_name = item_name

	local attendance = MemeTracker_Attendance[player_name]

	if attendance then
		to_date = 	 MemeTracker_Attendance[player_name].to_date
		last_5 = MemeTracker_Attendance[player_name].last_5
	else 
		to_date = 0
		last_5 = 0
	end

	MemeTracker_RecipientTable[index].attendance_to_date = to_date.."%"
	MemeTracker_RecipientTable[index].attendance_last_5 = last_5.."%"
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

local function MemeTracker_IsAutoClose()
	return getglobal("MemeTracker_SessionAutoEndCheckButton"):GetChecked() == 1
end

local function Session_CanEnd()

	if MemeTracker_OverviewTable.in_session == true and MemeTracker_IsAutoClose() == true then
		vote_total = {}
		votes = 0

		for index, entry in MemeTracker_RecipientTable do
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

local function RecipientTable_UpdateVotes()

	local tally_table = VoteTable_Tally()
	local vote_total = {}
	local total_votes = 0
	for index, entry in MemeTracker_RecipientTable do
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

local function List_Contains(list, target_value)
	for index, value in ipairs(list) do
		local start, _ = string.find(target_value, value ) 
		if String_Starts_With(target_value, value) then
			return true
		end
	end
	return false
end

-- Session Table 

local function MemeTracker_RecipientTable_Sort_Function(sort_direction, sort_field, a, b)
	if sort_field then
		if sort_direction == "ascending" then
			if ( a[sort_field] == b[sort_field]) then
				return a.player_name < b.player_name
			else
				return a[sort_field] < b[sort_field]
			end
		else
			if ( a[sort_field] == b[sort_field]) then
				return a.player_name > b.player_name
			else
				return a[sort_field] > b[sort_field]
			end
		end
	else 
		return a.player_name < b.player_name
	end
end 

local function RecipientTable_Sort()
	table.sort(MemeTracker_RecipientTable, function(a,b) return MemeTracker_RecipientTable_Sort_Function(sort_direction, sort_field, a, b) end)
end

function MemeTracker_RecipientListScrollFrame_Update()

	if not MemeTracker_RecipientTable then 
		MemeTracker_RecipientTable = {}
	end

	RecipientTable_UpdateVotes()
	RecipientTable_Sort()

	getglobal("MemeTracker_OverviewButtonTextItemName"):SetText(MemeTracker_OverviewTable.item_link)

	if MemeTracker_OverviewTable.votes and MemeTracker_OverviewTable.votes_needed then
		getglobal("MemeTracker_OverviewButtonTextVotes"):SetText(MemeTracker_OverviewTable.votes .. "/" .. MemeTracker_OverviewTable.votes_needed)
	end
	getglobal("MemeTracker_OverviewButtonTextVoters"):SetText(table.concat(MemeTracker_OverviewTable.voters, ", "))

	if (MemeTracker_OverviewTable.in_session == true) then
		getglobal("MemeTracker_SessionEndButton"):Enable()
		getglobal("MemeTracker_SessionCancelButton"):Enable()
	else
		getglobal("MemeTracker_SessionEndButton"):Disable()
		getglobal("MemeTracker_SessionCancelButton"):Disable()
	end

	local max_lines = getn(MemeTracker_RecipientTable)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_RecipientListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MemeTracker_RecipientListScrollFrame, max_lines, 15, 25)
	for line = 1,15 do

		local index = line + offset
		
		if index <= max_lines then
			local recipient = MemeTracker_RecipientTable[index]

			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerClass"):SetText(recipient.player_class)
			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerName"):SetText(recipient.player_name)
			getglobal("MemeTracker_RecipientListItem"..line.."TextItemName"):SetText(recipient.item_link)

			getglobal("MemeTracker_RecipientListItem"..line.."TextVotes"):SetText(recipient.votes)
			getglobal("MemeTracker_RecipientListItem"..line.."TextVoters"):SetText(recipient.voters_text)

			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceToDate"):SetText(recipient.attendance_to_date)
			getglobal("MemeTracker_RecipientListItem"..line.."TextPlayerAttendanceLast5"):SetText(recipient.attendance_last_5)

			if my_vote ~= nil and my_vote == recipient.player_name then
				getglobal("MemeTracker_RecipientListVoteBox"..line):SetChecked(true)
			else
				getglobal("MemeTracker_RecipientListVoteBox"..line):SetChecked(false)
			end

			getglobal("MemeTracker_RecipientListItem"..line):Show()
			getglobal("MemeTracker_RecipientListVoteBox"..line):Show()
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
end

-- Attendance Table 

function MemeTracker_AttendanceTable_Build()
	if not MemeTracker_Attendance then
		MemeTracker_Attendance = {}
	end
end

-- Loot History 

local function MemeTracker_LootHistory_Sort_Function(loot_sort_direction, loot_sort_field, a, b)

	if loot_sort_field then
		if loot_sort_direction == "ascending" then
			if ( a[loot_sort_field] == b[loot_sort_field]) then
				return a.time_stamp < b.time_stamp
			else
				return a[loot_sort_field] < b[loot_sort_field]
			end
		else
			if ( a[loot_sort_field] == b[loot_sort_field]) then
				return a.time_stamp > b.time_stamp
			else
				return a[loot_sort_field] > b[loot_sort_field]
			end
		end
	else 
		return a.time_stamp < b.time_stamp
	end
end 

local function MemeTracker_LootHistory_Sort()
	table.sort(MemeTracker_LootHistoryTable_Filtered, function(a,b) return MemeTracker_LootHistory_Sort_Function(loot_sort_direction, loot_sort_field, a, b) end)
end

function MemeTracker_LootHistoryTable_ListContains(target_value)
	for index, value in ipairs(MemeTracker_LootHistoryTable) do
		if (value.raid_id == target_value.raid_id 
			and value.item_id == target_value.item_id
			and value.boss_name == target_value.boss_name
			and value.player_name == target_value.player_name) then
			return true
		end
	end
	return false
end

function MemeTracker_LootHistoryTable_Build()
	MemeTracker_LootHistoryTable = {}

	if not MemeTrackerDB then
		MemeTrackerDB = {}
	end 
	for index in MemeTrackerDB do
			MemeTracker_LootHistoryTable[index] = {}
			local item_name =  MemeTrackerDB[index].item_name
			local item_quality = MemeTrackerDB[index].item_quality
			local item_id = MemeTrackerDB[index].item_id

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
			item_link = "|c" .. browse_rarityhexlink .. "|Hitem:" .. item_id .. ":0:0:0|h[" .. item_name .. "]|h|r"

			MemeTracker_LootHistoryTable[index].time_stamp    = MemeTrackerDB[index].time_stamp
			MemeTracker_LootHistoryTable[index].date         = MemeTrackerDB[index].date
			MemeTracker_LootHistoryTable[index].raid_id      = MemeTrackerDB[index].raid_id
			MemeTracker_LootHistoryTable[index].raid_name    = MemeTrackerDB[index].raid_name
			MemeTracker_LootHistoryTable[index].boss_name    = MemeTrackerDB[index].boss_name
			MemeTracker_LootHistoryTable[index].item_name    = item_name
			MemeTracker_LootHistoryTable[index].item_id      = item_id
			MemeTracker_LootHistoryTable[index].item_quality = item_quality
			MemeTracker_LootHistoryTable[index].item_link    = item_link
			MemeTracker_LootHistoryTable[index].player_name  = MemeTrackerDB[index].player_name
			MemeTracker_LootHistoryTable[index].player_class = MemeTrackerDB[index].player_class
		end

		MemeTracker_LootHistoryScrollFrame_Update()
end

function MemeTracker_LootHistory_Filter()
	MemeTracker_LootHistoryTable_Filtered = {}
	for k,v in pairs(MemeTracker_LootHistoryTable) do
		if searchString and searchString ~= "" then
			local search_list = Parse_String_List(searchString)
			if (List_Contains(search_list, v.player_name) == true) or (List_Contains(search_list, v.player_class) == true) then
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

	MemeTracker_LootHistory_Filter()
	MemeTracker_LootHistory_Sort()

	local maxlines = getn(MemeTracker_LootHistoryTable_Filtered)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_LootHistoryScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MemeTracker_LootHistoryScrollFrame, maxlines, 15, 25)

	for line=1,15 do
		 lineplusoffset = line + offset
		 if lineplusoffset <= maxlines then
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextPlayerClass"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].player_class)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextPlayerName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].player_name)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextItemName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].item_link)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextRaidName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].raid_name)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextBossName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].boss_name)
			getglobal("MemeTracker_LootHistoryListItem"..line.."TextDate"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].date)
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

function MemeTracker_Session_Dequeue(index)

	if not session_queue or not index or tonumber(index) < 1 or tonumber(index) > getn(session_queue) then
		echo("Please provide a valid queue list index")
	else 
		item_link = table.remove(session_queue, index)
		echo("Removed queued session for ", item_link)
	end
	-- body
end

-- recipient Broadcast

function MemeTracker_Broadcast_RecipientTable_Add(player_name, item_link)
	if MemeTracker_OverviewTable.in_session == true then
			addonEcho("TX_ENTRY_ADD#".. string.format("%s/%s", player_name, item_link) .."#");
	else
		echo("No session in progress")
	end	
end

function MemeTracker_Handle_RecipientTable_Add(message, sender)
	local _, _, player_name, item_link = string.find(message, "([^/]*)/(.*)")	
	RecipientTable_Add(player_name, item_link)
	MemeTracker_RecipientListScrollFrame_Update()
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
		echo("A session for "..MemeTracker_OverviewTable.item_link.." is in progress")
	elseif item_link == nil or item_link=="" then
		echo("Cannot start a session without loot")
	else
		addonEcho("TX_SESSION_START#"..item_link.."#");
	end
end

function MemeTracker_Handle_Session_Start(message, sender)

	local _, _, item_link, votes_needed = string.find(message, "([^/]+%]|h|r)%s*(.*)")	

	if not votes_needed or votes_needed == "" then
		votes_needed = DEFAULT_VOTES_NEEDED
	else 
		votes_needed = tonumber(votes_needed)
	end

	local item_link, item_quality, item_id, item_name = MemeTracker_ParseItemLink(item_link)

	MemeTracker_OverviewTable = {}
	MemeTracker_OverviewTable.in_session = true	
	MemeTracker_OverviewTable.item_id = item_id
	MemeTracker_OverviewTable.item_link = item_link
	MemeTracker_OverviewTable.item_name = item_name
	MemeTracker_OverviewTable.votes_needed = votes_needed
	MemeTracker_OverviewTable.votes = 0
	MemeTracker_OverviewTable.voters = ""

	echo("Session started : ".. item_link)

	Session_Clear()
	MemeTracker_RecipientListScrollFrame_Update()

	sample_itemlink = "|c" .. MemeTracker_color_common .. "|Hitem:" .. 8952 .. ":0:0:0|h[" .. "Your Current Item" .. "]|h|r"

	leaderRaidEcho("Session started : ".. item_link)
	leaderRaidEcho("To be considered for the item type in raid chat \"mt "..sample_itemlink.."\"")
end

-- Session End Broadcast

function MemeTracker_Broadcast_Session_End()
	if MemeTracker_OverviewTable.in_session == true then
		addonEcho("TX_SESSION_END#".."#");
	else
		echo("No Session in progress")
	end
end

function MemeTracker_Broadcast_Session_Cancel()
	if MemeTracker_OverviewTable.in_session == true then
		addonEcho("TX_SESSION_CANCEL#".."#");
	else
		echo("No Session in progress")
	end
end

function MemeTracker_Handle_Session_End(message, sender, cancel)
	MemeTracker_OverviewTable.in_session = false	

	local vote_total = {}
	local votes = 0

	for index, recipient in MemeTracker_RecipientTable do
		if recipient.votes and (recipient.votes > 0) then
			votes = votes +  recipient.votes
			vote_total[recipient.player_name] = recipient.votes
		end
	end

	local sortedKeys = getKeysSortedByValue(vote_total, function(a, b) return a > b end)
	stringList = {}
	for i,n in ipairs(sortedKeys) do table.insert(stringList, "#"..i.." ("..vote_total[n]..")"..": "..n) end

	if (cancel==1) or (getn(stringList) < 1)  then
		echo("Session canceled : ".. MemeTracker_OverviewTable.item_link.." - ("..MemeTracker_OverviewTable.votes.."/"
		..MemeTracker_OverviewTable.votes_needed..") "..table.concat( MemeTracker_OverviewTable.voters, ", " ))

		if getn(stringList) > 0 then
			echo(table.concat(stringList, ", "))
		end
		leaderRaidEcho("Session canceled : ".. MemeTracker_OverviewTable.item_link)
	else
		echo("Session ended : ".. MemeTracker_OverviewTable.item_link.." - ("..MemeTracker_OverviewTable.votes.."/"
		..MemeTracker_OverviewTable.votes_needed..") "..table.concat( MemeTracker_OverviewTable.voters, ", " ))
		echo(table.concat(stringList, ", "))

		leaderRaidEcho("Session ended : ".. MemeTracker_OverviewTable.item_link.." - Congratulations "..sortedKeys[1].."!")
	end
	MemeTracker_RecipientListScrollFrame_Update()
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

function MemeTracker_SendSync_String(table_name, entry)

	sync_string = "";

	if entry and table_name == "loothistory" then
		local lootHistory_entry = MemeTracker_LootHistoryTable[index]
		sync_string = string.format("%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s", 
			table_name,
			entry.date,
			entry.time_stamp,
			entry.raid_id,
			entry.raid_name,
			entry.boss_name,
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
			entry.to_date,
			entry.last_5)
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
		local _, _, date, time_stamp, raid_id, raid_name, boss_name, item_name, item_id, item_quality,  player_name, player_class =
		string.find(fields_string, "(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)");

		entry["date"] = date
		entry["time_stamp"] = time_stamp
		entry["raid_id"] = raid_id
		entry["raid_name"] = raid_name
		entry["boss_name"] = boss_name
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
		local _,_, player_name, player_class, to_date, last_5 = string.find(fields_string, "(.*)/(.*)/(.*)/(.*)");
		entry["player_name"] = player_name
		entry["player_class"] = player_class
		entry["to_date"] = to_date
		entry["last_5"] = last_5
	elseif table_name == "time_stamp" then
		time_stamp = fields_string
		entry["time_stamp"] = time_stamp
	end
	return entry
end 

function MemeTracker_Send_UploadSync()
	for k,v in pairs(MemeTracker_LootHistoryTable) do
		local sync_string = MemeTracker_SendSync_String("loothistory", v)
		MemeTracker_Broadcast_UploadSync_Add("loothistory", sync_string)
	end
	for k,v in pairs(MemeTracker_Attendance) do
		local sync_string = MemeTracker_SendSync_String("attendance", v)
		MemeTracker_Broadcast_UploadSync_Add("attendance", sync_string)
	end

	local sync_string = MemeTracker_SendSync_String("time_stamp", MemeTracker_LastUpdate)

	MemeTracker_Broadcast_UploadSync_Add("time_stamp", sync_string)
end 

function MemeTracker_Send_DownloadSync()
	for k,v in pairs(MemeTracker_LootHistoryTable) do
		local sync_string = MemeTracker_SendSync_String("loothistory", v)
		MemeTracker_Broadcast_DownloadSync_Add("loothistory", sync_string)
	end
	for k,v in pairs(MemeTracker_Attendance) do
		local sync_string = MemeTracker_SendSync_String("attendance", v)
		MemeTracker_Broadcast_DownloadSync_Add("attendance", sync_string)
	end

	local sync_string = MemeTracker_SendSync_String("time_stamp", MemeTracker_LastUpdate)

	MemeTracker_Broadcast_DownloadSync_Add("time_stamp", sync_string)
end 

function MemeTracker_Save_Sync()
	debug("MemeTracker_LootHistoryTable", getn(MemeTracker_LootHistoryTable))
	debug("MemeTracker_LootHistoryTable_Temp", getn(MemeTracker_LootHistoryTable_Temp))

	MemeTrackerDB = {}

	for k,v in pairs(MemeTracker_LootHistoryTable_Temp) do
		table.insert(MemeTrackerDB, v)
	end

	MemeTracker_LootHistoryTable_Temp = {}
	MemeTracker_LootHistoryTable_Build()

	MemeTracker_Attendance = {}

	for k,v in pairs(MemeTracker_Attendance_Temp) do
		MemeTracker_Attendance[k] = v
	end

	MemeTracker_Attendance_Temp = {}
	MemeTracker_AttendanceTable_Build();

	MemeTracker_LastUpdate = {}
	MemeTracker_LastUpdate["time_stamp"] = MemeTracker_LastUpdate_Temp["time_stamp"]
	
	MemeTracker_LastUpdate_Temp = {}

	MemeTracker_RecipientListScrollFrame_Update();
	MemeTracker_LootHistoryScrollFrame_Update();
end

function MemeTracker_Version_Start()
	if isLeader() and not version_request_in_progress then
		response_versions = {}
		if MemeTracker_LastUpdate ~= nil and  MemeTracker_LastUpdate["time_stamp"] ~= nil then
			response_versions[UnitName("player")] = MemeTracker_LastUpdate["time_stamp"]
		end
		getglobal("MemeTracker_LootHistorySyncButton"):Disable()
		version_request_in_progress = true
		MemeTracker_Broadcast_Version_Request()
	end
end

-- Version Broadcast

function MemeTracker_Broadcast_Version_Request()
	if isLeader() then
		debug("MemeTracker_Broadcast_Version_Request")
		addonEcho("TX_VERSION_REQUEST#".."#");
	end
end

function MemeTracker_Handle_Version_Request(message, sender)
	debug("MemeTracker_Handle_Version_Request")
	if not isLeader() then
		debug("MemeTracker_Handle_Version_Request")
		MemeTracker_Broadcast_Version_Response()
	end
end

function MemeTracker_Broadcast_Version_Response()
	if not isLeader() then
		debug("MemeTracker_Broadcast_Version_Response")
		if MemeTracker_LastUpdate ~= nil and MemeTracker_LastUpdate["time_stamp"] ~= nil then
			debug("MemeTracker_Broadcast_Version_Response")
			addonEcho("TX_VERSION_RESPONSE#"..MemeTracker_LastUpdate["time_stamp"].."#");
		end
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
		debug("time_stamp", time_stamp)
			debug("sender",sender)
		if time_stamp ~= nill and (max_time_stamp == nil or time_stamp > max_time_stamp) then
			debug("max_time_stamp", max_time_stamp)
			debug("max_sender", max_sender)

			max_time_stamp = time_stamp
			max_sender = sender
		end
	end

	if max_sender ~= UnitName("player") then
		debug("MemeTracker_Version_End", max_sender);
		MemeTracker_Broadcast_UploadSync_Request(max_sender)
	else 
		debug("MemeTracker_Version_End", "I am master");
		MemeTracker_Broadcast_DownloadSync_Start();
		MemeTracker_Send_DownloadSync();
		MemeTracker_Broadcast_DownloadSync_End();
	end
	--body
end

-- Upload Sync

function MemeTracker_Broadcast_UploadSync_Request(player_name)
	if isLeader() and not upload_sync_in_progress then
		debug("MemeTracker_Broadcast_UploadSync_Request")
		uploaders = 0
		MemeTracker_LootHistoryTable_Temp = {}
		MemeTracker_Attendance_Temp = {}
		MemeTracker_LastUpdate_Temp = {}
		upload_sync_in_progress = true;
		getglobal("MemeTracker_LootHistorySyncButton"):Disable()
		addonEcho("TX_UPLOADSYNC_REQUEST#"..player_name.."#");
	end
end

function MemeTracker_Handle_UploadSync_Request(message, sender)
	debug("MemeTracker_Handle_UploadSync_Request");
	local player_name = message
	if UnitName("player") == player_name then
		debug("MemeTracker_Handle_UploadSync_Request");
		MemeTracker_Broadcast_UploadSync_Start();
		MemeTracker_Send_UploadSync();
		MemeTracker_Broadcast_UploadSync_End();
	end
end

function MemeTracker_Broadcast_UploadSync_Start()
	debug("MemeTracker_Broadcast_UploadSync_Start");
	addonEcho("TX_UPLOADSYNC_START#".."#");
end

function MemeTracker_Handle_UploadSync_Start(message, sender)
	if isLeader() and upload_sync_in_progress then
		debug("MemeTracker_Handle_UploadSync_Start");
		uploaders = uploaders + 1
	end
end

function MemeTracker_Broadcast_UploadSync_Add(table_name, sync_string)
	addonEcho("TX_UPLOADSYNC_ADD#".. sync_string .."#");
end

function MemeTracker_Handle_UploadSync_Add(message, sender)
	if isLeader() and upload_sync_in_progress then
		local _, _, table_name, fields_string = string.find(message, "([^/]*)/(.*)");

		entry = MemeTracker_ReadSync_Entry(table_name, fields_string)

		if table_name == "loothistory" then
			table.insert(MemeTracker_LootHistoryTable_Temp, entry)
		elseif table_name == "attendance" then
			MemeTracker_Attendance_Temp[entry["player_name"]] = entry
		elseif table_name == "time_stamp" then
			MemeTracker_LastUpdate_Temp["time_stamp"] = entry["time_stamp"]
		end
	end
end

function MemeTracker_Broadcast_UploadSync_End()
	debug("MemeTracker_Broadcast_UploadSync_End");
	addonEcho("TX_UPLOADSYNC_END#".."#");
end

function MemeTracker_Handle_UploadSync_End(message, sender)
	if isLeader() and upload_sync_in_progress then
		debug("MemeTracker_Handle_UploadSync_End");
		uploaders = uploaders - 1
		if (uploaders <= 0) then
			upload_sync_in_progress = false

			debug("MemeTracker_Handle_UploadSync_End", "done")

			MemeTracker_Save_Sync()

			MemeTracker_Broadcast_DownloadSync_Start();
			MemeTracker_Send_DownloadSync();
			MemeTracker_Broadcast_DownloadSync_End();
		end
	end
end

-- Download Sync

function MemeTracker_Broadcast_DownloadSync_Start()
	if isLeader() and not download_sync_in_progress then
		debug("MemeTracker_Broadcast_DownloadSync_Start");
		download_sync_in_progress = true;
		getglobal("MemeTracker_LootHistorySyncButton"):Disable()
		addonEcho("TX_DOWNLOADSYNC_START#".."#");
	end
end

function MemeTracker_Handle_DownloadSync_Start(message, sender)
	if not isLeader() and not download_sync_in_progress then
		debug("MemeTracker_Handle_DownloadSync_Start");
		download_sync_in_progress = true;
		getglobal("MemeTracker_LootHistorySyncButton"):Disable()
		MemeTracker_LootHistoryTable_Temp = {}
		MemeTracker_Attendance_Temp = {}
		MemeTracker_LastUpdate_Temp = {}
	end
end

function MemeTracker_Broadcast_DownloadSync_Add(table_name, sync_string)
	if isLeader() and download_sync_in_progress then
		addonEcho("TX_DOWNLOADSYNC_ADD#".. sync_string .."#");
	end
end

function MemeTracker_Handle_DownloadSync_Add(message, sender)
	if not isLeader() and download_sync_in_progress then
		debug("MemeTracker_Handle_DownloadSync_Add");
		local _, _, table_name, fields_string = string.find(message, "([^/]*)/(.*)");

		entry = MemeTracker_ReadSync_Entry(table_name, fields_string)

		if table_name == "loothistory" then
			table.insert(MemeTracker_LootHistoryTable_Temp, entry)
		elseif table_name == "attendance" then
			MemeTracker_Attendance_Temp[entry["player_name"]] = entry 
		elseif table_name == "time_stamp" then
			MemeTracker_LastUpdate_Temp["time_stamp"] = entry["time_stamp"]
		end
	end
end

function MemeTracker_Broadcast_DownloadSync_End()
	if isLeader() and download_sync_in_progress then
		debug("MemeTracker_Broadcast_DownloadSync_End");
		download_sync_in_progress = false;
		getglobal("MemeTracker_LootHistorySyncButton"):Enable()
		addonEcho("TX_DOWNLOADSYNC_END#".."#");
	end
end

function MemeTracker_Handle_DownloadSync_End(message, sender)
	if not isLeader() and download_sync_in_progress then
		debug("MemeTracker_Handle_DownloadSync_End");
		download_sync_in_progress = false;
		getglobal("MemeTracker_LootHistorySyncButton"):Enable()
		MemeTracker_Save_Sync();
	end
end

-- UI LINK

function MemeTracker_ChatLink(link)
	 if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			ChatFrameEditBox:Insert(link)
		end
	end
end

function MemeTracker_RecipientButton_OnClick(button, index)
	local link = MemeTracker_RecipientTable[index].item_link
	MemeTracker_ChatLink(link)
end

function MemeTracker_LootHistoryButton_OnClick(button, index)
	local link = MemeTracker_LootHistoryTable_Filtered[index].item_link
	MemeTracker_ChatLink(link)
end

function MemeTracker_OverviewButton_OnClick()
	local link = MemeTracker_OverviewTable.item_link
	MemeTracker_ChatLink(link)
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

function MemeTracker_RecipientButton_OnEnter(index)
	local item_id = MemeTracker_RecipientTable[index].item_id
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

function MemeTracker_LootHistoryButton_OnEnter(index)
	local item_id = MemeTracker_LootHistoryTable_Filtered[index].item_id
	MemeTracker_Tooltip_Show(item_id)
end

function MemeTracker_LootHistoryButton_OnLeave()
	MemeTracker_Tooltip_Hide()
end

-- Session UI 

function MemeTracker_VoteCheckButton_OnClick(line)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_RecipientListScrollFrame);
	local index = line + offset
	local player_name = MemeTracker_RecipientTable[index].player_name

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

function MemeTracker_SessionEndButton_OnClick()
	MemeTracker_Broadcast_Session_End()
end

function MemeTracker_SessionCancelButton_OnClick()
	MemeTracker_Broadcast_Session_Cancel()
end

function MemeTracker_LootHistorySyncButton_OnClick()
	MemeTracker_Version_Start()
end

function MemeTracker_LootHistory_Sort_OnClick(field)
	if loot_sort_field == field and loot_sort_direction == "descending" then
		loot_sort_direction = "ascending"
	else
		loot_sort_direction = "descending"
	end

	loot_sort_field = field
	MemeTracker_LootHistoryScrollFrame_Update()
end

function MemeTracker_CouncilSession_Sort_OnClick(field)
	if sort_field == field and sort_direction == "descending" then
		sort_direction = "ascending"
	else
		sort_direction = "descending"
	end

	sort_field = field
	MemeTracker_RecipientListScrollFrame_Update()
end

function MemeTracker_LootHistoryTabButton_OnClick()
	local tally_table = VoteTable_Tally()

	local player_name_list = {}
	for index, entry in MemeTracker_RecipientTable do
		table.insert(player_name_list, entry.player_name)
	end

	player_name_string = table.concat(player_name_list, ", ");
	if (getn(player_name_list) > 0) then
		MemeTracker_LootHistorySearchBox:SetText(player_name_string)
		MemeTracker_Search_Update()
	end
	MemeTracker_LootHistoryTable_Show()
end 

function MemeTracker_LootSessionTabButton_OnClick()
	MemeTracker_RecipientTable_Show()
end

function MemeTracker_LootHistorySearchBox_OnEnterPressed()
	MemeTracker_Search_Update();
end

function MemeTracker_Search_Update()

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

function MemeTracker_SessionAutoEndCheckButton_OnLoad()
	getglobal("MemeTracker_SessionAutoEndCheckButton"):SetChecked(true)

	if isLeader() then
		getglobal("MemeTracker_SessionAutoEndCheckButton"):Enable()
	else
		getglobal("MemeTracker_SessionAutoEndCheckButton"):Disable()
	end
end

function MemeTracker_SessionAutoEndCheckButton_OnEnter()
	if isLeader() then
		getglobal("MemeTracker_SessionAutoEndCheckButton"):Enable()
	else
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
	getglobal("MemeTracker_AutoEnd_FontString"):Show()
	MemeTracker_RecipientListScrollFrame_Update();
	MemeTracker_LootSessionFrame:Show();
	MemeTracker_LootHistoryFrame:Hide();
end

function MemeTracker_LootHistoryTable_Show()
	getglobal("MemeTracker_AutoEnd_FontString"):Hide()
	if isLeader() then
		getglobal("MemeTracker_LootHistorySyncButton"):Show()
		getglobal("MemeTracker_LootHistorySyncButton"):Enable()
	else
		getglobal("MemeTracker_LootHistorySyncButton"):Disable()
		getglobal("MemeTracker_LootHistorySyncButton"):Hide()
	end

	MemeTracker_LootHistoryScrollFrame_Update();
	MemeTracker_LootSessionFrame:Hide();
	MemeTracker_LootHistoryFrame:Show();
end

-- Commands

function MemeTracker_OnChatMsgAddon(event, prefix, msg, channel, sender)
	if (prefix == MT_MESSAGE_PREFIX) then	
		if is_officer() then
			--	Split incoming message in Command, Payload (message) and Recipient
			local _, _, cmd, message, recipient = string.find(msg, "([^#]*)#([^#]*)#([^#]*)")

			if not cmd then
				return	-- cmd is mandatory, remaining parameters are optionel.
			end
			
			if not message then
				message = ""
			end
				
			debug(cmd, message)
			if cmd == "TX_ENTRY_ADD" then
				MemeTracker_Handle_RecipientTable_Add(message, sender)	
			elseif cmd == "TX_VOTE_ADD" then
				MemeTracker_Handle_VoteTable_Add(message, sender)
			elseif cmd == "TX_SESSION_START" then
					MemeTracker_Handle_Session_Start(message, sender)
			elseif cmd == "TX_SESSION_AUTOCLOSE" then
					MemeTracker_Handle_AutoClose(message, sender)
			elseif cmd == "TX_SESSION_END" then
					MemeTracker_Handle_Session_End(message, sender, 0)
			elseif cmd == "TX_SESSION_CANCEL" then
				MemeTracker_Handle_Session_End(message, sender, 1)	
			elseif cmd == "TX_UPLOADSYNC_REQUEST" then
				MemeTracker_Handle_UploadSync_Request(message, sender)
			elseif cmd == "TX_UPLOADSYNC_START" then
				MemeTracker_Handle_UploadSync_Start(message, sender)
			elseif cmd == "TX_UPLOADSYNC_ADD" then
				MemeTracker_Handle_UploadSync_Add(message, sender)
			elseif cmd == "TX_UPLOADSYNC_END" then
				MemeTracker_Handle_UploadSync_End(message, sender)
			elseif cmd == "TX_DOWNLOADSYNC_START" then
				MemeTracker_Handle_DownloadSync_Start(message, sender)
			elseif cmd == "TX_DOWNLOADSYNC_ADD" then
				MemeTracker_Handle_DownloadSync_Add(message, sender)
			elseif cmd == "TX_DOWNLOADSYNC_END" then
				MemeTracker_Handle_DownloadSync_End(message, sender)
			elseif cmd == "TX_VERSION_REQUEST" then
				MemeTracker_Handle_Version_Request(message, sender)
			elseif cmd == "TX_VERSION_RESPONSE" then
				MemeTracker_Handle_Version_Response(message, sender)
			else
				echo("Unknown command, raw msg="..msg)
			end
		end
	end
end

function MemeTracker_SlashCommand(msg)
	if msg =="" then
		if (MemeTracker_BrowseFrame:IsVisible()) then
			MemeTracker_BrowseFrame:Hide()
			MemeTracker_BrowseFrame:Hide()
		else
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
			if (cmd == "start") then 
				_,_, item_link = string.find(cmd_msg, "(.*)");
				MemeTracker_Session_Queue(item_link)
			elseif (cmd == "list") then
				debug("list")
				MemeTracker_Session_List()
			elseif (cmd == "remove") then
				MemeTracker_Session_Dequeue(cmd_msg)
				-- 	local _,_,item_quality, item_id, item_name= string.find(item_link , ".*c(%w+).*item:(.*):.*%[(.*)%]")
			elseif (cmd == "end") then
				MemeTracker_Broadcast_Session_End()
			elseif (cmd == "cancel") then
				MemeTracker_Broadcast_Session_Cancel()
			elseif (cmd == "help") then
				echo("MemeTracker v"..MemeTracker_Version.." Commands")
				echo("Open MemeTracker:   /mt")
				echo("Start session:   /mt start [item link] OR /mt [item link]")
				echo("End session:  /mt end")
				echo("List queued sessions:  /mt list")
				echo("Remove queued session:  /mt remove [index]")

				echo("Cancel session:   /mt cancel")
				echo("Print help:   /mt help")
			--elseif cmd == "add" then
			--	local _,_, player_name, item_link = string.find(cmd_msg, "(%S+)%s*(.*)");
			--	player_name = firstToUpper(player_name)
			--	MemeTracker_Broadcast_RecipientTable_Add(player_name, item_link)
			--	MemeTracker_RecipientListScrollFrame_Update()
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
			if (cmd == "help") then
				echo("MemeTracker v"..MemeTracker_Version.." Commands")
				echo("Open MemeTracker:   /mt")
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
	--if isLeader() then
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
	--end
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
	MemeTracker_LootHistoryTable_Build();
	MemeTracker_AttendanceTable_Build();
end

SlashCmdList["MemeTracker"] = MemeTracker_SlashCommand;
SLASH_MemeTracker1 = "/memetracker";
SLASH_MemeTracker2 = "/mt";
