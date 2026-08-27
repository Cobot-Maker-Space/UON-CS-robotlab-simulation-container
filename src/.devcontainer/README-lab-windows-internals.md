# 🔍 Robot Lab — how it actually works, file by file

**Audience:** you, six months from now, in a meeting, being asked *"why did you do it this way?"*

This document assumes you know your way around Linux and a terminal, that you use Windows as an
ordinary user, and that you have **never written a line of PowerShell**. It explains every file in
the Windows lab deployment: what it does, how it does it, and — the part that matters in a
review — **why it is built that way and what the alternative would have cost**.

- Want to *use* the system? → [root README](../../README.md)
- Want to *understand or defend* the system? → you are in the right place.

---

## Part 0 — The problem this exists to solve

Before this work, a student on a lab PC had to:

1. Install Git, clone a repo (which needed `git config core.longpaths true` first, or it failed)
2. Open a terminal, run a shell script to start a noVNC container
3. Open VS Code, open the right folder, press `Ctrl+Shift+P`, find "Reopen in Container"
4. Wait **10–25 minutes** while `colcon build` compiled the entire TurtleBot3 stack
5. Do all of that again on the next PC they sat at, because nothing persisted

Every one of those steps is a place a class of 60 students generates 60 support questions. Step 4
alone could consume most of a two-hour lab session.

**The target:** a student double-clicks one icon and is working within a minute. Everything else in
this document is a consequence of that goal, plus one hard constraint:

> **Students on lab PCs are not administrators.** Anything requiring admin rights must happen once,
> at imaging time, by IT — never at class time, by a student.

Hold those two ideas in your head and almost every decision below explains itself.

---

## Part 1 — Windows concepts you need (crash course for a Linux person)

Skip this if you already know it. If you don't, everything in Part 3 will look arbitrary without it.

### 1.1 Three different shells, and why we use two of them

| | Linux equivalent | What it is here |
|---|---|---|
| **`cmd.exe`** / `.cmd` files | `sh` — old, limited, universally present | The **double-click target**. Windows will run a `.cmd` when you double-click it. It will *not* run a `.ps1`. |
| **PowerShell** / `.ps1` files | `bash` + `python` — a real programming language | Where **all the logic** lives. |
| **PowerShell 7 / `pwsh`** | a newer bash | Not used. We target **Windows PowerShell 5.1**, which is what ships preinstalled on every Windows machine. Requiring an install would defeat the point. |

**Why both?** Double-clicking a `.ps1` file in Windows Explorer does *not* run it — by default it
opens it in Notepad. So each user-facing action needs a tiny `.cmd` file whose only job is to launch
PowerShell and hand it the real script. That is exactly what our four `.cmd` files do, and why they
are 6–12 lines each.

### 1.2 Execution Policy — and why `-ExecutionPolicy Bypass` is not a hack

By default Windows refuses to run `.ps1` scripts at all (`running scripts is disabled on this
system`). This is not a permissions system — it is a "don't accidentally run something you
downloaded" guard rail.

Every one of our `.cmd` files launches PowerShell like this:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0robotlab.ps1" start
```

Piece by piece:

| Fragment | Meaning | Why we chose it |
|---|---|---|
| `-NoProfile` | Don't load the user's PowerShell profile script | A student with a broken/slow profile can't break the launcher. Also faster. |
| `-ExecutionPolicy Bypass` | Ignore the script-blocking policy | **Applies to this one process only.** It changes nothing system-wide and needs **no admin rights** — which is the entire reason it works on a locked-down student account. |
| `-File "..."` | Run this script | |
| `%~dp0` | cmd-speak for "the folder this `.cmd` lives in", with trailing `\` | Makes the shortcut work regardless of where the repo is installed. The Linux equivalent of `$(dirname "$0")`. |
| `start` | An argument passed to the script | Selects which command to run — see `switch ($Command)` at the bottom of `robotlab.ps1`. |

> **If challenged:** "Isn't bypassing execution policy a security risk?" — No. Execution Policy is
> explicitly documented by Microsoft as *not* a security boundary; anyone who can run this `.cmd`
> could equally paste the script's contents into a PowerShell window. The alternative (setting the
> machine-wide policy to RemoteSigned) would be a *worse* change, because it is permanent, global,
> and needs admin.

### 1.3 PowerShell is object-based, and that has one big trap

In bash, a function "returns" an exit code and you capture its *stdout* with `$(...)`. In PowerShell,
**anything a function writes that isn't explicitly consumed becomes part of its return value.** There
is no separate stdout — the output stream *is* the return value.

This causes a bug you will see us defending against all over the codebase:

```powershell
# From Install-RobotLab.ps1 - the comment explains the trap
& winget install --id $WingetId --silent ... | Out-Host
```

Without `| Out-Host`, every line winget printed would be *added to what this function returns*. The
caller expects `$true`/`$false` and would instead receive an array of 40 winget output lines — which
PowerShell treats as truthy, so the check silently always passes.

The same reasoning explains every `| Out-Null` and `> $null` in the codebase. They are not noise
suppression for cosmetics; they are **return-value hygiene**.

`Write-Host` is the exception: it writes to the console *only* and never joins the return value.
That is why all our user-facing messages use `Write-Host` (via the `Write-Info`/`Write-Ok`/`Write-Warn`
/`Write-Err` helpers) rather than the more idiomatic `Write-Output`.

### 1.4 Cmdlets vs native commands — two different error systems

| | Example | How you detect failure |
|---|---|---|
| **Cmdlet** (built into PowerShell, returns objects) | `Get-LocalGroupMember`, `Select-String`, `Test-Path` | Throws an exception. Catch with `try/catch`, or suppress with `-ErrorAction SilentlyContinue`. |
| **Native command** (an actual `.exe`, returns text) | `docker`, `git`, `code`, `robocopy` | Sets `$LASTEXITCODE`. No exception. You must check it manually. |

This is why the code looks inconsistent but isn't:

```powershell
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { ... }   # cmdlet
docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) { ... }                                        # native
```

### 1.5 `$ErrorActionPreference = 'Stop'` — the sharpest edge in the whole codebase

Both PowerShell scripts set this near the top. It means *"if a cmdlet raises an error, abort the
script immediately"* — the rough equivalent of `set -e` in bash. We want that: a launcher that
half-works and then does something surprising is worse than one that stops and explains.

**But there is a vicious trap**, and we shipped a bug because of it:

> On Windows PowerShell 5.1, when a **native command writes to stderr** *and* its stderr is
> redirected, PowerShell wraps that output into an error record. Under `'Stop'`, that becomes a
> **terminating error** — the script dies. Adding `2>$null` does **not** save you; it is part of
> what triggers it.

This is what caused the `failed to parse template: function "devcontainer" not defined` crash: a
malformed `docker ps` call wrote to stderr, and `$ErrorActionPreference = 'Stop'` turned a
cosmetic problem into "VS Code never opens". See [`Get-DevContainerId`](../../launcher/robotlab.ps1)
for how it is now defended: the preference is overridden *inside that one function* and the whole
body is wrapped in `try/catch`.

**The general rule this taught us:** any function that is a *best-effort probe* — one whose callers
already treat "no answer" as a valid answer — must be incapable of throwing.

### 1.6 Splatting, and the backtick trap

PowerShell's line-continuation character is a backtick `` ` ``. It is notorious: **a single
invisible trailing space after the backtick silently breaks the command.** Debugging that on a lab
PC at 9am is miserable.

