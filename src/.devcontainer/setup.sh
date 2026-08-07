#!/usr/bin/env bash
# setup.sh - devcontainer postCreateCommand.
#
# This runs once per container creation and MUST be fast and non-destructive. The image already
# ships a compiled workspace (see Dockerfile), so the normal path through this script does no work
# at all beyond a couple of checks.
#
# Three behaviours were deliberately removed from an earlier version of this file, all of which
# cost a lab class real time or real work:
#
#   1. It ran `rm -rf build/* install/* log/*` and then a full `colcon build` on EVERY container
#      create. That is the 10-25 minute wait students used to sit through.
#   2. It `git clone`d vanilla upstream ROBOTIS TurtleBot3 into any src/ subfolder that was
#      missing. The packages in this repo are customised (our own URDFs and worlds), so that
#      silently replaced them with stock code whenever a folder went astray. src/ is the single
#      source of truth; nothing here may ever write to it.
#   3. It `apt-get install`ed the Gazebo packages at runtime, making a working network a hard
#      requirement for container start. Those are baked into the image now.
#
# NOTE FOR MAINTAINERS: the Dockerfile COPYs this file to /usr/local/bin/setup.sh, and
# devcontainer.json invokes that baked copy. Editing this file in git has NO effect until the
# image is rebuilt and pushed by .github/workflows/build-image.yml.
set -euo pipefail
IFS=$'\n\t'

WORKSPACE_DIR="/home/ros2_ws"
SRC_DIR="${WORKSPACE_DIR}/src"

echo "=== devcontainer setup.sh ==="

if [ ! -d "$SRC_DIR" ]; then
  echo "ERROR: ${SRC_DIR} does not exist."
  echo "  The workspace bind mount did not attach. Check 'workspaceMount' in devcontainer.json."
  exit 1
fi

if [ -z "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
  echo "ERROR: ${SRC_DIR} is empty."
  echo "  Expected this repository's customised TurtleBot3 packages to be mounted here."
  echo "  Refusing to continue - an earlier version of this script would have cloned stock"
  echo "  upstream packages over the top at this point, which is exactly what we must not do."
  exit 1
fi

# The prebuilt workspace arrives via the named volumes declared in devcontainer.json, which Docker
# seeds from the image the first time each volume is created. If setup.bash is there, the build is
# already done and there is nothing to do.
if [ -f "${WORKSPACE_DIR}/install/setup.bash" ]; then
  echo "Prebuilt workspace found at ${WORKSPACE_DIR}/install - skipping colcon build."
  echo "  Run 'robotlab-rebuild' if you have changed source and want to rebuild."
  echo "=== setup.sh finished (no build needed) ==="
  exit 0
fi

echo "No prebuilt workspace found. Building - this takes a while, but only happens once."

if [ -f /opt/ros/humble/setup.bash ]; then
  set +u
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
  set -u
else
  echo "ERROR: /opt/ros/humble/setup.bash not found. This is not the expected base image."
  exit 1
fi

if ! command -v colcon >/dev/null 2>&1; then
  echo "ERROR: colcon not found on PATH. This is not the expected base image."
  exit 1
fi

cd "$WORKSPACE_DIR"
colcon build --symlink-install

echo "=== setup.sh finished ==="
