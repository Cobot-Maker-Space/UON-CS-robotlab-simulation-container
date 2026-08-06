<#
.SYNOPSIS
    Idempotent helper for the "ros" Docker network + noVNC container - native Windows PowerShell edition.

.DESCRIPTION
    PowerShell equivalent of start_vnc.sh. Talks to Docker Desktop's `docker` CLI directly, so it
    runs from a plain Windows PowerShell prompt - no WSL distro, no bash, no admin rights needed
    (assuming Docker Desktop is already installed and the current user can run `docker` commands).

.PARAMETER Command
    One of: start, stop, status, restart. Defaults to start.

.EXAMPLE
    .\start_vnc.ps1 start

.EXAMPLE
    # Override defaults via environment variables, same as the bash version
    $env:HOST_PORT = "9000"
    .\start_vnc.ps1 start

.NOTES
    If PowerShell refuses to run this script ("running scripts is disabled on this system"),
    launch it with:
        powershell -ExecutionPolicy Bypass -File .\start_vnc.ps1 start
    This does not require admin rights and does not change any system-wide policy.

    IMPORTANT FOR MAINTAINERS: keep this file pure ASCII, and save it as UTF-8 *with* a BOM.
    Windows PowerShell 5.1 decodes BOM-less files using the system ANSI codepage, which turns a
    UTF-8 em dash into 'a<euro>"' - and that trailing character is U+201D, which PowerShell treats
    as a real string delimiter. Three of them anywhere in this file desynchronises the parser and
    produces a bogus "The string is missing the terminator" error hundreds of lines away.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'restart')]
    [string]$Command = 'start'
)

# --- Config (override via environment variables, same names as start_vnc.sh) ---
$NetworkName   = if ($env:NETWORK_NAME)   { $env:NETWORK_NAME }   else { 'ros' }
$NovncName     = if ($env:NOVNC_NAME)     { $env:NOVNC_NAME }     else { 'novnc' }
$NovncImage    = if ($env:NOVNC_IMAGE)    { $env:NOVNC_IMAGE }    else { 'theasp/novnc:latest' }
$DisplayWidth  = if ($env:DISPLAY_WIDTH)  { $env:DISPLAY_WIDTH }  else { '3000' }
$DisplayHeight = if ($env:DISPLAY_HEIGHT) { $env:DISPLAY_HEIGHT } else { '1800' }
$RunXterm      = if ($env:RUN_XTERM)      { $env:RUN_XTERM }      else { 'no' }
$HostPort      = if ($env:HOST_PORT)      { $env:HOST_PORT }      else { '8080' }

$VncUrl = "http://localhost:$HostPort/vnc.html"

# --- Helpers ---
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Err "docker CLI not found on PATH."
        Write-Host "  Docker Desktop is not installed, or this shell was opened before it was installed."
        Write-Host "  Close and reopen PowerShell first. If it still fails, this is an IT/imaging step."
        exit 1
    }

    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "The docker CLI is installed but the Docker engine is not responding."
        Write-Host "  Most likely causes, in order:"
        Write-Host "    1. Docker Desktop is not running. Start it and wait for the whale icon to stop animating."
        Write-Host "    2. Your account is not in the local 'docker-users' group (IT-side fix - see README-lab-windows.md)."
        Write-Host "  Raw error from docker:"
        docker info 2>&1 | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" }
        exit 1
    }
}

function Test-NetworkExists {
    docker network inspect $NetworkName > $null 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Get-ContainerNames {
    param([switch]$IncludeStopped)

    if ($IncludeStopped) {
        $raw = docker ps -a --format '{{.Names}}' 2>$null
    } else {
        $raw = docker ps --format '{{.Names}}' 2>$null
    }
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }

    # Native command output already arrives one line per array element, but be defensive about
    # single-string output and stray carriage returns.
    return @($raw) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' }
}

function Test-ContainerRunning {
    return ((Get-ContainerNames) -contains $NovncName)
}

function Test-ContainerExists {
    return ((Get-ContainerNames -IncludeStopped) -contains $NovncName)
}

function Test-PortInUse {
    # Get-NetTCPConnection ships with Windows 10/11 and needs no admin rights to query, but it is
    # only a warning aid here - never let it take the script down.
    try {
        $port = [int]$HostPort
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        return [bool]$conn
    } catch {
        return $false
    }
}

