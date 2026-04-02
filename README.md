# RammpUI

Unreal Engine 5.7 project implementing the user interface for the **RAMMP**
(Robotic Autonomous Mobile Manipulation Platform) prototype. Provides real-time
RGBD camera streaming, 3D point cloud (PGM) visualization, robot teleoperation,
modular UI layouts, and a Python-scriptable control layer.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          RammpUI  (UE 5.7)                           │
│                                                                      │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  ┌─────────────┐  │
│  │  RammsCore  │  │CameraCapture │  │RammsAssets │  │  RammpUI    │  │
│  │             │  │              │  │            │  │  Module     │  │
│  │ Kinova Gen3 │  │ RGB / Depth  │  │ Meshes     │  │ Game logic  │  │
│  │ Wheelchair  │  │ Motion Vec   │  │ Materials  │  │ & maps      │  │
│  │ Gripper     │  │ Intrinsics   │  │ Textures   │  │             │  │
│  │ Sensors     │  │ Extrinsics   │  │            │  │             │  │
│  └──────┬──────┘  └──────┬───────┘  └────────────┘  └───────┬─────┘  │
│         │                │                                  │        │
│         │        ┌───────┴──────────────────────────────────┘        │
│         │        │                                                   │
│  ┌──────┴────────┴─────────────────────┐   ┌──────────────────────┐  │
│  │      RammsStreaming Plugin          │   │    RammsUI Plugin    │  │
│  │  RMSS binary protocol (TCP :30030)  │   │  Widgets · Camera    │  │
│  │  LZ4 / JPEG / PNG compression       │   │  PGM · Themes · HUD  │  │
│  │  Multi-channel subscription         │   │  Layout · EventBus   │  │
│  └──────────────┬──────────────────────┘   └──────────┬───────────┘  │
│                 │                                     │              │
├─────────────────┼─────────────────────────────────────┼──────────────┤
│  Remote Control │ API  (HTTP :30010 / WS :30020)      │              │
└─────────────────┼─────────────────────────────────────┼──────────────┘
                  │                                     │
        ┌─────────┴──────────┐              Operator tablet / desktop
        │   ramms-tools      │
        │   (Python)         │
        │  CLI / TUI / Lib   │
        └────────────────────┘
```

### Actor Hierarchy

The runtime scene is organized under a single top-level actor with four child
actors and several components:

```mermaid
flowchart TB
    MD["<b>BP_MobileDisplay</b><br/>(Level Actor)"]

    MD --> RD["<b>BP_RAMMP_RemoteDisplay</b><br/>Child Actor"]
    MD --> CD["<b>BP_CollisionDetection</b><br/>Child Actor"]
    MD --> MV["<b>BP_MobileViews</b><br/>Child Actor"]
    MD --> CP["<b>BP_CameraProjection</b><br/>Child Actor"]

    MD --- TurnRadius["Turning Radius<br/>Static Mesh"]
    MD --- OutlinePP["Outline Post Process<br/>(robot + turning radius)"]
    MD --- Sink["URammsStreamSink<br/>(TCP :30030)"]
    MD --- Bridge["URammsStreamCameraBridge"]
    MD --- ProjMgr["URammsCameraProjectionManager<br/>2D decal / 3D PGM"]

    RD -.- RCPS["Remote Control<br/>Preset (RCPS)"]
    RD -.- IRobot{{"IRammsRobotController"}}

    MV -.- VCams{{"BPI_VirtualCameras"}}
    VCams --- ZCam1["BP_Zoomable_Camera 1<br/>(BPI_Zoomable)"]
    VCams --- ZCam2["BP_Zoomable_Camera 2<br/>(BPI_Zoomable)"]
    VCams --- ZCamN["BP_Zoomable_Camera N<br/>(BPI_Zoomable)"]

    CP -.- PlanarMesh["Planar Projection<br/>Mesh"]
    CP -.- EllipMesh["Ellipsoidal Projection<br/>Mesh"]

    CD -.- ObstaclePP["Obstacle / Dropoff<br/>Post Process Material"]

    style MD fill:#4a90d9,color:#fff
    style RD fill:#5ba55b,color:#fff
    style CD fill:#c0392b,color:#fff
    style MV fill:#8e44ad,color:#fff
    style CP fill:#d4a017,color:#000
