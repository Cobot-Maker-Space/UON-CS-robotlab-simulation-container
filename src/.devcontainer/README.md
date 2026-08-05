# 🐢 TurtleBot Desktop Development Container (with noVNC) — Windows Edition

This branch provides the same ready-to-use Docker-based ROS 2 Humble development environment for TurtleBot3 simulation and development, adapted for **Windows** via WSL2.

It includes:
- ROS 2 Humble preinstalled with navigation, SLAM, teleop, Gazebo, and visualization packages
- VS Code Dev Container configuration with useful extensions
- Integrated noVNC support for GUI access from your browser
- Persistent build and install caches for faster rebuilds

> ℹ️ **Why WSL2?** Docker Desktop for Windows requires the WSL2 backend to run Linux containers. Rather than porting the shell scripts to PowerShell, this branch runs everything inside a real Ubuntu (WSL2) shell, which behaves identically to native Linux — no rewritten commands needed.

📦 Prerequisites

- Windows 10 (2004+) or Windows 11
- [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/), with the **WSL 2 based engine** enabled
- [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) with an Ubuntu distro installed
- Visual Studio Code
- VS Code extensions: **Dev Containers** and **WSL**

🔧 Setup Instructions

1. Install WSL2 and Ubuntu

   Open an elevated PowerShell and run:

   ```powershell
   wsl --install
   ```

   Reboot if prompted. This installs WSL2 with Ubuntu as the default distro.

2. Configure Docker Desktop

   - Install Docker Desktop for Windows.
   - Go to **Settings → General** and confirm **"Use the WSL 2 based engine"** is checked.
   - Go to **Settings → Resources → WSL Integration** and enable integration with your Ubuntu distro.

3. Install VS Code extensions

   Install **Dev Containers** and **WSL** from the VS Code marketplace.

4. Prepare Git inside WSL2

   Open an Ubuntu (WSL2) terminal and run:

   ```bash
   git config --global core.autocrlf input
   git config --global core.longpaths true
   ```

   This avoids line-ending corruption and long-path clone failures on Windows.

5. Clone the Repository (inside WSL2, not on the Windows filesystem)

   Clone into your Linux home directory rather than `C:\Users\...` — this keeps file access fast and avoids Windows↔WSL2 filesystem overhead for the bind mounts used later.

   ```bash
   cd ~
   git clone https://github.com/Cobot-Maker-Space/UON-CS-robotlab-simulation-container.git
   ```

6. Start the noVNC Service

   Before opening the devcontainer, make sure the shared Docker network and noVNC service are running.

   ```bash
   cd ~/UON-CS-robotlab-simulation-container/src/.devcontainer/
   chmod +x start_novnc.sh
   ./start_novnc.sh start
   ```

   This will:
   - Create a `ros` Docker network if it doesn't exist
   - Launch a `theasp/novnc:latest` container mapped to `http://localhost:8080`

   Docker Desktop automatically forwards WSL2 ports to `localhost` on Windows, so once running, open:

   ➡ `http://localhost:8080/vnc.html` and click **Connect** to access the container's desktop GUI.

7. Open in VS Code

   From the same WSL2 terminal, launch VS Code attached to WSL:

   ```bash
   code .
   ```

   Then press `Ctrl+Shift+P` → select:

   **Dev Containers: Reopen in Container**

   VS Code will now build and launch the ROS 2 development container, automatically attaching it to the `ros` network so it can reach the noVNC container.

8. Test the Setup

   Inside the VS Code terminal:

   ```bash
   source /opt/ros/humble/setup.bash
   ros2 topic list
   ```

   If ROS 2 is installed correctly, you'll see a list of topics (or an empty list if nothing is publishing).

🛠 Troubleshooting & Common Issues

| Issue | Solution |
|---|---|
| `docker` command not found / permission denied in WSL2 | Confirm Docker Desktop's WSL Integration is enabled for your Ubuntu distro (**Settings → Resources → WSL Integration**). Unlike native Linux, you do **not** need to add your user to a `docker` group — Docker Desktop handles this. |
| `start_novnc.sh: bad interpreter: /bin/bash^M` | The script has Windows (CRLF) line endings. Run `dos2unix start_novnc.sh` inside WSL2, or re-clone after setting `git config --global core.autocrlf input` (see step 4). |
| Gazebo spawn service failed | Don't Ctrl+C — let it fail completely, then close and restart. |
| Cannot connect to noVNC | Run `./start_novnc.sh status` to check if the container is running. |
| Webcam (`/dev/video0`) not accessible | `/dev/video0` is a Linux device path with no Windows equivalent through Docker Desktop's WSL2 backend. Passing a USB webcam through requires [usbipd-win](https://github.com/dorssel/usbipd-win) to attach the device into WSL2 first. If you don't need real camera hardware, remove `--device=/dev/video0` and `--group-add=video` from `devcontainer.json`'s `runArgs`. |
| `Unable to create file [..]: Filename too long` on clone | Run `git config --global core.longpaths true` (see step 4). |
| Dev container build is very slow / VS Code feels laggy | Make sure the repo was cloned inside the WSL2 filesystem (e.g. `~/...`), not under `/mnt/c/...` or a Windows path opened via Remote-WSL. Cross-filesystem bind mounts are slow. |

💡 Notes

- Default user inside container: `team`
- Workspace is mounted to `/home/ros2_ws/src`
- Network: `ros` (shared between devcontainer and noVNC container)
- GUI apps (RViz2, Gazebo) accessible via browser at `http://localhost:8080/vnc.html`
- All Docker/devcontainer behavior (networking, bind mounts, `DISPLAY=novnc:0.0`, `postCreateCommand`) is identical to the Linux setup once running inside WSL2 — Docker Desktop always mediates through a Linux VM, even on Windows, so no commands in this repo needed to change.
- Includes:
  - Navigation2, SLAM Toolbox, Teleop
  - Gazebo + plugins
  - Cartographer, RViz2
  - VS Code extensions preinstalled for: ROS, C++, Python, Git integration
