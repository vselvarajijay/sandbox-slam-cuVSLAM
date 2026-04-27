# DGX Spark: cuVSLAM (NVIDIA) via Docker

This repository wires up [nvidia-isaac/cuVSLAM](https://github.com/nvidia-isaac/cuVSLAM) (PyCuVSLAM + RealSense) for **NVIDIA DGX Spark** (ARM64, **CUDA 13**, GB10 / Blackwell). Use the upstream **`Dockerfile.realsense-cu13`** (Ubuntu 24.04, CUDA 13.0) — not the CUDA 12 image, which is aimed at x86_64 and Jetson CUDA 12.x workflows.

## Requirements

- [Docker](https://docs.docker.com/engine/install/) and [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) (standard on DGX).
- [git-lfs](https://git-lfs.com/) (`apt install git-lfs`) for the `cuVSLAM` clone.
- A recent NVIDIA driver (the upstream image documents **>= 580** for CUDA 13.0; DGX Spark typically ships 580+).

## Quick start

1. **Clone** the official cuVSLAM tree into this repo (uses Git LFS):

   ```bash
   ./scripts/clone_cuvslam.sh
   ```

2. **Build** the CUDA 13 image (compiles from source; first run is slow):

   ```bash
   ./scripts/build_docker_spark.sh
   ```

3. **Run** an interactive shell in the container:

   ```bash
   ./scripts/run_cuvslam_docker.sh
   ```

   Inside the container, example:

   ```bash
   python3 examples/realsense/run_stereo.py
   ```

   (Requires an Intel RealSense and USB passthrough; the run script maps `/dev/bus/usb` and any `/dev/video*` nodes.)

   **`scripts/run_kitti_e2e.sh`** uses real **`…/dataset/sequences/06`** when present; if not, it turns on the bundled **synthetic** `demo` and prints a short notice. For real roads, unpack [KITTI odometry](http://www.cvlibs.net/datasets/kitti/eval_odometry.php) to `…/06`. To run `track_kitti.py` **directly** (no e2e script) with only the synthetic bundle, set `KITTI_USE_SYNTHETIC_DEMO=1` — see `cuVSLAM/examples/kitti/README.md`.

   ```bash
   ./scripts/run_kitti_e2e.sh
   # Dense SGBM map:  ./scripts/run_kitti_e2e.sh --dense
   # Several sequences (one Rerun .rrd per sequence): ./scripts/run_kitti_e2e_batch.sh
   ```

   **TUM RGB-D (e.g. freiburg1/room + `fr1_room.rrd`):** `scripts/fetch_tum_fr1_room.sh`, then see `cuVSLAM/examples/tum/README.md`.

**Compose** (optional):

```bash
docker compose build
docker compose run --rm cuvslam bash
```

`docker-compose.yml` names the image `pycuvslam:realsense-cu13` and uses the same Dockerfile as the build script.

## 3D mapping with nvblox (Isaac ROS, separate container)

**nvblox** (TSDF / costmaps) and the ROS **cuVSLAM** node run in NVIDIA’s **Isaac ROS** dev environment, not inside `pycuvslam:realsense-cu13`. On DGX Spark, use `isaac_ros_common`’s **`scripts/run_dev.sh`** (present on **`release-3.2`**; not on `main` — see doc), then `ros2 launch nvblox_examples_bringup realsense_example.launch.py` (RealSense + VSLAM + nvblox). See [docs/ISAAC_ROS_NVBLOX_DGX.md](docs/ISAAC_ROS_NVBLOX_DGX.md) and `./scripts/prepare_isaac_nvblox_workspace.sh` to clone into **`~/isaac_ros_ws`** at **`ISAAC_ROS_GITREF=release-3.2`** by default (override with **`NVBLOX_ISAAC_WS`** / **`ISAAC_ROS_GITREF`**; **`ISAAC_NVBLOX_SYNC=1`** forces re-clone if you previously checked out **`main`**). The script does not use **`ISAAC_ROS_WS`** for the clone path. To measure topic **Hz** (real-time vs dropped), use **`./scripts/benchmark_nvblox_perf.sh`** (details in that doc section).

On **DGX Spark**, if `run_dev.sh` fails with **`nvidia.com/pva=all`**, run **`./scripts/patch_isaac_run_dev_spark.sh`** (see doc).

## Image choice (why not CUDA 12?)

| Host | Suggested image |
|------|------------------|
| DGX Spark (aarch64, system CUDA 13) | `Dockerfile.realsense-cu13` — this setup |
| Desktop x86_64, CUDA 12.6+ driver, Ubuntu 22.04 stack | `Dockerfile.realsense-cu12` (see upstream [docker/README.md](https://github.com/nvidia-isaac/cuVSLAM/blob/main/docker/README.md)) |

The default upstream `run_docker.sh` uses the CUDA 12 path unless you pass `24` for the CUDA 13 path. The scripts in this repository default to the **CUDA 13** image to match DGX Spark.

## Environment variables

| Variable | Meaning |
|----------|--------|
| `CUVSLAM_DIR` | Path to the cloned cuVSLAM tree (default: `<repo>/cuVSLAM`) |
| `CUVSLAM_DOCKER_TAG` | Image tag (default: `pycuvslam:realsense-cu13`) |
| `CUVSLAM_DOCKERFILE` | Dockerfile path inside `CUVSLAM_DIR` (default: `docker/Dockerfile.realsense-cu13`) |
| `DATASETS` / `DATASETS_DIR` | Dataset path for examples |

## NGC

Building uses public images (`nvidia/cuda:13.0.0-devel-ubuntu24.04` on Docker Hub). NGC login is not required for this path unless you switch to a private NGC image.

## License

The upstream **cuVSLAM** and **PyCuVSLAM** code is under NVIDIA’s license; see the [cuVSLAM repository](https://github.com/nvidia-isaac/cuVSLAM). This small wrapper repo only adds helper scripts and compose.
