<#
.SYNOPSIS
    ROS Simulator launcher - brings up the whole TurtleBot3 simulation environment in one step.

.DESCRIPTION
    Everything a student used to do by hand:

      - check Docker Desktop and VS Code are present and working
      - create their own private copy of the ROS workspace, once, on first run
      - create the 'ros' Docker network and start the noVNC container
      - make sure the ROS 2 image is present
      - open the browser at the noVNC desktop
      - open VS Code ALREADY ATTACHED to the dev container

    Students do not run this directly. They double-click "Start ROS Simulator.cmd", or the shortcut
    that Install-RobotLab.ps1 puts on the desktop.

.PARAMETER Command
    start   Bring everything up. The default.
    stop    Stop the dev container and noVNC. Leaves the student's work and build cache alone.
    status  Report what is running.
    reset   Delete the build cache volumes. Destructive; asks for confirmation.
    doctor  Run every preflight check and report, without starting anything.

.NOTES
    Requires no admin rights. Called via "powershell -ExecutionPolicy Bypass -File", which affects
    only that one process and changes nothing system-wide.

    MAINTAINERS: keep this file PURE ASCII. Windows PowerShell 5.1 decodes a file with no byte
    order mark using the system ANSI codepage. A UTF-8 em dash then becomes three characters, the
    last of which is U+201D, which the parser treats as a real string delimiter. The result is a
    bogus "string is missing the terminator" error reported hundreds of lines from the actual
    character. As long as every byte is ASCII, both decodings are identical and this cannot bite.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'reset', 'doctor')]
    [string]$Command = 'start'
)

$ErrorActionPreference = 'Stop'

# --- Paths ------------------------------------------------------------------------------------
# The launcher lives at <repo>/launcher/, so the repository root is one level up. Self-locating,
# so it works whether IT deployed to C:\ProgramData\ROSSimulator\repo or a developer is running it
# from a personal clone.
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$RepoSrc    = Join-Path $RepoRoot 'src'
$StartVnc   = Join-Path $RepoSrc '.devcontainer\start_vnc.ps1'

# The student's own writable workspace. Kept short and inside their profile, well clear of the
# 260-character path limit, and private to their Windows account on a shared lab PC.
$SimHome  = if ($env:ROSSIM_HOME) { $env:ROSSIM_HOME } else { Join-Path $env:USERPROFILE 'ROSSimulator' }
$UserWorkspace = Join-Path $SimHome 'ros2_ws'
$UserSrc       = Join-Path $UserWorkspace 'src'

$HostPort = if ($env:HOST_PORT) { $env:HOST_PORT } else { '8080' }
$VncUrl   = "http://localhost:$HostPort/vnc.html"

$MinFreeGb = 15

# --- Output helpers ---------------------------------------------------------------------------
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message"  -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "[ OK ] $Message"  -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message"  -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[FAIL] $Message"  -ForegroundColor Red }

function Write-Remedy {
    # A student staring at a red error needs the fix, not a stack trace.
    param([string[]]$Lines)
    foreach ($line in $Lines) { Write-Host "       $line" -ForegroundColor Gray }
}

function Stop-WithError {
    # Exits non-zero. The .cmd wrappers pause on a non-zero exit, so a student who double-clicked
    # the shortcut still gets to read this before the window closes. Pausing here as well would
    # make them press a key twice.
    param([string]$Message, [string[]]$Remedy, [int]$Code = 1)
    Write-Host ""
    Write-Err $Message
    if ($Remedy) { Write-Remedy $Remedy }
    Write-Host ""
    exit $Code
}

# --- Preflight checks -------------------------------------------------------------------------
# Each returns $true/$false and prints its own diagnosis, so 'doctor' can run them all and 'start'
# can stop at the first failure.

function Test-DockerCli {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Err "Docker is not installed, or this window was opened before it was installed."
        Write-Remedy @(
            "This is an IT setup step, not something you can fix from here.",
            "If Docker Desktop was only just installed, close this window and try again."
        )
        return $false
    }
    Write-Ok "Docker CLI found."
    return $true
}

function Test-DockerEngine {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Docker Desktop is not responding."
        Write-Remedy @(
            "1. Start Docker Desktop from the Start menu and wait for the whale icon to stop",
            "   animating. It can take a minute or two on a cold boot.",
            "2. If it is already running, your account may not be in the 'docker-users' group.",
            "   That one needs IT."
        )
        return $false
    }
    Write-Ok "Docker engine is responding."
    return $true
}

