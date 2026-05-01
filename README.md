# cuVSLAM (NVIDIA) via Docker — DGX Spark & Jetson Orin

This repository wires up [nvidia-isaac/cuVSLAM](https://github.com/nvidia-isaac/cuVSLAM) (PyCuVSLAM + RealSense) for **NVIDIA DGX Spark** (ARM64, **CUDA 13**, GB10 / Blackwell) and **Jetson Orin** (L4T, **CUDA 12.6**). Spark uses upstream **`Dockerfile.realsense-cu13`** (Ubuntu 24.04, CUDA 13.0, driver **580+**). Orin uses **`Dockerfile.realsense-cu12`**; for **Luxonis OAK-D** use **`Dockerfile.orin-oakd`** (same cu12 stack plus **`depthai`**, Rerun gRPC defaults). The CUDA 13 image will fail at `docker run` on Jetson with NVIDIA runtime “requirements not met” because L4T does not satisfy the CUDA 13 driver policy the same way DGX Spark does.

## Requirements

- [Docker](https://docs.docker.com/engine/install/) and [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) (standard on DGX).
- [git-lfs](https://git-lfs.com/) (`apt install git-lfs`) for the `cuVSLAM` clone.
- A recent NVIDIA driver (the upstream image documents **>= 580** for CUDA 13.0 on Spark; **>= 560** for CUDA 12.6 on the cu12 path — see upstream [docker/README.md](https://github.com/nvidia-isaac/cuVSLAM/blob/main/docker/README.md)).

## Jetson Orin (L4T)

Use the **CUDA 12** scripts (not `build_docker_spark.sh` / `run_cuvslam_docker.sh`).

### Jetson Orin + Luxonis OAK-D (image tuned for “open Rerun on Mac only”)

Dedicated image **`pycuvslam:orin-oakd`** from **`cuVSLAM/docker/Dockerfile.orin-oakd`**: same CUDA **12.6** + cuVSLAM + RealSense stack as **`Dockerfile.realsense-cu12`**, plus **`depthai`**, and Dockerfile defaults **`RERUN_SERVE_GRPC=1`** and **`RERUN_GRPC_PORT=9876`** so you do not need ad‑hoc `pip install` for OAK or remote Rerun.

**On the Orin**

1. `./scripts/clone_cuvslam.sh`
2. `./scripts/build_docker_orin_oakd.sh` (slow first build)
3. Optional: `export RERUN_SERVE_GRPC_HINT_IP=<ip>` if the printed Mac URL should not use this host’s `tailscale ip -4`. When Tailscale is installed and the variable is unset, **`run_cuvslam_docker_orin_oakd.sh`** picks that IPv4 automatically and prints a **`rerun rerun+http://…`** line plus **`nc -zv <ip> 9876`** for a quick connectivity check from the Mac.
4. `./scripts/run_cuvslam_docker_orin_oakd.sh` — **with no arguments** this starts **`python3 examples/oak-d/run_stereo.py`**. Pass another command to override (e.g. `bash`, `python3 examples/realsense/run_stereo.py`).

**On your Mac** (after step 4 is running): install the [Rerun viewer](https://rerun.io/docs/getting-started/installing-viewer), then:

```bash
rerun rerun+http://<ORIN_TAILSCALE_IP>:9876/proxy
```

Use **`tailscale ip -4` on the Orin** for that host part — **not** the Mac’s address. If the viewer reports **“transport error” / “left unexpectedly”**: (1) confirm **`nc -zv <ORIN_IP> 9876`** from the Mac succeeds, (2) match **Rerun viewer** on the Mac to the **`rerun-sdk`** generation in the image (`docker run --rm pycuvslam:orin-oakd python3 -c "import rerun as rr; print(rr.__version__)"`), (3) ensure the **OAK-D** is connected so **`run_stereo.py`** keeps running (if Python exits, gRPC stops).

**Compose:** `docker compose -f docker-compose.orin-oakd.yml build` then `docker compose -f docker-compose.orin-oakd.yml run --rm cuvslam` (same default OAK-D command). Add a CUDA bind mount in an override if you need host `/usr/local/cuda-12.*` like the shell script (compose file does not mount it by default).

To use a **local** spawned viewer instead of gRPC: `RERUN_SERVE_GRPC=0 ./scripts/run_cuvslam_docker_orin_oakd.sh bash`

### Full workflow: clone, rebuild image, run examples, Rerun on Mac

**On the Orin** (SSH is fine; Tailscale IP is OK).

1. **Dependencies:** Docker, [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html), and Git LFS (`sudo apt install git-lfs && git lfs install`). Clone this **sandbox** repo and `cd` into it.

2. **Clone upstream cuVSLAM** (LFS objects required):

   ```bash
   ./scripts/clone_cuvslam.sh
   ```

3. **Build the CUDA 12.6 Docker image** (first time or after Dockerfile / base-image changes; long on Orin):

   ```bash
   ./scripts/build_docker_orin.sh
   ```

   Produces **`pycuvslam:realsense-cu12`**.

4. **When you must rebuild:** upstream **`docker/Dockerfile.realsense-cu12`** or **`docker/Dockerfile.orin-oakd`** changes, you change **`cuVSLAM/examples/requirements.txt`** (Python deps such as **`rerun-sdk`** are installed at image build time), or you want a clean rebuild after **`git pull`** in `cuVSLAM`. Edits to bind-mounted **Python-only** files still apply at run time, but **`pip install …` inside the image** only matches what was built in unless you reinstall in the container.

5. **Run with Rerun streaming to your Mac** — set env on the **host**, then start the container with a Python example (camera/USB must match the script):

   ```bash
   export RERUN_SERVE_GRPC=1
   export RERUN_SERVE_GRPC_HINT_IP=<ORIN_TAILSCALE_IP>   # optional; use tailscale ip -4 on the Orin
   # optional: export RERUN_GRPC_PORT=9876

   ./scripts/run_cuvslam_docker_orin.sh python3 examples/oak-d/run_stereo.py
   # Prefer OAK-D defaults + depthai: ./scripts/run_cuvslam_docker_orin_oakd.sh
   # or RealSense: ./scripts/run_cuvslam_docker_orin.sh python3 examples/realsense/run_stereo.py
   ```

   The container uses **`--network host`** so gRPC listens on the Orin’s interfaces (including Tailscale). Ensure nothing blocks TCP **`9876`** on that path (host firewall / `ufw`).

6. **Interactive shell instead** (then run Python yourself):

   ```bash
   export RERUN_SERVE_GRPC=1
   export RERUN_SERVE_GRPC_HINT_IP=<ORIN_TAILSCALE_IP>
   ./scripts/run_cuvslam_docker_orin.sh
   ```

**On your Mac**

1. Install the **native Rerun viewer** (align with **`rerun-sdk`** in the container when possible — check with `docker run --rm pycuvslam:realsense-cu12 python3 -c "import rerun as rr; print(rr.__version__)"` or the **`orin-oakd`** tag if you use that image). See [Installing Rerun](https://rerun.io/docs/getting-started/installing-viewer) (`brew install rerun` / docs for `pip`).

2. Connect to the Orin’s gRPC proxy (**replace IP/port** if you changed them; use the Orin’s `tailscale ip -4`, not the Mac’s):

   ```bash
   rerun rerun+http://<ORIN_TAILSCALE_IP>:9876/proxy
   ```

3. Start this **after** the Python example has begun (or within a few seconds); `serve_grpc` buffers some data for late viewers.

---

**Short reference**

- **Orin (RealSense / generic cu12):** `./scripts/clone_cuvslam.sh` → `./scripts/build_docker_orin.sh` → `./scripts/run_cuvslam_docker_orin.sh` — sets `NVIDIA_DISABLE_REQUIRE=1` by default, mounts host `/usr/local/cuda-12.*` when present, bind-mounts `./cuVSLAM` → `/cuvslam`.
- **Orin + OAK-D:** `./scripts/build_docker_orin_oakd.sh` → `./scripts/run_cuvslam_docker_orin_oakd.sh` (default `python3 examples/oak-d/run_stereo.py`, Rerun gRPC on in the image).

**Compose (Orin):** `docker compose -f docker-compose.orin.yml build` then `docker compose -f docker-compose.orin.yml run --rm cuvslam bash`. Set `RERUN_SERVE_GRPC=1` in the environment or in an `.env` file next to compose.

**Compose (Orin + OAK-D):** `docker compose -f docker-compose.orin-oakd.yml build` then `docker compose -f docker-compose.orin-oakd.yml run --rm cuvslam`. Same caveats as the OAK-D README block: no host CUDA bind mount by default (add an override if you need `/usr/local/cuda-12.*` like the shell script).

**KITTI / other helper scripts** default to the Spark image tag; on Orin run with `CUVSLAM_DOCKER_TAG=pycuvslam:realsense-cu12` or `pycuvslam:orin-oakd` as appropriate (images from `run_cuvslam_docker_orin.sh` / `run_cuvslam_docker_orin_oakd.sh` builds).

## Quick start (DGX Spark)

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

## Image choice

| Host | Suggested image | Wrapper scripts |
|------|-----------------|-----------------|
| DGX Spark (aarch64, CUDA 13 / driver 580+) | `Dockerfile.realsense-cu13` | `build_docker_spark.sh`, `run_cuvslam_docker.sh` |
| Jetson Orin (L4T, CUDA 12.x) | `Dockerfile.realsense-cu12` | `build_docker_orin.sh`, `run_cuvslam_docker_orin.sh` |
| Jetson Orin + Luxonis OAK-D | `Dockerfile.orin-oakd` → `pycuvslam:orin-oakd` | `build_docker_orin_oakd.sh`, `run_cuvslam_docker_orin_oakd.sh` |
| Desktop x86_64, CUDA 12.6+ driver | `Dockerfile.realsense-cu12` | upstream `docker/run_docker.sh` or same Dockerfile with `docker build` |

The default upstream `run_docker.sh` uses the CUDA 12 path unless you pass `24` for the CUDA 13 path. This repo’s **Spark** entrypoints default to **CUDA 13**; **Orin** entrypoints use **CUDA 12** ( **`orin-oakd`** extends the cu12 image with **OAK-D** / **`depthai`** and Rerun gRPC defaults).

## Environment variables

| Variable | Meaning |
|----------|--------|
| `CUVSLAM_DIR` | Path to the cloned cuVSLAM tree (default: `<repo>/cuVSLAM`) |
| `CUVSLAM_DOCKER_TAG` | Image tag (Spark: `pycuvslam:realsense-cu13`; Orin: `pycuvslam:realsense-cu12`; Orin+OAK-D: `pycuvslam:orin-oakd`) |
| `CUVSLAM_DOCKERFILE` | Dockerfile path inside `CUVSLAM_DIR` (Spark default: `docker/Dockerfile.realsense-cu13`) |
| `NVIDIA_DISABLE_REQUIRE` | Orin run script: set to `1` (default) so L4T can start the CUDA 12.6 image; use `0` to enforce NVIDIA toolkit checks. |
| `RERUN_SERVE_GRPC` | Set to `1` to use Rerun **`serve_grpc`** (viewer on another machine); unset uses local `spawn` viewer. |
| `RERUN_GRPC_PORT` | gRPC port for `serve_grpc` (default `9876`). |
| `RERUN_SERVE_GRPC_HINT_IP` | Optional host reminder for the Mac `rerun rerun+http://…` URL. **`run_cuvslam_docker_orin_oakd.sh`** also auto-uses `tailscale ip -4` when this is unset and Tailscale is installed. |
| `DATASETS` / `DATASETS_DIR` | Dataset path for examples |

## NGC

Building uses public CUDA images on Docker Hub (`nvidia/cuda:13.0.0-devel-ubuntu24.04` for Spark, `nvidia/cuda:12.6.0-devel-ubuntu22.04` for Orin). NGC login is not required unless you switch to a private NGC image.

## License

The upstream **cuVSLAM** and **PyCuVSLAM** code is under NVIDIA’s license; see the [cuVSLAM repository](https://github.com/nvidia-isaac/cuVSLAM). This small wrapper repo only adds helper scripts and compose.
