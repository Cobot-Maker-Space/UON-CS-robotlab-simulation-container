<#
.SYNOPSIS
    One-time Robot Lab setup for a Windows lab machine. Run as administrator, at imaging time.

.DESCRIPTION
    Prepares a shared lab PC so that a standard, non-admin student account can run the whole
    TurtleBot3 simulation environment by double-clicking one shortcut.

    What it does:
      1. Verifies Docker Desktop, VS Code and Git are present (optionally installs them via winget)
      2. Adds a student group to the local 'docker-users' group, so non-admins can use Docker
      3. Clones this repository to a machine-wide location
      4. Pre-pulls both container images - roughly 2.6 GB, which is the step that must NOT happen
         for the first time in front of a class
      5. Creates the 'ros' Docker network
      6. Puts "Robot Lab" shortcuts on the all-users desktop and Start menu

    It is safe to re-run: everything it does is idempotent, and re-running is the intended way to
    update a machine after new work is pushed.

.PARAMETER StudentGroup
    Group or account to add to 'docker-users', e.g. "DOMAIN\Students" or "Authenticated Users".
    Omit to skip this step and do it through Group Policy instead.

.PARAMETER InstallPath
    Where the machine-wide clone lives. Students never edit this; the launcher copies it into
    each student's own profile on their first run.

.PARAMETER Branch
    Branch to deploy. Defaults to the Windows lab testing branch.

.PARAMETER InstallMissing
    Attempt to install any missing prerequisite with winget. Off by default, because most sites
    deploy Docker Desktop and VS Code through their own imaging or Intune, and Docker Desktop has
    licensing terms an institution needs to have accepted deliberately.

.PARAMETER SkipImagePull
    Skip the image download. Only useful when re-running purely to refresh the shortcuts or repo.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-RobotLab.ps1 -StudentGroup "UONDOMAIN\CS-Students"

.NOTES
    MAINTAINERS: keep this file PURE ASCII. See the note at the top of robotlab.ps1 for why.
#>
[CmdletBinding()]
param(
    [string]$StudentGroup,
    [string]$InstallPath = "$env:ProgramData\RobotLab\repo",
    [string]$RepoUrl     = 'https://github.com/Cobot-Maker-Space/UON-CS-robotlab-simulation-container.git',
    [string]$Branch      = 'clickable-lab-machines-testing',
    [string]$NovncImage  = 'theasp/novnc:latest',
    [switch]$InstallMissing,
    [switch]$SkipImagePull
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor White }
function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[ OK ] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[FAIL] $m" -ForegroundColor Red }

# --- Must be admin ------------------------------------------------------------------------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as administrator."
    Write-Host "  Right-click PowerShell, choose 'Run as administrator', then run it again." -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "  Robot Lab - machine setup" -ForegroundColor White
Write-Host "  Target: $InstallPath (branch $Branch)" -ForegroundColor Gray

# --- 1. Prerequisites ---------------------------------------------------------------------------
Write-Step "1/6  Prerequisites"

function Test-Prerequisite {
    param([string]$Name, [string]$CommandName, [string]$WingetId, [string]$Hint)

    if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
        Write-Ok "$Name is installed."
        return $true
    }

    if ($InstallMissing) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Err "$Name is missing and winget is not available to install it."
            return $false
        }
        Write-Info "Installing $Name via winget ($WingetId)..."
        # Out-Host, not bare invocation: a native command's stdout would otherwise join this
        # function's return value, so the caller would get an array of winget output lines
        # instead of the $true/$false it expects.
        & winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Err "winget failed to install $Name (exit code $LASTEXITCODE)."
            return $false
        }
        Write-Ok "$Name installed. A reboot may be needed before it works."
        return $true
    }

    Write-Err "$Name is not installed."
    Write-Host "  $Hint" -ForegroundColor Gray
    Write-Host "  Or re-run this script with -InstallMissing to attempt it via winget." -ForegroundColor Gray
    return $false
}

# Splatted hashtables rather than backtick line continuations. A backtick with a single trailing
# space after it silently breaks the command, which is a miserable thing to debug on a lab PC.
$prerequisites = @(
    @{
        Name        = 'Docker Desktop'
        CommandName = 'docker'
        WingetId    = 'Docker.DockerDesktop'
        Hint        = 'Install Docker Desktop with the WSL2 backend enabled.'
    },
    @{
        Name        = 'VS Code'
        CommandName = 'code'
        WingetId    = 'Microsoft.VisualStudioCode'
        Hint        = 'Install VS Code, making sure the "Add to PATH" option is selected.'
    },
    @{
        Name        = 'Git'
        CommandName = 'git'
        WingetId    = 'Git.Git'
        Hint        = 'Install Git for Windows.'
    }
)

