# 🐢 Robot Lab — Windows lab PC deployment

For **shared lab PCs** where students log in with a **non-admin account**.

IT prepares the machine once. After that a student double-clicks one shortcut and gets the full
TurtleBot3 environment: Gazebo and RViz in a browser tab, VS Code already attached to the ROS 2
container, and their own private workspace.

No git, no PowerShell, no `Ctrl+Shift+P`, and no waiting for a build.

> Setting up your **own** machine rather than a lab PC? Use [README.md](README.md) (WSL2) or the
> root [README.md](../../README.md) (Linux/macOS). Both still work and are unaffected by this.

---

## 📦 One-time setup — IT / lab staff, needs admin

Open **PowerShell as administrator** on the machine image and run:

```powershell
git clone --branch clickable-lab-machines-testing https://github.com/Cobot-Maker-Space/UON-CS-robotlab-simulation-container.git C:\Temp\robotlab
powershell -ExecutionPolicy Bypass -File C:\Temp\robotlab\launcher\Install-RobotLab.ps1 -StudentGroup "DOMAIN\Students"
```

That script is idempotent — re-run it any time to update a machine. It:

1. Verifies **Docker Desktop**, **VS Code** and **Git** are installed
   (add `-InstallMissing` to attempt them via `winget`)
2. Adds your student group to the local **`docker-users`** group, so non-admins can use Docker
3. Clones the repo to `C:\ProgramData\RobotLab\repo`
4. **Pre-pulls both container images (~2.6 GB)** — the step that must never happen for the first
   time in front of a class
5. Creates the `ros` Docker network
6. Puts a **Robot Lab** shortcut on the all-users desktop and in the Start menu

### One thing the installer cannot do for you

- **Docker Desktop must be running** before a student launches. Set it to start on login.

The VS Code Dev Containers extension installs per user, but you do not need a login script or GPO
for it: the launcher checks for it on every run and silently installs it for the current account
the first time it is missing, before opening VS Code. No admin rights are needed for that install.
If it ever fails (e.g. no network on first run), the launcher falls back to printing the exact
command so a student is never left guessing:
```powershell
code --install-extension ms-vscode-remote.remote-containers
```

### Verify before a class

Log in as a **real student account** — not an admin one — and run **Robot Lab - Check** from the
Start menu. It runs every preflight check and reports what is wrong. Then double-click **Robot Lab**
once and confirm it comes all the way up.

---

## 🔧 Student instructions

Double-click **Robot Lab** on the desktop.

The first launch takes about a minute while your personal copy of the workspace is created. After
that it is a few seconds. Two things open:

| Where | What you do there |
|---|---|
| **Browser tab** (`http://localhost:8080/vnc.html`) | Gazebo and RViz appear here. Click **Connect** if the page looks blank. |
| **VS Code** | Edit code. Its terminal is *inside* the container, so `ros2` commands work there. |

Your files live in `%USERPROFILE%\RobotLab\ros2_ws\src` and are private to your account.

Try it:

```bash
ros2 launch turtlebot3_gazebo turtlebot3_world.launch.py
```

### Rebuilding after you change code

Python nodes and launch files take effect immediately. After changing **C++**, run this in the
VS Code terminal:

```bash
robotlab-rebuild                    # rebuild everything, incrementally
robotlab-rebuild turtlebot3_gazebo  # rebuild just one package, much faster
robotlab-rebuild --clean            # start over from scratch (slow, ~20 min)
```

### The other shortcuts

Under **Start menu → Robot Lab**:

- **Robot Lab - Stop** — shuts the containers down. Your work is untouched.
- **Robot Lab - Check** — diagnoses why it will not start. Try this first.
- **Robot Lab - Reset** — clears the compiled workspace cache. Use after IT updates the image, or
  if the container will not start. Asks for confirmation; leaves your source code alone.

---

## 🛠 Troubleshooting

Run **Robot Lab - Check** first — it identifies most of these automatically.

