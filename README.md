# GenshinWishCounter

Get your **Genshin Impact wish-history link** (the `authkey` URL) and copy it to the clipboard, ready to paste into [paimon.moe](https://paimon.moe) or any wish importer.

Local-only and safe: it reads the in-game webview cache, validates the link against the **official** HoYoverse/miHoYo gacha API, then copies it. No remote code, no admin elevation.

## Requirements

- Windows + PowerShell 5.1+ (built in)
- Open the in-game **Wish History** at least once before running (so the link is in the cache)

## Usage

**Easiest** — double-click `Get-WishLink.cmd`.

**PowerShell:**

```powershell
# Global (default)
powershell -ExecutionPolicy Bypass -File .\Get-WishLink.ps1

# China server
powershell -ExecutionPolicy Bypass -File .\Get-WishLink.ps1 -Region china

# Force a game folder (if auto-detect fails)
powershell -ExecutionPolicy Bypass -File .\Get-WishLink.ps1 -GamePath "D:\Games\Genshin Impact\Genshin Impact game"
```

The link is copied automatically and also printed in full, along with every path used (log file, game folder, webCaches, cache file).

## Multiple accounts

**Multiple game (HoYoverse) accounts on one client**
The cache keeps links from every account you opened Wish History with. The script tries the **most recently opened** link first and validates it. To target a specific account:

1. Launch the game and log into **that** account.
2. Open **Wish History** and let it load.
3. Run the script — the freshly opened account's link is now newest and wins.

If you get the wrong account, fully close the game, log into the right one, reopen Wish History, then re-run.

**Multiple Windows user accounts on one PC**
Paths live under each user's `%USERPROFILE%`. Run the script from the **same Windows account that runs the game**, or pass `-GamePath` to point at the correct install folder.

## Troubleshooting

| Message | Fix |
| --- | --- |
| `webCaches not found` | Game moved/renamed, or Wish History never opened. Enter the game path when prompted, or use `-GamePath`. |
| `No wish-history URL found` | Open the in-game Wish History first, then re-run. |
| `UNVERIFIED` link | authkey expired or network blocked — reopen Wish History and re-run. |

## Notes

- The link carries a **temporary, read-only** `authkey` (~24h). It cannot log in, spend, or change anything — but don't share it publicly.
- Inspired by MadeBaruna's `getlink.ps1`, rewritten for clarity, safety, and richer output.
