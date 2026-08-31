#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

build_mode=if-missing
action=up

usage() {
    cat <<'EOF'
Usage: ./run.sh [--build|--build-only|--rebuild-only|--down|--help]

  no option       Start the simulation, building the image if absent
  --build         Rebuild the image, then start the simulation
  --build-only    Build the image without starting the simulation
  --rebuild-only  Force a clean image rebuild without starting
  --down          Stop and remove this project's container
EOF
}

case "${1:-}" in
    "") ;;
    --build) build_mode=always ;;
    --build-only) build_mode=always; action=build ;;
    --rebuild-only) build_mode=no-cache; action=build ;;
    --down) action=down ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

if [[ $(uname -s) != Linux ]]; then
    echo "ERROR: this project requires native Linux for host networking and X11 forwarding." >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker Engine is not installed." >&2
    exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: the Docker Compose plugin is unavailable." >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: Docker is installed but this user cannot reach the daemon.
Add ${USER:-your-user} to the docker group, then log out and back in:
  sudo usermod -aG docker "${USER:-your-user}"
EOF
    exit 1
fi

export HOST_UID=${HOST_UID:-$(id -u)}
export HOST_GID=${HOST_GID:-$(id -g)}
export VIDEO_GID=${VIDEO_GID:-$(getent group video | cut -d: -f3 || true)}
export RENDER_GID=${RENDER_GID:-$(getent group render | cut -d: -f3 || true)}
VIDEO_GID=${VIDEO_GID:-$HOST_GID}
RENDER_GID=${RENDER_GID:-$HOST_GID}
export VIDEO_GID RENDER_GID
export SIM_IMAGE=${SIM_IMAGE:-ardupilot-blueboat:4.7.0}

compose_files=(-f compose.yaml)
if [[ -d /dev/dri ]]; then
    compose_files+=(-f compose.gpu.yaml)
fi

if [[ $action == down ]]; then
    docker compose "${compose_files[@]}" down --remove-orphans
    exit 0
fi

case $build_mode in
    no-cache)
        echo "Rebuilding $SIM_IMAGE without cache..."
        docker compose "${compose_files[@]}" build --no-cache
        ;;
    always)
        echo "Rebuilding $SIM_IMAGE..."
        docker compose "${compose_files[@]}" build
        ;;
    if-missing)
        if ! docker image inspect "$SIM_IMAGE" >/dev/null 2>&1; then
            echo "Building $SIM_IMAGE (the first build can take several minutes)..."
            docker compose "${compose_files[@]}" build
        else
            echo "Reusing existing image $SIM_IMAGE"
        fi
        ;;
esac

if [[ $action == build ]]; then
    exit 0
fi

if [[ -z ${DISPLAY:-} ]]; then
    echo "ERROR: DISPLAY is empty. Run from the logged-in Linux desktop session." >&2
    exit 1
fi
if ! command -v xauth >/dev/null 2>&1; then
    echo "ERROR: xauth is required. Install it with: sudo apt install xauth" >&2
    exit 1
fi
if [[ ! -d /tmp/.X11-unix ]]; then
    echo "ERROR: /tmp/.X11-unix is unavailable; X11/Xwayland cannot be forwarded." >&2
    exit 1
fi

software=${SOFTWARE_RENDERING:-0}
case "${software,,}" in
    1|true|yes|on)
        export SOFTWARE_RENDERING=1 LIBGL_ALWAYS_SOFTWARE=1
        ;;
    0|false|no|off|"")
        export SOFTWARE_RENDERING=0 LIBGL_ALWAYS_SOFTWARE=0
        if [[ ! -d /dev/dri ]]; then
            echo "ERROR: /dev/dri is unavailable. Retry with SOFTWARE_RENDERING=1 make run" >&2
            exit 1
        fi
        ;;
    *) echo "ERROR: SOFTWARE_RENDERING must be a boolean value." >&2; exit 2 ;;
esac

mkdir -p logs
if [[ ! -w logs ]]; then
    echo "ERROR: $PROJECT_DIR/logs is not writable by UID $HOST_UID." >&2
    exit 1
fi

runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
XAUTH_FILE=$(mktemp "$runtime_dir/ardupilot-blueboat-xauth.XXXXXX")
export XAUTH_FILE
container_started=0
cleanup() {
    status=$?
    trap - EXIT
    if [[ $container_started == 1 ]]; then
        docker compose "${compose_files[@]}" down --remove-orphans || true
    fi
    rm -f -- "$XAUTH_FILE"
    exit "$status"
}
trap cleanup EXIT

cookie=$(xauth nlist "$DISPLAY" 2>/dev/null || true)
if [[ -z $cookie ]]; then
    echo "ERROR: no Xauthority cookie exists for DISPLAY=$DISPLAY." >&2
    exit 1
fi
printf '%s\n' "$cookie" | sed -e 's/^..../ffff/' | xauth -f "$XAUTH_FILE" nmerge -
chmod 0600 "$XAUTH_FILE"

display_number=${DISPLAY##*:}
display_number=${display_number%%.*}
if [[ ! -S /tmp/.X11-unix/X${display_number} ]]; then
    echo "ERROR: DISPLAY=$DISPLAY does not match /tmp/.X11-unix/X${display_number}." >&2
    exit 1
fi

echo "Host IDs: uid=$HOST_UID gid=$HOST_GID video_gid=$VIDEO_GID render_gid=$RENDER_GID"
echo "World: ${WORLD:-blueboat_waves.sdf}; display: $DISPLAY"
echo "MAVLink: ${MAVLINK_QGC:-udp:127.0.0.1:14550} (QGC), ${MAVLINK_API:-udp:127.0.0.1:14551} (student API)"
if pgrep -f '[Q]GroundControl' >/dev/null 2>&1; then
    echo "QGroundControl is running and should auto-connect on UDP 14550."
else
    echo "Start /home/ppatel/Applications/QGroundControl-v5.1.4-x86_64.AppImage to use the ground station."
fi

container_started=1
docker compose "${compose_files[@]}" up --remove-orphans
