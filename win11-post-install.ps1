# ============================================================
#  win11-post-install
#  Utilidad interactiva para preparar una instalacion limpia de
#  Windows 11 IoT LTSC: bootstrap de WinGet + Microsoft Store,
#  catalogo de aplicaciones (winget) y extras (fuera de winget).
#
#  Pensado para Windows 11 IoT LTSC. En otras versiones de Windows
#  puede o no funcionar; no hay garantia.
#
#  USO:
#    .\win11-post-install.ps1            # menu interactivo (pide admin en modo real)
#    .\win11-post-install.ps1 -Mode real # salta el menu de modo (lo usa el propio relanzamiento)
#    .\win11-post-install.ps1 -Mode dryrun
#
#  Requiere ejecutarse en consola (powershell.exe), no en el ISE.
# ============================================================
param([string]$Mode = "")

Set-StrictMode -Off

# ------------------------------------------------------------
# Utilidades de bajo nivel
# ------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause {
    Read-Host "`nPulsa ENTER para volver al menu" | Out-Null
}

function Show-Menu {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string[]]$Options
    )
    $idx = 0
    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $idx) {
                Write-Host ("  > " + $Options[$i]) -ForegroundColor Black -BackgroundColor White
            } else {
                Write-Host ("    " + $Options[$i])
            }
        }
        Write-Host ""
        Write-Host "Flechas: mover | ENTER: elegir | ESC: salir" -ForegroundColor DarkGray

        $key = [Console]::ReadKey($true).Key
        if ($key -eq [ConsoleKey]::UpArrow)    { $idx = [Math]::Max(0, $idx - 1) }
        elseif ($key -eq [ConsoleKey]::DownArrow) { $idx = [Math]::Min($Options.Count - 1, $idx + 1) }
        elseif ($key -eq [ConsoleKey]::Enter)  { return $idx }
        elseif ($key -eq [ConsoleKey]::Escape) { return -1 }
    }
}

function Show-Checklist {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Items
    )
    $states = New-Object bool[] $Items.Count
    $idx = 0
    $top = 0
    $winH = [Math]::Max(8, [int][Console]::WindowHeight)
    $maxVisible = [Math]::Max(1, $winH - 6)
    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ""

        # ventana de visualizacion centrada en la seleccion
        if ($idx -lt $top) { $top = $idx }
        if ($idx -ge $top + $maxVisible) { $top = $idx - $maxVisible + 1 }
        $top = [Math]::Max(0, [Math]::Min($top, [Math]::Max(0, $Items.Count - $maxVisible)))

        for ($i = $top; $i -lt [Math]::Min($Items.Count, $top + $maxVisible); $i++) {
            $mark = if ($states[$i]) { "[x]" } else { "[ ]" }
            $line = "  $mark  " + $Items[$i].Name
            if ($i -eq $idx) {
                Write-Host $line -ForegroundColor Black -BackgroundColor White
            } else {
                Write-Host $line
            }
        }

        if ($top -gt 0) { Write-Host "  ^ mas arriba" -ForegroundColor DarkGray }
        if ($top + $maxVisible -lt $Items.Count) { Write-Host "  v mas abajo" -ForegroundColor DarkGray }

        Write-Host ""
        Write-Host "Flechas: mover | ESPACIO: marcar/desmarcar | A: todas | N: ninguna | ENTER: instalar | ESC: volver" -ForegroundColor DarkGray

        $key = [Console]::ReadKey($true).Key
        if ($key -eq [ConsoleKey]::UpArrow)      { $idx = [Math]::Max(0, $idx - 1) }
        elseif ($key -eq [ConsoleKey]::DownArrow){ $idx = [Math]::Min($Items.Count - 1, $idx + 1) }
        elseif ($key -eq [ConsoleKey]::Spacebar) { $states[$idx] = -not $states[$idx] }
        elseif ($key -eq [ConsoleKey]::A)        { for ($i = 0; $i -lt $Items.Count; $i++) { $states[$i] = $true } }
        elseif ($key -eq [ConsoleKey]::N)        { for ($i = 0; $i -lt $Items.Count; $i++) { $states[$i] = $false } }
        elseif ($key -eq [ConsoleKey]::Enter) {
            $selected = @()
            for ($i = 0; $i -lt $Items.Count; $i++) { if ($states[$i]) { $selected += $i } }
            return ,$selected
        }
        elseif ($key -eq [ConsoleKey]::Escape)   { return $null }
    }
}

