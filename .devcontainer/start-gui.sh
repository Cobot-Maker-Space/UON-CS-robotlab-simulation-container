#!/usr/bin/env bash
set -e

mkdir -p ~/.vnc
chmod 755 ~/.vnc
cp .devcontainer/vnc-xstartup ~/.vnc/xstartup
chmod +x ~/.vnc/xstartup

# Non-interactive password (required even with -SecurityTypes None on some tigervnc builds)
echo "vncpassword123" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Kill any stale session from a previous container start
vncserver -kill :1 &>/dev/null || true

# Run supervisor in the background, detached from this exec session
nohup /usr/bin/supervisord -c .devcontainer/supervisord.conf > /tmp/supervisord-boot.log 2>&1 &
disown