function Test-VsCode {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Err "VS Code ('code' command) is not on PATH."
        Write-Remedy @(
            "VS Code is either not installed or was installed without the 'Add to PATH' option.",
            "This is an IT setup step."
        )
        return $false
    }
    Write-Ok "VS Code found."
    return $true
}

function Test-DevContainersExtension {
    # 'code --list-extensions' is slow (a few seconds), so this is checked once per run.
    $extensions = & code --list-extensions 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not list VS Code extensions. Continuing anyway."
        return $true
    }
    if ($extensions -notcontains 'ms-vscode-remote.remote-containers') {
        Write-Warn "The VS Code 'Dev Containers' extension is not installed. Installing it now (first run only)..."
        & code --install-extension ms-vscode-remote.remote-containers 2>$null | Out-Null
        $extensions = & code --list-extensions 2>$null
        if ($extensions -notcontains 'ms-vscode-remote.remote-containers') {
            Write-Err "Could not install the VS Code 'Dev Containers' extension."
            Write-Remedy @(
                "Install it manually with:",
                "  code --install-extension ms-vscode-remote.remote-containers",
                "This does not need admin rights."
            )
            return $false
        }
    }
    Write-Ok "Dev Containers extension installed."
    return $true
}

function Test-DiskSpace {
    try {
        $drive = (Get-Item $env:USERPROFILE).PSDrive.Name
        $free  = (Get-PSDrive $drive).Free
        $freeGb = [math]::Round($free / 1GB, 1)
        if ($free -lt ($MinFreeGb * 1GB)) {
            Write-Warn "Only $freeGb GB free on ${drive}: - the images and workspace need about $MinFreeGb GB."
            return $false
        }
        Write-Ok "Disk space: $freeGb GB free."
        return $true
    } catch {
        Write-Warn "Could not check free disk space. Continuing."
        return $true
    }
}

function Test-UsernameIsVolumeSafe {
    # devcontainer.json builds the cache volume names from ${localEnv:USERNAME} and cannot sanitise
    # it. Docker only accepts [a-zA-Z0-9][a-zA-Z0-9_.-]* as a volume name, so a domain account with
    # a space or a backslash in it would fail at container-create time with a message that gives no
    # hint about the real cause. Catch it here instead.
    if ($env:USERNAME -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') {
        Write-Err "The Windows username '$($env:USERNAME)' cannot be used in a Docker volume name."
        Write-Remedy @(
            "Docker volume names allow only letters, digits, underscore, dot and hyphen.",
            "Report this to IT: the volume naming in src/.devcontainer/devcontainer.json needs",
            "adjusting for this account naming scheme."
        )
        return $false
    }
    Write-Ok "Username '$($env:USERNAME)' is valid for per-user cache volumes."
    return $true
}

function Test-RepoLayout {
    if (-not (Test-Path $RepoSrc)) {
        Write-Err "Cannot find the repository source at: $RepoSrc"
        Write-Remedy @(
            "This launcher expects to live in <repo>\launcher\. It looks like it was copied",
            "somewhere else. Run it from its original location."
        )
        return $false
    }
    if (-not (Test-Path $StartVnc)) {
        Write-Err "Cannot find start_vnc.ps1 at: $StartVnc"
        return $false
    }
    Write-Ok "Repository layout looks right ($RepoRoot)."
    return $true
}

function Invoke-Preflight {
    param([switch]$ContinueOnFailure)

    Write-Info "Checking this machine is ready..."
    $checks = @(
        { Test-RepoLayout },
        { Test-DockerCli },
        { Test-DockerEngine },
        { Test-VsCode },
        { Test-DevContainersExtension },
        { Test-UsernameIsVolumeSafe },
        { Test-DiskSpace }
    )

    $failed = 0
    foreach ($check in $checks) {
        $ok = & $check
        if (-not $ok) {
            $failed++
            if (-not $ContinueOnFailure) { return $false }
        }
    }
    return ($failed -eq 0)
}

# --- Per-user workspace -----------------------------------------------------------------------

