# ROS 2 Humble dev container for the UoN robot lab.
#
# IMPORTANT: the build context is the REPOSITORY ROOT, not this directory, because the image bakes
# in a compiled copy of the customised packages under src/. Build it with:
#
#   docker build -f src/.devcontainer/Dockerfile -t ghcr.io/cobot-maker-space/windows-robot-simulation:humble-sim-2026-09 .
#
# .github/workflows/build-image.yml does exactly that. See also .dockerignore at the repo root.
FROM ros:humble

ARG USERNAME=team
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Where the workspace lives. This path is baked into the compiled CMake caches below, and
# devcontainer.json mounts the student's source at exactly the same path, which is what lets the
# prebuilt build/ tree still serve incremental rebuilds at runtime. Do not change one without
# the other.
ARG WORKSPACE_DIR=/home/ros2_ws

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

ENV SHELL=/bin/bash
ENV DEBIAN_FRONTEND=noninteractive

# ros-humble-gazebo-ros-pkgs and ros-humble-gazebo-plugins used to be apt-installed by setup.sh on
# every container create, which made a working network a hard requirement for container start and
# added minutes to it. They are baked in here instead.
#
# ubuntu-mate-desktop is heavy (~1.5 GB) and is a candidate for removal: the desktop session the
# student actually sees belongs to the separate novnc container, and this container only needs
# enough of X to render Gazebo/RViz onto it. Left in place for now because dropping it risks
# subtle font/theme breakage mid-term - worth revisiting out of teaching season.
RUN apt-get update && apt-get install -y \
    python3-pip \
    net-tools nano iputils-ping curl fswebcam gnupg2 lsb-release sudo \
    build-essential mesa-utils python3-colcon-common-extensions \
    ros-humble-navigation2 ros-humble-nav2-bringup ros-humble-slam-toolbox \
    ros-humble-teleop-twist-keyboard \
    ros-humble-rqt* \
    ros-humble-gazebo-ros-pkgs \
    ros-humble-gazebo-plugins \
    ros-humble-cartographer ros-humble-cartographer-ros \
    ros-humble-rviz2 \
    # VNC + Desktop + noVNC
    ubuntu-mate-desktop \
    openbox x11-apps novnc websockify \
    tigervnc-standalone-server tigervnc-common supervisor \
    git wget curl python3-pip tini locales tzdata dos2unix \
    && rm -rf /var/lib/apt/lists/*

# dos2unix guards against a contributor committing these with CRLF from a Windows checkout.
# .gitattributes should already prevent it, but a broken shebang here breaks every container.
COPY src/.devcontainer/setup.sh /usr/local/bin/setup.sh
COPY src/.devcontainer/rossim-rebuild /usr/local/bin/rossim-rebuild
RUN dos2unix /usr/local/bin/setup.sh /usr/local/bin/rossim-rebuild \
    && chmod +x /usr/local/bin/setup.sh /usr/local/bin/rossim-rebuild

RUN usermod -aG video $USERNAME \
    && mkdir -p ${WORKSPACE_DIR}/src ${WORKSPACE_DIR}/build ${WORKSPACE_DIR}/install ${WORKSPACE_DIR}/log \
    && chown -R $USER_UID:$USER_GID ${WORKSPACE_DIR}

# Source ROS in every interactive shell. The install/ guard matters: on a clean-rebuild the file
# is briefly absent, and an unguarded source prints an error on every new terminal.
RUN printf '%s\n' \
    'source /opt/ros/humble/setup.bash' \
    '[ -f /home/ros2_ws/install/setup.bash ] && source /home/ros2_ws/install/setup.bash' \
    >> /home/$USERNAME/.bashrc

USER $USERNAME

# --- Prebuild the customised workspace -------------------------------------------------------
#
# This is what removes the 10-25 minute wait from a student's first container start. The compiled
# build/ and install/ trees are picked up automatically at runtime: devcontainer.json mounts named
# volumes over these paths, and Docker seeds a newly created named volume from the image content
# already there.
#
# These are OUR packages, not upstream ROBOTIS ones - custom URDFs and worlds. Nothing anywhere in
# this repo may clone over src/.
#
# build/ is shipped as well as install/, which costs image size but means a student's first
# 'rossim-rebuild' is incremental rather than a full 20-minute compile.
COPY --chown=$USER_UID:$USER_GID src/ ${WORKSPACE_DIR}/src/

# --symlink-install must match the flag used by rossim-rebuild and setup.sh: colcon refuses to
# build into an install tree created with a different layout. The symlinks it creates point into
# ${WORKSPACE_DIR}/src, which is exactly where the student's copy gets bind-mounted, so they still
# resolve at runtime - and edits to Python nodes and launch files take effect without a rebuild.
RUN /bin/bash -c "source /opt/ros/humble/setup.bash \
    && cd ${WORKSPACE_DIR} \
    && colcon build --symlink-install \
    && rm -rf ${WORKSPACE_DIR}/log/*"

WORKDIR ${WORKSPACE_DIR}

# noVNC is served by the separate 'novnc' container, not this one. Kept only as documentation of
# the port the student's browser goes to.
EXPOSE 8080
