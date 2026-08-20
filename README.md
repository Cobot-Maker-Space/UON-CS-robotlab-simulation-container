# 🐢 UON ROS 2 Humble RobotLab — GitHub Codespaces Edition

**Nothing to install. No Docker. No local clone. It runs in your browser.**

This branch turns the RobotLab simulation environment into a **GitHub Codespace** — a full
ROS 2 Humble container running on GitHub's servers, with a Linux desktop (RViz2, rqt, Gazebo)
streamed to a browser tab through noVNC.

Because everything runs remotely, your own machine only needs a browser. A Chromebook, a
locked-down lab PC, or (in theory) an iPad can all drive the same environment.

> **Which branch am I on?** The Codespaces configuration (the `.devcontainer/` folder) lives on
> the **`testing`** branch. It does **not** exist on `main`. The `codespace-testing` branch is an
> identical mirror — if the instructions below say `testing` and you only see `codespace-testing`,
> either one works. Just be consistent: fork it, select it, and create the Codespace *from it*.

---

## 📋 What you get

| Component | Detail |
|---|---|
| Base image | `ghcr.io/mohammad-areeb/uon-ros2:latest` (built from [`.devcontainer/Dockerfile`](.devcontainer/Dockerfile)) |
| ROS distro | ROS 2 **Humble** |
| ROS packages | Navigation2, Nav2 bringup, SLAM Toolbox, Cartographer, RViz2, all `rqt` plugins, teleop, Gazebo + `gazebo_ros_pkgs` |
| Robot packages | TurtleBot3, TurtleBot3 msgs, TurtleBot3 simulations, DynamixelSDK (already vendored in [`src/`](src/)) |
| Desktop | TigerVNC (`:1`, 1280×800) + Openbox, supervised by `supervisord` |
| Browser access | noVNC served by `websockify` on **port 8080** |
| Machine size | 4-core (declared via `hostRequirements` in [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json)) |
| Preset env | `ROS_DOMAIN_ID=30`, `TURTLEBOT3_MODEL=waffle`, `DISPLAY=:1` |

---

## ⏱️ Before you start — understand your Codespaces quota

Codespaces is **free but metered**. GitHub gives you a monthly allowance of *core-hours*, and
your usage is billed as `cores × hours`. A 4-core machine therefore burns your allowance
**twice as fast** as a 2-core one.

### Monthly allowance by account type

| Account type | Core-hours/month | Storage | Source |
|---|---|---|---|
| Free personal account (unverified) | 120 | 15 GB | GitHub Docs |
| GitHub Student Developer Pack (Codespaces at Pro level) | 180 | 20 GB | GitHub Education |

### What that means in real wall-clock hours

| Machine | Free account (120 core-hrs) | Student Pack (180 core-hrs) |
|---|---|---|
| 2-core | 60 real hours/month (~15 hrs/week) | 90 real hours/month (~22.5 hrs/week) |
| **4-core** | **30 real hours/month (~7.5 hrs/week)** | **45 real hours/month (~11.25 hrs/week)** |

### Why we use 4-core

2-core machines do not have the processing power for this workload — Gazebo, Nav2 and a full
GUI desktop on 2 cores is not usable. The devcontainer therefore requests 4 cores, and you should
budget your hours on the 4-core row above.

### 🎓 Students: claim the Student Developer Pack

Link your **university email address** to your GitHub account and apply at
**<https://github.com/education/students>**. This upgrades your Codespaces allowance to Pro level
and takes your 4-core budget from **30 → 45 real hours/month**, at no cost.

Do this *before* your first lab session — approval is usually quick, but it is not instant.

### 👩‍🏫 Staff: apply for Educator status

Staff can apply for **GitHub Educator/Teacher status** to unlock the same 180 core-hour limit.
The process is the same idea: add your university email to your GitHub account, then upload your
staff ID card. In practice this has been approved in **a day or less**.

---

## 🚀 Setup tutorial

### Step 1 — Fork the repository

1. Open the lab repository:
   **<https://github.com/Cobot-Maker-Space/UON-CS-robotlab-simulation-container>**
2. Click **Fork** (top-right of the page).
3. On the *Create a new fork* page, find the checkbox **"Copy the `main` branch only"** and
   **UNTICK it.**

   > ⚠️ **This is the single most important click in this tutorial.** The lab environment lives on
   > the `codespace-testing` branch, not `main`. If you leave that box ticked, your fork will contain only
   > `main`, the `.devcontainer/` folder will be missing, and nothing else here will work.

4. **Do not rename the fork.** Leave it as `UON-CS-robotlab-simulation-container`. The build script
   uses that exact path (`/workspaces/UON-CS-robotlab-simulation-container`), so a renamed fork will
   fail to build.
5. Click **Create fork**. GitHub takes you to your own copy of the repository.

