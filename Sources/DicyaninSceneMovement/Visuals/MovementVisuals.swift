import Foundation
import simd

#if os(visionOS)
import RealityKit
import UIKit

/// Factory helpers for the laser beam, teleport reticle, and walk orb. All are
/// plain entities so callers can restyle or replace them.
public enum MovementVisuals {

    public static func makeLaser(color: UIColor = .cyan) -> ModelEntity {
        // Unit length beam along -Z, scaled per frame by the system.
        let mesh = MeshResource.generateBox(width: 0.006, height: 0.006, depth: 1.0)
        var mat = UnlitMaterial(color: color.withAlphaComponent(0.85))
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = "SceneMovement.Laser"
        e.components.set(OpacityComponent(opacity: 0))
        return e
    }

    public static func makeReticle(color: UIColor = .cyan) -> ModelEntity {
        let mesh = MeshResource.generateCylinder(height: 0.004, radius: 0.18)
        var mat = UnlitMaterial(color: color.withAlphaComponent(0.5))
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = "SceneMovement.Reticle"
        e.components.set(OpacityComponent(opacity: 0))
        return e
    }

    public static func makeWalkOrb(color: UIColor = .systemTeal) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.06)
        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = "SceneMovement.WalkOrb"
        e.components.set(OpacityComponent(opacity: 0))
        // Soft glow via a larger faint halo child.
        let halo = ModelEntity(
            mesh: .generateSphere(radius: 0.11),
            materials: [UnlitMaterial(color: color.withAlphaComponent(0.18))]
        )
        halo.components.set(OpacityComponent(opacity: 0.4))
        e.addChild(halo)
        return e
    }
}
#endif