# ------------------------------------------------------------
# Modo de ejecucion
# ------------------------------------------------------------
if ($Mode -eq "") {
    $m = Show-Menu -Title "win11-post-install - Modo de ejecucion" -Options @(
        "Ejecucion real (instalar)",
        "Dry-run (simulacion: no instala ni modifica nada)"
    )
    if ($m -eq -1) { Write-Host "Cancelado." -ForegroundColor Yellow; exit 0 }
    $Mode = if ($m -eq 0) { "real" } else { "dryrun" }
}

$DryRun = ($Mode -eq "dryrun")

# ------------------------------------------------------------
# Elevacion a administrador (solo en modo real)
# ------------------------------------------------------------
if ($Mode -eq "real" -and -not (Test-Admin)) {
    Write-Host "[!] Relanzando como administrador..." -ForegroundColor Yellow
    $script = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Mode real"
    exit
}

# ------------------------------------------------------------
# Banner
# ------------------------------------------------------------
Clear-Host
Write-Host "=== win11-post-install - Windows 11 IoT LTSC ===" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "MODO DRY-RUN: no se instalara ni modificara nada." -ForegroundColor Yellow
} else {
    Write-Host "MODO REAL." -ForegroundColor Green
}

# ------------------------------------------------------------
# 1. Bootstrap de WinGet (IoT LTSC no lo incluye)
# ------------------------------------------------------------
function Invoke-WingetBootstrap {
    $tag = "v1.29.280"
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -Headers @{ 'User-Agent' = 'win11-post-install' } -ErrorAction Stop
        $tag = $rel.tag_name
    } catch {
        if (-not $DryRun) { Write-Host "[!] No se pudo consultar la ultima version; usando $tag" -ForegroundColor Yellow }
    }
    $base = "https://github.com/microsoft/winget-cli/releases/download/$tag"
    $work = "$env:TEMP\winget-bootstrap"
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -notin @("x64", "x86", "arm64")) { $arch = "x64" }

    if ($DryRun) {
        Write-Host "`n=== [DRYRUN] BOOTSTRAP DE WINGET ===" -ForegroundColor Cyan
        Write-Host "[DRYRUN] Release winget-cli: $tag"
        Write-Host "[DRYRUN] Descargar: $base/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Write-Host "[DRYRUN] Descargar: $base/DesktopAppInstaller_Dependencies.zip"
        Write-Host "[DRYRUN] Add-AppxPackage: VCLibs x86/x64 + WindowsAppRuntime 1.8"
        Write-Host "[DRYRUN] Add-AppxPackage: AppInstaller.msixbundle"
        Write-Host "[DRYRUN] Anadir al PATH: $env:LOCALAPPDATA\Microsoft\WindowsApps"
        return
    }

    Write-Host "`n=== INSTALANDO WINGET (App Installer) ===" -ForegroundColor Cyan
    Set-ExecutionPolicy Bypass -Scope Process -Force
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Write-Host "[*] Descargando App Installer ($tag)..."
    Invoke-WebRequest -Uri "$base/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "$work\AppInstaller.msixbundle" -UseBasicParsing
    Write-Host "[*] Descargando dependencias..."
    Invoke-WebRequest -Uri "$base/DesktopAppInstaller_Dependencies.zip" -OutFile "$work\deps.zip" -UseBasicParsing
    Expand-Archive -Path "$work\deps.zip" -DestinationPath "$work\deps" -Force
    $depDir = "$work\deps\$arch"
    $depOrder = @(
        "Microsoft.VCLibs.140.00_*_$arch.appx",
        "Microsoft.VCLibs.140.00.UWPDesktop_*_$arch.appx",
        "Microsoft.WindowsAppRuntime.1.8_*_$arch.appx"
    )
    foreach ($pattern in $depOrder) {
        $pkg = Get-ChildItem -LiteralPath $depDir -Filter $pattern | Select-Object -First 1
        if ($pkg) {
            Write-Host "[*] Instalando dependencia: $($pkg.Name)"
            Add-AppxPackage -Path $pkg.FullName -ForceApplicationShutdown -ErrorAction Continue
        }
    }
    Write-Host "[*] Instalando App Installer..."
    Add-AppxPackage -Path "$work\AppInstaller.msixbundle" -ForceApplicationShutdown -ErrorAction Continue
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
    if ($env:Path -notlike "*$wingetPath*") { $env:Path += ";$wingetPath" }
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Write-Host "[OK] WinGet instalado." -ForegroundColor Green
    } else {
        Write-Host "[!] WinGet no se detecto. Revisa la instalacion manualmente." -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Workflow: Utilidades (WinGet + Microsoft Store)
# ------------------------------------------------------------
function Invoke-Utilities {
    $items = @(
        [pscustomobject]@{ Name = "WinGet (App Installer)"; Key = "winget" },
        [pscustomobject]@{ Name = "Microsoft Store"; Key = "store" }
    )
    $sel = Show-Checklist -Title "Utilidades - marca con ESPACIO y confirma con ENTER" -Items $items
    if ($null -eq $sel -or $sel.Count -eq 0) {
        Write-Host "No se selecciono ninguna utilidad." -ForegroundColor Yellow
        return
    }
    $keys = @($sel | ForEach-Object { $items[$_].Key })

    if ($keys -contains "winget") {
        if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
            Write-Host "[OK] WinGet ya esta presente." -ForegroundColor Green
        } else {
            Invoke-WingetBootstrap
        }
    }

    if ($keys -contains "store") {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue) -and -not $DryRun) {
            Write-Host "[!] Microsoft Store se instala con WinGet, pero WinGet no esta disponible. Instala WinGet primero." -ForegroundColor Red
        } elseif ($DryRun) {
            Write-Host "[DRYRUN] winget install --id 9WZDNCRFJBMP --source msstore --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
        } elseif (-not (Get-AppxPackage -Name "Microsoft.WindowsStore")) {
            Write-Host "`n=== INSTALANDO MICROSOFT STORE ===" -ForegroundColor Cyan
            winget install --id 9WZDNCRFJBMP --source msstore --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
            if (Get-AppxPackage -Name "Microsoft.WindowsStore") {
                Write-Host "[OK] Microsoft Store instalada." -ForegroundColor Green
            } else {
                Write-Host "[!] No se pudo instalar la Store." -ForegroundColor Red
            }
        } else {
            Write-Host "[OK] Microsoft Store ya esta presente." -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------
# Metadatos del catalogo: nombre amigable + categoria
# ------------------------------------------------------------
$AppMeta = @{
    "Audacity.Audacity"                          = @{Name="Audacity"; Cat="5. MULTIMEDIA"}
    "CrystalDewWorld.CrystalDiskInfo"            = @{Name="CrystalDiskInfo"; Cat="2. SISTEMA"}
    "Wagnardsoft.DisplayDriverUninstaller"       = @{Name="Display Driver Uninstaller"; Cat="2. SISTEMA"}
    "Git.Git"                                    = @{Name="Git"; Cat="6. DESARROLLO"}
    "JetBrains.IntelliJIDEA.Community"           = @{Name="IntelliJ IDEA Community"; Cat="6. DESARROLLO"}
    "shinchiro.mpv"                              = @{Name="MPV Player"; Cat="5. MULTIMEDIA"}
    "7zip.7zip"                                  = @{Name="7-Zip"; Cat="2. SISTEMA"}
    "nomacs.nomacs"                              = @{Name="nomacs (image viewer)"; Cat="5. MULTIMEDIA"}
    "VideoLAN.VLC"                               = @{Name="VLC"; Cat="5. MULTIMEDIA"}
    "EpicGames.EpicGamesLauncher"                = @{Name="Epic Games Launcher"; Cat="7. JUEGOS"}
    "OpenJS.NodeJS"                              = @{Name="Node.js"; Cat="6. DESARROLLO"}
    "LibreWolf.LibreWolf"                        = @{Name="LibreWolf"; Cat="3. WEB Y COMUNICACION"}
    "OBSProject.OBSStudio"                       = @{Name="OBS Studio"; Cat="5. MULTIMEDIA"}
    "Valve.Steam"                                = @{Name="Steam"; Cat="7. JUEGOS"}
    "qBittorrent.qBittorrent"                    = @{Name="qBittorrent"; Cat="3. WEB Y COMUNICACION"}
    "ElectronicArts.EADesktop"                   = @{Name="EA App"; Cat="7. JUEGOS"}
    "Python.Launcher"                            = @{Name="Python Launcher"; Cat="6. DESARROLLO"}
    "Microsoft.VCRedist.2015+.x86"               = @{Name="Visual C++ 2015-2022 x86"; Cat="1. RUNTIMES"}
    "Tailscale.Tailscale"                        = @{Name="Tailscale"; Cat="2. SISTEMA"}
    "AsaphaHalifa.AudioRelay"                    = @{Name="AudioRelay"; Cat="5. MULTIMEDIA"}
    "Microsoft.VCRedist.2015+.x64"               = @{Name="Visual C++ 2015-2022 x64"; Cat="1. RUNTIMES"}
    "Bitwarden.Bitwarden"                        = @{Name="Bitwarden"; Cat="2. SISTEMA"}
    "Brave.Brave"                                = @{Name="Brave"; Cat="3. WEB Y COMUNICACION"}
    "Discord.Discord"                            = @{Name="Discord"; Cat="3. WEB Y COMUNICACION"}
    "Gyan.FFmpeg"                                = @{Name="FFmpeg"; Cat="5. MULTIMEDIA"}
    "Postman.Postman"                            = @{Name="Postman"; Cat="6. DESARROLLO"}
    "PrismLauncher.PrismLauncher"                = @{Name="Prism Launcher"; Cat="7. JUEGOS"}
    "Rufus.Rufus"                                = @{Name="Rufus"; Cat="2. SISTEMA"}
    "SST.opencode"                               = @{Name="opencode (CLI)"; Cat="6. DESARROLLO"}
    "Spotify.Spotify"                            = @{Name="Spotify"; Cat="5. MULTIMEDIA"}
    "SST.OpenCodeDesktop"                        = @{Name="OpenCode Desktop"; Cat="6. DESARROLLO"}
    "sxyazi.yazi"                                = @{Name="Yazi"; Cat="6. DESARROLLO"}
    "9NKSQGP7F2NH"                               = @{Name="WhatsApp"; Cat="3. WEB Y COMUNICACION"}
    "Fastfetch-cli.Fastfetch"                    = @{Name="Fastfetch"; Cat="2. SISTEMA"}
    "Python.Python.3.14"                         = @{Name="Python 3.14"; Cat="6. DESARROLLO"}
    "Microsoft.VisualStudioCode"                 = @{Name="Visual Studio Code"; Cat="6. DESARROLLO"}
    "Python.Python.3.12"                         = @{Name="Python 3.12"; Cat="6. DESARROLLO"}
    "M2Team.NanaZip"                             = @{Name="NanaZip"; Cat="2. SISTEMA"}
    "Microsoft.AppInstaller"                     = @{Name="App Installer"; Cat="1. RUNTIMES"}
    "Microsoft.DirectX"                          = @{Name="DirectX"; Cat="1. RUNTIMES"}
    "Microsoft.DotNet.Native.Runtime"            = @{Name=".NET Native Runtime"; Cat="1. RUNTIMES"}
    "Microsoft.DotNet.DesktopRuntime.8"          = @{Name=".NET Desktop Runtime 8"; Cat="1. RUNTIMES"}
    "Microsoft.DotNet.DesktopRuntime.10"         = @{Name=".NET Desktop Runtime 10"; Cat="1. RUNTIMES"}
    "Microsoft.UI.Xaml.2.8"                      = @{Name="UI.Xaml 2.8"; Cat="1. RUNTIMES"}
    "Microsoft.VCLibs.Desktop.14"                = @{Name="VCLibs Desktop 14"; Cat="1. RUNTIMES"}
    "Microsoft.VCLibs.14"                        = @{Name="VCLibs 14"; Cat="1. RUNTIMES"}
    "Microsoft.WindowsAppRuntime.1.8"            = @{Name="Windows App Runtime 1.8"; Cat="1. RUNTIMES"}
    "Microsoft.WindowsAppRuntime.2"              = @{Name="Windows App Runtime 2"; Cat="1. RUNTIMES"}
    "Microsoft.WindowsTerminal"                  = @{Name="Windows Terminal"; Cat="2. SISTEMA"}
    "ApacheFriends.Xampp.8.2"                    = @{Name="XAMPP 8.2 (Apache + MariaDB + phpMyAdmin)"; Cat="4. PRODUCTIVIDAD"}
    "EclipseAdoptium.Temurin.25.JDK"             = @{Name="Eclipse Temurin JDK 25"; Cat="6. DESARROLLO"}
    "EclipseAdoptium.Temurin.24.JDK"             = @{Name="Eclipse Temurin JDK 24"; Cat="6. DESARROLLO"}
}

function Get-WingetSource([string]$Id) {
    # IDs de Microsoft Store no contienen punto (ej. 9NKSQGP7F2NH)
    if ($Id -notmatch '\.') { return "msstore" }
    return "winget"
}

function Load-Catalog {
    $jsonPath = Join-Path $PSScriptRoot "winget-packages.json"
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        Write-Host "[ERROR] No se encontro winget-packages.json junto al script." -ForegroundColor Red
        Write-Host "[ERROR] Esperado: $jsonPath" -ForegroundColor Red
        return $null
    }
    $backup = (ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $jsonPath)).Sources.Packages.PackageIdentifier

    $apps = foreach ($id in $backup) {
        $meta = $AppMeta[$id]
        if ($meta) {
            [pscustomobject]@{ Id = $id; Name = "$($meta.Cat)  $($meta.Name)"; Cat = $meta.Cat }
        } else {
            [pscustomobject]@{ Id = $id; Name = "OTROS  $id"; Cat = "OTROS" }
        }
    }
    return @($apps | Sort-Object Name)
}

