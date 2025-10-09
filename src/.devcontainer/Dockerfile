FROM ros:humble
# FROM ghcr.io/sloretz/ros:humble-desktop
# FROM osrf/ros:humble-desktop-full  

ARG USERNAME=team
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create user
# RUN groupadd --gid $USER_GID $USERNAME && \
#     useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

RUN groupadd --gid $USER_GID $USERNAME \
&& useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    #
    # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
&& apt-get update \
&& apt-get install -y sudo \
&& echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
&& chmod 0440 /etc/sudoers.d/$USERNAME

ENV SHELL=/bin/bash
ENV DEBIAN_FRONTEND=noninteractive

# Install ROS packages and other dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    net-tools nano iputils-ping curl fswebcam gnupg2 lsb-release sudo \
    build-essential mesa-utils python3-colcon-common-extensions \
    ros-humble-navigation2 ros-humble-nav2-bringup ros-humble-slam-toolbox \
    ros-humble-teleop-twist-keyboard \
    ros-humble-rqt* \
   # ros-humble-gazebo-ros-pkgs \
   # ros-humble-gazebo-plugins \
    ros-humble-cartographer ros-humble-cartographer-ros \
    ros-humble-rviz2 \
    # VNC + Desktop + noVNC
    ubuntu-mate-desktop \ 
    openbox x11-apps novnc websockify \
    tigervnc-standalone-server tigervnc-common supervisor \
    git wget curl python3-pip tini locales tzdata dos2unix \
    && rm -rf /var/lib/apt/lists/*

COPY setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh
    
# Setup ROS environment
RUN echo "source /opt/ros/humble/setup.bash && source /home/ros2_ws/install/setup.bash" >> /home/$USERNAME/.bashrc

# Add user to video group (for rendering access)
RUN usermod -aG video $USERNAME

USER $USERNAME

# For novnc 
EXPOSE 8080




# ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
