Overview: 
MemeTracker is an addon Villageburn developed to aid the guild's Loot Council process. It is composed of two parts.
1. An interface for voting at part of the Loot Council 
2. A history of all loot that has been handed out in past raids.  Results can be filtered based on player name, use commas to show loot received multiple players. This is the same information available within the Guild Tracker Google Sheet (sans ZG loot).

Addon Installation Instructions:
1. Rename this folder from "MemeTracker-master" to "MemeTracker"
1. In a file browser, navigate to your "World of Warcraft" directory.
2. Navigate to your addons directory (Interface/AddOns/).
3. Place the "MemeTracker" folder here. Overwrite any existing versions of the addon.



Loot History Saving Instructions:
1. This step no longer needed
~~1. Exit World of Warcraft completely.
2. In a file browser, navigate to your "World of Warcraft" directory.
3. Navigate to your account's saved variable directory (WTF/Account/<account_name>/SavedVariables/).
4. Place the "MemeTracker.lua" file found in the "SavedVariables" folder here. Overwrite any existing versions of the file.
5. To keep this information up to date, you will need to re-save the latest version of the file found the add-ons discord channel (or this github page) prior to each raid.
~~

Base Commands:
* Open MemeTracker:	/mt
* Print help:  		/mt help

Loot Council (Officer) only commands:
* Start session:   	/mt start [item link] <optional # of votes_needed (defaults to 5)>
* End session:   		/mt end
* Cancel session: 	/mt cancel

Loot Session Process:
1. Each piece of loot is voted on within its own loot session.
2. A LC member will start a session using the /mt start [item link] command. This will announce to the raid that the session has started.
3. To enter their name into the session pool, raid members will type in raid chat "mt [current item link]" with the item they wish to upgrade. These submission will automatically be picked up by the addon and appear in the MemeTracker window. 
4. Each LC member can submit their vote by checking the box to the left of the member's name in the window. A member is free to unvote and change their vote at any point throughout the session.
5. While a session is in progress, the "Player Loot History" will automatically filter to only show items received by players currently being voted on.
5. The session will end once one person has received the majority of the votes or 5 votes total have been submitted, the session will end. It cannot end in a tie though, instead it will prompt LC member's to re-vote.  The session can also be manually ended using the /mt end command or by clicking the button in the top left corner.
6. Once ended, the winner will be announced in raid chat.
7. A session can be canceled (ended without announcing a winner) using the /mt cancel command or by clicking the button in the top left corner.
8. The information concerning the last loot session will remain visible until the next session is started.

Disclaimer: I am not a lua developer, this addon works just well enough to be functional, not efficient or clean. 
