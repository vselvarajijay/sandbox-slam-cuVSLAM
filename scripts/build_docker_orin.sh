#!/usr/bin/env bash
# Build PyCuVSLAM Docker image for Jetson Orin: aarch64 + CUDA 12.6 (Ubuntu 22.04).
# Use this on L4T / JetPack — not Dockerfile.realsense-cu13 (CUDA 13 requires driver 580+ / DGX Spark).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
TAG="${CUVSLAM_DOCKER_TAG:-pycuvslam:realsense-cu12}"
DOCKERFILE="${CUVSLAM_DOCKERFILE:-docker/Dockerfile.realsense-cu12}"
if [[ "${DOCKERFILE}" = /* ]]; then
  DOCKERFILE_ABS="${DOCKERFILE}"
else
  DOCKERFILE_ABS="${CUVSLAM_DIR}/${DOCKERFILE}"
fi

if [[ ! -f "${DOCKERFILE_ABS}" ]]; then
  echo "Error: expected ${DOCKERFILE_ABS} — run: ${ROOT_DIR}/scripts/clone_cuvslam.sh" >&2
  exit 1
fi

if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "Note: Jetson Orin is aarch64; this host is $(uname -m). Image is multi-arch but Orin path is aarch64 + CUDA 12." >&2
fi

echo "Building ${TAG} from ${CUVSLAM_DIR} (${DOCKERFILE_ABS})"
echo "First build compiles librealsense, cuVSLAM, and PyCuVSLAM (slow on Orin)."

docker build -f "${DOCKERFILE_ABS}" -t "${TAG}" "${CUVSLAM_DIR}"
echo "Built ${TAG}. Run: ${ROOT_DIR}/scripts/run_cuvslam_docker_orin.sh"
