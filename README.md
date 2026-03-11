# RammpUI

Unreal Engine 5.7 project implementing the user interface and simulation
environment for the **RAMMP** (Robotic Assistive Mobility and Manipulation
Platform) prototypes. Provides real-time robot control, multi-camera
visualization, sensor streaming, and a Python-scriptable control layer.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RammpUI  (UE 5.7)                           │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐  │
│  │  RammsCore   │  │CameraCapture │  │       RammpUI Module      │  │
│  │  (Submodule) │  │ (Submodule)  │  │   Game logic & maps       │  │
│  │              │  │              │  └───────────────────────────┘  │
│  │ Wheelchair   │  │ RGB / Depth  │                                 │
│  │ Kinova Arm   │  │ Motion Vec   │  ┌───────────────────────────┐  │
│  │ Gripper      │  │ Intrinsics   │  │        RammsUI Plugin     │  │
│  │ Sensors      │  │ Extrinsics   │  │   Widgets, Camera, HUD    │  │
│  └──────┬───────┘  └──────┬───────┘  └─────────────┬─────────────┘  │
│         │                 │                        │                │
│         │        ┌────────┴────────────────────────┘                │
│         │        │                                                  │
│  ┌──────┴────────┴──────────────────┐                               │
│  │      RammsStreaming Plugin       │                               │
│  │  RMSS binary protocol (TCP)      │                               │
│  │  Port 30030                      │                               │
│  └──────────────┬───────────────────┘                               │
│                 │                                                   │
├─────────────────┼───────────────────────────────────────────────────┤
│  Remote Control │ API  (HTTP :30010 / WS :30020)                    │
└─────────────────┼───────────────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┐
        │   ramms-tools      │
        │   (Python)         │
        │                    │
        │  CLI / TUI / Lib   │
        └────────────────────┘
```

## Plugins

All plugins are **git submodules** — clone with `--recurse-submodules` or run
`git submodule update --init --recursive` after cloning.

| Plugin | Repo | Description |
|--------|------|-------------|
| **RammsCore** | `atdev-inc/ramms-core` | Powered wheelchair, Kinova Gen3 arm, gripper, and sensor simulation |
| **RammsUI** | `atdev-inc/ramms-ui` | UI widgets (camera, arm, mebot, status), camera projection, Remote Control bridge |
| **RammsStreaming** | `atdev-inc/ramms-streaming` | Bidirectional binary streaming (RMSS protocol) for camera/sensor data over TCP |
| **CameraCapture** | `finger563/unreal-camera-capture` | Multi-camera capture (RGB, depth, motion vectors) with metadata serialization |

### Plugin Dependency Graph

```
RammsUI ──→ RammsStreaming ──→ CameraCapture
```

## Port Assignments

| Service | Port | Protocol |
|---------|------|----------|
| UE Remote Control HTTP | 30010 | REST API |
| UE Remote Control WebSocket | 30020 | WebSocket |
| RMSS Binary Streaming | 30030 | Custom TCP |

## Getting Started

### Prerequisites

- **Unreal Engine 5.7** (source or launcher build)
- **Visual Studio 2022** with C++ game development workload
- **Python ≥ 3.10** (for external tools — see [ramms-tools](https://github.com/atdev-inc/ramms-tools))

### Clone & Build

```bash
git clone --recurse-submodules git@github.com:atdev-inc/rammp-ui.git
```

Open `RammpUI.uproject` in UE 5.7 Editor or generate project files:

```bash
# Windows — generate VS solution
"C:\Program Files\Epic Games\UE_5.7\Engine\Build\BatchFiles\GenerateProjectFiles.bat" RammpUI.uproject
```

Then open `RammpUI.sln` in Visual Studio and build (Development Editor).

### First Run

1. Open the project in UE Editor
2. The default map (`Map_UI`) loads automatically
3. Enable **Remote Control API** plugin (enabled by default in this project)
4. Press **Play** to start PIE — the RMSS streaming server starts automatically on port 30030

### Python Tools

Install [ramms-tools](https://github.com/atdev-inc/ramms-tools) for external
control, monitoring, and testing:

```bash
pip install -e path/to/ramms-tools          # Core library + CLI
pip install -e 'path/to/ramms-tools[all]'   # + TUI + compression + EXR support
```

Key tools:

| Command | Description |
|---------|-------------|
| `ramms-tui` | Interactive terminal dashboard (arm, mebot, IMU, streaming) |
| `ramms-kinova` | Kinova Gen3 arm control CLI |
| `ramms-gripper` | Gripper control CLI |
| `ramms-mebot` | Mebot motor control CLI |
| `ramms-imu` | IMU data streaming with coordinate frame transforms |
| `ramms-stream` | RMSS stream monitor (FPS, bandwidth, dropped frames) |
| `ramms-stream-test` | Send synthetic or captured camera frames to UE |
| `ramms-notify` | Push UI notifications |
| `ramms-status` | Update status panel (battery, speed, mode, e-stop) |

## Project Structure

```
RammpUI/
├── Config/                  # UE project configuration
├── Content/                 # Assets, maps, blueprints
│   └── Maps/Map_UI          # Default UI map
├── Plugins/
│   ├── CameraCapture/       # Multi-camera data capture
│   ├── RammsCore/           # Robot simulation (wheelchair, arm, gripper)
│   ├── RammsStreaming/      # RMSS binary streaming protocol
│   └── RammsUI/             # UI widgets & camera pipeline
├── Scripts/                 # Standalone Python utilities
│   ├── send_notification.py # Push notifications via Remote Control API
│   └── set_status.py        # Update status panel via Remote Control API
├── Source/RammpUI/          # Project game module
├── RammpUI.uproject         # UE project descriptor
└── RammpUI.sln              # Visual Studio solution
```

## Camera & Streaming Pipeline

The system supports two camera data paths:

**Live simulation cameras** (within UE):
```
SceneCaptureComponent2D → CameraCapture → RammsStreamSourceComponent → RMSS server
                                                                           ↓
                          RammsCameraWidget ← CameraProviderComponent ← StreamSinkComponent
```

**External camera replay** (Python → UE):
```
ramms-stream-test → TCP :30030 → StreamSinkComponent → StreamCameraBridge
                                                              ↓
                                          CameraProviderComponent → RammsCameraWidget
                                                              ↓
                                          ProjectionManager → Decal projectors (world-space)
```

## License

MIT — see [LICENSE](LICENSE) for details.
