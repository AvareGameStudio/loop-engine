class_name IAPCatalog
extends RefCounted
## Hybrid IAP surface. Catalog only — wire store SKUs in production.

const PRODUCTS := [
	{
		"id": "no_ads_bundle",
		"title": "No-Ads Bundle",
		"blurb": "Remove interstitial & banner pressure. Revives still optional.",
		"price": "$4.99",
		"flag": "no_ads",
	},
	{
		"id": "auto_tap",
		"title": "Auto-Crack",
		"blurb": "The crew taps the Good window for you. Perfects stay yours.",
		"price": "$2.99",
		"flag": "auto_tap",
	},
	{
		"id": "dial_obsidian",
		"title": "Obsidian Dial",
		"blurb": "Cosmetic vault face. Zero P2W.",
		"price": "$1.99",
		"flag": "cosmetic",
	},
]


static func grant(product_id: String) -> void:
	match product_id:
		"no_ads_bundle":
			GameState.no_ads = true
		"auto_tap":
			GameState.auto_tap_purchased = true
			GameState.auto_tap_unlocked = true
			GameState.auto_tap = true
		"dial_obsidian":
			if not GameState.cosmetics.has("obsidian"):
				GameState.cosmetics.append("obsidian")
			GameState.equip_dial("obsidian")
	GameState.save_game()