function Initialize-UserWorkspace {
    if (Test-Path $UserSrc) {
        Write-Ok "Your workspace is at $UserSrc"
        return
    }

    Write-Info "First run for '$($env:USERNAME)'. Setting up your own copy of the workspace..."
    Write-Info "  from: $RepoSrc"
    Write-Info "  to:   $UserSrc"

    New-Item -ItemType Directory -Force -Path $UserWorkspace | Out-Null

    # robocopy reports success with exit codes 0 to 7; anything from 8 up is a real failure. The
    # usual bug here is treating a non-zero exit as an error, which fails on every run that
    # actually copied something (code 1).
    & robocopy $RepoSrc $UserSrc /E /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        Stop-WithError -Message "Could not copy the workspace (robocopy exit code $rc)." -Remedy @(
            "Check you have space in your profile and that $RepoSrc is readable."
        )
    }

    if (-not (Test-Path (Join-Path $UserSrc '.devcontainer\devcontainer.json'))) {
        Stop-WithError -Message "The workspace copy is missing .devcontainer\devcontainer.json." -Remedy @(
            "The source at $RepoSrc looks incomplete. IT should re-clone the repository."
        )
    }

    Write-Ok "Workspace ready. Your work is saved here and is private to your account."
}

# --- Docker helpers ---------------------------------------------------------------------------

function Get-PinnedImage {
    # Read the image the dev container will actually use, rather than duplicating the name here
    # and letting the two drift apart.
    $configPath = Join-Path $UserSrc '.devcontainer\devcontainer.json'
    if (-not (Test-Path $configPath)) { return $null }
    $match = Select-String -Path $configPath -Pattern '^\s*"image"\s*:\s*"([^"]+)"' | Select-Object -First 1
    if (-not $match) { return $null }
    return $match.Matches[0].Groups[1].Value
}

function Confirm-RosImage {
    $image = Get-PinnedImage
    if (-not $image) {
        Write-Warn "Could not read the image name from devcontainer.json. VS Code will pull it if needed."
        return
    }

    docker image inspect $image > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "ROS 2 image is already downloaded."
        return
    }

    Write-Info "Downloading the ROS 2 image. This is a few GB and happens only once."
    Write-Info "On a lab PC this should already have been done by IT, so if you see this and you"
    Write-Info "are in a class, tell a demonstrator - it will take a while."
    docker pull $image
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError -Message "Failed to download the ROS 2 image '$image'." -Remedy @(
            "If this says 'denied' or 'manifest unknown', the image tag or its visibility is",
            "wrong on the registry - that is a maintainer fix, not something to retry.",
            "Otherwise check the network or proxy settings."
        )
    }
}

function Start-NoVnc {
    Write-Info "Starting the graphical desktop service (noVNC)..."
    # Delegate rather than reimplement: start_vnc.ps1 is already idempotent and hardened, and the
    # WSL2 and manual flows still depend on it behaving exactly this way.
    & powershell -NoProfile -ExecutionPolicy Bypass -File $StartVnc start
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError -Message "Could not start the noVNC container." -Remedy @(
            "Read the message above from start_vnc.ps1 - it explains what failed.",
            "If port $HostPort is in use, set a different one first:",
            "  `$env:HOST_PORT = '9000'"
        )
    }
}