```

| Actor / Component | Role |
|---|---|
| **BP_MobileDisplay** | Top-level actor. Owns streaming components, projection manager, turning radius mesh, and outline post process. On BeginPlay: sets input mode (Game+UI), creates UI widgets (LayoutHost, layouts, pool), starts RMSS streaming server, binds UI subsystem events. |
| **BP_RAMMP_RemoteDisplay** | Implements `IRammsRobotController`. Registers with `URammsUISubsystem`, handles visualization/highlighting events, and emits state changes when the RCPS is updated by the Python ROS↔UE bridge. |
| **BP_CollisionDetection** | Listens for `ObstacleHeightChanged`, `DropoffDepthChanged`, `VisualizationLayerToggle`, and `HighlightChanged` events. Configures a post process material that colors objects above the obstacle height or below the dropoff depth. |
| **BP_MobileViews** | Implements `BPI_VirtualCameras`. Defines scene cameras (`BP_Zoomable_Camera` actors implementing `BPI_Zoomable`) and provides switching between them. |
| **BP_CameraProjection** | Listens for `PlanarProjectionEnabled` and `EllipsoidalProjectionEnabled` custom UI events. Contains the meshes onto which 2D image decals are projected. |

### Robot ↔ UI Data Flow

Two communication channels connect the physical robot to the Unreal Engine
interface: the **Remote Control Preset** (RCPS) for bidirectional command and
state data, and the **RMSS streaming protocol** for camera data.

```mermaid
flowchart LR
    subgraph Robot["Physical Robot"]
        Arm["Kinova Gen3<br/>Arm"]
        Base["Wheelchair<br/>Base"]
        Cameras["RGBD<br/>Cameras"]
        Sensors["IMU / Bumpers<br/>/ E-Stop"]
    end

    subgraph PythonBridge["Python ROS ↔ UE Bridge"]
        ROS["ROS 2<br/>Topics / Services"]
        RC_Client["Remote Control<br/>Client"]
        StreamClient["RMSS Stream<br/>Client"]
    end

    subgraph UE["Unreal Engine"]
        subgraph CommandPath["Command & State Path"]
            RCWS["Remote Control<br/>WebSocket :30020"]
            RCPS["Remote Control<br/>Preset (RCPS)"]
            RemoteDisp["BP_RAMMP_RemoteDisplay<br/>(IRammsRobotController)"]
            Subsystem["URammsUISubsystem<br/>Events · Properties · State"]
            UIWidgets["UI Widgets<br/>(Arm, Mebot, Status, etc.)"]
        end

        subgraph CameraPath["Camera Data Path"]
            RMSS["RMSS Server<br/>TCP :30030"]
            SinkComp["URammsStreamSink"]
            BridgeComp["URammsStreamCameraBridge"]
            Provider["Camera Provider"]
            CamWidget["URammsCameraWidget"]
            ProjMgr["URammsCameraProjectionManager"]
        end
    end

    %% Robot to Python
    Arm <-->|"joint states /<br/>commands"| ROS
    Base <-->|"velocity /<br/>odometry"| ROS
    Sensors -->|"telemetry"| ROS
    Cameras -->|"RGBD frames"| ROS

    %% Python to UE — commands/state
    ROS <--> RC_Client
    RC_Client <-->|"HTTP / WS"| RCWS
    RCWS <--> RCPS
    RCPS <--> RemoteDisp
    RemoteDisp <-->|"register /<br/>events"| Subsystem
    Subsystem <--> UIWidgets

    %% Python to UE — camera
    ROS --> StreamClient
    StreamClient -->|"LZ4 / JPEG /<br/>PNG frames"| RMSS
    RMSS --> SinkComp
    SinkComp --> BridgeComp
    BridgeComp --> Provider
    Provider --> CamWidget
    Provider --> ProjMgr

    style Robot fill:#2c3e50,color:#fff
    style PythonBridge fill:#1a5276,color:#fff
    style CommandPath fill:#1e8449,color:#fff
    style CameraPath fill:#6c3483,color:#fff
