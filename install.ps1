<#
  Obsilain installer (Windows PowerShell)

  Usage:
    powershell -ExecutionPolicy Bypass -File install.ps1 [-Vault "C:\path\to\vault"] [-Beautitab] [-Wallpaper "C:\path\img.jpg"]

    -Vault      Path to your Obsidian vault (folder containing .obsidian\).
                If omitted, detects your vaults and lets you pick.
    -Beautitab  Also install the Beautitab plugin (executable code from its official release).
    -Wallpaper  Local image to use as background (sets --lain-wp for you).

  Installs Border theme + lain-glass.css snippet and enables them in appearance.json.
  A timestamped backup of .obsidian is taken before any config edit.
#>
[CmdletBinding()]
param(
  [string]$Vault,
  [switch]$Beautitab,
  [string]$Wallpaper
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw      = 'https://raw.githubusercontent.com/danisotosol/obsilain/main'
$BorderRaw    = 'https://raw.githubusercontent.com/Akifyss/obsidian-border/main'
$BeautitabApi = 'https://api.github.com/repos/andrewmcgivery/obsidian-beautitab/releases/latest'

function Info($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[+] $m" -ForegroundColor Green }
function Fail($m){ Write-Host "[x] $m" -ForegroundColor Red }

# ---- detect vault ----------------------------------------------------------
if (-not $Vault) {
  $oj = Join-Path $env:APPDATA 'obsidian\obsidian.json'
  if (Test-Path $oj) {
    $vaults = @((Get-Content $oj -Raw | ConvertFrom-Json).vaults.PSObject.Properties.Value.path)
    if ($vaults.Count -gt 0) {
      Info 'Detected vaults:'
      for ($i = 0; $i -lt $vaults.Count; $i++) { Write-Host ("   {0}) {1}" -f ($i + 1), $vaults[$i]) }
      $c = Read-Host 'Pick a number (or type a path)'
      if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $vaults.Count) { $Vault = $vaults[[int]$c - 1] }
      else { $Vault = $c }
    }
  }
}
if (-not $Vault) { $Vault = Read-Host 'Path to your Obsidian vault' }

$obs = Join-Path $Vault '.obsidian'
if (-not (Test-Path $obs)) { Fail "No .obsidian folder in: $Vault"; exit 1 }
Ok "Vault: $Vault"

# ---- backup ----------------------------------------------------------------
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$obs.backup-$stamp"
Copy-Item $obs $backup -Recurse
Ok "Backup: $backup"

New-Item -ItemType Directory -Force -Path (Join-Path $obs 'themes\Border') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $obs 'snippets') | Out-Null

# ---- Border theme ----------------------------------------------------------
Info 'Downloading Border theme...'
Invoke-WebRequest "$BorderRaw/theme.css"     -OutFile (Join-Path $obs 'themes\Border\theme.css')     -UseBasicParsing
Invoke-WebRequest "$BorderRaw/manifest.json" -OutFile (Join-Path $obs 'themes\Border\manifest.json') -UseBasicParsing
Ok 'Border installed.'

# ---- lain-glass snippet ----------------------------------------------------
Info 'Downloading lain-glass snippet...'
$snippetPath = Join-Path $obs 'snippets\lain-glass.css'
Invoke-WebRequest "$RepoRaw/lain-glass.css" -OutFile $snippetPath -UseBasicParsing
Ok 'Snippet installed.'

# ---- optional wallpaper ----------------------------------------------------
if ($Wallpaper) {
  if (Test-Path $Wallpaper) {
    $abs = (Resolve-Path $Wallpaper).Path -replace '\\', '/'
    $url = "app://local/$abs"
    $css = Get-Content $snippetPath -Raw
    $rep = '${1}url("' + $url + '");'
    $css = ([regex]'(--lain-wp:\s*)url\([^)]*\)[^;]*;').Replace($css, $rep, 1)
    Set-Content $snippetPath $css -Encoding UTF8
    Ok "Wallpaper set: $url"
  } else { Fail "Wallpaper not found: $Wallpaper (skipping)." }
}

# ---- optional Beautitab plugin --------------------------------------------
if ($Beautitab) {
  Info 'Installing Beautitab plugin (executable code from official release)...'
  $pdir = Join-Path $obs 'plugins\beautitab'
  New-Item -ItemType Directory -Force -Path $pdir | Out-Null
  $rel = Invoke-RestMethod $BeautitabApi -Headers @{ 'User-Agent' = 'obsilain-installer' }
  foreach ($f in 'manifest.json', 'main.js', 'styles.css') {
    $asset = $rel.assets | Where-Object { $_.name -eq $f } | Select-Object -First 1
    if ($asset) { Invoke-WebRequest $asset.browser_download_url -OutFile (Join-Path $pdir $f) -UseBasicParsing }
  }
  Ok 'Beautitab installed (enable Community plugins in Obsidian if in Restricted mode).'
}

# ---- enable appearance.json ------------------------------------------------
$ap  = Join-Path $obs 'appearance.json'
$obj = if (Test-Path $ap) { Get-Content $ap -Raw | ConvertFrom-Json } else { New-Object psobject }
$ht  = [ordered]@{}
foreach ($p in $obj.PSObject.Properties) { if ($p.Name -ne 'enabledCssSnippets') { $ht[$p.Name] = $p.Value } }
$ht['cssTheme'] = 'Border'
$snips = @()
if ($obj.PSObject.Properties.Name -contains 'enabledCssSnippets') { $snips = @($obj.enabledCssSnippets) }
if ($snips -notcontains 'lain-glass') { $snips += 'lain-glass' }
$ht['enabledCssSnippets'] = $snips
$json = $ht | ConvertTo-Json -Depth 10
# Windows PowerShell collapses single-element arrays to a scalar; restore array form.
if ($snips.Count -eq 1) {
  $json = $json -replace '("enabledCssSnippets"\s*:\s*)"([^"]*)"', ('$1[' + "`n    " + '"$2"' + "`n  ]")
}
Set-Content $ap $json -Encoding UTF8
Ok 'appearance.json updated (theme=Border, snippet=lain-glass).'

# ---- enable community-plugins.json (Beautitab) -----------------------------
if ($Beautitab) {
  $cp  = Join-Path $obs 'community-plugins.json'
  $arr = @()
  if (Test-Path $cp) { $arr = @(Get-Content $cp -Raw | ConvertFrom-Json) }
  if ($arr -notcontains 'beautitab') { $arr += 'beautitab' }
  $body = "[`n" + (($arr | ForEach-Object { '  "' + $_ + '"' }) -join ",`n") + "`n]"
  Set-Content $cp $body -Encoding UTF8
  Ok 'community-plugins.json updated (beautitab).'
}

Write-Host ''
Ok 'Done. Reload Obsidian (Ctrl+R).'
if (-not $Wallpaper) {
  Write-Host '    Tip: set your wallpaper by editing --lain-wp in .obsidian\snippets\lain-glass.css'
}