# ------------------------------------------------------------
# Workflow: Aplicaciones (WinGet)
# ------------------------------------------------------------
function Invoke-Apps {
    $apps = Load-Catalog
    if ($null -eq $apps -or $apps.Count -eq 0) {
        Write-Host "[ERROR] No se pudo cargar el catalogo." -ForegroundColor Red
        return
    }

    $sel = Show-Checklist -Title "Aplicaciones (WinGet) - marca con ESPACIO y confirma con ENTER" -Items $apps
    if ($null -eq $sel -or $sel.Count -eq 0) {
        Write-Host "No se selecciono ninguna aplicacion." -ForegroundColor Yellow
        return
    }

    $accion = if ($DryRun) { "COMANDOS QUE SE EJECUTARIAN" } else { "INSTALANDO" }
    Write-Host "`n=== $accion : $($sel.Count) APLICACIONES ===" -ForegroundColor Cyan
    $fail = @()
    foreach ($i in $sel) {
        $id  = $apps[$i].Id
        $src = Get-WingetSource $id
        $cmd = "winget install --id $id --source $src --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
        if ($DryRun) {
            Write-Host "[DRYRUN] $cmd"
            continue
        }
        Write-Host "[*] Instalando: $id"
        winget install --id $id --source $src --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
        if ($LASTEXITCODE -ne 0) { $fail += $id }
    }

    if (-not $DryRun) {
        Write-Host "`n=== RESUMEN ===" -ForegroundColor Cyan
        Write-Host "Correctas: $($sel.Count - $fail.Count) / $($sel.Count)"
        if ($fail.Count -gt 0) {
            Write-Host "Fallaron:" -ForegroundColor Red
            $fail | ForEach-Object { Write-Host "  - $_" }
        }
    } else {
        Write-Host "`n=== DRY-RUN COMPLETADO ===" -ForegroundColor Green
    }
}

