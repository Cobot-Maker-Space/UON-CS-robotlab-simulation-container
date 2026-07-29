#!/usr/bin/env bash
set -e

source /opt/ros/humble/setup.bash

cd /workspaces/UON-CS-robotlab-simulation-container

colcon build --symlink-install --parallel-workers 2

echo "source install/setup.bash" >> ~/.bashrc