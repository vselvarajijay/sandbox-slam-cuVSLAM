#!/usr/bin/env bash
# Check that official KITTI visual odometry is available under the cuVSLAM example tree
# (not only the small synthetic "demo" clip).
#
# After you download data_odometry_gray.zip or data_odometry_color.zip from
#   http://www.cvlibs.net/datasets/kitti/eval_odometry.php
# unpack and merge the `dataset` folder so you have, e.g.:
#   <cuVSLAM>/examples/kitti/dataset/sequences/00/calib.txt
#
# Usage: ./scripts/verify_kitti_data.sh
#   CUVSLAM_DIR=~/path/to/cuVSLAM ./scripts/verify_kitti_data.sh
#
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
BASE="${CUVSLAM_DIR}/examples/kitti/dataset/sequences"

if [[ ! -d "${CUVSLAM_DIR}" ]]; then
  echo "CUVSLAM_DIR not found: ${CUVSLAM_DIR}" >&2
  exit 1
fi
echo "Checking: ${BASE}"
echo ""
have_real=0
if [[ -f "${BASE}/demo/calib.txt" ]]; then
  echo "  [ok]  demo/ (bundled synthetic / smoke test — not real KITTI driving video)"
else
  echo "  [---]  demo/ missing"
fi
for id in 00 01 02 03 04 05 06 07 08 09 10; do
  c="${BASE}/${id}/calib.txt"
  if [[ -f "${c}" ]]; then
    n=$(find "${BASE}/${id}/image_0" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l)
    echo "  [ok]  ${id}/  (calib + image_0 with ${n} png frames)"
    have_real=1
  else
    echo "  [ -- ]  ${id}/  (not found)"
  fi
done
echo ""
if [[ "${have_real}" -eq 0 ]]; then
  echo "No real training sequence (00–10) found. You only have the synthetic 'demo' until you" >&2
  echo "download and merge the KITTI odometry archive. See:" >&2
  echo "  https://www.cvlibs.net/datasets/kitti/eval_odometry.php" >&2
  echo "  cuVSLAM/examples/kitti/README.md  (section: Dataset setup)" >&2
  exit 1
fi
echo "At least one real KITTI sequence is present. Example runs:" >&2
echo "  KITTI_SEQUENCE=06 KITTI_SAVE_RRD=.../out.rrd  ./scripts/run_kitti_e2e.sh" >&2
echo "  ./scripts/run_kitti_e2e_batch.sh --no-clone" >&2
exit 0
