# Produit les clips et leurs apercus avec Godot 4.7 en version editeur.
param([string]$Godot = 'godot', [string]$Scenario = '*')

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work = New-Item -ItemType Directory -Force (Join-Path $project "../.tmp/rules-demos/run-$PID")
$stage = New-Item -ItemType Directory -Force (Join-Path $work.FullName 'project')

# Movie Maker fixe les dimensions au demarrage. Le projet de rendu partage
# les ressources deja importees et possede sa propre configuration.
foreach ($name in @('assets', 'data', 'scripts', 'scenes', 'tools', 'addons', '.godot')) {
    $junction = Join-Path $stage.FullName $name
    if (-not (Test-Path -LiteralPath $junction)) {
        New-Item -ItemType Junction -Path $junction -Target (Join-Path $project $name) | Out-Null
    }
}
foreach ($name in @('project.godot', 'default_bus_layout.tres')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $stage.FullName
}
$scenarios = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'scenarios') -Filter '*.json' |
    Where-Object { $_.BaseName -like $Scenario } | Sort-Object Name)
if ($scenarios.Count -eq 0) { throw "Scenario inconnu : $Scenario" }

$profile = New-Item -ItemType Directory -Force (Join-Path $work.FullName 'profile')
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = $profile.FullName
    $env:LOCALAPPDATA = $profile.FullName
    $assets = New-Item -ItemType Directory -Force (Join-Path $project 'assets/rules_demos')
    foreach ($file in $scenarios) {
        $id = $file.BaseName
        $height = 300
        if ($id -eq 'weaken_adjacent') { $height = 480 }
        @"
[display]
window/size/viewport_width=720
window/size/viewport_height=$height
window/size/window_width_override=720
window/size/window_height_override=$height
"@ | Set-Content -Encoding ascii -LiteralPath (Join-Path $stage.FullName 'override.cfg')
        $clip = Join-Path $work.FullName "$id.ogv"
        $poster = Join-Path $work.FullName "$id.png"
        $engineArgs = @('--path', $stage.FullName, '--write-movie', $clip, '--fixed-fps', '30',
            '--disable-vsync', '--quit-after', '900', 'res://tools/rules_demos/RulesDemo.tscn',
            '--', $id, $poster)
        $log = & $Godot @engineArgs
        $log | Write-Output
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $clip) -or
                -not (Test-Path -LiteralPath $poster) -or -not ($log -match "RULES_DEMO_OK $id")) {
            throw "Le rendu a echoue : $id"
        }
        Copy-Item -LiteralPath $clip, $poster -Destination $assets.FullName -Force
    }
} finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
}
