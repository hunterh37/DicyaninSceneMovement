import Foundation
import simd

#if os(visionOS)
import RealityKit

/// Moves the scene root so the player appears to walk toward the pinched spot.
/// The world slides under the player at `walkSpeed` until `remainingShift` is
/// consumed. Pure ECS: state lives on `SceneMovementRootComponent`, this system
/// only integrates it each frame.
public struct PinchWalkSystem: System {
    static let query = EntityQuery(where: .has(SceneMovementRootComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        guard dt > 0 else { return }

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var root = entity.components[SceneMovementRootComponent.self] else { continue }
            guard root.mode == .pinchToWalk || root.mode == .tapToWalk,
                  var remaining = root.remainingShift else { continue }

            remaining.y = 0
            let dist = simd_length(remaining)
            if dist <= root.arriveRadius {
                root.remainingShift = nil
                entity.components.set(root)
                continue
            }

            let dir = remaining / dist
            let step = min(root.walkSpeed * dt, dist)
            entity.position += dir * step
            root.remainingShift = remaining - dir * step
            entity.components.set(root)
        }
    }
}
#endif
