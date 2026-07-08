import Foundation
import simd

#if os(visionOS)
import RealityKit

/// Movement modes exposed by the package.
public enum SceneMovementMode: Sendable, Equatable {
    /// Nothing tracked, no laser, no walking.
    case off
    /// Classic VR laser: point a hand forward, pinch to teleport to the hit point.
    case laserTeleport
    /// Look somewhere, pinch to drop an orb, then the scene slides so you "walk" there.
    case pinchToWalk
    /// Tap a spot in the scene (SwiftUI SpatialTapGesture) to walk there. No hands
    /// or gaze needed; the host drives the destination via `walk(to:)`.
    case tapToWalk
}

/// Attach to the single entity that holds the whole movable world. Teleport and
/// walk translate this entity's transform (never the camera, which the OS owns).
public struct SceneMovementRootComponent: Component {
    public var mode: SceneMovementMode = .off
    /// Metres per second for pinch to walk.
    public var walkSpeed: Float = 1.6
    /// Player is considered "arrived" within this XZ distance of the target.
    public var arriveRadius: Float = 0.2
    /// World space ground position of the player (device projected to y = groundY).
    /// Updated every frame by the manager from the device anchor.
    public var playerGroundPosition: SIMD3<Float> = .zero
    /// Ground plane height in world space used for teleport / walk targets.
    public var groundY: Float = 0
    /// Remaining world space translation to apply to the root to reach the walk
    /// destination. nil when not walking. XZ only (y forced to 0).
    public var remainingShift: SIMD3<Float>?

    public init() {}
}

/// Marks an entity as a valid teleport / walk surface. Only hits against entities
/// carrying this component (or their ancestors) count. Requires a CollisionComponent.
public struct TeleportSurfaceComponent: Component {
    public init() {}
}
#endif
