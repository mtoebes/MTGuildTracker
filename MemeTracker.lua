local PARTY_CHANNEL				= "PARTY"
local RAID_CHANNEL				= "RAID"
local YELL_CHANNEL				= "YELL"
local SAY_CHANNEL				= "SAY"
local WARN_CHANNEL				= "RAID_WARNING"
local GUILD_CHANNEL				= "GUILD"
local WHISPER_CHANNEL			= "WHISPER"
local OFFICER_CHANNEL			= "OFFICER"

MemeTracker_Title = "MemeTracker"
MemeTracker_Version = "1.2.2"
MemeTracker_EntryTable = {}
MemeTracker_LootHistoryTable = {}
MemeTracker_LootHistoryTable_Filtered = {}
MemeTracker_VoteTable = {}
MemeTracker_OverviewTable = {}

my_vote = nil

sort_direction = "descending"
sort_field = "player_name"

loot_sort_direction = "descending"
loot_sort_field = "time_stamp";

local votes_needed
local loot_in_session = nil
local in_session = false

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

local function is_officer()
	guild_name, guild_rank, _ = GetGuildInfo("player")
	if guild_name == "meme team" and (guild_rank == "Class Oracle" or guild_rank == "Officer" or guild_rank == "Suprememe Leadr" or guild_rank == "Loot Council") then
		return true
	else 
		return false
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

local function guildEcho(msg)
	SendChatMessage(msg, GUILD_CHANNEL)
end

local function officerEcho(msg)
	SendChatMessage(msg, OFFICER_CHANNEL)
end

local function whisper(receiver, msg)
	SendChatMessage(msg, WHISPER_CHANNEL, nil, receiver);
end

local function leaderRaidEcho(msg)
	if isLeader() then
		raidEcho(msg)
	end
end

local function firstToUpper(name)
    return string.gsub(name, "^%l",string.upper)
end

local function EntryTable_GetPlayerIndex(player_name)
       local index = 1;
       while MemeTracker_EntryTable[index] do
               if ( player_name == MemeTracker_EntryTable[index].player_name ) then
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

local function EntryTable_Clear()
	MemeTracker_EntryTable = {}
end

local function VoteTable_Clear()
	my_vote = nil
	MemeTracker_VoteTable = {}
end

local function Session_Clear()
	EntryTable_Clear()
	VoteTable_Clear()
end

local function EntryTable_Add(player_name, item_link)
	local index = EntryTable_GetPlayerIndex(player_name)
	player_name = firstToUpper(player_name)

	if (index == nil) then
		index = getn(MemeTracker_EntryTable) + 1
		MemeTracker_EntryTable[index] = {}
		MemeTracker_EntryTable[index].voters = {}
	end

	local item_link, item_quality, item_id, item_name = MemeTracker_ParseItemLink(item_link)
	MemeTracker_EntryTable[index].player_class = getPlayerClass(player_name)
	MemeTracker_EntryTable[index].player_name = player_name
	MemeTracker_EntryTable[index].item_id = item_id
	MemeTracker_EntryTable[index].item_link = item_link
	MemeTracker_EntryTable[index].item_name = item_name

	local attendance = MemeTracker_Attendance[player_name]

	if attendance then
		to_date = 	 MemeTracker_Attendance[player_name].to_date
		last_5 = MemeTracker_Attendance[player_name].last_5
	else 
		to_date = 0
		last_5 = 0
	end

	MemeTracker_EntryTable[index].attendance_to_date = to_date.."%"
	MemeTracker_EntryTable[index].attendance_last_5 = last_5.."%"

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
	return getglobal("MemeTracker_AutoEndCheckButton"):GetChecked() == 1
end

local function Session_CanEnd()

	if MemeTracker_OverviewTable.in_session == true and MemeTracker_IsAutoClose() == true then
		vote_total = {}
		votes = 0

		for index, entry in MemeTracker_EntryTable do
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

local function EntryTable_UpdateVotes()

	local tally_table = VoteTable_Tally()
	local vote_total = {}
	local total_votes = 0
	for index, entry in MemeTracker_EntryTable do
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

local function MemeTracker_EntryTable_Sort_Function(sort_direction, sort_field, a, b)
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

local function EntryTable_Sort()
	table.sort(MemeTracker_EntryTable, function(a,b) return MemeTracker_EntryTable_Sort_Function(sort_direction, sort_field, a, b) end)
end

