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
3. Install **Visual Studio Code** with the **Dev Containers** extension. VS Code and its
   extensions can also be installed per-user without admin if you'd rather have students (or a
   login script) do this step.
4. (Recommended) Set long-path support once at the machine level so clones never fail on deep
   paths:
   ```powershell
   git config --system core.longpaths true
   ```
5. (Recommended) If Group Policy locks PowerShell's script execution policy, either sign
   `start_vnc.ps1` for your environment or confirm `-ExecutionPolicy Bypass` (used below) is
   permitted for standard users under your GPO. Bypass only affects the one process running the
   script — it does not change any system-wide setting and does not require admin rights — but a
   sufficiently strict GPO can still block it, so verify this once on a representative lab image.

Once these steps are done, everything below runs as a standard, non-admin student.

---

## 🔧 Student instructions

### 1. Clone the repository

```powershell
git clone https://github.com/Cobot-Maker-Space/UON-CS-robotlab-simulation-container.git
cd UON-CS-robotlab-simulation-container
```

No specific folder matters here the way it does for WSL2 — there's no cross-filesystem
performance penalty on native Windows, so the default location (e.g. `Documents\`) is fine.

### 2. Start the noVNC service

```powershell
cd .\src\.devcontainer\
powershell -ExecutionPolicy Bypass -File .\start_vnc.ps1 start
```

This will:
- Create a `ros` Docker network if it doesn't exist
- Launch a `theasp/novnc:latest` container mapped to `http://localhost:8080`

Other commands work the same way: `... start_vnc.ps1 stop`, `status`, `restart`.

Once running, open:

➡ **http://localhost:8080/vnc.html** and click **Connect** to access the container's desktop GUI.

### 3. Open in VS Code

```powershell
code .
```

Press `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**. VS Code builds and launches the
ROS 2 container and attaches it to the `ros` network so it can reach the noVNC container —
identical to the Linux/WSL2 flow from here on, since the container itself never knows or cares
what host OS it's running under.

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
| Webcam (`/dev/video0`) not accessible | There's no Windows equivalent of this Linux device path through Docker Desktop. If lab PCs don't have/need a camera, remove `--device=/dev/video0` and `--group-add=video` from `devcontainer.json`'s `runArgs`. |
| `Unable to create file [..]: Filename too long` on clone | Needs `git config --system core.longpaths true`, which requires admin — set this once during imaging (see one-time setup above), since students can't run it themselves. |
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