$prereqOk = $true
foreach ($prerequisite in $prerequisites) {
    if (-not (Test-Prerequisite @prerequisite)) { $prereqOk = $false }
}

if (-not $prereqOk) {
    Write-Host ""
    Write-Err "Install the missing prerequisites, then run this script again."
    exit 1
}

# The Dev Containers extension installs per-user, so this only covers the account running the
# script. On a shared machine it has to be handled per student.
Write-Info "Checking the VS Code Dev Containers extension for the CURRENT account..."
$extensions = & code --list-extensions 2>$null
if ($extensions -contains 'ms-vscode-remote.remote-containers') {
    Write-Ok "Dev Containers extension present for $($env:USERNAME)."
} else {
    Write-Info "Installing it for $($env:USERNAME)..."
    & code --install-extension ms-vscode-remote.remote-containers 2>$null | Out-Null
}
Write-Info "VS Code extensions are PER USER. The launcher installs this one automatically for each"
Write-Host "  student on their first run, so no login script or GPO is needed for it." -ForegroundColor Gray

# --- 2. docker-users group ----------------------------------------------------------------------
Write-Step "2/6  Docker access for non-admin accounts"

if ($StudentGroup) {
    try {
        $existing = Get-LocalGroupMember -Group 'docker-users' -ErrorAction Stop |
            Where-Object { $_.Name -ieq $StudentGroup -or $_.Name -ilike "*\$($StudentGroup.Split('\')[-1])" }
        if ($existing) {
            Write-Ok "'$StudentGroup' is already in docker-users."
        } else {
            Add-LocalGroupMember -Group 'docker-users' -Member $StudentGroup -ErrorAction Stop
            Write-Ok "Added '$StudentGroup' to docker-users."
        }
    } catch {
        Write-Err "Could not add '$StudentGroup' to docker-users: $($_.Exception.Message)"
        Write-Host "  Check the group name, and that Docker Desktop is installed (it creates" -ForegroundColor Gray
        Write-Host "  the docker-users group). Students cannot use Docker until this is done." -ForegroundColor Gray
    }
} else {
    Write-Warn "No -StudentGroup given, so docker-users was not touched."
    Write-Host "  Non-admin students cannot talk to Docker until their group is a member." -ForegroundColor Gray
    Write-Host "  Either re-run with -StudentGroup 'DOMAIN\Students', or handle it via GPO." -ForegroundColor Gray
}

# --- 3. Repository ------------------------------------------------------------------------------
Write-Step "3/6  Repository"

if (Test-Path (Join-Path $InstallPath '.git')) {
    Write-Info "Updating the existing clone at $InstallPath..."
    & git -C $InstallPath fetch origin --quiet
    & git -C $InstallPath checkout $Branch --quiet
    & git -C $InstallPath reset --hard "origin/$Branch" --quiet
    if ($LASTEXITCODE -ne 0) { Write-Err "git update failed."; exit 1 }
    Write-Ok "Updated to the latest $Branch."
} else {
    Write-Info "Cloning $RepoUrl ($Branch)..."
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InstallPath) | Out-Null
    # No core.longpaths dance is needed any more: the 221 MB cache/ tree with its 271-character
    # paths is no longer tracked, so a stock clone stays well inside MAX_PATH.
    & git clone --branch $Branch --single-branch $RepoUrl $InstallPath
    if ($LASTEXITCODE -ne 0) { Write-Err "git clone failed."; exit 1 }
    Write-Ok "Cloned to $InstallPath."
}

$launcherDir = Join-Path $InstallPath 'launcher'
$startCmd    = Join-Path $launcherDir 'Start Robot Lab.cmd'
if (-not (Test-Path $startCmd)) {
    Write-Err "Expected the launcher at $startCmd but it is not there."
    Write-Host "  Is '$Branch' the right branch?" -ForegroundColor Gray
    exit 1
}

# --- 4. Images ----------------------------------------------------------------------------------
Write-Step "4/6  Container images"