```

| Path | Protocol | Direction | Data |
|------|----------|-----------|------|
| **Command & State** | UE Remote Control (HTTP :30010 / WS :30020) | Bidirectional | Joint targets, velocities, gripper commands, mode changes, e-stop, battery, robot state |
| **Camera Streams** | RMSS binary (TCP :30030) | Robot → UE | Color frames, depth frames, camera intrinsics, camera extrinsics, image masks |

### UI Event Architecture

The `URammsUISubsystem` event bus drives communication between actors and
widgets. Events are either built-in typed delegates or custom string-keyed
events with struct payloads.

```mermaid
flowchart TB
    subgraph EventBus["URammsUISubsystem — Event Bus"]
        VizToggle["VisualizationLayerToggle<br/>(FName Layer, bool)"]
        Highlight["HighlightChanged<br/>(FName Target, FLinearColor)"]
        StateBC["OnRobotStateChanged<br/>(FRammsRobotState)"]
        PropChanged["OnPropertyChanged<br/>(FName Key, Value)"]
        CustomEvt["OnCustomUIEvent<br/>(FName EventName, Payload)"]
    end

    subgraph CustomEvents["Custom UI Events (string-keyed)"]
        Evt3D["3DProjectionEnabled<br/>(bool)"]
        EvtPlanar["PlanarProjectionEnabled<br/>(bool)"]
        EvtEllip["EllipsoidalProjectionEnabled<br/>(bool)"]
        EvtObst["ObstacleHeightChanged<br/>(float)"]
        EvtDrop["DropoffDepthChanged<br/>(float)"]
    end

    subgraph Emitters["Event Emitters"]
        RemDisp["BP_RAMMP_RemoteDisplay<br/>(RCPS updates)"]
        Widgets["UI Widgets<br/>(user interaction)"]
    end

    subgraph Listeners["Event Listeners"]
        RemDisp2["BP_RAMMP_RemoteDisplay"]
        CollDet["BP_CollisionDetection"]
        CamProj["BP_CameraProjection"]
        MobDisp["BP_MobileDisplay"]
        ProjMgr2["ProjectionManager"]
        AllWidgets["All Themed Widgets"]
    end

    %% Emitters fire events
    RemDisp -->|"state updates"| StateBC
    RemDisp -->|"property updates"| PropChanged
    Widgets -->|"user commands"| CustomEvt
    Widgets -->|"toggle layers"| VizToggle
    Widgets -->|"set highlight"| Highlight

    %% Custom events
    CustomEvt --- Evt3D
    CustomEvt --- EvtPlanar
    CustomEvt --- EvtEllip
    CustomEvt --- EvtObst
    CustomEvt --- EvtDrop

    %% Listeners subscribe
    VizToggle -->|"collision zones"| MobDisp
    VizToggle -->|"obstacle / dropoff layers"| CollDet
    Highlight -->|"chair outline color"| MobDisp
    Highlight -->|"obstacle highlighting"| CollDet
    StateBC --> AllWidgets

    Evt3D -->|"switch 2D↔3D"| ProjMgr2
    EvtPlanar --> CamProj
    EvtEllip --> CamProj
    EvtObst --> CollDet
    EvtDrop --> CollDet
    Highlight --> RemDisp2

    style EventBus fill:#2c3e50,color:#fff
    style CustomEvents fill:#1a5276,color:#fff
    style Emitters fill:#1e8449,color:#fff
    style Listeners fill:#6c3483,color:#fff
