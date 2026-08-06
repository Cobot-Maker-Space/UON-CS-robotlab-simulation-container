# 🐢 TurtleBot Desktop Development Container — Windows Lab Deployment (no WSL, no admin)

This doc is for **lab PCs** where students log in with a **non-admin account**. It uses the
native Windows `start_vnc.ps1` script instead of `start_vnc.sh`, so nobody needs to open a WSL
Ubuntu shell or touch anything that requires elevation at run time.

If you're setting this up on your own machine and are happy using WSL2, use
[README.md](README.md) instead — that flow still works and is unaffected by this one.

---

## How the two Windows paths differ

| | [README.md](README.md) (WSL2) | This doc (native PowerShell) |
|---|---|---|
| Where you run commands | Ubuntu shell inside WSL2 | Plain Windows PowerShell |
| Script used | `start_vnc.sh` | `start_vnc.ps1` |
| Requires a WSL Linux distro visible to the user | Yes | No |
| Good fit for | Your own dev machine | Shared/lab PCs, non-admin student accounts |

Either way, Docker Desktop is doing the same thing under the hood (it always runs containers
inside its own hidden Linux VM). The difference is only which shell the *student* types into.

---

## 📦 One-time setup (done by IT/lab staff, requires admin — not by students)

This is the part that needs elevation. Do it once when imaging/deploying the lab machines:

1. Install **Docker Desktop for Windows** with the WSL2 backend enabled. This silently pulls in
   the WSL2 platform components; students never need to see or open a WSL distro.
2. Add the student login group (e.g. a domain "Students" group, or "Authenticated Users") to the
   local **`docker-users`** group, so non-admin accounts can talk to the Docker engine:
   ```powershell
   Add-LocalGroupMember -Group "docker-users" -Member "DOMAIN\Students"
   ```
3. Install **Visual Studio Code** with the **Dev Containers** extension, and **Git for Windows**.
   VS Code and its extensions can also be installed per-user without admin if you'd rather have
   students (or a login script) do this step.
4. (Optional) Set long-path support machine-wide so students don't have to:
   ```powershell
   git config --system core.longpaths true
   ```
   This is **optional** — the student instructions below use `git config --global`, which achieves
   the same thing per-user and needs **no admin rights**. Setting it at the system level just saves
   students one command.
5. (Recommended) If Group Policy locks PowerShell's script execution policy, either sign
   `start_vnc.ps1` for your environment or confirm `-ExecutionPolicy Bypass` (used below) is
   permitted for standard users under your GPO. Bypass only affects the one process running the
   script — it does not change any system-wide setting and does not require admin rights — but a
   sufficiently strict GPO can still block it, so verify this once on a representative lab image.

Once these steps are done, everything below runs as a standard, non-admin student.

---

## 🔧 Student instructions

### 1. Configure Git, then clone the repository

This repo contains a pre-built `cache/` tree whose deepest path is ~271 characters, which exceeds
the classic Windows 260-character `MAX_PATH` limit. **Run this once before cloning** — it is a
per-user setting and needs **no admin rights**:

```powershell
git config --global core.longpaths true
```

Then clone:

```powershell
git clone https://github.com/Cobot-Maker-Space/UON-CS-robotlab-simulation-container.git
cd UON-CS-robotlab-simulation-container
```