### Step 2 — Switch to the `codespace-testing` branch

1. On *your fork's* page, click the branch dropdown (it reads **`main`** by default) — it's just
   above the file list on the left.
2. Select **`codespace-testing`**.
3. Confirm the selector now reads `codespace-testing` and that you can see a `.devcontainer` folder in the
   file list before continuing.

### Step 3 — Create the Codespace *from the `codespace-testing` branch*

> **Why this matters:** a Codespace is permanently tied to the branch it was created from. Create
> one from `main` and it will have no ROS 2 image, no VNC setup and no build scripts — and it will
> still burn your hours.

1. With `codespace-testing` selected, click the green **Code** button.
2. Choose the **Codespaces** tab (not *Local*).
3. Click **Create codespace on codespace-testing**.

GitHub opens a new tab and starts building. This pulls the ROS 2 Humble image and then runs
`.devcontainer/setup.sh`, which does a full `colcon build --symlink-install` of the TurtleBot3
workspace. **The first launch takes several minutes — this is normal. Don't close the tab.**

### Step 4 — Wait for configuration to finish

- You'll see a progress screen, sometimes with a terminal-style log. For detailed progress, click
  the **"Building codespace"** pop-up in the bottom-right corner.
- When it's done, the VS Code editor loads fully: the file explorer on the left shows the repo's
  folders (`src`, `.devcontainer`, …) and a terminal panel appears at the bottom.
- **Read the setup terminal output.** It should end cleanly with colcon reporting that all packages
  finished building, and no red error text. If you see errors here, write them down — every later
  step assumes the workspace built successfully.

### Step 5 — Open a fresh terminal

Don't reuse the setup terminal. Open a clean shell so the ROS environment is fully sourced:

- Click the **+** icon in the terminal panel, or use **Terminal → New Terminal**.

Sanity check:

```bash
ros2 topic list
```

An empty list (or just `/parameter_events` and `/rosout`) means ROS 2 is working.

### Step 6 — Find the forwarded port 8080

1. In the same panel group as the terminal, click the **Ports** tab (next to *Terminal* and
   *Problems*).
2. Port **8080** should be listed — it is forwarded automatically by the devcontainer config. If
   it's not there yet, wait a few seconds; the VNC and noVNC services start just after the Codespace
   finishes configuring.
3. Hover over the 8080 row and click the **globe / "Open in Browser"** icon. This opens it in a new
   browser tab.

   *(You can also right-click → "Preview in Editor" to keep it inside VS Code, but a separate
   browser tab is much easier to work with for a remote desktop.)*

### Step 7 — Open the noVNC viewer

> **What you'll see first:** the port-8080 tab initially shows a plain **directory listing**
> (`app/`, `core/`, `include/`, `vendor/`, `vnc.html`, …). This is expected and means noVNC is being
> served correctly. You have *not* reached the desktop yet.

1. Click **`vnc.html`** in that listing — or add `/vnc.html` to the end of the URL yourself, e.g.
   `https://your-codespace-name-8080.app.github.dev/vnc.html`
2. The noVNC viewer loads with a **Connect** button in the middle. Click it.
3. No VNC password is required in this environment — if a password box appears, leave it blank and
   confirm.
4. You should now see a mostly empty grey/black desktop with a small taskbar. That's the **Openbox**
   virtual desktop running inside your Codespace. **An empty desktop is correct — nothing is wrong.**

💡 **Tip:** open the small vertical "burger" menu on the left edge of the noVNC page and set
**Scaling Mode → Local Scaling** so the desktop fits your browser window.

### Step 8 — Test it with `rqt`

1. Go back to your **Codespace terminal tab** (not the VNC browser tab).
2. Run:

   ```bash
   rqt
   ```

3. Switch to the browser tab showing the VNC desktop. The `rqt` window should appear there within a
   few seconds.

If a window appears on the VNC desktop, **your environment is fully working** and you're ready to
start the lab.

---

## 🤖 Running the simulation

`TURTLEBOT3_MODEL` is already set to `waffle`, so you can launch straight away. Use a **separate
terminal per command** (the **+** button in the terminal panel).

```bash
# Terminal 1 — Gazebo world (appears on the VNC desktop)
ros2 launch turtlebot3_gazebo turtlebot3_world.launch.py

# Terminal 2 — drive the robot with the keyboard
ros2 run turtlebot3_teleop teleop_keyboard

# Terminal 3 — visualisation
rviz2      # heavier
rqt        # lighter — prefer this for image topics
```

Your own packages go in [`src/`](src/). Rebuild with:

```bash
colcon build --symlink-install
source install/setup.bash
```

---

## 🛠 Troubleshooting

