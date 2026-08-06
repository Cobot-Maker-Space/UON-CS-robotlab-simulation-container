# 🐢 TurtleBot Desktop Development Container (with noVNC)

This repository provides a ready-to-use **Docker-based ROS 2 Humble development environment** for **Windows and Linux machines** (amd based systems) for TurtleBot3 simulation and development.  

It includes:
- ROS 2 Humble preinstalled with navigation, SLAM, teleop, Gazebo, and visualization packages  
- VS Code Dev Container configuration with useful extensions  
- Integrated **noVNC support** for GUI access from your browser  
- Persistent build and install caches for faster rebuilds  

Whether you're running on Linux, macOS, or Windows, this container lets you start working with TurtleBot development in minutes.

> 🪟 **On Windows?** This root doc assumes a bash-compatible shell (Linux, macOS, or WSL2). If
> you're setting up your own machine with WSL2, see [src/.devcontainer/README.md](src/.devcontainer/README.md).
> If you're deploying to shared lab PCs where students log in without admin rights, see
> [src/.devcontainer/README-lab-windows.md](src/.devcontainer/README-lab-windows.md) — it uses a
> native PowerShell script instead of WSL2/bash.

---

## 📦 Prerequisites

- **Docker** (with your user in the `docker` group)
- **Visual Studio Code**
- **Dev Containers extension**

---

## 🔧 Setup Instructions

### 1. Clone the Repository

```bash
git clone --branch main --single-branch https://github.com/RobotTeaching/UON-CS-robotlab-simulation-container.git
```

---

### 2. Start the noVNC Service

Before opening the devcontainer, make sure the shared Docker network and noVNC service are running.  

Run:

```bash
cd ~/UON-CS-robotlab-simulation-container/src/.devcontainer/
./start_vnc.sh start
```

This will:
- Create a `ros` Docker network if it doesn't exist
- Launch a `theasp/novnc:latest` container mapped to `http://localhost:8080`

Once running, open:

➡ **http://localhost:8080/vnc.html** and click **Connect** to access the container’s desktop GUI.

---

### 3. Open in VS Code

Launch VS Code → open the `src/` directory → press `Ctrl+Shift+P` → select:

```
Dev Containers: Reopen in Container
```

VS Code will now build and launch the ROS 2 development container, automatically attaching it to the `ros` network so it can reach the noVNC container.

---

### 4. Test the Setup

Inside the VS Code terminal:

```bash
source /opt/ros/humble/setup.bash
ros2 topic list
```

If ROS 2 is installed correctly, you’ll see a list of topics (or an empty list if nothing is publishing).

---


<!-- ### 5. Switching from First-Time Setup to Development Mode

By default, the first container build will clone and build the required TurtleBot3 packages.  
After this initial build, edit `.devcontainer/devcontainer.json` and switch:

```jsonc
// Comment this line:
"postCreateCommand": "rm -rf build/* install/* log/* src/* && cd src/ && git clone -b humble https://github.com/ROBOTIS-GIT/DynamixelSDK.git && git clone -b humble https://github.com/ROBOTIS-GIT/turtlebot3.git && git clone -b humble https://github.com/ROBOTIS-GIT/turtlebot3_msgs.git && git clone -b humble https://github.com/ROBOTIS-GIT/turtlebot3_simulations.git && cd .. && colcon build --symlink-install"

// Uncomment this line:
"postCreateCommand": "colcon build --symlink-install"
```

This will prevent re-cloning packages every time and speed up container startup.  

You can now create custom packages under `/home/ros2_ws/src/` and they will persist between container sessions.
 -->
---

## 🛠 Troubleshooting & Common Issues

| Issue | Solution |
|------|----------|
| **Permission denied: docker** | Add your user to the docker group:<br>`sudo usermod -aG docker $USER && newgrp docker` |
| **Gazebo spawn service failed** | Don’t Ctrl+C — let it fail completely, then close and restart. |
| **Cannot connect to noVNC** | Run `./start_novnc.sh status` to check if the container is running. |
| **Unable to create file [..]: Filename too long on clone** | Run `git config --system core.longpaths true` in a administrator terminal. |
| **ASLA error** or any other gazebo error | Press `Ctrl + Shift + P`, choose `Reopen folder locally` and then again `Ctrl + Shift + P` and mow choose `Rebuild and Reopen in container` |


---

## 💡 Notes

- Default user inside container: `team-beta`
- Workspace is mounted to `/home/ros2_ws/src`
- Network: `ros` (shared between devcontainer and noVNC container)
- GUI apps (RViz2, Gazebo) accessible via **browser** at `http://localhost:8080/vnc.html`
- Includes:
  - Navigation2, SLAM Toolbox, Teleop
  - Gazebo + plugins
  - Cartographer, RViz2
- VS Code extensions preinstalled for:
  - ROS
  - C++
  - Python
  - Git integration

---
