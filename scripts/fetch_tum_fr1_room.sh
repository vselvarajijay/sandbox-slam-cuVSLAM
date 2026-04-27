#!/usr/bin/env bash
# Download TUM freiburg1 / room (loop-friendly indoor path). Public wget from TUM.
# See cuVSLAM/examples/tum/README.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TUM_EX="${ROOT_DIR}/cuVSLAM/examples/tum"
SEQ="rgbd_dataset_freiburg1_room"
TGZ_NAME="${SEQ}.tgz"
URL="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/${TGZ_NAME}"

if [[ ! -d "${TUM_EX}" ]]; then
  echo "Expected ${TUM_EX} (clone cuVSLAM under repo root)." >&2
  exit 1
fi
if [[ ! -f "${TUM_EX}/freiburg1_rig.yaml" ]]; then
  echo "Missing ${TUM_EX}/freiburg1_rig.yaml" >&2
  exit 1
fi

mkdir -p "${TUM_EX}/dataset"
cd "${TUM_EX}/dataset"
echo "Fetching ${URL}"
wget -O "${TGZ_NAME}" "${URL}"
tar -xzf "${TGZ_NAME}"
rm -f "${TGZ_NAME}"
cp -f "${TUM_EX}/freiburg1_rig.yaml" "${SEQ}/"
echo
echo "Ready: ${TUM_EX}/dataset/${SEQ}"
echo "Run (from ${TUM_EX}):"
echo "  export TUM_DATASET_DIR=\"${TUM_EX}/dataset/${SEQ}\""
echo "  TUM_SAVE_RRD=\"${TUM_EX}/rerun_out/fr1_room.rrd\" python3 track_tum.py"
echo
echo "In Docker, host path is under your checkout: e.g. .../cuVSLAM/examples/tum/..."
