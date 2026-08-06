<#
.SYNOPSIS
    Idempotent helper for the "ros" Docker network + noVNC container — native Windows PowerShell edition.

.DESCRIPTION
    PowerShell equivalent of start_vnc.sh. Talks to Docker Desktop's `docker` CLI directly, so it
    runs from a plain Windows PowerShell prompt — no WSL distro, no bash, no admin rights needed
    (assuming Docker Desktop is already installed and the current user can run `docker` commands).

.PARAMETER Command
    One of: start, stop, status, restart. Defaults to start.

.EXAMPLE
    .\start_vnc.ps1 start

.EXAMPLE
    # Override defaults via environment variables, same as the bash version
    $env:HOST_PORT = 9000
    .\start_vnc.ps1 start

.NOTES
    If PowerShell refuses to run this script ("running scripts is disabled on this system"),
    launch it with:
        powershell -ExecutionPolicy Bypass -File .\start_vnc.ps1 start
    This does not require admin rights and does not change any system-wide policy.
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

# --- Helpers ---
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Err "docker CLI not found. Install/start Docker Desktop and try again."
        exit 1
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Docker CLI found but the Docker engine isn't responding. Is Docker Desktop running?"
        exit 1
    }
}

function Test-NetworkExists {
    docker network inspect $NetworkName *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-ContainerRunning {
    $names = (docker ps --format '{{.Names}}') -split "`n" | Where-Object { $_ -ne '' }
    return $names -contains $NovncName
}

function Test-ContainerExists {
    $names = (docker ps -a --format '{{.Names}}') -split "`n" | Where-Object { $_ -ne '' }
    return $names -contains $NovncName
}

function Test-PortInUse {
    # Get-NetTCPConnection ships with Windows 10/11 and needs no admin rights to query.
    $conn = Get-NetTCPConnection -LocalPort $HostPort -State Listen -ErrorAction SilentlyContinue
    return [bool]$conn
}

function Start-NoVnc {
    Assert-Docker

    if (Test-NetworkExists) {
        Write-Info "Docker network '$NetworkName' already exists."
    } else {
        Write-Info "Creating docker network '$NetworkName'..."
        docker network create $NetworkName | Out-Null
    }

    if (Test-ContainerRunning) {
        Write-Info "noVNC container '$NovncName' is already running."
        Write-Host ""
        Write-Info "Open http://localhost:$HostPort/vnc.html and click Connect."
        return
    }

    if (Test-ContainerExists) {
        Write-Info "Container '$NovncName' exists but is not running — attempting 'docker start'..."
        docker start $NovncName | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Started existing container '$NovncName'."
            Write-Host ""
            Write-Info "Open http://localhost:$HostPort/vnc.html and click Connect."
            return
        } else {
            Write-Warn "Failed to start existing container '$NovncName'. Removing it and re-creating."
            docker rm -f $NovncName *> $null
        }
    }

    if (Test-PortInUse) {
        Write-Warn "Host port $HostPort looks busy. docker run may fail to bind that port."
    }

    Write-Info "Running new noVNC container '$NovncName' (image: $NovncImage)..."
    docker run -d --rm --network $NetworkName `
        --env "DISPLAY_WIDTH=$DisplayWidth" `
        --env "DISPLAY_HEIGHT=$DisplayHeight" `
        --env "RUN_XTERM=$RunXterm" `
        --name $NovncName -p "${HostPort}:8080" $NovncImage | Out-Null

    Start-Sleep -Milliseconds 800
    if (Test-ContainerRunning) {
        Write-Info "noVNC started: http://localhost:$HostPort/vnc.html"
    } else {
        Write-Err "Failed to start noVNC container. Check 'docker ps -a' and container logs with:"
        Write-Host "  docker ps -a | Select-String $NovncName"
        Write-Host "  docker logs $NovncName"
        exit 2
    }
}

function Stop-NoVnc {
    Assert-Docker
    if (Test-ContainerExists) {
        Write-Info "Stopping and removing container '$NovncName'..."
        docker rm -f $NovncName *> $null
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