| Symptom | Fix |
|---|---|
| **Port 8080 shows "This page isn't working" / HTTP 502** | Give it another 20–30 seconds after configuration finishes, then refresh. The VNC services start slightly after the container is ready. |
| **Nothing loads at all on port 8080** | Reopen the **Ports** tab and confirm 8080 is listed (either *Public* or *Private* visibility works for viewing it yourself), then open it again. If it's missing entirely, re-run `bash .devcontainer/start-gui.sh` in a terminal. |
| **`rqt` / `rviz2` says "cannot connect to display"** | Check `echo $DISPLAY` prints `:1` (it's preset by the devcontainer). If it's empty, run `export DISPLAY=:1`. Also make sure you have already clicked **Connect** on the `vnc.html` page — the session must be active. |
| **GUI windows stopped appearing / desktop froze** | Restart the whole GUI stack: `bash .devcontainer/start-gui.sh`, then reload the `vnc.html` tab. |
| **Want to see why VNC failed** | Check the logs: `cat /tmp/vncserver.err.log`, `cat /tmp/websockify.err.log`, `cat /tmp/supervisord.log`. |
| **`colcon build` failed during setup** | Re-run it manually: `source /opt/ros/humble/setup.bash && colcon build --symlink-install --parallel-workers 2`. |
| **Gazebo spawn service failed** | Don't `Ctrl+C` mid-launch — let it fail completely, then relaunch. |
| **Codespace is slow or laggy** | Expected: it's a full GUI stack on a remote 4-core machine. Don't run Gazebo and RViz2 simultaneously if things feel sluggish, and prefer `rqt` over `rviz2` for viewing image data. |
| **No `.devcontainer` folder / Codespace has no ROS** | You created the Codespace from `main`. Delete it, switch to the `testing` branch, and create a new one. |
| **Build fails with "no such directory /workspaces/UON-CS-robotlab-simulation-container"** | You renamed your fork. Rename it back to `UON-CS-robotlab-simulation-container`. |

---

## ⚠️ Managing your Codespace hours

**Your usage is limited and does not reset instantly.** Every hour your Codespace is *running* —
including sitting idle in a forgotten background tab — counts against your monthly quota.

- **Always stop your Codespace when you finish a session.** Go to
  **<https://github.com/codespaces>**, find your Codespace, and click **Stop**.
- **Closing the browser tab does NOT stop it.** It keeps running and keeps billing.
- Codespaces auto-stop after a period of inactivity (**30 minutes** by default). You can lower this
  to **15 minutes** in your Codespaces settings to save hours — and you should. Stopping does **not**
  delete anything: your files, builds and terminals' working state persist, and you resume from the
  same point next time.
- Don't rely on the auto-stop alone — stop it manually.
- **Deleting** a Codespace *does* discard anything you haven't committed and pushed. Commit your work.
- If you haven't already: **apply for the GitHub Student Developer Pack**
  (<https://github.com/education/students>) — it meaningfully increases your monthly free hours for
  free.

---

## ⚖️ Why Codespaces (and where it hurts)

**Pros**

- **No hardware requirements at all.** Any machine with a browser works — no Docker, no admin
  rights, no 15 GB image download over campus Wi-Fi.
- **Everyone has an identical setup**, so support is dramatically easier: one person's problem is
  everyone's problem, and one fix solves it for the whole cohort.
- **Sessions are resumable.** The 30-minute (or 15-minute) inactivity timeout only *suspends* the
  Codespace — it doesn't delete it. Students restart and carry on from where they left off.

**Cons**

- **Hours are tight without a Student Pack** — 30 real hours/month on 4-core is roughly 7.5 hours a
  week.
- **Lag is unavoidable.** It's a full GUI desktop streamed from a remote 4-core machine; heavy 3D
  work (Gazebo + RViz2 together) will feel sluggish.

---

## 📁 Reference

| Thing | Value |
|---|---|
| Workspace path in container | `/workspaces/UON-CS-robotlab-simulation-container` |
| Container user | `vscode` (passwordless `sudo`) |
| Display | `:1` (1280×800, 24-bit) |
| VNC server port (internal) | `5901` |
| noVNC / websockify port (forwarded) | `8080` → `/vnc.html` |
| `ROS_DOMAIN_ID` | `30` |
| `TURTLEBOT3_MODEL` | `waffle` |
| Runs on container **create** | [`.devcontainer/setup.sh`](.devcontainer/setup.sh) — `colcon build --symlink-install --parallel-workers 2` |
| Runs on every container **start** | [`.devcontainer/start-gui.sh`](.devcontainer/start-gui.sh) — starts VNC + noVNC via [`supervisord.conf`](.devcontainer/supervisord.conf) |
| Preinstalled VS Code extensions | C/C++, CMake, ROS, GitLens |

> 💻 **Prefer to run this locally instead?** A Docker + VS Code Dev Containers setup for
> Windows/Linux machines lives on the `main` and `lab-testing-windows` branches.