function Get-DevContainerId {
    # The Dev Containers extension labels the container it creates with the host folder it was
    # opened from. That label is how we can tell, from outside VS Code, whether the attach worked.
    #
    # Deliberately not using '--filter label=key=value': that is an exact string match, and the
    # extension has not always written the path in the same shape (drive letter case, trailing
    # separator, forward vs back slashes). A near-miss there would make a perfectly good attach
    # look like a failure and pop up a second VS Code window. Compare the paths ourselves instead.
    #
    # Deliberately not using 'docker ps --format' with a {{.Label "..."}} template either. Windows
    # PowerShell 5.1 strips the inner double quotes when it builds the command line for a native
    # executable, so docker actually receives {{.Label devcontainer.local_folder}}, Go's template
    # parser reads that bare word as a function call, and the whole command fails with
    #     failed to parse template: function "devcontainer" not defined
    # 'docker inspect' piped through ConvertFrom-Json needs no quoting inside a template at all, so
    # the native argument parser cannot corrupt it, on 5.1 or on PowerShell 7.
    #
    # This is a best-effort probe and every caller treats $null as "not running", so it must never
    # throw. With $ErrorActionPreference = 'Stop' set at the top of this script, ANY native command
    # that writes to stderr raises a TERMINATING NativeCommandError, and '2>$null' does not prevent
    # that on 5.1. The assignment below shadows the script-level preference for this function only,
    # and the try/catch is the second line of defence.
    $ErrorActionPreference = 'Continue'

    try {
        $ids = @(docker ps -q 2>$null)
        if ($LASTEXITCODE -ne 0 -or $ids.Count -eq 0) { return $null }

        $target = $UserSrc.TrimEnd('\', '/').Replace('/', '\')

        # Out-String matters: ConvertFrom-Json on 5.1 takes pipeline input line by line and chokes
        # on a multi-line JSON document.
        $raw = docker inspect $ids 2>$null | Out-String
        if ($raw -and $raw.Trim()) {
            foreach ($container in @($raw | ConvertFrom-Json)) {
                $folder = $container.Config.Labels.'devcontainer.local_folder'
                if (-not $folder) { continue }
                $folder = "$folder".Trim().TrimEnd('\', '/').Replace('/', '\')
                if ($folder -ieq $target) { return $container.Id }
            }
        }

        # Fallback for the case where that label is absent or renamed by a future extension version:
        # any running container built from the image devcontainer.json pins is almost certainly ours.
        $image = Get-PinnedImage
        if ($image) {
            $id = docker ps -q --filter "ancestor=$image" 2>$null
            if ($LASTEXITCODE -eq 0 -and $id) { return ($id | Select-Object -First 1) }
        }
    } catch {
        return $null
    }

    return $null
}

# --- VS Code ----------------------------------------------------------------------------------

function Get-DevContainerUri {
    # The Dev Containers extension accepts a folder URI of the form
    #   vscode-remote://dev-container+<hex>/<path inside the container>
    # where <hex> is the hex-encoded UTF-8 of a small JSON object naming the host folder. This is
    # what removes the "Ctrl+Shift+P, Reopen in Container" step.
    #
    # This is an internal contract of the extension, not a documented stable API, and its exact
    # shape has changed between extension versions. Every caller must handle it not working -
    # see Open-VsCode below, which always falls back to opening the folder normally.
    param([string]$HostPath)

    $escaped = $HostPath -replace '\\', '\\'
    $json    = '{"hostPath":"' + $escaped + '"}'
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hex     = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
    return "vscode-remote://dev-container+$hex/home/ros2_ws"
}

function Show-ManualFallback {
    Write-Host ""
    Write-Warn "VS Code did not attach to the container automatically."
    Write-Host "  Do this instead - it takes two steps:" -ForegroundColor Gray
    Write-Host "    1. VS Code should now be open on the folder $UserSrc" -ForegroundColor Gray
    Write-Host "    2. Press Ctrl+Shift+P, type 'Reopen in Container', press Enter" -ForegroundColor Gray
    Write-Host ""
}

function Open-VsCode {
    $existing = Get-DevContainerId
    if ($existing) {
        Write-Ok "The dev container is already running. Opening VS Code."
    } else {
        Write-Info "Starting the ROS 2 dev container and opening VS Code..."
        Write-Info "The first start on this account takes a minute while the workspace cache is set up."
    }

    $uri = Get-DevContainerUri -HostPath $UserSrc
    & code --folder-uri $uri
    $codeExit = $LASTEXITCODE

    if ($codeExit -ne 0) {
        Write-Warn "VS Code rejected the direct container URI (exit code $codeExit)."
        & code $UserSrc
        Show-ManualFallback
        return
    }

    # 'code' returns immediately, so exit code 0 proves nothing. Watch for the container the
    # extension creates instead. Container creation plus postCreateCommand can legitimately take a
    # couple of minutes the very first time a cache volume is seeded from the image.
    $timeoutSeconds = 180
    $waited = 0
    Write-Info "Waiting for the container to come up (up to $timeoutSeconds seconds)..."
    while ($waited -lt $timeoutSeconds) {
        Start-Sleep -Seconds 3
        $waited += 3
        if (Get-DevContainerId) {
            Write-Ok "VS Code is attached to the dev container."
            return
        }
        if ($waited % 30 -eq 0) { Write-Info "  still starting... ($waited s)" }
    }

    Write-Warn "The container did not appear within $timeoutSeconds seconds."
    & code $UserSrc
    Show-ManualFallback
}

# --- Commands ---------------------------------------------------------------------------------

function Invoke-Start {
    Write-Host ""
    Write-Host "  ROS Simulator" -ForegroundColor White
    Write-Host "  ---------" -ForegroundColor White
    Write-Host ""

    if (-not (Invoke-Preflight)) {
        Stop-WithError -Message "This machine is not ready. See the failure above." -Remedy @(
            "Run 'ROS Simulator - Check' or 'robotlab.ps1 doctor' for the full list of checks."
        )
    }

    Write-Host ""
    Initialize-UserWorkspace
    Write-Host ""
    Start-NoVnc
    Write-Host ""
    Confirm-RosImage
    Write-Host ""

    Write-Info "Opening the robot desktop in your browser: $VncUrl"
    Write-Info "If the page is blank, click the Connect button."
    Start-Process $VncUrl | Out-Null

    Write-Host ""
    Open-VsCode

    Write-Host ""
    Write-Ok "ROS Simulator is ready."
    Write-Host ""
    Write-Host "  Browser tab : Gazebo and RViz appear here  ($VncUrl)" -ForegroundColor Gray
    Write-Host "  VS Code     : edit code, and use its terminal to run ROS commands" -ForegroundColor Gray
    Write-Host "  Your files  : $UserSrc" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  After changing C++ source, run 'rossim-rebuild' in the VS Code terminal." -ForegroundColor Gray
    Write-Host ""
}

function Invoke-Stop {
    if (-not (Test-DockerCli)) { exit 1 }
    if (-not (Test-DockerEngine)) { exit 1 }

    $id = Get-DevContainerId
    if ($id) {
        Write-Info "Stopping the dev container..."
        docker stop $id > $null 2>&1
        Write-Ok "Dev container stopped."
    } else {
        Write-Info "No dev container running."
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $StartVnc stop

    Write-Host ""
    Write-Ok "Stopped. Your work in $UserSrc is untouched."
}

function Invoke-Status {
    if (-not (Test-DockerCli)) { exit 1 }
    if (-not (Test-DockerEngine)) { exit 1 }

    Write-Host ""
    $id = Get-DevContainerId
    if ($id) {
        Write-Ok "Dev container is running."
        docker ps --filter "id=$id" --format "  {{.ID}}  {{.Image}}  {{.Status}}"
    } else {
        Write-Info "Dev container is not running."
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $StartVnc status

    Write-Host ""
    Write-Info "Workspace: $UserSrc"
    if (Test-Path $UserSrc) { Write-Ok "  exists" } else { Write-Warn "  not created yet" }

    Write-Info "Cache volumes for '$($env:USERNAME)':"
    $volumes = docker volume ls --format '{{.Name}}' --filter "name=rossim-" 2>$null |
        Where-Object { $_ -like "*-$($env:USERNAME)" }
    if ($volumes) { $volumes | ForEach-Object { Write-Host "  $_" } }
    else { Write-Host "  none yet (they are created on first container start)" }
}

function Invoke-Reset {
    if (-not (Test-DockerCli)) { exit 1 }
    if (-not (Test-DockerEngine)) { exit 1 }

    Write-Host ""
    Write-Warn "This deletes your compiled workspace cache and forces a fresh one from the image."
    Write-Host "  Use this if the container will not start, or after IT updates the image." -ForegroundColor Gray
    Write-Host "  Your source code in $UserSrc is NOT touched by this." -ForegroundColor Gray
    Write-Host ""
    $answer = Read-Host "Type RESET to continue, or anything else to cancel"
    if ($answer -cne 'RESET') {
        Write-Info "Cancelled. Nothing was changed."
        return
    }

    $id = Get-DevContainerId
    if ($id) {
        Write-Info "Stopping and removing the dev container..."
        docker rm -f $id > $null 2>&1
    }

    foreach ($kind in @('build', 'install', 'log')) {
        $name = "rossim-$kind-$($env:USERNAME)"
        docker volume rm $name > $null 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok "Removed volume $name" }
        else { Write-Info "Volume $name was not present." }
    }

    Write-Host ""
    Write-Ok "Cache cleared. Start ROS Simulator again to rebuild it from the image."
    Write-Host ""
    Write-Warn "Your source code was left alone, on purpose."
    Write-Host "  If you also want a clean copy of the original packages, rename or delete" -ForegroundColor Gray
    Write-Host "  $UserSrc yourself first - back up anything you wrote before you do." -ForegroundColor Gray
}

function Invoke-Doctor {
    Write-Host ""
    Write-Host "  ROS Simulator - system check" -ForegroundColor White
    Write-Host ""
    $allOk = Invoke-Preflight -ContinueOnFailure

    Write-Host ""
    Write-Info "Paths"
    Write-Host "  repository : $RepoRoot"
    Write-Host "  workspace  : $UserSrc"
    $image = Get-PinnedImage
    Write-Host "  image      : $(if ($image) { $image } else { '(could not read devcontainer.json)' })"

    Write-Host ""
    if ($allOk) {
        Write-Ok "Everything checks out. ROS Simulator should start normally."
    } else {
        Write-Err "One or more checks failed. See the details above."
    }
    Write-Host ""
}

# --- Entry point ------------------------------------------------------------------------------
switch ($Command) {
    'start'  { Invoke-Start }
    'stop'   { Invoke-Stop }
    'status' { Invoke-Status }
    'reset'  { Invoke-Reset }
    'doctor' { Invoke-Doctor }
}
