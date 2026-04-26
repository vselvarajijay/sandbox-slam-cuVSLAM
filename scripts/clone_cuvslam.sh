#!/usr/bin/env bash
# Clone nvidia-isaac/cuVSLAM (required for Docker build). Uses git-lfs for assets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${1:-${ROOT_DIR}/cuVSLAM}"
UPSTREAM="${CUVSLAM_UPSTREAM:-https://github.com/nvidia-isaac/cuVSLAM.git}"
REF="${CUVSLAM_REF:-main}"

if [[ -d "${TARGET}/.git" ]]; then
  echo "cuVSLAM already present at ${TARGET}. Pull latest with: (cd ${TARGET} && git pull && git lfs pull)"
  exit 0
fi

if ! command -v git-lfs &>/dev/null; then
  echo "Error: git-lfs is required (the repo uses LFS for images and shared libraries)." >&2
  echo "Install: sudo apt install git-lfs && git lfs install" >&2
  exit 1
fi

echo "Cloning ${UPSTREAM} (ref: ${REF}) -> ${TARGET}"
git clone --branch "${REF}" --depth 1 "${UPSTREAM}" "${TARGET}"
cd "${TARGET}"
git lfs install
git lfs pull

echo "Done. Next: ${ROOT_DIR}/scripts/build_docker_spark.sh"
