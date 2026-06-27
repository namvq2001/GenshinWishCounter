#Requires -Version 5.1
<#
.SYNOPSIS
    Extract the Genshin Impact wish-history link (authkey) and copy it to the clipboard.
.DESCRIPTION
    Local-only: reads the in-game webview cache, validates the link against the
    official HoYoverse/miHoYo gacha API, then copies it. No remote code, no admin.
.PARAMETER Region
    'global' (default) or 'china'.
.PARAMETER GamePath
    Optional Genshin folder (install root, or the *_Data folder) to skip auto-detection.
.EXAMPLE
    .\Get-WishLink.ps1
.EXAMPLE
    .\Get-WishLink.ps1 -Region china
.EXAMPLE
    .\Get-WishLink.ps1 -GamePath "D:\Games\Genshin Impact\Genshin Impact game"
#>

[CmdletBinding()]
param(
    [ValidateSet('global', 'china')]
    [string]$Region = 'global',

    [string]$GamePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # faster Invoke-WebRequest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }  # avoid URL mojibake
try { Add-Type -AssemblyName System.Web -ErrorAction Stop }      catch { }

# --- output helpers ---
function Write-Info { param([string]$m) Write-Host "[i] $m" -ForegroundColor Cyan }
function Write-Good { param([string]$m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "[x] $m" -ForegroundColor Red }
function Write-Kv {
    param([string]$label, [string]$value)
    Write-Host ("    {0,-16}: " -f $label) -ForegroundColor DarkGray -NoNewline
    Write-Host $value -ForegroundColor White
}
$rule = ('=' * 72)

# --- core functions ---
function Get-GameDirFromLog {
    param([string]$LogFile)
    if (-not (Test-Path -LiteralPath $LogFile)) { return $null }
    try { $lines = Get-Content -LiteralPath $LogFile -ErrorAction Stop } catch { return $null }
    foreach ($line in $lines) {
        if ($line -match '([A-Za-z]:[\\/].+?(?:GenshinImpact_Data|YuanShen_Data))') { return $Matches[1] }
    }
    return $null
}

function Find-WebCachesDir {
    param([string]$Base)
    if ([string]::IsNullOrWhiteSpace($Base) -or -not (Test-Path -LiteralPath $Base)) { return $null }
    foreach ($c in @(
            (Join-Path $Base 'webCaches'),
            (Join-Path $Base 'GenshinImpact_Data\webCaches'),
            (Join-Path $Base 'YuanShen_Data\webCaches'))) {
        if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
    }
    try {  # depth-limited recursive fallback
        $hit = Get-ChildItem -LiteralPath $Base -Directory -Recurse -Depth 3 -Filter 'webCaches' `
                   -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    } catch { }
    return $null
}

function Get-CacheDataFile {
    param([string]$WebCaches)
    $verDir = Get-ChildItem -LiteralPath $WebCaches -Directory -ErrorAction Stop |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $verDir) { throw "No cache version subfolder under: $WebCaches" }
    $data2 = Join-Path $verDir.FullName 'Cache\Cache_Data\data_2'
    if (-not (Test-Path -LiteralPath $data2)) { throw "Cache file not found: $data2" }
    [pscustomobject]@{ VersionDir = $verDir.FullName; DataFile = (Resolve-Path -LiteralPath $data2).Path }
}

function Get-WishUrls {
    param([string]$DataFile)
    $tmp = Join-Path $env:TEMP ('wishcache_' + [guid]::NewGuid().ToString('N') + '.bin')
    Copy-Item -LiteralPath $DataFile -Destination $tmp -Force
    try { $content = Get-Content -LiteralPath $tmp -Encoding UTF8 -Raw -ErrorAction Stop }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    $urls = [System.Collections.Generic.List[string]]::new()
    $records = $content -split '1/0/'
    for ($i = $records.Length - 1; $i -ge 0; $i--) {   # newest cache records last -> walk backwards
        $rec = $records[$i]
        if ($rec -match 'webview_gacha' -and $rec -match '(https://[^\s"\x00]+?game_biz=)') {
            if (-not $urls.Contains($Matches[1])) { $urls.Add($Matches[1]) }
        }
    }
    return , $urls   # comma prevents a 1-item list from being unrolled
}

function Test-WishUrl {
    param([string]$Url, [string]$ApiHost)
    try {
        $b = [System.UriBuilder]::new($Url)
        $b.Host = $ApiHost; $b.Path = 'gacha_info/api/getGachaLog'; $b.Fragment = ''
        $q = [System.Web.HttpUtility]::ParseQueryString($b.Query)
        $q.Set('lang', 'en'); $q.Set('gacha_type', '301'); $q.Set('size', '5')
        $b.Query = $q.ToString()
        $resp = Invoke-WebRequest -Uri $b.Uri.AbsoluteUri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return [bool](($resp.Content | ConvertFrom-Json).retcode -eq 0)
    } catch { return $false }
}

# --- region config (origin via char codes keeps this file pure-ASCII) ---
if ($Region -eq 'china') {
    $logPath = Join-Path $env:USERPROFILE "AppData\LocalLow\miHoYo\$([char]0x539f)$([char]0x795e)\output_log.txt"
    $apiHost = 'public-operation-hk4e.mihoyo.com'
} else {
    $logPath = Join-Path $env:USERPROFILE 'AppData\LocalLow\miHoYo\Genshin Impact\output_log.txt'
    $apiHost = 'public-operation-hk4e-sg.hoyoverse.com'
}

# --- main ---
Write-Host ''
Write-Info "Genshin wish-history link extractor   (region: $Region)"
Write-Kv 'Log file' $logPath
Write-Kv 'API host' $apiHost
Write-Host ''

# 1) Game *_Data folder: -GamePath > log auto-detect > manual prompt.
if ($PSBoundParameters.ContainsKey('GamePath') -and $GamePath) {
    Write-Info 'Using -GamePath argument.'
    $gameDir = $GamePath.Trim('"').Trim()
} else {
    Write-Info 'Auto-detecting game folder from log...'
    $gameDir = Get-GameDirFromLog -LogFile $logPath
    if ($gameDir) { Write-Good 'Detected game folder from log.' } else { Write-Warn 'Not found in log.' }
}

# 2) Resolve webCaches; loop with manual prompt until found or aborted.
$webCaches = $null
while ($true) {
    if ($gameDir) {
        Write-Kv 'Game folder' $gameDir
        try { $webCaches = Find-WebCachesDir -Base $gameDir } catch { $webCaches = $null }
    }
    if ($webCaches) { break }

    Write-Fail 'webCaches not found (game moved/renamed, or Wish History never opened).'
    Write-Host "    Enter the Genshin folder containing 'GenshinImpact_Data' (or the *_Data folder)."
    Write-Host '    Example: D:\Games\Genshin Impact\Genshin Impact game' -ForegroundColor DarkGray
    $inp = Read-Host '    Game path (blank to abort)'
    if ([string]::IsNullOrWhiteSpace($inp)) { Write-Fail 'Aborted.'; exit 1 }
    $gameDir = $inp.Trim('"').Trim()
    if (-not (Test-Path -LiteralPath $gameDir)) { Write-Fail "Path does not exist: $gameDir"; $gameDir = $null }
}
Write-Good "webCaches: $webCaches"

# 3) Locate the data_2 cache file.
try { $cache = Get-CacheDataFile -WebCaches $webCaches }
catch { Write-Fail "Cannot locate cache file: $($_.Exception.Message)"; exit 1 }
Write-Kv 'Cache version' $cache.VersionDir
Write-Kv 'Cache file'    $cache.DataFile

# 4) Extract candidate URLs.
Write-Host ''
Write-Info 'Reading cache and extracting wish URLs...'
try { $urls = Get-WishUrls -DataFile $cache.DataFile }
catch { Write-Fail "Failed to read cache: $($_.Exception.Message)"; exit 1 }
if ($null -eq $urls -or $urls.Count -eq 0) {
    Write-Fail 'No wish-history URL found. Open the in-game Wish History first, then re-run.'
    exit 1
}
Write-Good "Found $($urls.Count) candidate URL(s). Validating newest first..."

# 5) Validate against the official API; first valid one wins (capped).
$maxTries = [Math]::Min($urls.Count, 12)
$finalUrl = $null
for ($i = 0; $i -lt $maxTries; $i++) {
    Write-Host ("    [{0}/{1}] testing... " -f ($i + 1), $maxTries) -NoNewline
    if (Test-WishUrl -Url $urls[$i] -ApiHost $apiHost) {
        Write-Host 'VALID' -ForegroundColor Green; $finalUrl = $urls[$i]; break
    }
    Write-Host 'expired/invalid' -ForegroundColor DarkYellow
    Start-Sleep -Milliseconds 250
}

# 6) Fall back to newest unverified URL if validation failed.
$validated = [bool]$finalUrl
if (-not $finalUrl) {
    $finalUrl = $urls[0]
    Write-Warn 'No URL passed validation (authkey expired or network blocked).'
    Write-Warn 'Falling back to the most recent URL (UNVERIFIED).'
}

# 7) Copy + report.
try { Set-Clipboard -Value $finalUrl; $clip = 'copied to clipboard' }
catch { $clip = 'clipboard copy FAILED - copy the link below manually' }

Write-Host ''
Write-Host $rule -ForegroundColor DarkGray
if ($validated) { Write-Good 'WISH HISTORY LINK  (validated)' } else { Write-Warn 'WISH HISTORY LINK  (UNVERIFIED)' }
Write-Host $rule -ForegroundColor DarkGray
Write-Host $finalUrl -ForegroundColor White
Write-Host $rule -ForegroundColor DarkGray
Write-Good "Link $clip. Paste it into paimon.moe (or your importer)."

Write-Host ''
Write-Info 'Paths used:'
Write-Kv 'Log file'   $logPath
Write-Kv 'Game dir'   $gameDir
Write-Kv 'webCaches'  $webCaches
Write-Kv 'Cache file' $cache.DataFile
Write-Host ''
Write-Warn 'This link carries a temporary read-only authkey (~24h). Do not share it publicly.'
Write-Host ''
