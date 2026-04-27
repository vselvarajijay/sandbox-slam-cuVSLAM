#!/usr/bin/env bash
# Download and unpack a TUM freiburg3 sequence (no registration; public wget from TUM).
# Default: long office / household (good for indoor motion with turns).
# See cuVSLAM/examples/tum/README.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TUM_EX="${ROOT_DIR}/cuVSLAM/examples/tum"

# Basename: rgbd_dataset_freiburg3_<name>  (e.g. long_office_household, structure_notexture_near)
SEQ="${1:-rgbd_dataset_freiburg3_long_office_household}"
TGZ_NAME="${SEQ}.tgz"
URL="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/${TGZ_NAME}"

if [[ ! -d "${TUM_EX}" ]]; then
  echo "Expected ${TUM_EX} (clone cuVSLAM under repo root, or set path)." >&2
  exit 1
fi
if [[ ! -f "${TUM_EX}/freiburg3_rig.yaml" ]]; then
  echo "Missing ${TUM_EX}/freiburg3_rig.yaml" >&2
  exit 1
fi

mkdir -p "${TUM_EX}/dataset"
cd "${TUM_EX}/dataset"
echo "Fetching ${URL}"
wget -O "${TGZ_NAME}" "${URL}"
tar -xzf "${TGZ_NAME}"
rm -f "${TGZ_NAME}"
cp -f "${TUM_EX}/freiburg3_rig.yaml" "${SEQ}/"
echo
echo "Ready: ${TUM_EX}/dataset/${SEQ}"
if [[ "${SEQ}" != "rgbd_dataset_freiburg3_long_office_household" ]]; then
  echo "Run: export TUM_DATASET_DIR=${TUM_EX}/dataset/${SEQ} && python3 track_tum.py"
else
  echo "Run from ${TUM_EX}: python3 track_tum.py   (or set TUM_DATASET_DIR if you moved the tree)"
fi