function Wait-ForContainer {
    param([int]$TimeoutSeconds = 15)

    $deadline = $TimeoutSeconds * 1000
    $waited = 0
    while ($waited -lt $deadline) {
        if (Test-ContainerRunning) { return $true }
        Start-Sleep -Milliseconds 500
        $waited += 500
    }
    return (Test-ContainerRunning)
}

function Start-NoVnc {
    Assert-Docker

    if (Test-NetworkExists) {
        Write-Info "Docker network '$NetworkName' already exists."
    } else {
        Write-Info "Creating docker network '$NetworkName'..."
        docker network create $NetworkName > $null
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to create docker network '$NetworkName'."
            exit 3
        }
    }

    if (Test-ContainerRunning) {
        Write-Info "noVNC container '$NovncName' is already running."
        Write-Host ""
        Write-Info "Open $VncUrl and click Connect."
        return
    }

    if (Test-ContainerExists) {
        Write-Info "Container '$NovncName' exists but is not running - attempting 'docker start'..."
        docker start $NovncName > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Started existing container '$NovncName'."
            Write-Host ""
            Write-Info "Open $VncUrl and click Connect."
            return
        }
        Write-Warn "Failed to start existing container '$NovncName'. Removing it and re-creating."
        docker rm -f $NovncName > $null 2>&1
    }

    if (Test-PortInUse) {
        Write-Warn "Host port $HostPort already has a listener. 'docker run' may fail to bind it."
        Write-Warn "Set a different port first, e.g.:  `$env:HOST_PORT = '9000'"
    }

    # Pull explicitly rather than letting 'docker run -d' do it silently. On a fresh lab PC this is
    # a few hundred MB and the script would otherwise look frozen for several minutes.
    docker image inspect $NovncImage > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Image '$NovncImage' not present locally. Pulling (first run only, this can take a few minutes)..."
        docker pull $NovncImage
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to pull '$NovncImage'. Check your network / proxy settings."
            exit 3
        }
    }

    Write-Info "Running new noVNC container '$NovncName' (image: $NovncImage)..."

    # Build the argument list as an array and splat it. Backtick line-continuations are fragile
    # (a single trailing space after the backtick silently breaks the command), so avoid them.
    $runArgs = @(
        'run', '-d', '--rm',
        '--network', $NetworkName,
        '--env', "DISPLAY_WIDTH=$DisplayWidth",
        '--env', "DISPLAY_HEIGHT=$DisplayHeight",
        '--env', "RUN_XTERM=$RunXterm",
        '--name', $NovncName,
        '-p', "${HostPort}:8080",
        $NovncImage
    )
    docker @runArgs > $null

    if ($LASTEXITCODE -eq 0 -and (Wait-ForContainer)) {
        Write-Info "noVNC started: $VncUrl"
        Write-Host ""
        Write-Info "Next: open the 'src' folder in VS Code and run 'Dev Containers: Reopen in Container'."
    } else {
        Write-Err "Failed to start noVNC container. Diagnose with:"
        Write-Host "  docker ps -a"
        Write-Host "  docker logs $NovncName"
        exit 2
    }
}

function Stop-NoVnc {
    Assert-Docker
    if (Test-ContainerExists) {
        Write-Info "Stopping and removing container '$NovncName'..."
        docker rm -f $NovncName > $null 2>&1
        Write-Info "Stopped."
    } else {
        Write-Info "No container named '$NovncName' found."
    }
}

function Get-NoVncStatus {
    Assert-Docker
    if (Test-ContainerRunning) {
        Write-Info "Container '$NovncName' is running."
        docker ps --filter "name=$NovncName" --format "  {{.ID}}  {{.Image}}  {{.Status}}  Ports: {{.Ports}}"
        Write-Info "Open $VncUrl and click Connect."
    } elseif (Test-ContainerExists) {
        Write-Info "Container '$NovncName' exists but is stopped."
        docker ps -a --filter "name=$NovncName" --format "  {{.ID}}  {{.Image}}  {{.Status}}  Ports: {{.Ports}}"
    } else {
        Write-Info "noVNC container not present."
    }

    if (Test-NetworkExists) {
        Write-Info "Docker network '$NetworkName' exists."
    } else {
        Write-Warn "Docker network '$NetworkName' does not exist."
    }
}

switch ($Command) {
    'start'   { Start-NoVnc }
    'stop'    { Stop-NoVnc }
    'status'  { Get-NoVncStatus }
    'restart' { Stop-NoVnc; Start-NoVnc }
}