The preferred alternative is **splatting** — build the arguments as a data structure, then expand it:

```powershell
$runArgs = @(
    'run', '-d', '--rm',
    '--network', $NetworkName,
    '-p', "${HostPort}:8080",
    $NovncImage
)
docker @runArgs          # the @ expands the array into separate arguments
```

The same `@` works on hashtables to fill named parameters, which is how the prerequisite checks work:

```powershell
$prerequisites = @( @{ Name = 'Docker Desktop'; CommandName = 'docker'; ... }, ... )
foreach ($prerequisite in $prerequisites) {
    Test-Prerequisite @prerequisite      # Name=, CommandName=, ... filled from the hashtable keys
}
```

> **Honest note for a review:** `Install-RobotLab.ps1` still uses backtick continuations in the
> shortcut-creation section (`New-RobotLabShortcut -Path (...) \`` + newline). It works, but it
> contradicts the rule stated in that same file's comments. It is a fair thing for a reviewer to
> catch, and worth tidying.

### 1.7 Native commands and quotes — the bug we hit

PowerShell 5.1 **strips embedded double quotes** when building the command line for a native `.exe`.
So this:

```powershell
docker ps --format '{{.ID}}|{{.Label "devcontainer.local_folder"}}'
```

...reaches docker as `{{.ID}}|{{.Label devcontainer.local_folder}}`. Docker's Go template parser
reads the now-unquoted word as a *function name* and fails. The single quotes protected the string
inside PowerShell but not across the boundary into the executable.

**The fix we chose:** don't pass quotes across that boundary at all. Read the data as JSON instead:

```powershell
$ids = @(docker ps -q 2>$null)
$raw = docker inspect $ids 2>$null | Out-String
foreach ($container in @($raw | ConvertFrom-Json)) {
    $folder = $container.Config.Labels.'devcontainer.local_folder'
}
```

No quoting inside a template means nothing for the argument parser to corrupt — on 5.1 *or*
PowerShell 7, whose argument handling differs again. (`Out-String` is required because 5.1's
`ConvertFrom-Json` processes pipeline input line-by-line and chokes on multi-line JSON.)

### 1.8 Windows paths, users and groups

| Concept | Linux analogue | Where we use it |
|---|---|---|
| `C:\ProgramData` | `/opt` or `/usr/share` | The IT-managed clone. All users can read it; only admins can write. |
| `%USERPROFILE%` (`C:\Users\alice`) | `$HOME` | The student's private workspace copy. |
| `C:\Users\Public\Desktop` | — | A desktop shortcut that appears for *every* user of the machine. |
| **`docker-users` local group** | the `docker` group | Docker Desktop creates it. **A non-admin account cannot talk to Docker unless it is a member.** This is the single most important IT-side step. |
| `.lnk` shortcut | `.desktop` file | What the installer generates so students have an icon to click. |
| **MAX_PATH (260 chars)** | no equivalent | Windows historically refuses paths longer than 260 characters. This bit us badly — see §3.11. |

**Per-user vs per-machine** is a recurring theme. VS Code *extensions* install per user. Docker
*images* are per machine. Getting this wrong is why the installer prints a loud warning about the
Dev Containers extension: the installer runs as an admin, so it can only install the extension for
*the admin's* account, not for the students who will later log in.

---

## Part 2 — The architecture in one picture

```
    ┌─────────────────── ONE WINDOWS LAB PC ───────────────────────┐
    │                                                              │
    │  C:\ProgramData\RobotLab\repo\      ← IT-managed git clone   │
    │            │                          (read-only to students)│
    │            │  robocopy, once per student, on first launch    │
    │            ▼                                                 │
    │  C:\Users\alice\RobotLab\ros2_ws\src ← alice's private copy  │
    │            │                                                 │
    │            │  bind-mounted into the container                │
    │            ▼                                                 │
    │  ┌──────────────────┐   'ros' network   ┌──────────────────┐ │
    │  │ ROS 2 container  │──────────────────>│ novnc container  │ │
    │  │                  │  X11 over TCP     │                  │ │
    │  │ Gazebo, RViz     │  DISPLAY=         │ X server +       │ │
    │  │ colcon, ros2 CLI │    novnc:0.0      │ VNC + web server │ │
    │  │                  │                   │                  │ │
    │  │ VS Code attaches │                   │ localhost:8080   │ │
    │  └──────────────────┘                   └────────┬─────────┘ │
    │                                                  │           │
    └──────────────────────────────────────────────────┼───────────┘
                                                       ▼
                                            Student's browser tab
```

### Why two containers instead of one?

The ROS container **produces** graphics; the novnc container **displays** them. They talk over a
user-defined Docker network called `ros`, on which Docker provides DNS — so the hostname `novnc`
resolves automatically. `DISPLAY=novnc:0.0` means *"X display 0, on the machine called novnc"*,
which X11 serves over TCP port 6000.

**Defence:** the alternative is running the X server, VNC server and web server *inside* the ROS
container (which is what the Codespaces branch does, via `supervisord`). Both work. The two-container
split was inherited from the pre-existing Linux/WSL2 setup, and keeping it means the Windows lab
flow, the WSL2 flow and the manual flow all share **one** implementation of "start the desktop"
(`start_vnc.ps1` / `start_vnc.sh`) rather than three that drift apart. The cost is a second container
and a slightly odd `DISPLAY` value.

---

## Part 3 — Every file, explained

### 3.1 `launcher/Start Robot Lab.cmd` (and its three siblings)

```bat
@echo off
title Robot Lab
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0robotlab.ps1" start
if errorlevel 1 (
    echo.
    pause
)
```

**What it does:** the double-click target. Nothing more.

**Every design choice in six lines:**

