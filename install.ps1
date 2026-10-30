# Installs or updates The Lost Expedition pack for TLauncher and the official Minecraft Launcher.
# Run again any time to get updates. Mods live in .minecraft\lost-expedition\mods,
# so other versions and the normal mods folder stay untouched.
param(
  [string]$Modlist = 'https://raw.githubusercontent.com/oguzhan00yildiz/lost-expedition/main/modlist.json'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$h = @{ 'User-Agent' = 'LostExpedition-installer/1.0' }

$mcDir = Join-Path $env:APPDATA '.minecraft'
$packDir = Join-Path $mcDir 'lost-expedition'
$modsDir = Join-Path $packDir 'mods'
$shaderDir = Join-Path $mcDir 'shaderpacks'
$resourceDir = Join-Path $mcDir 'resourcepacks'
New-Item -ItemType Directory -Force $modsDir, $shaderDir, $resourceDir | Out-Null

Write-Host 'Reading mod list...'
if (Test-Path $Modlist) { $list = Get-Content $Modlist -Raw | ConvertFrom-Json }
else { $list = [Text.Encoding]::UTF8.GetString((Invoke-WebRequest $Modlist -UseBasicParsing -Headers $h).RawContentStream.ToArray()).TrimStart([char]0xFEFF) | ConvertFrom-Json }

# Fabric version for the launcher. The id is the name shown in the TLauncher version list.
$versionId = "Lost Expedition $($list.minecraft)"
$versionDir = Join-Path $mcDir "versions\$versionId"
New-Item -ItemType Directory -Force $versionDir | Out-Null
$fabric = Invoke-RestMethod "https://meta.fabricmc.net/v2/versions/loader/$($list.minecraft)/$($list.fabricLoader)/profile/json" -Headers $h
# TLauncher hides versions whose inheritsFrom parent is missing, so merge vanilla into one flat file.
$manifest = Invoke-RestMethod 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -Headers $h
$vanilla = Invoke-RestMethod ($manifest.versions | Where-Object id -eq $list.minecraft).url -Headers $h
$vanilla.id = $versionId
$vanilla.mainClass = $fabric.mainClass
$vanilla.libraries = @($fabric.libraries) + @($vanilla.libraries)
$vanilla.arguments.game = @($vanilla.arguments.game) + @($fabric.arguments.game)
$vanilla.arguments.jvm = @($vanilla.arguments.jvm) + @($fabric.arguments.jvm) + "-Dfabric.modsFolder=$modsDir"
# The offline server gives each player MD5("OfflinePlayer:<name>") as ID, but TLauncher sends its own
# account ID. FTB Teams needs both to match, so the game starts with the server's offline ID.
function Get-OfflineUuid([string]$name) {
  $b = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("OfflinePlayer:$name"))
  $b[6] = ($b[6] -band 0x0f) -bor 0x30
  $b[8] = ($b[8] -band 0x3f) -bor 0x80
  (($b | ForEach-Object { $_.ToString('x2') }) -join '')
}
$tlProfiles = Join-Path $mcDir 'TlauncherProfiles.json'
$playerName = $null
if (Test-Path $tlProfiles) {
  $tlp = Get-Content $tlProfiles -Raw | ConvertFrom-Json
  if ($tlp.selectedAccountUUID) { $playerName = $tlp.accounts.($tlp.selectedAccountUUID).displayName }
}
# Official launcher: the active Microsoft account's Minecraft name.
foreach ($accFile in 'launcher_accounts.json', 'launcher_accounts_microsoft_store.json') {
  $accPath = Join-Path $mcDir $accFile
  if ($playerName -or -not (Test-Path $accPath)) { continue }
  $acc = Get-Content $accPath -Raw | ConvertFrom-Json
  if ($acc.activeAccountLocalId) { $playerName = $acc.accounts.($acc.activeAccountLocalId).minecraftProfile.name }
}
if (-not $playerName) { $playerName = Read-Host 'Your Minecraft name' }
$offlineUuid = Get-OfflineUuid $playerName
$vanilla.arguments.game = @($vanilla.arguments.game | ForEach-Object { if ($_ -eq '${auth_uuid}') { $offlineUuid } else { $_ } })

$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $versionDir "$versionId.json"), ($vanilla | ConvertTo-Json -Depth 20), $utf8)
$tl = [ordered]@{ activateSkinCapeForUserVersion = $false; skipHashsumValidation = $false; tlauncherVersion = 0; source = 'local_version_repo'; skinVersion = $false }
[IO.File]::WriteAllText((Join-Path $versionDir 'TLauncherAdditional.json'), ($tl | ConvertTo-Json), $utf8)