```

| Event | Emitter(s) | Listener(s) | Purpose |
|-------|-----------|-------------|---------|
| `VisualizationLayerToggle` | Toolbar / UI widgets | BP_MobileDisplay (turning radius), BP_CollisionDetection (obstacle/dropoff layers) | Toggle visibility of 3D visualization overlays |
| `HighlightChanged` | Toolbar / UI widgets | BP_MobileDisplay (chair outline), BP_CollisionDetection, BP_RAMMP_RemoteDisplay | Change highlight colors on robot meshes and overlays |
| `OnRobotStateChanged` | BP_RAMMP_RemoteDisplay | Status panel, arm/mebot controllers, all subscribed widgets | Broadcast updated robot telemetry (speed, battery, mode, joint states) |
| `OnPropertyChanged` | BP_RAMMP_RemoteDisplay | Any widget observing a specific key | Notify that a key-value property in the store was modified |
| `3DProjectionEnabled` | UI toggle | ProjectionManager | Switch between 2D decal and 3D PGM camera projection |
| `PlanarProjectionEnabled` | UI toggle | BP_CameraProjection | Enable/disable planar decal projection mesh |
| `EllipsoidalProjectionEnabled` | UI toggle | BP_CameraProjection | Enable/disable ellipsoidal decal projection mesh |
| `ObstacleHeightChanged` | UI slider | BP_CollisionDetection | Adjust height threshold for obstacle coloring |
| `DropoffDepthChanged` | UI slider | BP_CollisionDetection | Adjust depth threshold for dropoff coloring |

## Plugins

All plugins are **git submodules**. Clone with `--recurse-submodules` or run
`git submodule update --init --recursive` after cloning.

| Plugin | Purpose |
|--------|---------|
| **RammsUI** | UI widgets, camera widget, projection/PGM, styling, event bus, robot command dispatch, layout management, orientation support, themes |
| **RammsStreaming** | TCP-based RMSS binary streaming protocol, streaming subsystem, source/sink components |
| **RammsCore** | Robot-specific components — skeletal pose, kinematic chains, Kinova Gen3 controller, wheelchair, gripper |
| **CameraCapture** | UE scene capture → streaming bridge (RGB, depth, motion vectors, intrinsics/extrinsics) |
| **RammsAssets** | Shared meshes, materials, and textures used across the project |

### Plugin Dependency Chain

```
RammsUI ──→ RammsStreaming ──→ CameraCapture
  │
  └─ (uses) RammsCore, RammsAssets