- `@echo off` — don't echo each command as it runs. Cosmetic; keeps the window clean for a student.
- `title Robot Lab` — names the console window, so a student with several open can tell them apart.
- `%~dp0` — self-locating, so the repo can be installed anywhere.
- **`if errorlevel 1 ( pause )`** — this is the important one. In cmd, `errorlevel 1` means "exit
  code was 1 **or higher**". If the PowerShell script failed, we hold the window open so the student
  can *read the error*. If it succeeded, the window closes immediately and doesn't clutter the
  desktop.

That last point is a genuine design decision worth defending: **a window that flashes and vanishes is
the single worst failure mode for a non-technical user**, because it destroys the evidence. Note the
matching half of this contract inside `robotlab.ps1`:

```powershell
function Stop-WithError {
    # Exits non-zero. The .cmd wrappers pause on a non-zero exit, so a student who double-clicked
    # the shortcut still gets to read this before the window closes. Pausing here as well would
    # make them press a key twice.
```

The three siblings differ only in which command they pass and that they **always** `pause`:

| File | Command | Why it always pauses |
|---|---|---|
| `Stop Robot Lab.cmd` | `stop` | Its output *is* the point — you want to see it stopped. |
| `Robot Lab (Check).cmd` | `doctor` | It is a diagnostic report. A report you cannot read is useless. |
| `Robot Lab (Reset).cmd` | `reset` | Destructive; the confirmation and result must both be visible. |

---

### 3.2 `launcher/Install-RobotLab.ps1` — the once-per-machine, admin-only installer

318 lines, run once by IT at imaging time. Six numbered stages, and it is **idempotent** — re-running
it is the intended way to update a machine.

#### The header: `<# ... #>` comment-based help

```powershell
<#
.SYNOPSIS
.DESCRIPTION
.PARAMETER StudentGroup
.EXAMPLE
#>
```

This is not a plain comment. PowerShell parses these tags, so `Get-Help .\Install-RobotLab.ps1`
prints real documentation — the same mechanism built-in cmdlets use. Free, discoverable docs for
whoever inherits this.

#### Parameters

```powershell
param(
    [string]$StudentGroup,
    [string]$InstallPath = "$env:ProgramData\RobotLab\repo",
    [string]$RepoUrl     = 'https://github.com/.../UON-CS-robotlab-simulation-container.git',
    [string]$Branch      = 'clickable-lab-machines-testing',
    [switch]$InstallMissing,
    [switch]$SkipImagePull
)
```

A `[switch]` is a flag — present means `$true`. **Everything is parameterised with a sane default**,
so IT can redirect the install path or deploy a different branch without editing the script. Editing
a script to change a value is how sites end up with local forks that never get updates.

#### The admin check

```powershell
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
```

PowerShell can call .NET directly — `[Namespace.Type]::Method()`. This is asking Windows "is the
current user's token in the Administrators role?"

**Why check at all, rather than letting it fail?** Because it would fail *halfway*: it would clone
the repo successfully and *then* fail to write the shortcut, leaving a half-installed machine. Fail
fast, with a fix in the message (`Right-click PowerShell, choose 'Run as administrator'`).

#### Stage 1 — Prerequisites

```powershell
if (Get-Command $CommandName -ErrorAction SilentlyContinue) { ... }
```

`Get-Command docker` is the equivalent of `which docker`. `-ErrorAction SilentlyContinue` stops the
cmdlet throwing when not found, so the `if` can handle it.

`-InstallMissing` is **off by default**, and this is a deliberate policy choice worth defending:

> Most universities deploy Docker Desktop and VS Code through their own imaging or Intune, and
> **Docker Desktop's licence has terms an institution must accept deliberately.** A script that
> silently installs it on lab machines would be making a licensing decision that isn't ours to make.

The Dev Containers extension check is the interesting one:

```powershell
Write-Warn "VS Code extensions are PER USER. Students each need this extension."
```

The installer *cannot* solve this. It runs as an admin; extensions install into the running user's
profile. So it does the honest thing: install it for the current account, then **loudly tell IT the
exact command to push via GPO or a login script**, and make the student-facing launcher check for it
independently and print the same command. Two layers, because this is the failure most likely to
survive to class time.

#### Stage 2 — `docker-users`

```powershell
Add-LocalGroupMember -Group 'docker-users' -Member $StudentGroup -ErrorAction Stop
```

Wrapped in `try/catch`, so a wrong group name **warns but does not abort the install** — the other
five stages are still worth doing. This is why passing the literal placeholder `"DOMAIN\Students"`
produced a red `[FAIL]` line and then carried on to completion.

The membership check before adding it is deliberately fuzzy:

```powershell
Where-Object { $_.Name -ieq $StudentGroup -or $_.Name -ilike "*\$($StudentGroup.Split('\')[-1])" }
```

`-ieq` is case-insensitive equals; `-ilike` is case-insensitive wildcard match. Windows reports group
membership in several formats (`DOMAIN\Students`, `Students`, an SID), so an exact string comparison
would re-add an existing member every run and break idempotency.

#### Stage 3 — Repository

```powershell
if (Test-Path (Join-Path $InstallPath '.git')) {
    & git -C $InstallPath fetch origin --quiet
    & git -C $InstallPath checkout $Branch --quiet
    & git -C $InstallPath reset --hard "origin/$Branch" --quiet
} else {
    & git clone --branch $Branch --single-branch $RepoUrl $InstallPath
}
```

`git -C <dir>` runs git *as if* in that directory — avoids `cd`, which would leak state.

**`reset --hard` is the right call here and you should defend it confidently:** this clone is
machine-owned infrastructure that no human is supposed to edit. If someone *has* poked at it, that
is a fault to erase, not preserve. A `git pull` would fail with a merge conflict and leave the
machine stuck; `reset --hard` guarantees the machine matches the branch. The student's *own* work
lives somewhere else entirely (§3.3) and is never touched by this.

`--single-branch` keeps the clone small.

Then a sanity check that catches the most likely operator error:

```powershell
if (-not (Test-Path $startCmd)) {
    Write-Err "Expected the launcher at $startCmd but it is not there."
    Write-Host "  Is '$Branch' the right branch?"
```

#### Stage 4 — Pre-pulling images

**This is the stage the whole installer exists for.** ~2.6 GB of container image. If it is not
downloaded at imaging time, the first student to log in downloads it while their class waits.

The image name is not hardcoded — it is *read out of `devcontainer.json`*:

```powershell
$match = Select-String -Path $devcontainerJson -Pattern '^\s*"image"\s*:\s*"([^"]+)"' | Select-Object -First 1
$rosImage = $match.Matches[0].Groups[1].Value
```

