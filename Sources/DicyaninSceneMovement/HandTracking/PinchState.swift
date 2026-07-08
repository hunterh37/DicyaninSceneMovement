import Foundation
import simd

#if os(visionOS)
import ARKit

/// A single hand's tracked ray + pinch state for this frame.
public struct HandRayState: Sendable {
    public enum Chirality: Sendable { case left, right }
    public var chirality: Chirality
    /// World space origin of the pointing ray (index finger tip).
    public var origin: SIMD3<Float>
    /// World space normalized pointing direction (knuckle -> tip).
    public var direction: SIMD3<Float>
    /// Normalized 0...1 pinch amount (1 = fully pinched).
    public var pinch: Float
    public var isTracked: Bool

    public init(chirality: Chirality, origin: SIMD3<Float>, direction: SIMD3<Float>, pinch: Float, isTracked: Bool) {
        self.chirality = chirality
        self.origin = origin
        self.direction = direction
        self.pinch = pinch
        self.isTracked = isTracked
    }
}

/// Rising / falling edge detector for a pinch, with hysteresis so a held pinch
/// only fires once.
public struct PinchEdgeDetector: Sendable {
    private var engaged = false
    private let onThreshold: Float
    private let offThreshold: Float

    public init(onThreshold: Float = 0.85, offThreshold: Float = 0.6) {
        self.onThreshold = onThreshold
        self.offThreshold = offThreshold
    }

    /// Returns true on the frame the pinch first crosses the on threshold.
    public mutating func update(pinch: Float) -> Bool {
        if engaged {
            if pinch < offThreshold { engaged = false }
            return false
        } else {
            if pinch > onThreshold {
                engaged = true
                return true
            }
            return false
        }
    }

    public var isEngaged: Bool { engaged }
}

enum HandRayMath {
    /// Builds a pointing ray + pinch amount from an ARKit hand skeleton.
    static func rayState(from anchor: HandAnchor) -> HandRayState? {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            return HandRayState(
                chirality: anchor.chirality == .left ? .left : .right,
                origin: .zero, direction: SIMD3<Float>(0, 0, -1), pinch: 0, isTracked: false
            )
        }
        let base = anchor.originFromAnchorTransform

        func world(_ joint: HandSkeleton.JointName) -> SIMD3<Float> {
            let m = base * skeleton.joint(joint).anchorFromJointTransform
            return SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }

        let indexTip = world(.indexFingerTip)
        let indexKnuckle = world(.indexFingerKnuckle)
        let thumbTip = world(.thumbTip)

        var dir = indexTip - indexKnuckle
        let len = simd_length(dir)
        dir = len > 1e-5 ? dir / len : SIMD3<Float>(0, 0, -1)

        // Pinch: thumb tip to index tip distance mapped to 0...1 (2cm..7cm).
        let d = simd_length(thumbTip - indexTip)
        let pinch = simd_clamp((0.07 - d) / (0.07 - 0.02), 0, 1)

        return HandRayState(
            chirality: anchor.chirality == .left ? .left : .right,
            origin: indexTip, direction: dir, pinch: pinch, isTracked: true
        )
    }
}
#endif