function MemeTracker_ListScrollFrame_Update()

	if not MemeTracker_EntryTable then 
		MemeTracker_EntryTable = {}
	end

	EntryTable_UpdateVotes()
	EntryTable_Sort()

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

	local max_lines = getn(MemeTracker_EntryTable)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_ListScrollFrame);
	 -- maxlines is max entries, 10 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(MemeTracker_ListScrollFrame, max_lines, 15, 25)
	for line = 1,15 do

		local index = line + offset
		
		if index <= max_lines then
			local entry = MemeTracker_EntryTable[index]

			getglobal("MemeTracker_List"..line.."TextPlayerClass"):SetText(entry.player_class)
			getglobal("MemeTracker_List"..line.."TextPlayerName"):SetText(entry.player_name)
			getglobal("MemeTracker_List"..line.."TextItemName"):SetText(entry.item_link)

			getglobal("MemeTracker_List"..line.."TextVotes"):SetText(entry.votes)
			getglobal("MemeTracker_List"..line.."TextVoters"):SetText(entry.voters_text)

			getglobal("MemeTracker_List"..line.."TextPlayerAttendanceToDate"):SetText(entry.attendance_to_date)
			getglobal("MemeTracker_List"..line.."TextPlayerAttendanceLast5"):SetText(entry.attendance_last_5)

			if my_vote ~= nil and my_vote == entry.player_name then
				getglobal("MemeTracker_Checkbox"..line):SetChecked(true)
			else
				getglobal("MemeTracker_Checkbox"..line):SetChecked(false)
			end

			getglobal("MemeTracker_List"..line):Show()
			getglobal("MemeTracker_Checkbox"..line):Show()
			if (MemeTracker_OverviewTable.in_session == true) then
				getglobal("MemeTracker_Checkbox"..line):Enable() 
			else
				getglobal("MemeTracker_Checkbox"..line):Disable() 
			end

		 else
			getglobal("MemeTracker_List"..line):Hide()
			getglobal("MemeTracker_Checkbox"..line):Hide()
		 end	
	end
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

function MemeTracker_AttendanceTable_Build()
	if not MemeTracker_Attendance then
		MemeTracker_Attendance = {}
	end
end

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

