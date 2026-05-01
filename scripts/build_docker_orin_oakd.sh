#!/usr/bin/env bash
# Build Jetson Orin + OAK-D image: CUDA 12.6, cuVSLAM, RealSense stack, depthai, Rerun serve_grpc defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
TAG="${CUVSLAM_DOCKER_TAG:-pycuvslam:orin-oakd}"
DOCKERFILE="${CUVSLAM_DOCKERFILE:-docker/Dockerfile.orin-oakd}"
if [[ "${DOCKERFILE}" = /* ]]; then
  DOCKERFILE_ABS="${DOCKERFILE}"
else
  DOCKERFILE_ABS="${CUVSLAM_DIR}/${DOCKERFILE}"
fi

if [[ ! -f "${DOCKERFILE_ABS}" ]]; then
  echo "Error: expected ${DOCKERFILE_ABS} — run: ${ROOT_DIR}/scripts/clone_cuvslam.sh" >&2
  exit 1
fi

echo "Building ${TAG} from ${CUVSLAM_DIR} (${DOCKERFILE_ABS})"
echo "Includes depthai + default RERUN_SERVE_GRPC=1 for Mac viewer. First build is slow on Orin."

docker build -f "${DOCKERFILE_ABS}" -t "${TAG}" "${CUVSLAM_DIR}"
echo "Built ${TAG}. On Orin: ${ROOT_DIR}/scripts/run_cuvslam_docker_orin_oakd.sh"
echo "On Mac: rerun rerun+http://<ORIN_TAILSCALE_IP>:9876/proxy"