**Defence:** a hardcoded copy would eventually drift from the pin in `devcontainer.json`. When it
drifted, the symptom would be that IT "successfully" pre-pulled image A while every student pulled
image B live in class — the exact disaster this stage prevents. One source of truth, read at runtime.
(`robotlab.ps1` has the identical function, `Get-PinnedImage`, for the same reason.)

The error handling is written for the two failures that actually occur, and it explicitly tells the
operator when *retrying is pointless*:

```
'manifest unknown' means the tag does not exist on the registry.
'denied' or 'unauthorized' means the package is still private -
a maintainer needs to set its visibility to Public on GitHub.
```

#### Stage 6 — Shortcuts

```powershell
$shell = New-Object -ComObject WScript.Shell
$link  = $shell.CreateShortcut($Path)
$link.TargetPath = $Target
$link.Save()
```

There is no native cmdlet to create a `.lnk`, so this drives the **WScript.Shell COM object** — the
same automation interface VBScript has used since the 1990s. It is the standard approach and needs
no extra dependency.

One shortcut goes to `C:\Users\Public\Desktop` (visible to every user of the machine), the other four
into a Start-menu folder under `ProgramData` (likewise machine-wide). Both locations need admin,
which is why this is in the installer and not the launcher.

---

### 3.3 `launcher/robotlab.ps1` — the student-facing launcher

592 lines, run by a student with no admin rights, every time they start work. This is the heart of
the system.

#### The ASCII warning at the top — read this one twice

```
MAINTAINERS: keep this file PURE ASCII. Windows PowerShell 5.1 decodes a file with no byte
order mark using the system ANSI codepage. A UTF-8 em dash then becomes three characters, the
last of which is U+201D, which the parser treats as a real string delimiter. The result is a
bogus "string is missing the terminator" error reported hundreds of lines from the actual character.
```

Concretely: you paste a nice `—` into a comment. PowerShell 5.1 reads the file byte-by-byte in the
legacy codepage and sees three garbage characters, the last of which is a **closing curly quote**.
PowerShell treats that as a string delimiter, so every quote after it is now inverted, and the parser
reports a syntax error hundreds of lines away in a file that looks perfectly fine.

This is enforced by `.gitattributes` for line endings but **not** for encoding, so it relies on
discipline. `.md` files are exempt — nothing parses them as code, which is why this document can use
`—` freely.

#### Self-locating paths

```powershell
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$RepoSrc    = Join-Path $RepoRoot 'src'
$RobotLabHome  = if ($env:ROBOTLAB_HOME) { $env:ROBOTLAB_HOME } else { Join-Path $env:USERPROFILE 'RobotLab' }
$UserWorkspace = Join-Path $RobotLabHome 'ros2_ws'
$UserSrc       = Join-Path $UserWorkspace 'src'
```