# Official launcher lists only versions that have an installation profile, so add one.
$launcherProfiles = Join-Path $mcDir 'launcher_profiles.json'
if (Test-Path $launcherProfiles) { $lp = Get-Content $launcherProfiles -Raw | ConvertFrom-Json }
else { $lp = [pscustomobject]@{ profiles = [pscustomobject]@{}; version = 3 } }
if (-not $lp.profiles) { $lp | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$created = $now
if ($lp.profiles.'lost-expedition') { $created = $lp.profiles.'lost-expedition'.created }
$lp.profiles | Add-Member -Force -NotePropertyName 'lost-expedition' -NotePropertyValue ([pscustomobject][ordered]@{
  name = 'The Lost Expedition'; type = 'custom'; created = $created; lastUsed = $now
  lastVersionId = $versionId; icon = 'Bookshelf'; javaArgs = '-Xmx6G -Xms2G -XX:+UseZGC -XX:+ZGenerational'
})
[IO.File]::WriteAllText($launcherProfiles, ($lp | ConvertTo-Json -Depth 10), $utf8)

function Sync-Files($files, $dir, [switch]$Prune) {
  foreach ($f in $files) {
    $path = Join-Path $dir $f.file
    if ((Test-Path $path) -and (Get-FileHash $path -Algorithm SHA512).Hash -eq $f.sha512) { continue }
    Write-Host "Downloading $($f.file)"
    Invoke-WebRequest $f.url -OutFile $path -UseBasicParsing -Headers $h
    if ((Get-FileHash $path -Algorithm SHA512).Hash -ne $f.sha512) { Remove-Item $path; throw "Download damaged: $($f.file). Run the installer again." }
  }
  if ($Prune) {
    $keep = $files.file
    Get-ChildItem $dir -File | Where-Object { $_.Name -notin $keep } | ForEach-Object { Remove-Item $_.FullName; Write-Host "Removed $($_.Name)" }
  }
}

$clientFiles = $list.files | Where-Object { $_.side -ne 'server' }
Sync-Files @($clientFiles | Where-Object type -eq 'mod') $modsDir -Prune
# Shader folder is shared with other versions, so nothing gets removed there.
Sync-Files @($clientFiles | Where-Object type -eq 'shader') $shaderDir
$resourceFiles = @($clientFiles | Where-Object type -eq 'resourcepack')
Sync-Files $resourceFiles $resourceDir

# Key binding overrides fix clashes between mods (for example FTB Quests editor keys on W A S D).
$options = Join-Path $mcDir 'options.txt'
$keybindsUrl = $Modlist -replace 'modlist\.json$', 'keybinds.txt'
if (Test-Path $keybindsUrl) { $overrides = Get-Content $keybindsUrl -Encoding utf8 }
else { $overrides = (Invoke-WebRequest $keybindsUrl -UseBasicParsing -Headers $h).Content -split "`r?`n" }
$overrides = @($overrides | Where-Object { $_ -and $_ -notlike '#*' })
$names = $overrides | ForEach-Object { ($_ -split ':', 2)[0] }
$lines = @()
if (Test-Path $options) { $lines = @(Get-Content $options -Encoding utf8 | Where-Object { ($_ -split ':', 2)[0] -notin $names }) }
$lines += $overrides
# Continuity ships connected glass as built-in packs that start off. Add them and the pack's
# resource packs (Continuity draws their glowing ores), and keep the player's other packs.
$packLine = $lines | Where-Object { $_ -like 'resourcePacks:*' } | Select-Object -First 1
$packs = [Collections.Generic.List[string]]@('vanilla', 'fabric')
if ($packLine) { $packs = [Collections.Generic.List[string]]@(ConvertFrom-Json $packLine.Substring('resourcePacks:'.Length) | ForEach-Object { $_ }) }
foreach ($p in @('continuity:default', 'continuity:glass_pane_culling_fix') + @($resourceFiles | ForEach-Object { "file/$($_.file)" })) { if ($p -notin $packs) { $packs.Add($p) } }
$lines = @($lines | Where-Object { $_ -notlike 'resourcePacks:*' }) + ('resourcePacks:' + (ConvertTo-Json @($packs) -Compress))
# Without a version line Minecraft treats the file as pre-1.13 and reads key names as numbers.
# That fails, and Minecraft then resets every option to default. 3955 is the 1.21.1 data version.
if (-not ($lines | Where-Object { $_ -like 'version:*' })) { $lines = @('version:3955') + $lines }
# Minecraft misreads options.txt when it starts with a BOM, so write UTF-8 without one.
[IO.File]::WriteAllLines($options, [string[]]$lines, $utf8)

Write-Host ''
Write-Host 'Done.'
Write-Host '- TLauncher: pick "' -NoNewline
Write-Host $versionId -NoNewline -ForegroundColor Green
Write-Host '" in the version list, and press Play.'
Write-Host '- Minecraft Launcher: pick the "' -NoNewline
Write-Host 'The Lost Expedition' -NoNewline -ForegroundColor Green
Write-Host '" installation next to the Play button, and press Play.'
Write-Host "Set up for player name: $playerName. Run this installer again after you change your name."
