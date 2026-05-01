#!/usr/bin/env bash
# Run PyCuVSLAM container for Jetson Orin: CUDA 12.6 image + host CUDA mount + relax NVIDIA_REQUIRE (L4T).
# See cuVSLAM/docker/README.md (Jetson Orin Support).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
TAG="${CUVSLAM_DOCKER_TAG:-pycuvslam:realsense-cu12}"
IMAGE_TAG="${TAG}"

if ! docker image inspect "${IMAGE_TAG}" &>/dev/null; then
  echo "Error: image ${IMAGE_TAG} not found. Build with: ${ROOT_DIR}/scripts/build_docker_orin.sh" >&2
  exit 1
fi

if [[ ! -d "${CUVSLAM_DIR}" ]]; then
  echo "Error: CUVSLAM_DIR missing: ${CUVSLAM_DIR}" >&2
  exit 1
fi

ARCH=$(uname -m)
echo "Architecture: ${ARCH}"
echo "Image: ${IMAGE_TAG} (CUDA 12.6 — Jetson Orin / L4T; use Spark scripts for CUDA 13 on DGX Spark)"
echo "Mounting source: ${CUVSLAM_DIR} -> /cuvslam"

# Match paths inside the image (base: nvidia/cuda:12.6.0-devel-ubuntu22.04).
CUDA_MOUNT_ARGS=()
if [[ "${ARCH}" == "aarch64" ]]; then
  _mounted=""
  for cand in /usr/local/cuda-12.6 /usr/local/cuda-12.4 /usr/local/cuda-12.2 /usr/local/cuda-12; do
    if [[ -d "${cand}" ]]; then
      echo "Mounting host CUDA (read-only): ${cand} -> ${cand}"
      CUDA_MOUNT_ARGS+=( -v "${cand}:${cand}:ro" )
      _mounted=1
      break
    fi
  done
  if [[ -z "${_mounted}" ]] && [[ -e /usr/local/cuda ]]; then
    _real="$(readlink -f /usr/local/cuda 2>/dev/null || true)"
    if [[ -n "${_real}" ]] && [[ -d "${_real}" ]]; then
      echo "Mounting host CUDA from /usr/local/cuda -> ${_real} (read-only)"
      CUDA_MOUNT_ARGS+=( -v "${_real}:${_real}:ro" )
    fi
  fi
  if [[ ${#CUDA_MOUNT_ARGS[@]} -eq 0 ]]; then
    echo "Warning: no /usr/local/cuda-12.* found to mount; container uses image CUDA only." >&2
  fi
fi

# L4T often reports a lower driver than the image's NVIDIA_REQUIRE_CUDA; upstream recommends this on Jetson.
# Set NVIDIA_DISABLE_REQUIRE=0 to enforce checks (e.g. desktop aarch64 with new drivers).
NV_DISABLE="${NVIDIA_DISABLE_REQUIRE:-1}"

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

RUN_CMD=( "$@" )
if [[ ${#RUN_CMD[@]} -eq 0 ]]; then
  RUN_CMD=( /bin/bash )
fi

DOCKER_ENV=(
  -e NVIDIA_DRIVER_CAPABILITIES=all
  -e DISPLAY="${DISPLAY:-}"
  -e XAUTHORITY="${XAUTH}"
  -e QT_X11_NO_MITSHM=1
  -e _X11_NO_MITSHM=1
  -e _MITSHM=0
)
if [[ "${NV_DISABLE}" != "0" ]]; then
  DOCKER_ENV+=( -e "NVIDIA_DISABLE_REQUIRE=${NV_DISABLE}" )
fi

# Rerun remote viewer (optional): pass through from host — see README (RERUN_SERVE_GRPC).
DOCKER_ENV+=( -e RERUN_SERVE_GRPC -e RERUN_GRPC_PORT -e RERUN_SERVE_GRPC_HINT_IP )

# Use a TTY only when stdout is a terminal (avoids "input device is not a TTY" from scripts/CI).
DOCKER_IT=( -i )
[[ -t 1 ]] && DOCKER_IT+=( -t )

# shellcheck disable=SC2046,SC2086
docker run "${DOCKER_IT[@]}" \
  --rm \
  --gpus all \
  --runtime=nvidia \
  --privileged \
  --network host \
  "${DOCKER_ENV[@]}" \
  -v "${XSOCK}":"${XSOCK}" \
  -v "${XAUTH}":"${XAUTH}" \
  -v "${CUVSLAM_DIR}":/cuvslam \
  -v "${DATASETS}":"${DATASETS}" \
  "${VIDEO_ARGS[@]}" \
  "${CUDA_MOUNT_ARGS[@]}" \
  -v /dev/bus/usb:/dev/bus/usb \
  -w /cuvslam \
  "${IMAGE_TAG}" \
  "${RUN_CMD[@]}"

xhost -local:docker 2>/dev/null || true