| Issue | Solution |
|---|---|
| Nothing happens / window flashes and closes | Run **Robot Lab - Check** from the Start menu. It keeps its window open and explains what failed. |
| `Docker Desktop is not responding` | Start Docker Desktop from the Start menu and wait for the whale icon to stop animating — a cold boot takes a minute or two. |
| Permission or pipe error talking to Docker | The account is not in the local `docker-users` group. IT-side fix; see the one-time setup above. |
| `Could not install the VS Code Dev Containers extension` | The launcher tries to install it automatically on first run; this means that failed (usually no network). Run `code --install-extension ms-vscode-remote.remote-containers` yourself. No admin needed. |
| VS Code opens the folder but does not attach to the container | The launcher falls back to this deliberately. Press `Ctrl+Shift+P`, type **Reopen in Container**, press Enter. |
| Host port 8080 already in use | Something else is bound to it. Set another port first: `$env:HOST_PORT = "9000"`, then start again. |
| `manifest unknown` or `denied` when pulling the image | The image tag does not exist, or the GHCR package is still private. Maintainer fix — not something to retry. |
| Container will not start after IT updated the image | Run **Robot Lab - Reset**. A Docker named volume is only seeded when it is first created, so an existing cache does not pick up a new image on its own. |
| Gazebo spawn service failed | Don't `Ctrl+C` — let it fail completely, then close and restart. |
| Webcam not accessible in the container | Expected. Passing a USB camera into Docker Desktop's VM needs [usbipd-win](https://github.com/dorssel/usbipd-win) and admin rights. Lab PCs are set up without camera passthrough. |

---

## 💡 How it fits together

```
C:\ProgramData\RobotLab\repo\      IT-managed clone. Students never edit this.
%USERPROFILE%\RobotLab\ros2_ws\    Per-student copy, made on first launch. Their work lives here.

  novnc container  <--- 'ros' network --->  ROS 2 dev container
  serves the desktop                        runs Gazebo/RViz, renders onto novnc
  at localhost:8080                         via DISPLAY=novnc:0.0
```

- Default user inside the container: `team`
- Workspace mounts at `/home/ros2_ws/src`
- `build/`, `install/` and `log/` live in **per-user Docker named volumes**
  (`robotlab-build-<username>` and friends), not on the host filesystem
- The image ships an **already-compiled** workspace. Docker seeds each new named volume from it, so
  a student's first start inherits the finished build instead of running `colcon` for 20 minutes

### Notes for maintainers

- **`setup.sh` is baked into the image.** `postCreateCommand` runs `/usr/local/bin/setup.sh`, the
  copy `COPY`'d in at build time — *not* the one in your checkout. Editing it in git does nothing
  until the image is rebuilt and pushed.
- **The image build context is the repository root**, not `.devcontainer/`, because the Dockerfile
  copies `src/` in to prebuild it. See [.dockerignore](../../.dockerignore).
- **`src/` is the single source of truth** for the TurtleBot3 packages. They are ours, with custom
  URDFs and worlds — not tracked against upstream ROBOTIS. Nothing in this repo may clone over
  them. An earlier `setup.sh` did exactly that whenever a package folder went missing.
- **Publishing:** run the **Build dev container image** GitHub Action. It publishes to the testing
  package `ghcr.io/cobot-maker-space/uon-windows-testing` and refuses to run if the tag it would
  publish does not match the pin in `devcontainer.json`. New GHCR packages are **private by
  default** — set the visibility to Public after the first push, or no lab PC can pull it.
- **`cache/` is no longer tracked.** It was 3,995 files and 221 MB with a 271-character deepest
  path, which is why `git config core.longpaths true` used to be mandatory before cloning. It is
  not needed any more.
- **Keep `*.ps1` and `*.cmd` pure ASCII.** Windows PowerShell 5.1 decodes a BOM-less file using the
  ANSI codepage; a pasted em dash then becomes a character the parser reads as a string delimiter,
  producing a bogus error hundreds of lines from the real one.