if ($SkipImagePull) {
    Write-Warn "Skipping image download because -SkipImagePull was given."
} else {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Docker Desktop is not running, so the images cannot be pre-pulled."
        Write-Host "  Start Docker Desktop and re-run this script. Without this step, the first" -ForegroundColor Gray
        Write-Host "  student to log in downloads about 2.6 GB while the class waits." -ForegroundColor Gray
    } else {
        # Read the image out of devcontainer.json rather than hardcoding it here, so this cannot
        # drift from what the dev container actually uses.
        $devcontainerJson = Join-Path $InstallPath 'src\.devcontainer\devcontainer.json'
        $match = Select-String -Path $devcontainerJson -Pattern '^\s*"image"\s*:\s*"([^"]+)"' | Select-Object -First 1
        if (-not $match) {
            Write-Err "Could not read the image name from $devcontainerJson."
            exit 1
        }
        $rosImage = $match.Matches[0].Groups[1].Value

        foreach ($image in @($rosImage, $NovncImage)) {
            Write-Info "Pulling $image ..."
            docker pull $image
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Failed to pull $image."
                Write-Host "  'manifest unknown' means the tag does not exist on the registry." -ForegroundColor Gray
                Write-Host "  'denied' or 'unauthorized' means the package is still private -" -ForegroundColor Gray
                Write-Host "  a maintainer needs to set its visibility to Public on GitHub." -ForegroundColor Gray
                exit 1
            }
            Write-Ok "$image is cached locally."
        }
    }
}

# --- 5. Docker network --------------------------------------------------------------------------
Write-Step "5/6  Docker network"

docker info > $null 2>&1
if ($LASTEXITCODE -eq 0) {
    docker network inspect ros > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Docker network 'ros' already exists."
    } else {
        docker network create ros | Out-Null
        Write-Ok "Created Docker network 'ros'."
    }
} else {
    Write-Warn "Docker not running - skipped. The launcher creates the network itself anyway."
}

# --- 6. Shortcuts -------------------------------------------------------------------------------
Write-Step "6/6  Shortcuts"

function New-RobotLabShortcut {
    param([string]$Path, [string]$Target, [string]$Description)

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath       = $Target
    $link.WorkingDirectory = Split-Path -Parent $Target
    $link.Description      = $Description
    # Cosmetic only, and only if VS Code is where we expect. A student picks the shortcut out by
    # its icon, so it is worth setting when we can.
    $codeIcon = "$env:ProgramFiles\Microsoft VS Code\Code.exe"
    if (Test-Path $codeIcon) { $link.IconLocation = "$codeIcon,0" }
    $link.Save()
    Write-Ok "Created: $Path"
}

$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
$startMenuDir  = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Robot Lab'
New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null

New-RobotLabShortcut -Path (Join-Path $publicDesktop 'Robot Lab.lnk') `
    -Target $startCmd -Description 'Start the TurtleBot3 simulation environment'

foreach ($entry in @(
    @{ Name = 'Robot Lab';         File = 'Start Robot Lab.cmd';   Desc = 'Start the TurtleBot3 simulation environment' },
    @{ Name = 'Robot Lab - Stop';  File = 'Stop Robot Lab.cmd';    Desc = 'Shut the simulation environment down' },
    @{ Name = 'Robot Lab - Check'; File = 'Robot Lab (Check).cmd'; Desc = 'Diagnose why Robot Lab will not start' },
    @{ Name = 'Robot Lab - Reset'; File = 'Robot Lab (Reset).cmd'; Desc = 'Clear the compiled workspace cache' }
)) {
    New-RobotLabShortcut -Path (Join-Path $startMenuDir "$($entry.Name).lnk") `
        -Target (Join-Path $launcherDir $entry.File) -Description $entry.Desc
}

# --- Done ---------------------------------------------------------------------------------------
Write-Host ""
Write-Host "  Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Students now log in with a normal account and double-click 'Robot Lab' on the" -ForegroundColor Gray
Write-Host "  desktop. On their first run the launcher copies the workspace into their profile," -ForegroundColor Gray
Write-Host "  which takes a few seconds; after that it starts in well under a minute." -ForegroundColor Gray
Write-Host ""
Write-Host "  Still to confirm before a class:" -ForegroundColor Yellow
Write-Host "   - every student account has the VS Code Dev Containers extension" -ForegroundColor Gray
if (-not $StudentGroup) {
    Write-Host "   - the student group is a member of the local 'docker-users' group" -ForegroundColor Gray
}
Write-Host "   - Docker Desktop is set to start on login, or students know to start it" -ForegroundColor Gray
Write-Host "   - log in as a real student account and run 'Robot Lab - Check' once" -ForegroundColor Gray
Write-Host ""
