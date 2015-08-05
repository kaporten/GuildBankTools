GuildBankTools
==========

WildStar addon with minor Guild Bank improvements, such as filtering by name, and auto-stacking items.

Source code can be found on [GitHub](https://github.com/kaporten/GuildBankTools).

Released versions are published on [Curse](http://www.curse.com/ws-addons/wildstar/229979-guildbanktools). Full addon description can be found on Curse as well.

Double addon registration issue?
----------
Due to addon folder renames, you may see GuildBankTools registered twice on the Addons list in-game, which will cause Lua errors. You can fix the double-entry issue this way:

1. Shut down WildStar completely.
1. Uninstall GuildBankTools (delete directory "%APPDATA%\NCSOFT\WildStar\Addons\GuildBankTools", or remove it via Curse Client - you can keep the settings).
1. Start WildStar and log in on any character.
1. Shut down WildStar again, and re-install the addon.

Alternative fix:

1. Shut down WildStar completely.
1. Open file "%APPDATA%\NCSOFT\WildStar\Addons.xml" in a text editor.
1. Search for lines containing "GuildBankTools" or "guildbanktools". You'll find 2 lines. 
1. Delete the all-lowercase line and save the file.
1. Start WildStar again.
