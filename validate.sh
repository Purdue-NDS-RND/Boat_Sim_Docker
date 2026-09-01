#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

scripts=(run.sh start-sim.sh sitl-process-wrapper.sh healthcheck.sh validate.sh smoke.sh)
bash -n "${scripts[@]}"
for script in "${scripts[@]}" smoke-test.py; do
    [[ -x $script ]] || { echo "ERROR: $script is not executable" >&2; exit 1; }
done
python3 -m py_compile smoke-test.py

required=(
    Dockerfile compose.yaml compose.gpu.yaml Makefile
    config/blueboat.parm worlds/blueboat_waves.sdf worlds/blueboat_calm.sdf
    worlds/blueboat_harbor.sdf
    README.md docs/SETUP.md docs/USING_THE_SIM.md docs/TROUBLESHOOTING.md docs/DEVELOPMENT.md
)
for path in "${required[@]}"; do
    [[ -f $path ]] || { echo "ERROR: required file missing: $path" >&2; exit 1; }
done

pins=(
    1511f27194f1dcc3728270883047bdf022b3fd53
    082a0fe231f6e63bc8d1598f1cba461d9e2ea7f5
    25bc38ed8c6c0345840159a8cbc0b02781d52f3c
    ca8629df4e191235753dfae92ef725d30b923364
)
for pin in "${pins[@]}"; do
    grep -q "$pin" Dockerfile || { echo "ERROR: Dockerfile is missing source pin $pin" >&2; exit 1; }
    grep -q "$pin" compose.yaml || { echo "ERROR: compose.yaml is missing source pin $pin" >&2; exit 1; }
done

grep -q '<uri>model://blueboat</uri>' worlds/blueboat_waves.sdf
grep -q '<uri>model://blueboat</uri>' worlds/blueboat_calm.sdf
grep -q '<uri>model://blueboat</uri>' worlds/blueboat_harbor.sdf
grep -q '<amplitude>0.08</amplitude>' worlds/blueboat_waves.sdf
grep -q '<amplitude>0.0</amplitude>' worlds/blueboat_calm.sdf
grep -q '<amplitude>0.25</amplitude>' worlds/blueboat_harbor.sdf
grep -q '<model name="dock">' worlds/blueboat_harbor.sdf
grep -q '<collision name="deck_collision">' worlds/blueboat_harbor.sdf
grep -Eq '^FRAME_CLASS[[:space:]]+2$' config/blueboat.parm

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    XAUTH_FILE=/dev/null DISPLAY=:0 HOST_UID=$(id -u) HOST_GID=$(id -g) \
        docker compose -f compose.yaml config --quiet
else
    echo "WARNING: Docker Compose is unavailable; skipped Compose resolution." >&2
fi

echo "Static validation passed."
