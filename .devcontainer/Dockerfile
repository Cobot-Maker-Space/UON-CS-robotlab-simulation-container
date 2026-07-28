FROM ros:humble

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash

# Create user with sudo privileges
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Core ROS 2 packages, GUI stack, and direct noVNC packages
RUN apt-get update && apt-get install -y \
    python3-pip net-tools nano iputils-ping curl fswebcam gnupg2 lsb-release sudo \
    build-essential mesa-utils python3-colcon-common-extensions \
    ros-humble-navigation2 ros-humble-nav2-bringup ros-humble-slam-toolbox \
    ros-humble-teleop-twist-keyboard ros-humble-rqt* \
    ros-humble-cartographer ros-humble-cartographer-ros ros-humble-rviz2 \
    ros-humble-gazebo-ros-pkgs ros-humble-gazebo-plugins \
    openbox novnc websockify tigervnc-standalone-server supervisor \
    git wget tini locales tzdata dos2unix \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install paho-mqtt
    
RUN echo "source /opt/ros/humble/setup.bash" >> /home/$USERNAME/.bashrc \
    && echo "if [ -f /workspaces/UON-CS-robotlab-simulation-container/install/setup.bash ]; then source /workspaces/UON-CS-robotlab-simulation-container/install/setup.bash; fi" >> /home/$USERNAME/.bashrc

USER $USERNAME

# For novnc 
EXPOSE 8080




# ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
