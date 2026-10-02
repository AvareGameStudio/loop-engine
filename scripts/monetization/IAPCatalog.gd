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
		"title": "Auto-Tap Idle Loop",
		"blurb": "Offline-safe lock cadence. Core skill loop remains for high scores.",
		"price": "$2.99",
		"flag": "auto_tap",
	},
	{
		"id": "trail_aurora",
		"title": "Aurora Trail",
		"blurb": "Cosmetic pointer trail. Zero P2W.",
		"price": "$1.99",
		"flag": "cosmetic",
	},
]


static func grant(product_id: String) -> void:
	match product_id:
		"no_ads_bundle":
			GameState.no_ads = true
		"auto_tap":
			GameState.auto_tap = true
		"trail_aurora":
			if not GameState.cosmetics.has("aurora"):
				GameState.cosmetics.append("aurora")
	GameState.save_game()