```

## Key Features

### 1. Camera System
Multi-camera provider architecture with a streaming bridge. Display modes
include Fullscreen, Windowed, and Corner overlay. The camera widget maintains
aspect ratio automatically and switches between live simulation feeds and
external RGBD streams. Streams are associated via metadata-driven GroupID and
Role tags, enabling automatic depth-to-color stream linking and format-aware
depth scaling.

### 2. 3D Projection (PGM)
GPU-accelerated depth-to-3D mesh reconstruction via World Position Offset
materials and the `RammsPGM.ush` shader. A CPU fallback path is available for
platforms without compute shader support. Depth frames from the streaming
pipeline drive real-time point cloud visualization projected into world space.

### 3. Layout System
Orientation-aware layout host with crossfade transitions between arrangements.
Widgets are managed through a pool and reparented on layout change. Portrait
and landscape modes are auto-detected, enabling tablet-friendly operation.

### 4. Theme System
Subsystem-driven runtime theme switching. Ships with dark and light built-in
themes; custom themes can be authored as `UDataAsset` instances and hot-swapped
at runtime without restarting the application.

### 5. Robot Control
Interface-based command dispatch decouples the UI from specific robot hardware.
Includes status panels, arm and base controllers, and a virtual joystick widget
for direct teleoperation.

### 6. Event Bus
`URammsUISubsystem` provides typed events, custom events with struct payloads,
a key-value property store, and state broadcast notifications. All UI modules
communicate through this central bus rather than direct references.

### 7. Streaming Protocol (RMSS)
Bidirectional binary protocol over TCP with LZ4, JPEG, and PNG compression
options. Supports multi-channel subscription so clients can selectively receive
camera, depth, or sensor channels without excess bandwidth.

## Network Ports

| Service | Port | Protocol |
|---------|------|----------|
| UE Remote Control HTTP | 30010 | REST API |
| UE Remote Control WebSocket | 30020 | WebSocket |
| RMSS Binary Streaming | 30030 | Custom TCP |

## Getting Started

### Prerequisites

- **Unreal Engine 5.7** (source or launcher build)
- **Visual Studio 2022** with C++ game development workload
- **Python ≥ 3.10** (optional — for external tools via [ramms-tools](https://github.com/atdev-inc/ramms-tools))

### Clone & Build

```bash
git clone --recurse-submodules git@github.com:atdev-inc/rammp-ui.git
```

Open `RammpUI.uproject` in UE 5.7 Editor, or generate project files manually:

```bash
# Windows — generate VS solution
"C:\Program Files\Epic Games\UE_5.7\Engine\Build\BatchFiles\GenerateProjectFiles.bat" RammpUI.uproject
```

Then open `RammpUI.sln` in Visual Studio and build (Development Editor).

### First Run

1. Open the project in UE Editor
2. The default map (`Map_UI`) loads automatically
3. Remote Control API plugin is enabled by default
4. Press **Play** — the RMSS streaming server starts on port 30030

## Project Structure

```
RammpUI/
├── Source/RammpUI/          # Project-level C++ game module (minimal)
├── Content/                 # Blueprint assets, levels, UI maps
│   └── Maps/Map_UI          # Default UI map
├── Config/                  # UE project settings
├── Plugins/
│   ├── RammsUI/             # UI plugin (main) — widgets, camera, PGM, themes
│   ├── RammsStreaming/      # RMSS binary streaming protocol
│   ├── RammsCore/           # Robot components (arm, wheelchair, gripper)
│   ├── CameraCapture/       # Scene capture → streaming bridge
│   └── RammsAssets/         # Shared meshes, materials, textures
├── Scripts/                 # Standalone Python utilities
│   ├── send_notification.py # Push notifications via Remote Control API
│   └── set_status.py        # Update status panel via Remote Control API
├── RammpUI.uproject         # UE project descriptor
└── RammpUI.sln              # Visual Studio solution
```

## Camera & Streaming Pipeline

Two camera data paths are supported. See the **Robot ↔ UI Data Flow** diagram
above for the full end-to-end picture.

**Live simulation cameras** (within UE):
```
SceneCaptureComponent2D → CameraCapture → StreamSourceComponent → RMSS server
                                                                       ↓
                         RammsCameraWidget ← CameraProvider ← StreamSinkComponent
```

**External camera replay** (Robot → Python → UE):
```
Robot RGBD cameras → ROS 2 → Python bridge → RMSS TCP :30030
                                                     ↓
                               StreamSinkComponent → StreamCameraBridge
                                                          ↓
                                    CameraProvider → RammsCameraWidget
                                                          ↓
                     ProjectionManager → 2D Decal / 3D PGM projectors
```

The `StreamCameraBridge` is demand-driven: it only produces CPU-side raw data
when a subscriber explicitly requests it (e.g., CPU PGM mode). GPU subscribers
(camera widget, GPU PGM) receive texture references directly without readback.

**Stream associations:** Streams are grouped by `GroupID` metadata and tagged
with roles (`color`, `depth`, `mask`, `infrared`). The `StreamCameraBridge`
tracks a persistent channel→stream_id mapping and re-registers streams when the
sender's `stream_id` metadata override changes. The projection manager uses
GroupID+Role matching to automatically link depth streams to their corresponding
color projectors and apply appropriate depth format scaling.

## Python Tools

Install [ramms-tools](https://github.com/atdev-inc/ramms-tools) for external
streaming clients, control, and monitoring:

```bash
pip install -e path/to/ramms-tools          # Core library + CLI
pip install -e 'path/to/ramms-tools[all]'   # + TUI + compression + EXR support
```

Connect to RMSS port **30030** for frame streaming. Key commands:

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

## License

MIT — see [LICENSE](LICENSE) for details.
