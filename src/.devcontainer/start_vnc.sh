#!/usr/bin/env bash
# start_vnc.sh — idempotent helper for the "ros" network + noVNC container
set -euo pipefail

# --- Config (override via env vars) ---
NETWORK_NAME="${NETWORK_NAME:-ros}"
NOVNC_NAME="${NOVNC_NAME:-novnc}"
NOVNC_IMAGE="${NOVNC_IMAGE:-theasp/novnc:latest}"
DISPLAY_WIDTH="${DISPLAY_WIDTH:-3000}"
DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-1800}"
RUN_XTERM="${RUN_XTERM:-no}"
HOST_PORT="${HOST_PORT:-8080}"

# --- Helpers ---
info(){ printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[ERROR]\e[0m %s\n" "$*"; }

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    err "docker CLI not found. Install Docker and try again."
    exit 1
  fi
}

network_exists() {
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1
}

container_running() {
  docker ps --format '{{.Names}}' | grep -Fx -- "$NOVNC_NAME" >/dev/null 2>&1
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fx -- "$NOVNC_NAME" >/dev/null 2>&1
}

port_in_use() {
  # try ss, fallback to lsof; if neither available, assume unknown
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :${HOST_PORT} )" | grep -q LISTEN 2>/dev/null
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i :"${HOST_PORT}" | grep -q LISTEN 2>/dev/null
  else
    return 1
  fi
}

start() {
  ensure_docker

  if network_exists; then
    info "Docker network '${NETWORK_NAME}' already exists."
  else
    info "Creating docker network '${NETWORK_NAME}'..."
    docker network create "$NETWORK_NAME"
  fi

  if container_running; then
    info "noVNC container '${NOVNC_NAME}' is already running."
    echo
    info "Open http://localhost:${HOST_PORT}/vnc.html and click Connect."
    return 0
  fi

  if container_exists; then
    info "Container '${NOVNC_NAME}' exists but is not running — attempting 'docker start'..."
    if docker start "$NOVNC_NAME" >/dev/null; then
      info "Started existing container '${NOVNC_NAME}'."
      echo
      info "Open http://localhost:${HOST_PORT}/vnc.html and click Connect."
      return 0
    else
      warn "Failed to start existing container '${NOVNC_NAME}'. Removing it and re-creating."
      docker rm -f "$NOVNC_NAME" >/dev/null || true
    fi
  fi

  if port_in_use; then
    warn "Host port ${HOST_PORT} looks busy. docker run may fail to bind that port."
  fi

  # 127.0.0.1 on purpose: this desktop has no password and forwards keyboard and mouse, so it
  # must not be published on 0.0.0.0. Reached through localhost either way.
  info "Running new noVNC container '${NOVNC_NAME}' (image: ${NOVNC_IMAGE})..."
  docker run -d --rm --network "$NETWORK_NAME" \
    --env "DISPLAY_WIDTH=${DISPLAY_WIDTH}" \
    --env "DISPLAY_HEIGHT=${DISPLAY_HEIGHT}" \
    --env "RUN_XTERM=${RUN_XTERM}" \
    --name "$NOVNC_NAME" -p "127.0.0.1:${HOST_PORT}:8080" "$NOVNC_IMAGE" >/dev/null

  sleep 0.8
  if container_running; then
    info "noVNC started: http://localhost:${HOST_PORT}/vnc.html"
  else
    err "Failed to start noVNC container. Check 'docker ps -a' and container logs with:"
    echo "  docker ps -a | grep ${NOVNC_NAME}"
    echo "  docker logs ${NOVNC_NAME} || true"
    exit 2
  fi
}

stop() {
  ensure_docker
  if container_exists; then
    info "Stopping and removing container '${NOVNC_NAME}'..."
    docker rm -f "$NOVNC_NAME" >/dev/null || true
    info "Stopped."
  else
    info "No container named '${NOVNC_NAME}' found."
  fi
}

status() {
  ensure_docker
  if container_running; then
    info "Container '${NOVNC_NAME}' is running."
    docker ps --filter "name=${NOVNC_NAME}" --format "  {{.ID}}  {{.Image}}  {{.Status}}  Ports: {{.Ports}}"
  elif container_exists; then
    info "Container '${NOVNC_NAME}' exists but is stopped."
    docker ps -a --filter "name=${NOVNC_NAME}" --format "  {{.ID}}  {{.Image}}  {{.Status}}  Ports: {{.Ports}}"
  else
    info "noVNC container not present."
  fi

  if network_exists; then
    info "Docker network '${NETWORK_NAME}' exists."
  else
    warn "Docker network '${NETWORK_NAME}' does not exist."
  fi
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  restart) stop; start ;;
  *) echo "Usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
