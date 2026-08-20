
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "=== devcontainer setup.sh starting ==="

# Hardcode the correct workspace directory
WORKSPACE_DIR="/home/ros2_ws"
SRC_DIR="${WORKSPACE_DIR}/src"

echo "Workspace dir: $WORKSPACE_DIR"
echo "Src dir: $SRC_DIR"

# Determine if we can run apt (root or sudo)
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    echo "Using sudo for package installs"
  else
    echo "Note: not running as root and sudo not found — skipping apt installs"
    SUDO=""
  fi
else
  echo "Running as root"
fi

# Install Gazebo packages only if apt is available
if [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
  echo "Updating apt and installing gazebo packages..."
  $SUDO apt-get update -y
  $SUDO apt-get install -y ros-humble-gazebo-ros-pkgs ros-humble-gazebo-plugins || {
    echo "Warning: apt-get install failed (continuing)."
  }
fi

# Ensure src folder exists
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"

# Clean build/install/log only if they exist and have content
if [ -d "$WORKSPACE_DIR/build" ] || [ -d "$WORKSPACE_DIR/install" ] || [ -d "$WORKSPACE_DIR/log" ]; then
  echo "Cleaning build/install/log directories (only inside) ..."
  rm -rf "${WORKSPACE_DIR}/build/"* "${WORKSPACE_DIR}/install/"* "${WORKSPACE_DIR}/log/"* || true
fi

# Repos to ensure present (name|url)
repos=(
  "DynamixelSDK|https://github.com/ROBOTIS-GIT/DynamixelSDK.git"
  "turtlebot3|https://github.com/ROBOTIS-GIT/turtlebot3.git"
  "turtlebot3_msgs|https://github.com/ROBOTIS-GIT/turtlebot3_msgs.git"
  "turtlebot3_simulations|https://github.com/ROBOTIS-GIT/turtlebot3_simulations.git"
)

clone_if_missing() {
  local folder="$1"; shift
  local url="$1"; shift
  if [ -d "${SRC_DIR}/${folder}" ]; then
    echo "✅ ${folder} already exists — skipping clone."
  else
    echo "⬇️  Cloning ${folder}..."
    git clone -b humble "${url}" "${SRC_DIR}/${folder}" || {
      echo "Error cloning ${folder}. Continuing..."
    }
  fi
}

for entry in "${repos[@]}"; do
  name="${entry%%|*}"
  url="${entry##*|}"
  clone_if_missing "$name" "$url"
done


# Source ROS and build
if [ -f /opt/ros/humble/setup.bash ]; then
  echo "Sourcing ROS 2 humble setup..."
  set +u
  source /opt/ros/humble/setup.bash
  set -u
fi

# Build the workspace
cd "$WORKSPACE_DIR"
echo "Running colcon build --symlink-install ..."
if command -v colcon >/dev/null 2>&1; then
  colcon build --symlink-install || {
    echo "colcon build failed. Check logs in ${WORKSPACE_DIR}/log"
    exit 1
  }
else
  echo "colcon not found in PATH. Please install colcon inside the container and re-run this script."
  exit 1
fi


echo "=== setup.sh finished successfully ==="


#!/usr/bin/env bash
# # setup.sh - devcontainer postCreateCommand.
# #
# # This runs once per container creation and MUST be fast and non-destructive. The image already
# # ships a compiled workspace (see Dockerfile), so the normal path through this script does no work
# # at all beyond a couple of checks.
# #
# # Three behaviours were deliberately removed from an earlier version of this file, all of which
# # cost a lab class real time or real work:
# #
# #   1. It ran `rm -rf build/* install/* log/*` and then a full `colcon build` on EVERY container
# #      create. That is the 10-25 minute wait students used to sit through.
# #   2. It `git clone`d vanilla upstream ROBOTIS TurtleBot3 into any src/ subfolder that was
# #      missing. The packages in this repo are customised (our own URDFs and worlds), so that
# #      silently replaced them with stock code whenever a folder went astray. src/ is the single
# #      source of truth; nothing here may ever write to it.
# #   3. It `apt-get install`ed the Gazebo packages at runtime, making a working network a hard
# #      requirement for container start. Those are baked into the image now.
# #
# # NOTE FOR MAINTAINERS: the Dockerfile COPYs this file to /usr/local/bin/setup.sh, and
# # devcontainer.json invokes that baked copy. Editing this file in git has NO effect until the
# # image is rebuilt and pushed by .github/workflows/build-image.yml.
# set -euo pipefail
# IFS=$'\n\t'

# WORKSPACE_DIR="/home/ros2_ws"
# SRC_DIR="${WORKSPACE_DIR}/src"

# echo "=== devcontainer setup.sh ==="

# if [ ! -d "$SRC_DIR" ]; then
#   echo "ERROR: ${SRC_DIR} does not exist."
#   echo "  The workspace bind mount did not attach. Check 'workspaceMount' in devcontainer.json."
#   exit 1
# fi

# if [ -z "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
#   echo "ERROR: ${SRC_DIR} is empty."
#   echo "  Expected this repository's customised TurtleBot3 packages to be mounted here."
#   echo "  Refusing to continue - an earlier version of this script would have cloned stock"
#   echo "  upstream packages over the top at this point, which is exactly what we must not do."
#   exit 1
# fi

# # The prebuilt workspace arrives via the named volumes declared in devcontainer.json, which Docker
# # seeds from the image the first time each volume is created. If setup.bash is there, the build is
# # already done and there is nothing to do.
# if [ -f "${WORKSPACE_DIR}/install/setup.bash" ]; then
#   echo "Prebuilt workspace found at ${WORKSPACE_DIR}/install - skipping colcon build."
#   echo "  Run 'robotlab-rebuild' if you have changed source and want to rebuild."
#   echo "=== setup.sh finished (no build needed) ==="
#   exit 0
# fi

# echo "No prebuilt workspace found. Building - this takes a while, but only happens once."

# if [ -f /opt/ros/humble/setup.bash ]; then
#   set +u
#   # shellcheck disable=SC1091
#   source /opt/ros/humble/setup.bash
#   set -u
# else
#   echo "ERROR: /opt/ros/humble/setup.bash not found. This is not the expected base image."
#   exit 1
# fi

# if ! command -v colcon >/dev/null 2>&1; then
#   echo "ERROR: colcon not found on PATH. This is not the expected base image."
#   exit 1
# fi

# cd "$WORKSPACE_DIR"
# colcon build --symlink-install

# echo "=== setup.sh finished ==="