function MemeTracker_LootHistory_Sort()
	table.sort(MemeTracker_LootHistoryTable_Filtered, function(a,b) return MemeTracker_LootHistory_Sort_Function(loot_sort_direction, loot_sort_field, a, b) end)
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

			getglobal("MemeTracker_LootHistory"..line.."TextPlayerClass"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].player_class)
			getglobal("MemeTracker_LootHistory"..line.."TextPlayerName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].player_name)
			getglobal("MemeTracker_LootHistory"..line.."TextItemName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].item_link)
			getglobal("MemeTracker_LootHistory"..line.."TextRaidName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].raid_name)
			getglobal("MemeTracker_LootHistory"..line.."TextBossName"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].boss_name)
			getglobal("MemeTracker_LootHistory"..line.."TextDate"):SetText(MemeTracker_LootHistoryTable_Filtered[lineplusoffset].date)

			getglobal("MemeTracker_LootHistory"..line):Show()
		 else
			getglobal("MemeTracker_LootHistory"..line):Hide()
		 end	
	end
end

-- Broadcast 
function MemeTracker_Broadcast_EntryTable_Add(player_name, item_link)
	if MemeTracker_OverviewTable.in_session == true then
			addonEcho("TX_ENTRY_ADD#".. string.format("%s/%s", player_name, item_link) .."#");
	else
		echo("No session in progress")
	end	
end

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

function MemeTracker_Broadcast_Session_Start(item_link)
	if MemeTracker_OverviewTable.in_session == true then
		echo("A session for "..MemeTracker_OverviewTable.item_link.." is in progress")
	elseif item_link == nil or item_link=="" then
		echo("Cannot start a session without loot")
	else
		addonEcho("TX_SESSION_START#"..item_link.."#");
	end
end

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

function MemeTracker_Broadcast_AutoEnd(autoclose) 
	if autoclose then 
		addonEcho("TX_SESSION_AUTOCLOSE#".."1".."#");
	else
		addonEcho("TX_SESSION_AUTOCLOSE#".."0".."#");
	end
end
-- Handle functions
function MemeTracker_Handle_EntryTable_Add(message, sender)
	local _, _, player_name, item_link = string.find(message, "([^/]*)/(.*)")	
	EntryTable_Add(player_name, item_link)
	MemeTracker_ListScrollFrame_Update()
end

function MemeTracker_Handle_VoteTable_Add(message, sender)
	local _, _, player_name = string.find(message, "([^/]+)")	

	VoteTable_Add(player_name, sender)
	MemeTracker_ListScrollFrame_Update()
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
		MemeTracker_ListScrollFrame_Update()

		sample_itemlink = "|c" .. MemeTracker_color_common .. "|Hitem:" .. 8952 .. ":0:0:0|h[" .. "Your Current Item" .. "]|h|r"

		leaderRaidEcho("Session started : ".. item_link)
		leaderRaidEcho("To be considered for the item type in raid chat \"mt "..sample_itemlink.."\"")
end

function MemeTracker_Handle_Session_End(message, sender, cancel)
	MemeTracker_OverviewTable.in_session = false	

	local vote_total = {}
	local votes = 0

	for index, entry in MemeTracker_EntryTable do
		if entry.votes and (entry.votes > 0) then
			votes = votes +  entry.votes
			vote_total[entry.player_name] = entry.votes
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
	MemeTracker_ListScrollFrame_Update()
end

function MemeTracker_Handle_AutoClose(message, sender)
	local _, _, state = string.find(message, "(.*)");

	if state == "1" then
		getglobal("MemeTracker_AutoEndCheckButton"):SetChecked(true)
	else
		getglobal("MemeTracker_AutoEndCheckButton"):SetChecked(false)
	end
end

function MemeTracker_VoteCheckButton_OnClick(line)
	local offset = FauxScrollFrame_GetOffset(MemeTracker_ListScrollFrame);
	local index = line + offset
	local player_name = MemeTracker_EntryTable[index].player_name

	if getglobal("MemeTracker_Checkbox"..line):GetChecked() then
		my_vote = player_name
	else
		my_vote = nil
	end

	for other_line = 1,15 do
		if other_line ~= line then
			getglobal("MemeTracker_Checkbox"..line):SetChecked(false)
		end
	end

	MemeTracker_Broadcast_VoteTable_Add(my_vote)
end

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
				
			if cmd == "TX_ENTRY_ADD" then
				MemeTracker_Handle_EntryTable_Add(message, sender)	
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
			else
				echo("Unknown command, raw msg="..msg)
			end
		end
	end
end

-- UI TODO

function MemeTracker_SessionEndButton_OnClick()
	MemeTracker_Broadcast_Session_End()
end

function MemeTracker_SessionCancelButton_OnClick()
	MemeTracker_Broadcast_Session_Cancel()
end

function MemeTracker_OnLoad()
	echo("Type /mt or /memetracker for more info");
	    this:RegisterEvent("VARIABLES_LOADED");

	this:RegisterEvent("CHAT_MSG_ADDON");
	this:RegisterEvent("CHAT_MSG_RAID");
	this:RegisterEvent("CHAT_MSG_RAID_LEADER");
	this:RegisterEvent("CHAT_MSG_OFFIER");

end

local function MemeTracker_Initialize()
	MemeTracker_LootHistoryTable_Build();
	MemeTracker_AttendanceTable_Build();
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

-- UI LINK

function MemeTracker_ListButton_OnClick(button, index)
	 if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			local link = MemeTracker_EntryTable[index].item_link
			ChatFrameEditBox:Insert(link)
		end
	end
end

function MemeTracker_LootHistoryButton_OnClick(button, index)
	 if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			local link = MemeTracker_LootHistoryTable_Filtered[index].item_link
			ChatFrameEditBox:Insert(link)
		end
	end
end

function MemeTracker_OverviewButton_OnClick()
	 if button == "LeftButton" then
		if( IsShiftKeyDown() and ChatFrameEditBox:IsVisible() ) then
			local link = MemeTracker_OverviewTable.item_link
			ChatFrameEditBox:Insert(link)
		end
	end		
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
function MemeTracker_ListButton_OnEnter(index)
	local item_id = MemeTracker_EntryTable[index].item_id
	
	if item_id then
		MemeTracker_Tooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
		MemeTracker_Tooltip:SetHyperlink("item:" .. item_id .. ":0:0:0")
		MemeTracker_Tooltip:Show()
	end
end

function MemeTracker_ListButton_OnLeave()
	MemeTracker_Tooltip:Hide()	
end

function MemeTracker_OverviewButton_OnEnter()
	local item_id = MemeTracker_OverviewTable.item_id
	
	if item_id then
		MemeTracker_Tooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
		MemeTracker_Tooltip:SetHyperlink("item:" .. item_id .. ":0:0:0")
		MemeTracker_Tooltip:Show()
	end
end

function MemeTracker_OverviewButton_OnLeave()
	MemeTracker_Tooltip:Hide()	
end

function MemeTracker_LootHistoryButton_OnEnter(index)
	local item_id = MemeTracker_LootHistoryTable_Filtered[index].item_id
	
	if item_id then
		MemeTracker_Tooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
		MemeTracker_Tooltip:SetHyperlink("item:" .. item_id .. ":0:0:0")
		MemeTracker_Tooltip:Show()
	end
end

function MemeTracker_LootHistoryButton_OnLeave()
	MemeTracker_Tooltip:Hide()	
end
-- Sorting 

function MemeTracker_LootHistory_Sort_OnClick(field)
		if loot_sort_field == field and loot_sort_direction == "descending" then
		loot_sort_direction = "ascending"
	else
		loot_sort_direction = "descending"
	end

	loot_sort_field = field
	MemeTracker_LootHistoryScrollFrame_Update()
end

function MemeTracker_Sort_OnClick(field)
	if sort_field == field and sort_direction == "descending" then
		sort_direction = "ascending"
	else
		sort_direction = "descending"
	end

	sort_field = field
	MemeTracker_ListScrollFrame_Update()
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

		if is_officer() then
			if (cmd == "start") then
				_,_, item_link = string.find(cmd_msg, "(.*)");
				MemeTracker_Broadcast_Session_Start(item_link)
			elseif (cmd == "end") then
				MemeTracker_Broadcast_Session_End()
			elseif (cmd == "cancel") then
				MemeTracker_Broadcast_Session_Cancel()
			elseif (cmd == "help") then
				echo("MemeTracker v"..MemeTracker_Version.." Commands")
				echo("Open MemeTracker:   /mt")
				echo("Start session:   /mt start [item link]")
				echo("End session:  /mt end")
				echo("Cancel session:   /mt cancel")
				echo("Print help:   /mt help")
			--elseif cmd == "add" then
			--	local _,_, player_name, item_link = string.find(cmd_msg, "(%S+)%s*(.*)");
			--	player_name = firstToUpper(player_name)
			--	MemeTracker_Broadcast_EntryTable_Add(player_name, item_link)
			--	MemeTracker_ListScrollFrame_Update()
			--elseif cmd == "vote" then
			--	_,_, sender, player_name = string.find(cmd_msg, "(%S+)%s+(.*)");
			--	VoteTable_Add(player_name, sender)
			--	MemeTracker_ListScrollFrame_Update()
			else
				echo("Unknown command"..cmd.. ". Type /mt help to see a list of commands")
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
			MemeTracker_Broadcast_EntryTable_Add(sender, item_link)
		end
	--end
end

function MemeTracker_PlayerLootHistoryButton_OnClick()
	local tally_table = VoteTable_Tally()

	local player_name_list = {}
	for index, entry in MemeTracker_EntryTable do
		table.insert(player_name_list, entry.player_name)
	end

	player_name_string = table.concat(player_name_list, ", ");
	if (getn(player_name_list) > 0) then
		MemeTracker_LootHistory_SearchBox:SetText(player_name_string)
		MemeTracker_Search_Update()
	end
	MemeTracker_LootHistoryTable_Show()
end 

function MemeTracker_EntryTable_Show()
	MemeTracker_ListScrollFrame_Update();
	MemeTracker_ListBrowse:Show();
	MemeTracker_LootHistoryBrowse:Hide();
end

function MemeTracker_LootHistoryTable_Show()
	MemeTracker_LootHistoryScrollFrame_Update();
	MemeTracker_ListBrowse:Hide();
	MemeTracker_LootHistoryBrowse:Show();
end

function MemeTracker_Search_Update()

	local msg = MemeTracker_LootHistory_SearchBox:GetText();

	if( msg and msg ~= "" ) then
		searchString = string.lower(msg);
	else
		searchString = nil;
	end

	FauxScrollFrame_SetOffset(MemeTracker_LootHistoryScrollFrame, 0);

	getglobal("MemeTracker_LootHistoryScrollFrameScrollBar"):SetValue(0);

	MemeTracker_LootHistoryScrollFrame_Update()
end 

function MemeTracker_AutoEndCheckButton_OnLoad()
	getglobal("MemeTracker_AutoEndCheckButton"):SetChecked(true)

	if isLeader() then
		getglobal("MemeTracker_AutoEndCheckButton"):Enable()
	else
		getglobal("MemeTracker_AutoEndCheckButton"):Disable()
	end
end

function MemeTracker_AutoEndCheckButton_OnEnter()
		if isLeader() then
				echo("MemeTracker_AutoEndCheckButton_OnEnter enable")

			getglobal("MemeTracker_AutoEndCheckButton"):Enable()
		else
				echo("MemeTracker_AutoEndCheckButton_OnEnter disable")

			getglobal("MemeTracker_AutoEndCheckButton"):Disable()
		end
end

function MemeTracker_AutoEndCheckButton_OnClick()
	if isLeader() then
		MemeTracker_Broadcast_AutoEnd(getglobal("MemeTracker_AutoEndCheckButton"):GetChecked())
		if Session_CanEnd() then
			MemeTracker_Broadcast_Session_End()
		end
	end
end

SlashCmdList["MemeTracker"] = MemeTracker_SlashCommand;
SLASH_MemeTracker1 = "/memetracker";
SLASH_MemeTracker2 = "/mt";