No specific folder matters here the way it does for WSL2 — there's no cross-filesystem
performance penalty on native Windows, so the default location (e.g. `Documents\`) is fine.
Keep the path reasonably short, though, since it is added on top of that 271 characters.

Line endings need no configuration: the repo's `.gitattributes` already forces LF on `*.sh` and
`Dockerfile`, so the scripts that run inside the Linux container stay valid regardless of your
local `core.autocrlf` setting.

### 2. Start the noVNC service

```powershell
cd .\src\.devcontainer\
powershell -ExecutionPolicy Bypass -File .\start_vnc.ps1 start
```

This will:
- Create a `ros` Docker network if it doesn't exist
- Pull `theasp/novnc:latest` if it isn't cached yet (**first run only — a few hundred MB, so give
  it a few minutes**; the script prints a message while it downloads)
- Launch the noVNC container mapped to `http://localhost:8080`

Other commands work the same way: `... start_vnc.ps1 stop`, `status`, `restart`.

Once running, open:

➡ **http://localhost:8080/vnc.html** and click **Connect** to access the container's desktop GUI.

### 3. Open the `src` folder in VS Code

> ⚠️ **This must be the `src` folder — not the repo root, and not `.devcontainer`.**
> `devcontainer.json` lives at `src/.devcontainer/`, and VS Code only discovers it when `src` is the
> folder you opened. It also resolves the build/install/log cache mounts relative to that folder.
> Open the repo root and **Reopen in Container** won't be offered at all; open `.devcontainer` and
> the container comes up with the wrong folders mounted.

From `src\.devcontainer\` (where step 2 left you):

```powershell
code ..
```

Or from anywhere: `code <path-to-repo>\src`

Press `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**. VS Code builds and launches the
ROS 2 container and attaches it to the `ros` network so it can reach the noVNC container —
identical to the Linux/WSL2 flow from here on, since the container itself never knows or cares
what host OS it's running under.

The first build compiles the whole ROS 2 workspace via `postCreateCommand` (`colcon build
--symlink-install`) and takes a long time. Let it finish.

### 4. Test the setup

Inside the VS Code terminal:

```bash
source /opt/ros/humble/setup.bash
ros2 topic list
```

---

## 🛠 Troubleshooting

| Issue | Solution |
|---|---|
| `start_vnc.ps1 cannot be loaded because running scripts is disabled on this system` | Run it via `powershell -ExecutionPolicy Bypass -File .\start_vnc.ps1 start` (see student instructions above) rather than double-clicking or dot-sourcing it directly. No admin rights needed. |
| `docker: command not found` / `docker` not recognized | Docker Desktop isn't installed or isn't on PATH — this is an IT/imaging step, not something a student can fix. |
| `error during connect... this error may indicate that the docker daemon is not running` | Docker Desktop is installed but not started. Launch it from the Start menu and wait for the whale icon to settle before retrying. |
| Permission/pipe error running `docker ps` | The student account isn't in the local `docker-users` group — an IT-side fix (see one-time setup above). |
| Cannot connect to noVNC | Run `powershell -ExecutionPolicy Bypass -File .\start_vnc.ps1 status` to check if the container is running. |
| Gazebo spawn service failed | Don't Ctrl+C — let it fail completely, then close and restart. |
| **Reopen in Container** isn't offered in the command palette | You opened the wrong folder. VS Code must have **`src`** open, because `devcontainer.json` lives at `src/.devcontainer/`. See step 3. |
| `error gathering device information while adding custom device "/dev/video0": no such file or directory` | Something re-added `--device=/dev/video0` to `devcontainer.json`'s `runArgs`. Docker Desktop's Linux VM has no `/dev/video0`, so the container can never start with that flag. It is removed by default on this branch — leave it out. |
| Webcam not accessible inside the container | Expected on Windows. Passing a real USB camera through requires [usbipd-win](https://github.com/dorssel/usbipd-win) to attach the device into Docker Desktop's VM first, which needs admin. Lab PCs are set up without camera passthrough. |
| `The string is missing the terminator: "` when running `start_vnc.ps1` | The file lost its UTF-8 BOM and picked up a non-ASCII character (typically an em dash pasted from a doc). Windows PowerShell 5.1 then decodes it as ANSI, producing a `”` that it treats as a real string delimiter — so the reported line number is meaningless. Re-checkout the file with `git checkout -- start_vnc.ps1`. If you must edit it, keep it pure ASCII and save as **UTF-8 with BOM**. |
| `Unable to create file [..]: Filename too long` on clone | Run `git config --global core.longpaths true` and clone again (step 1). This is a per-user setting and needs **no admin rights**. |
| Host port 8080 already in use | Another process (or a leftover container) is bound to it. Run `... start_vnc.ps1 status`, or set `$env:HOST_PORT = "9000"` before calling `start_vnc.ps1 start` to use a different port. |

---

## 💡 Notes

- Default user inside container: `team`
- Workspace is mounted to `/home/ros2_ws/src`
- Network: `ros` (shared between devcontainer and noVNC container)
- GUI apps (RViz2, Gazebo) accessible via browser at `http://localhost:8080/vnc.html`
- `setup.sh` and the `Dockerfile` run entirely *inside* the Linux container, so they're
  identical regardless of host OS — nothing there needed to change for this flow. Only the
  host-side network/noVNC bootstrap (`start_vnc.sh` → `start_vnc.ps1`) needed a Windows-native
  version.