# ------------------------------------------------------------
# Workflow: Extras (fuera de winget, desde extras.json)
# ------------------------------------------------------------
function Invoke-Extras {
    $extrasPath = Join-Path $PSScriptRoot "extras.json"
    if (-not (Test-Path -LiteralPath $extrasPath)) {
        Write-Host "[ERROR] No se encontro extras.json junto al script." -ForegroundColor Red
        Write-Host "[ERROR] Esperado: $extrasPath" -ForegroundColor Red
        return
    }
    $extras = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $extrasPath)
    if ($null -eq $extras) { $extras = @() }
    elseif ($extras -isnot [array]) { $extras = @($extras) }
    if ($extras.Count -eq 0) {
        Write-Host "No hay extras definidos en extras.json." -ForegroundColor Yellow
        return
    }

    $sel = Show-Checklist -Title "Otros (extras) - marca con ESPACIO y confirma con ENTER" -Items $extras
    if ($null -eq $sel -or $sel.Count -eq 0) {
        Write-Host "No se selecciono ningun extra." -ForegroundColor Yellow
        return
    }

    $fail = @()
    foreach ($i in $sel) {
        $e = $extras[$i]
        Write-Host ""
        Write-Host "=== Extra: $($e.name) ===" -ForegroundColor Cyan

        # Requisito previo (python, git, etc.)
        if ($e.requires) {
            $found = $false
            switch ($e.requires) {
                "python" { $found = [bool](Get-Command python -ErrorAction SilentlyContinue) -or [bool](Get-Command py -ErrorAction SilentlyContinue) }
                "git"    { $found = [bool](Get-Command git -ErrorAction SilentlyContinue) }
            }
            if (-not $found) {
                Write-Host "[!] $($e.name): falta el requisito '$($e.requires)'. Instalalo primero (seccion Aplicaciones)." -ForegroundColor Red
                $fail += $e.name
                continue
            }
        }

        # Deteccion de ya-instalado
        if ($e.check) {
            $installed = $false
            if ($DryRun) {
                Write-Host "[DRYRUN] comprobar: $($e.check)"
            } else {
                $LASTEXITCODE = $null
                Invoke-Expression $e.check *> $null
                $installed = ($LASTEXITCODE -eq 0)
            }
            if ($installed) {
                Write-Host "[OK] $($e.name) ya parece instalado; se omite." -ForegroundColor Green
                continue
            }
        }

        # Seleccion de variante (ej. esquema de TeX Live)
        $install = [string]$e.install
        if ($e.choices) {
            $label = if ($e.choices.label) { [string]$e.choices.label } else { "Variante" }
            $opts = @($e.choices.options)
            if ($opts.Count -eq 0) {
                Write-Host "[!] $($e.name): choices sin opciones." -ForegroundColor Red
                $fail += $e.name
                continue
            }
            $c = Show-Menu -Title "$($e.name) - $label" -Options $opts
            if ($c -eq -1) {
                Write-Host "Cancelado: $($e.name)." -ForegroundColor Yellow
                continue
            }
            $install = $install.Replace('{choice}', $opts[$c])
        }

        # Entradas interactivas (prompts declarados en extras.json)
        $script:InputValues = @{}
        if ($e.inputs) {
            $empty = $false
            foreach ($inp in $e.inputs) {
                $prompt = if ($inp.prompt) { [string]$inp.prompt } else { "Valor para $($inp.var)" }
                $val = Read-Host "  $prompt"
                if ([string]::IsNullOrWhiteSpace($val)) { $empty = $true; break }
                Set-Variable -Name $inp.var -Value $val -Scope Script
                $script:InputValues[$inp.var] = $val
            }
            if ($empty) {
                Write-Host "[!] $($e.name): entrada vacia; se omite." -ForegroundColor Red
                $fail += $e.name
                continue
            }
        }

        if ($DryRun) {
            if ($script:InputValues.Count -gt 0) {
                $kv = foreach ($k in $script:InputValues.Keys) { "$k='$($script:InputValues[$k])'" }
                Write-Host "[DRYRUN] entradas: $($kv -join ', ')"
            }
            Write-Host "[DRYRUN] $install"
            continue
        }
        Write-Host "[*] Ejecutando: $install"
        $global:LASTEXITCODE = 0
        Invoke-Expression $install
        if ($global:LASTEXITCODE -ne 0) { $fail += $e.name }
    }

    if (-not $DryRun) {
        Write-Host "`n=== RESUMEN EXTRAS ===" -ForegroundColor Cyan
        if ($fail.Count -gt 0) {
            Write-Host "Fallaron o se omitieron:" -ForegroundColor Red
            $fail | ForEach-Object { Write-Host "  - $_" }
        } else {
            Write-Host "Extras procesados correctamente." -ForegroundColor Green
        }
    } else {
        Write-Host "`n=== DRY-RUN COMPLETADO ===" -ForegroundColor Green
    }
}

# ------------------------------------------------------------
# Menu principal (no lineal)
# ------------------------------------------------------------
$menuOptions = @(
    "Utilidades: WinGet + Microsoft Store",
    "Aplicaciones (WinGet)",
    "Otros (extras desde extras.json)",
    "Salir"
)

while ($true) {
    $choice = Show-Menu -Title "win11-post-install - Menu principal" -Options $menuOptions
    if ($choice -eq -1 -or $choice -eq 3) {
        Write-Host "Saliendo." -ForegroundColor Green
        break
    }
    switch ($choice) {
        0 { Invoke-Utilities }
        1 { Invoke-Apps }
        2 { Invoke-Extras }
    }
    Pause
}