`$PSScriptRoot` is the folder containing the running script. Since the launcher lives at
`<repo>\launcher\`, the repo root is one level up. **The script works from `C:\ProgramData\RobotLab\repo`
or from a developer's personal clone with no configuration.**

`Join-Path` rather than string concatenation, because it handles the separators correctly.

Note the `if ($env:X) { $env:X } else { default }` idiom — PowerShell has no `${VAR:-default}`. Every
tunable (`ROBOTLAB_HOME`, `HOST_PORT`) follows this pattern, so a demonstrator can override behaviour
without editing files.

#### The preflight checks

Seven small functions, each returning `$true`/`$false` and printing its own diagnosis. They are
collected as **script blocks** — chunks of un-executed code stored in a variable:

```powershell
$checks = @(
    { Test-RepoLayout },
    { Test-DockerCli },
    ...
)
foreach ($check in $checks) {
    $ok = & $check          # '&' is the call operator - it executes the block
```

**Why this shape?** Because two commands need the same checks with opposite behaviour:

- `start` stops at the **first** failure — no point continuing if Docker is dead.
- `doctor` runs **all** of them and reports everything — a student wants one complete list, not to
  fix-and-rerun seven times.

One `-ContinueOnFailure` switch, one list of checks, no duplication.

Each check earns its place by mapping to a real support ticket:

| Check | The failure it prevents |
|---|---|
| `Test-RepoLayout` | Someone copied the `.cmd` file to the desktop instead of using the shortcut. |
| `Test-DockerCli` | Docker not installed, or the window was opened before it was. |
| `Test-DockerEngine` | Docker Desktop not started **or** the account isn't in `docker-users`. |
| `Test-VsCode` | VS Code installed without "Add to PATH". |
| `Test-DevContainersExtension` | The per-user extension gap — prints the exact fix. |
| `Test-DiskSpace` | Warns below 15 GB before a multi-GB pull fails cryptically. |
| `Test-UsernameIsVolumeSafe` | See below — the cleverest check in the file. |

```powershell
if ($env:USERNAME -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') {
```

**Why:** `devcontainer.json` builds Docker volume names from `${localEnv:USERNAME}` and has no way to
sanitise it. Docker only accepts `[a-zA-Z0-9][a-zA-Z0-9_.-]*` as a volume name. A domain account with
a space or a backslash would fail *at container-create time*, deep inside VS Code, with an error that
gives no hint about the real cause. Catching it here converts a 40-minute debugging session into one
clear sentence naming the actual problem and who can fix it.

This is the general philosophy of the file: **detect the failure at the layer where you can still
explain it.**

#### `Initialize-UserWorkspace` — the per-student copy

```powershell
& robocopy $RepoSrc $UserSrc /E /NFL /NDL /NJH /NJS /NP | Out-Null
$rc = $LASTEXITCODE
if ($rc -ge 8) { Stop-WithError ... }
```

`robocopy` is the Windows bulk-copy tool. The flags suppress per-file/per-directory logging, the
job header/summary and the progress bar — without them a 4,000-file copy floods the console.

**The exit code check is the thing to notice.** Robocopy does not follow the usual convention:

| Code | Meaning |
|---|---|
| 0 | Nothing to copy, already identical |
| 1 | **Files copied successfully** |
| 2–7 | Extra/mismatched files, still success |
| **≥ 8** | Genuine failure |

The classic bug is `if ($LASTEXITCODE -ne 0) { fail }`, which fails on **every run that actually
copied anything**. Hence `-ge 8`.

**Why copy at all instead of pointing everyone at the shared clone?**

1. **Students must be able to write** — they are editing code. The `ProgramData` clone is read-only
   to them, by design.
2. **Shared lab PC.** Alice and Bob log into the same machine on different days. Separate copies mean
   Bob cannot clobber Alice's work.
3. **The IT clone stays pristine**, so `git reset --hard` at update time is always safe.

The cost is disk (one copy per student per machine) and that a student's copy does not automatically
pick up repo updates. That trade is correct for a teaching lab: **a student losing their coursework is
catastrophic; a student running slightly older lab packages is not.**

#### `Open-VsCode` and the URI trick

```powershell
$escaped = $HostPath -replace '\\', '\\'
$json    = '{"hostPath":"' + $escaped + '"}'
$bytes   = [System.Text.Encoding]::UTF8.GetBytes($json)
$hex     = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
return "vscode-remote://dev-container+$hex/home/ros2_ws"
```

This builds a URI that tells VS Code *"open this folder, already inside its dev container"* — hex-
encoding a small JSON object naming the host folder. **This is what removes the `Ctrl+Shift+P` →
"Reopen in Container" step**, which was step 3 of the old five-step process.

(The `-replace '\\', '\\'` turns each single backslash into two, because a Windows path has to be
escaped to be legal JSON.)

**The critical part is that this is an unsupported internal contract**, and the code says so:

```powershell
# This is an internal contract of the extension, not a documented stable API, and its exact
# shape has changed between extension versions. Every caller must handle it not working -
```

So `Open-VsCode` never trusts it:

1. Try the direct URI.
2. If `code` returns non-zero → open the plain folder and print the two manual steps.
3. If `code` returns zero, **that still proves nothing** — `code` returns immediately. So poll for up
   to 180 seconds waiting for the container to appear.
4. If it never appears → open the plain folder and print the manual steps.

**Defend it like this:** we took a convenience shortcut on an undocumented API, and we wrapped it in
a fallback that degrades to exactly the documented workflow. Worst case, the student is where they
would have been anyway, with on-screen instructions. Best case — the normal case — they skip a step
that generated support questions.

The 180-second timeout is not arbitrary: container creation plus `postCreateCommand` can legitimately
take a couple of minutes the very first time a named volume is seeded from the image.

#### `Get-DevContainerId` — the probe, and the bug it taught us

Its job: *"is the dev container already running, and is it ours?"*

Two deliberate refusals, both documented in the code:

1. **Not `--filter label=key=value`.** That is an exact string match, and the extension has not always
   written the path in the same shape (drive-letter case, trailing separator, forward vs back
   slashes). A near-miss would make a perfectly good attach look like a failure and pop a **second**
   VS Code window at the student. So we fetch the label and compare paths ourselves, after
   normalising case and separators.
2. **Not a `{{.Label "..."}}` format template** — that is the PowerShell quote-stripping bug from
   §1.7. We read JSON via `docker inspect` instead.

Plus the hardening from §1.5: function-scoped `$ErrorActionPreference`, and a `try/catch` that
returns `$null`. And a fallback — if the label is ever renamed by a future extension version, any
running container built from our pinned image is almost certainly ours.

> **This function is the best single answer to "what did you learn?"** It documents three separate
> failure modes discovered in practice, and defends against each one explicitly rather than silently.

#### The command dispatcher

```powershell
switch ($Command) {
    'start'  { Invoke-Start }
    'stop'   { Invoke-Stop }
    'status' { Invoke-Status }
    'reset'  { Invoke-Reset }
    'doctor' { Invoke-Doctor }
}
```

Combined with `[ValidateSet('start','stop','status','reset','doctor')]` on the parameter, PowerShell
rejects an invalid command *before the script body runs*, with a helpful message listing the valid
options. One file, five entry points, and the four `.cmd` shortcuts are just different arguments to it.

`Invoke-Reset` deserves a note:

```powershell
$answer = Read-Host "Type RESET to continue, or anything else to cancel"
if ($answer -cne 'RESET') { ... }
```

`-cne` is **case-sensitive** not-equals. Typing `reset` is not enough. For a destructive action on a
student's environment, requiring deliberate capitals is cheap insurance — and the prompt states
plainly that source code is not touched.

---

### 3.4 `src/.devcontainer/devcontainer.json` — the contract between VS Code and Docker

This file is what the Dev Containers extension reads to build the environment.

```jsonc
"image": "ghcr.io/cobot-maker-space/uon-windows-testing:lab-2026-08",
```

**Three decisions in one line:**

1. **A dated tag, not `:latest`.** A later image push cannot change what a running lab class is
   using. This is not theoretical — the file's own comment records that the production package once
   had a single tag `2026-08-07` while `devcontainer.json` pinned `:latest`, *a tag that never
   existed*, so every student got `manifest unknown`.
2. **A separate testing package** (`uon-windows-testing`), so this branch cannot affect anyone
   pulling production.
3. **`image:` not `build:`** — students pull a prebuilt image rather than building a Dockerfile
   locally. 60 students building the same image is 60× the work and 60 chances to fail.

```jsonc
"workspaceFolder": "/home/ros2_ws",
"workspaceMount": "source=${localWorkspaceFolder},target=/home/ros2_ws/src,type=bind",
```

The student's Windows folder is bind-mounted to `/home/ros2_ws/src`. **Note the asymmetry:** VS Code
*shows* `/home/ros2_ws` (the whole colcon workspace) but only `src/` is their real Windows folder.
`build/`, `install/` and `log/` are volumes. This is what lets a student see a normal ROS workspace
while their files live safely on the host.

```jsonc
"mounts": [
    "source=robotlab-build-${localEnv:USERNAME},target=/home/ros2_ws/build,type=volume",
    ...
]
```

**This is the most important design decision in the entire project.** Two reasons, both in the file's
comments:

1. **Speed.** Docker seeds a **newly created** named volume from whatever the image already has at
   that path. The image ships an already-compiled workspace, so a student's first container start
   *inherits the finished build for free* instead of running colcon for 20 minutes.
2. **Shared lab PCs.** `${localEnv:USERNAME}` gives every Windows account its own volumes, so two
   students on one machine cannot corrupt each other's build tree.

And the caveat, which explains why `Robot Lab - Reset` has to exist:

> A volume is seeded **only** when it is first created. Pointing this file at a newer image will not
> refresh a volume that already exists.

So after IT publishes a new image, an existing student volume keeps the *old* build. `Reset` deletes
the volumes so the next start re-seeds them. **If you are asked "why does Reset exist?", that is the
answer** — it is not a generic "turn it off and on again" button, it is the specific remedy for
Docker's volume-seeding semantics.

```jsonc
"runArgs": [ "--network=ros", "--group-add=video" ],
```

With a warning that is worth quoting in a review:

> `--device=/dev/video0` must **NOT** be added here. Docker Desktop's Linux VM has no such device, so
> the flag makes container creation fail outright on **every** Windows machine.

That is why the user-facing README lists "webcam not accessible" as *expected* rather than a bug:
USB passthrough into Docker Desktop's VM needs `usbipd-win` and admin rights, which students do not
have.

```jsonc
"postCreateCommand": "bash /usr/local/bin/setup.sh"
```

Note the path: `/usr/local/bin/setup.sh`, the copy **baked into the image**, *not*
`src/.devcontainer/setup.sh` from the checkout. **Editing `setup.sh` in git does nothing until the
image is rebuilt and pushed.** This trips up every new maintainer, which is why the warning appears
in three separate files.

> **One honest weakness to acknowledge:** `"privileged": true` grants the container far more
> capability than a ROS simulation needs. It was inherited from the pre-existing configuration
> (typically added for device access). Given `--device` was deliberately removed, this is worth
> re-testing without — it is the kind of thing a security-minded reviewer will spot, and "we haven't
> revisited it yet" is a much better answer than not having noticed.

---

### 3.5 `src/.devcontainer/Dockerfile` — where the 20 minutes went

```dockerfile
# IMPORTANT: the build context is the REPOSITORY ROOT, not this directory
FROM ros:humble
ARG WORKSPACE_DIR=/home/ros2_ws
```

**The build context is the repo root** because the image bakes in a compiled copy of `src/`. A
Dockerfile can only `COPY` from inside its context, so the context must contain `src/`. That is also
why `.dockerignore` exists at the root — without it, the entire `.git` directory would be uploaded to
the builder on every build.

The apt layer bakes in Gazebo, with the reasoning recorded:

> `ros-humble-gazebo-ros-pkgs` and `ros-humble-gazebo-plugins` used to be apt-installed by `setup.sh`
> on every container create, which made **a working network a hard requirement for container start**
> and added minutes to it.

A lab with flaky wifi could previously fail to *start containers*. Now the network is only needed to
pull the image once.

There is also a candid note that `ubuntu-mate-desktop` (~1.5 GB) is probably unnecessary — the
desktop the student sees belongs to the *novnc* container — but that removing it mid-term risks
subtle font/theme breakage. **That is exactly the right way to record a known-suboptimal decision:
name it, size it, explain the timing.**

```dockerfile
RUN dos2unix /usr/local/bin/setup.sh /usr/local/bin/robotlab-rebuild && chmod +x ...
```

Defence in depth. `.gitattributes` should already force LF on these files, but if a contributor ever
commits CRLF from a Windows checkout, the shebang becomes `#!/usr/bin/env bash\r` and **every
container breaks** with `bad interpreter: /bin/bash^M`. `dos2unix` costs nothing and removes the
possibility.

#### The prebuild — the payoff

```dockerfile
COPY --chown=$USER_UID:$USER_GID src/ ${WORKSPACE_DIR}/src/
RUN /bin/bash -c "source /opt/ros/humble/setup.bash \
    && cd ${WORKSPACE_DIR} \
    && colcon build --symlink-install \
    && rm -rf ${WORKSPACE_DIR}/log/*"
```

The workspace is compiled **at image build time, once, on a GitHub runner** — instead of 60 times, on
60 lab PCs, in front of a class.

Three subtleties, all of which matter:

- **`WORKSPACE_DIR` must match `devcontainer.json`.** The path is baked into the compiled CMake
  caches. Change one without the other and the prebuilt tree becomes useless.
- **`--symlink-install` must match `robotlab-rebuild` and `setup.sh`.** colcon *refuses* to build into
  an install tree created with a different layout. Mixing symlink and non-symlink invocations against
  the same workspace is an error.
- **`--symlink-install` is also a feature for students**: the symlinks point into `src/`, which is
  exactly where the student's copy is bind-mounted — so **edits to Python nodes and launch files take
  effect with no rebuild at all**.
- **`build/` is shipped as well as `install/`.** That costs image size, but means a student's first
  `robotlab-rebuild` is *incremental* rather than a full 20-minute compile.

---

### 3.6 `src/.devcontainer/setup.sh` — the script that deliberately does almost nothing

Runs once per container creation. Its entire job now is to **verify and get out of the way**:

```bash
if [ -f "${WORKSPACE_DIR}/install/setup.bash" ]; then
  echo "Prebuilt workspace found - skipping colcon build."
  exit 0
fi
```

The header documents three behaviours that were *removed*, and each is a war story worth telling:

1. It ran `rm -rf build/* install/* log/*` and a **full `colcon build` on every container create**.
   That is the 10–25 minute wait students used to sit through — and note it *deleted the cache first*,
   so the cache never once served its purpose.
2. It **`git clone`d vanilla upstream ROBOTIS TurtleBot3** into any missing `src/` subfolder. Our
   packages are customised — our own URDFs and worlds. So a folder going astray meant **silently
   replacing the teaching materials with stock upstream code**. That is a data-loss bug wearing a
   convenience-feature costume.
3. It `apt-get install`ed Gazebo at runtime (see §3.5).

The replacement for behaviour 2 is the important part:

```bash
if [ -z "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
  echo "ERROR: ${SRC_DIR} is empty."
  echo "  Refusing to continue - an earlier version of this script would have cloned stock"
  echo "  upstream packages over the top at this point, which is exactly what we must not do."
  exit 1
fi
```

**It fails loudly instead of silently guessing.** If you are asked to name one principle the rewrite
follows, this is it: *`src/` is the single source of truth, and nothing in this repository may ever
write to it.*

`set -euo pipefail` is standard bash hardening — exit on error, on undefined variable, and on any
failure within a pipeline.

---

### 3.7 `src/.devcontainer/robotlab-rebuild` — the student's build command

```bash
robotlab-rebuild                    # incremental build of everything
robotlab-rebuild turtlebot3_gazebo  # just one package, much faster
robotlab-rebuild --clean            # wipe and start over (10-25 min)
```

Since `setup.sh` no longer builds on startup, students need an explicit, memorable way to rebuild.
`colcon build --symlink-install` typed by hand is easy to get wrong — and getting the flag wrong is
not a harmless mistake, it corrupts the install tree layout.

Two details worth pointing at:

```bash
rm -rf "${WORKSPACE_DIR}/build/"* "${WORKSPACE_DIR}/install/"* "${WORKSPACE_DIR}/log/"*
```

**Contents, not the directories.** Those directories are named-volume mount points; deleting them
would break the mounts.

```bash
-h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' ; exit 0 ;;
```

`--help` prints the script's own header comment by reading its own source. The help text cannot
drift from the documentation because it *is* the documentation.

---

### 3.8 `src/.devcontainer/start_vnc.ps1` and `start_vnc.sh` — the desktop service

Two implementations of the same idempotent logic: **PowerShell for Windows, bash for Linux/WSL2.**
Both support `start`, `stop`, `status` (`.ps1` adds `restart`) and both read the same environment
variables (`HOST_PORT`, `NOVNC_IMAGE`, `DISPLAY_WIDTH`...).

`robotlab.ps1` does not reimplement any of this:

```powershell
# Delegate rather than reimplement: start_vnc.ps1 is already idempotent and hardened, and the
# WSL2 and manual flows still depend on it behaving exactly this way.
& powershell -NoProfile -ExecutionPolicy Bypass -File $StartVnc start
```

**Defend the duplication like this:** yes, having `.ps1` and `.sh` versions is duplication — but the
alternative is requiring WSL/bash on a locked-down Windows lab PC just to start a container. The two
files are small, stable, and have identical interfaces. What we refused to duplicate is the *third*
copy that would have appeared inside `robotlab.ps1`.

The start logic escalates carefully rather than assuming:

1. Network exists? Create it if not.
2. Container already running? Say so and stop.
3. Container exists but stopped? `docker start` it — **reuse rather than recreate**.
4. That failed? `docker rm -f` and recreate.
5. Port busy? **Warn** (not fail) and name the fix: `$env:HOST_PORT = '9000'`.
6. Image missing? Pull it **explicitly** — because `docker run -d` would pull silently and the script
   would appear frozen for several minutes on a fresh PC.
7. Run it, then poll up to 15 seconds for it to actually appear.

Step 6 is a small thing that matters a lot: **a progress bar is the difference between "downloading"
and "broken" to a user.**

`Assert-Docker` is also worth noting — when the engine is unreachable it prints the two likely causes
*in order of likelihood* and then dumps the last 5 lines of the raw `docker info` error, so a
demonstrator has something concrete to act on.

---

### 3.9 `.github/workflows/build-image.yml` — publishing the image

Builds and pushes the image to GHCR. Manual trigger (`workflow_dispatch`) or a `lab-*` git tag.

The header states why it exists:

> Before this workflow existed the image was built by hand on someone's laptop and pushed, which is
> how the production package ended up with a single tag while `devcontainer.json` pinned `:latest` —
> a tag that never existed, so every student got `manifest unknown`.

**The guard step is the best part of this file:**

```yaml
- name: Verify devcontainer.json pins the tag being built
  run: |
    PINNED=$(grep -oP '^\s*"image"\s*:\s*"\K[^"]+' src/.devcontainer/devcontainer.json)
    EXPECTED="${{ steps.meta.outputs.image }}:${{ steps.meta.outputs.tag }}"
    if [ "${PINNED}" != "${EXPECTED}" ]; then exit 1; fi
```

**The workflow refuses to publish an image that `devcontainer.json` does not point at.** The exact
class of failure that motivated the workflow is now structurally impossible.

The smoke tests check the four things that actually break in front of a class:

```yaml
docker run --rm "$IMAGE" test -f /home/ros2_ws/install/setup.bash   # prebuilt workspace present?
... ros2 pkg list | grep -c turtlebot3                              # OUR packages resolve?
... ros2 pkg prefix gazebo_ros                                      # gazebo baked in, not apt'd?
... command -v robotlab-rebuild                                     # helper on PATH?
```

Test 1 is the one that protects the headline feature: if the prebuild silently failed, the image would
still be *valid* and students would face a full colcon build. Only an explicit assertion catches that.

Other decisions:

- **Free up disk space** — the image is a compiled workspace on a ~2.3 GB base, so the runner needs
  ~20 GB of preinstalled toolchains removed first.
- **`platforms: linux/amd64` only**, with a comment explaining that adding arm64 needs the ROS apt
  packages *and* the workspace build to work there, and roughly doubles build time. A reader knows
  both the decision and its cost.
- **GHCR rejects uppercase**, so the owner name `Cobot-Maker-Space` is lowercased at runtime.
- **The final step prints a reminder** that new GHCR packages are private by default, with a copy-
  pasteable anonymous-pull check. This turns institutional knowledge into something the tool tells you.

---

### 3.10 `.dockerignore`

Because the build context is the repo root, without this file **every build uploads the entire `.git`
history and the Windows launcher** to the Docker builder. It excludes `.git/`, `.github/`,
`launcher/`, `*.md`, host-side `build/install/log`, and:

```
# Untracked locally but may still exist on a maintainer's disk from before it was removed from
# git. 221 MB of stale colcon output that must not end up in the image.
cache/
```

That is defensive against a *maintainer's local disk state*, not against the repo. Good instinct —
`.dockerignore` protects the build from the machine it runs on.

---

### 3.11 `.gitignore` — the 221 MB story

```
# These used to be committed (3,995 files, 221 MB, deepest path 271 chars), which is what
# forced every Windows user to set `git config core.longpaths true` before cloning. They were
# also deleted on every container create by the old setup.sh, so they never once served as a
# cache.
cache/
```

Read that twice, because it is two bugs stacked on each other:

1. Committed build output made the repo huge and **exceeded Windows' 260-character path limit**, so
   cloning failed on a stock Windows machine until you ran an obscure git config command.
2. And it was **pointless anyway**, because `setup.sh` deleted it on every container create.

Removing it fixed a user-facing failure *and* deleted 221 MB *and* removed a documentation step. The
old README's `core.longpaths` troubleshooting row is gone because the cause is gone — which is the
right way to fix a documented workaround.

---

### 3.12 `.gitattributes` — line endings, which are not a cosmetic issue

```gitattributes
*.sh text eol=lf          # A CRLF shebang produces "bad interpreter: /bin/bash^M"
*.ps1 text eol=crlf       # CRLF is what cmd.exe and PowerShell expect
```

Git stores LF internally and converts on checkout. Files that run **inside the Linux container**
(`*.sh`, `Dockerfile`, `robotlab-rebuild`) get LF; files that run on the **Windows host** (`*.ps1`,
`*.cmd`, `*.bat`) get CRLF.

Without this, a Windows contributor's editor saves `setup.sh` with CRLF, the shebang becomes
`#!/usr/bin/env bash\r`, and **every container on every machine fails to start** with an error message
that names a file that looks fine. `dos2unix` in the Dockerfile is the second line of defence.

---

### 3.13 `src/.devcontainer/COLCON_IGNORE`

An empty file. Its *presence* tells colcon "there is nothing to build in this directory". Without it
colcon would scan `.devcontainer/` looking for packages. Zero bytes, one job.

---

## Part 4 — Five questions you will be asked, and the answers

**Q: Why prebuild the workspace into the image instead of building on the student's machine?**
Because building took 10–25 minutes, happened on *every* container create, and happened during class.
Building once on a GitHub runner replaces 60 builds with 1. The cost is a larger image (pre-pulled at
imaging time, when nobody is waiting) and the discipline that `setup.sh` changes need an image rebuild.

**Q: Why Docker named volumes for `build/install/log` instead of just using the host filesystem?**
Two reasons that both had to be true. **Seeding**: Docker populates a newly created named volume from
the image's content at that path — which is the mechanism that delivers the prebuilt workspace for
free. A bind mount would shadow it with an empty host folder and destroy the benefit entirely.
**Isolation**: `${localEnv:USERNAME}` in the volume name gives each Windows account its own build tree
on a shared PC. The known cost is that volumes are only seeded once, which is precisely why
`Robot Lab - Reset` exists.

**Q: Why copy the workspace into each student's profile instead of sharing one folder?**
Students need write access; the IT clone is read-only to them by design. Separate copies mean one
student cannot destroy another's work, and the IT clone stays pristine so `git reset --hard` at update
time is always safe. The trade — a student's copy does not auto-update — is the right way round: losing
coursework is catastrophic, running slightly older lab packages is not.

**Q: Why is the image tag pinned to a date instead of `:latest`?**
So a mid-term image push cannot change what a running class is using. This is not hypothetical: the
project has *already* been burned by a `devcontainer.json` pinning `:latest` when no such tag existed,
giving every student `manifest unknown`. The CI workflow now refuses to publish a tag that
`devcontainer.json` does not pin, making that failure structurally impossible.

**Q: Why so much error-handling code for something that "just starts a container"?**
Because the users are non-admin students on locked-down machines, in a timed session, and the
alternative to a clear message is a support queue. Nearly every check in `robotlab.ps1` maps to a
real observed failure: the per-user extension gap, the `docker-users` group, Docker Desktop not
started, a username that is not a legal Docker volume name. The design rule is **detect each failure
at the layer where you can still explain it** — a username check that costs one regex saves an hour
of debugging a cryptic container-create error inside VS Code.

---

## Part 5 — What happens, step by step

### First launch, on a machine IT has prepared

1. Student double-clicks **Robot Lab** → `Start Robot Lab.cmd` → `powershell ... robotlab.ps1 start`
2. `Invoke-Start` runs the seven preflight checks, stopping at the first failure
3. `Initialize-UserWorkspace` sees no `%USERPROFILE%\RobotLab\ros2_ws\src` → robocopy from the
   ProgramData clone (a few seconds)
4. `Start-NoVnc` delegates to `start_vnc.ps1` → creates the `ros` network if needed, starts the
   `novnc` container
5. `Confirm-RosImage` reads the pin from `devcontainer.json`, confirms the image is cached (IT
   pre-pulled it)
6. `Start-Process $VncUrl` → the browser tab opens
7. `Open-VsCode` builds the `vscode-remote://dev-container+<hex>/home/ros2_ws` URI and launches VS Code
8. The Dev Containers extension creates the container: bind-mounts the student's `src/`, creates the
   three `robotlab-*-<username>` volumes — **Docker seeds them from the image's compiled workspace**
9. `postCreateCommand` runs the baked `setup.sh`, which finds `install/setup.bash` already there and
   exits immediately
10. `Open-VsCode` polls until it sees the container → "VS Code is attached to the dev container"

### Second launch

Steps 3, 5 and 8 are all no-ops — the workspace exists, the image is cached, the volumes exist and
keep their build. Well under a minute.

### After IT publishes a new image

`devcontainer.json` gets a new pin, IT re-runs `Install-RobotLab.ps1` (which `reset --hard`s the
clone and pre-pulls the new image). But **existing student volumes still hold the old build** — they
are only seeded at creation. The student runs **Robot Lab - Reset**, which deletes their volumes so
the next start re-seeds them from the new image. Their source code in `src/` is untouched.

---

## Part 6 — Known weaknesses (say these before someone else does)

Being able to name your own system's limits is what separates "I wrote this" from "I understand this".

| Weakness | Status |
|---|---|
| `"privileged": true` in `devcontainer.json` | Inherited; broader than a ROS simulation needs. Worth re-testing without, especially since `--device` was deliberately removed. |
| `ubuntu-mate-desktop` adds ~1.5 GB | Documented in the Dockerfile as a removal candidate. The visible desktop belongs to the novnc container, so it is probably dead weight — but changing it mid-term risks font/theme breakage. |
| The `vscode-remote://` URI is an undocumented internal contract | Accepted risk, fully mitigated: every failure path falls back to the documented "Reopen in Container" flow with on-screen instructions. |
| A student's workspace copy never auto-updates | Deliberate — it protects their work. But a lab package change mid-term needs a communicated manual step. |
| Backtick line continuations remain in `Install-RobotLab.ps1` | Contradicts that file's own stated rule. Cosmetic, but a fair review catch. |
| `-StudentGroup` accepts an unverified string | Passing the literal placeholder `"DOMAIN\Students"` produces a `[FAIL]` and the install continues — correct behaviour, but the group name is never validated against the machine. |
| Webcam passthrough does not work | Genuine limitation of Docker Desktop's VM, not a bug. Needs `usbipd-win` and admin rights. Documented as expected. |

---

## Glossary

| Term | Meaning |
|---|---|
| **Bind mount** | A host folder mapped into a container. Changes flow both ways. Used for the student's `src/`. |
| **Named volume** | Docker-managed storage. Seeded from the image on first creation. Used for `build/install/log`. |
| **Cmdlet** | A PowerShell built-in command (`Verb-Noun`), returning objects, throwing on error. |
| **Native command** | An actual `.exe` (`docker`, `git`), returning text, setting `$LASTEXITCODE`. |
| **Splatting** | `@array` / `@hashtable` — expanding a data structure into command arguments. |
| **Execution Policy** | Windows' script-blocking guard rail. Not a security boundary. Bypassed per-process. |
| **`docker-users`** | Local Windows group whose members may talk to Docker. Non-admins need it. |
| **GHCR** | GitHub Container Registry (`ghcr.io`) — where the image is published. |
| **colcon** | The ROS 2 build tool. `--symlink-install` links rather than copies, so Python edits need no rebuild. |
| **noVNC** | VNC client that runs in a browser — how the Linux desktop reaches the student without any install. |
| **`postCreateCommand`** | Dev Containers hook, run once per *container creation* (not per start). |
