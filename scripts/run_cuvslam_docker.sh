#!/usr/bin/env bash
# Run PyCuVSLAM container (CUDA 13 / Ubuntu 24.04) — for DGX Spark: use this, not the CUDA 12 path.
# Adapted from nvidia-isaac/cuVSLAM docker/run_docker.sh (24 -> realsense-cu13).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
TAG="${CUVSLAM_DOCKER_TAG:-pycuvslam:realsense-cu13}"
IMAGE_TAG="${TAG}"

# Validate
if ! docker image inspect "${IMAGE_TAG}" &>/dev/null; then
  echo "Error: image ${IMAGE_TAG} not found. Build with: ${ROOT_DIR}/scripts/build_docker_spark.sh" >&2
  exit 1
fi

if [[ ! -d "${CUVSLAM_DIR}" ]]; then
  echo "Error: CUVSLAM_DIR missing: ${CUVSLAM_DIR}" >&2
  exit 1
fi

ARCH=$(uname -m)
echo "Architecture: ${ARCH}"
echo "Image: ${IMAGE_TAG} (CUDA 13 — matches DGX Spark system CUDA 13 / driver 580+)"
echo "Mounting source: ${CUVSLAM_DIR} -> /cuvslam"

# X11 (DISPLAY may be unset in SSH/headless; nmerge is best-effort for GUI in container)
XSOCK=/tmp/.X11-unix
XAUTH=/tmp/.docker.xauth
export DISPLAY="${DISPLAY:-}"
touch "${XAUTH}"
xauth nlist "${DISPLAY}" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "${XAUTH}" nmerge - 2>/dev/null || true
chmod 777 "${XAUTH}"

DATASETS="${DATASETS:-$(realpath -s "${HOME}/datasets" 2>/dev/null || echo "${HOME}/datasets")}"
mkdir -p "${DATASETS}"
xhost +local:docker 2>/dev/null || true

VIDEO_ARGS=()
if compgen -G /dev/video* > /dev/null; then
  for dev in /dev/video*; do
    [[ -e "$dev" ]] && VIDEO_ARGS+=(--device="${dev}:${dev}")
  done
fi

# Default to an interactive shell if no command is passed
RUN_CMD=( "$@" )
if [[ ${#RUN_CMD[@]} -eq 0 ]]; then
  RUN_CMD=( /bin/bash )
fi

# shellcheck disable=SC2046,SC2086
docker run -it \
  --rm \
  --gpus all \
  --runtime=nvidia \
  --privileged \
  --network host \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e DISPLAY="${DISPLAY:-}" \
  -e XAUTHORITY="${XAUTH}" \
  -e QT_X11_NO_MITSHM=1 \
  -e _X11_NO_MITSHM=1 \
  -e _MITSHM=0 \
  -e RERUN_SERVE_GRPC -e RERUN_GRPC_PORT -e RERUN_SERVE_GRPC_HINT_IP \
  -v "${XSOCK}":"${XSOCK}" \
  -v "${XAUTH}":"${XAUTH}" \
  -v "${CUVSLAM_DIR}":/cuvslam \
  -v "${DATASETS}":"${DATASETS}" \
  "${VIDEO_ARGS[@]}" \
  -v /dev/bus/usb:/dev/bus/usb \
  -w /cuvslam \
  "${IMAGE_TAG}" \
  "${RUN_CMD[@]}"

xhost -local:docker 2>/dev/null || true
