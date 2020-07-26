# TotalEncumbrance
I was excited to come across [Alaxandir's CoreRPG port](https://www.fantasygrounds.com/forums/showthread.php?57185-Coin-Weight-for-CoreRPG-(MoreCore-compatible)) of [Zuger's Coin Weight extension](https://svn.fantasygrounds.com/forums/showthread.php?41109-The-weight-of-the-coins), but it had visual issues in the Pathfinder ruleset. I made a few changes and enabled some extra features that had been left disabled/unfinished in the source mod. After seeing how it worked, it seemed like an obvious next step to extend its functionality to help fill the gaps in the existing functionality around weight, encumbrance, coins, and the like. At this point, the coin weight aspect is a tiny piece of this extension.

# Features
* Calculate coin weight. Two columns, one weighed and one not. 50 coins is 1 pound. (If using kg, leave this as coins per pound; the conversion will be done automatically)
* Automate encumbrance penalties based on total weight and current carrying capacity.
* Color-code the numbers in the penalties boxes to indicate their source. Red is for encumbrance and black is for armor.
* Roll arcane spell failure chance [when appropriate](https://www.fantasygrounds.com/forums/showthread.php?48977-Advanced-3-5e-and-Pathfinder-effects&p=528377&viewfull=1#post528377). Alternately, based on option toggle, prompt user to roll via a chat message which includes the spell failure chance.
* Update carrying capacities when strength-modifying effects are applied/changed/removed.
* Allow equipped armor to impose a max dex of zero. See the last section of the Compatibility and Configuration section, below.
* Auto-change speed penalties based on weight encumbrance and some supported Pathfinder conditions.
* Compute and display total inventory value and net worth at the top of the treasure box on the Inventory tab.


# Compatibility and Configuration
This extension has been tested with [FantasyGrounds Classic](https://www.fantasygrounds.com/home/FantasyGroundsClassic.php) 3.3.11 and [FantasyGrounds Unity](https://www.fantasygrounds.com/home/FantasyGroundsUnity.php) 4.0.0 (2020-07-16). The "Allow equipped armor to impose a max dex of zero" feature doesn't work in Unity yet.

In-game controls for enabling/disabling/configuring some extension components are in FantasyGrounds' "Options" menu.
Any values designed to be user-modifiable are located in [scripts/encumbrance_globals.lua](https://github.com/bmos/FG-PFRPG-TotalEncumbrance/blob/master/scripts/encumbrance_globals.lua) and include:
* How many coins weigh one pound
* The classes which have arcane failure in different categories of armor (or with shields)
* The encumbrance penalties imposed by medium or heavy encumbrance
* A list of armor that is supposed to have a maximum dex penalty of zero (as FG didn't support this and I wanted half-plate to work right without manual corrections)

# Video Demonstration (click for video)
[<img src="https://i.ytimg.com/vi_webp/Tj2rDt4oeL8/maxresdefault.webp">](https://youtu.be/Tj2rDt4oeL8)
