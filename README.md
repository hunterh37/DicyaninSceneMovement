# DicyaninSceneMovement

Classic VR locomotion for visionOS immersive scenes, as a reusable Swift package.

Two modes:
- Laser Teleport: point a hand forward, a laser + reticle track the floor, pinch to teleport.
- Pinch to Walk: look at a spot, pinch to drop a glowing orb, and the whole scene slides around you so you walk there.

Movement is applied by translating a single scene root entity (never the camera, which the OS owns).

## Setup

```swift
import DicyaninSceneMovement

// once at launch
SceneMovementManager.registerSystems()

@StateObject private var movement = SceneMovementManager()

RealityView { content in
    let world = Entity()            // put your whole scene under this
    content.add(world)

    // mark floors as walkable (needs a CollisionComponent too)
    floor.components.set(TeleportSurfaceComponent())

    movement.attach(root: world, in: content)
    Task { await movement.start() }
}

// switch modes
SceneMovementModePicker(manager: movement)
```

Requires hand tracking + world sensing authorization in the immersive space.
