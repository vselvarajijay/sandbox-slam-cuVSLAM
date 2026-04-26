#!/usr/bin/env bash
# Build PyCuVSLAM Docker image for DGX Spark: aarch64 + CUDA 13 (Blackwell / GB10).
# Matches upstream: docker/Dockerfile.realsense-cu13 (Ubuntu 24.04, CUDA 13.0).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
TAG="${CUVSLAM_DOCKER_TAG:-pycuvslam:realsense-cu13}"
DOCKERFILE="${CUVSLAM_DOCKERFILE:-docker/Dockerfile.realsense-cu13}"
# -f is resolved from the current working directory, not the build context — use an absolute path
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
  echo "Warning: DGX Spark is aarch64. This host is $(uname -m). Image is multi-arch but is intended for ARM64 + CUDA 13." >&2
fi

echo "Building ${TAG} from ${CUVSLAM_DIR} (${DOCKERFILE_ABS})"
echo "This compiles librealsense, cuVSLAM, and PyCuVSLAM; first build can take a long time."

docker build -f "${DOCKERFILE_ABS}" -t "${TAG}" "${CUVSLAM_DIR}"
echo "Built ${TAG}. Run: ${ROOT_DIR}/scripts/run_cuvslam_docker.sh"
