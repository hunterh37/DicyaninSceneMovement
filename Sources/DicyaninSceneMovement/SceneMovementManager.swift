import Foundation
import simd

#if os(visionOS)
import ARKit
import Combine
import RealityKit
import SwiftUI

/// Drop-in classic VR locomotion for a visionOS immersive scene.
///
/// Usage:
/// 1. `SceneMovementManager.registerSystems()` once at launch.
/// 2. Build your world under a single root entity, call `attach(root:in:)`.
/// 3. Mark floors with `TeleportSurfaceComponent` + a `CollisionComponent`.
/// 4. `await manager.start()` inside the immersive space, set `mode`.
@MainActor
public final class SceneMovementManager: ObservableObject {

    @Published public var mode: SceneMovementMode = .off {
        didSet { syncModeToRoot(); refreshVisualVisibility() }
    }

    public var walkSpeed: Float = 1.6 { didSet { mutateRoot { $0.walkSpeed = walkSpeed } } }
    public var groundY: Float = 0 { didSet { mutateRoot { $0.groundY = groundY } } }
    /// Which hand drives the laser. Pinch-to-walk always uses gaze.
    public var laserHand: HandRayState.Chirality = .right

    private let session = ARKitSession()
    private let handProvider = HandTrackingProvider()
    private let worldProvider = WorldTrackingProvider()

    private weak var root: Entity?
    private weak var scene: RealityKit.Scene?

    private let laser = MovementVisuals.makeLaser()
    private let reticle = MovementVisuals.makeReticle()
    private let orb = MovementVisuals.makeWalkOrb()

    private var latestHands: [HandRayState.Chirality: HandRayState] = [:]
    private var laserPinch = PinchEdgeDetector()
    private var gazePinch = PinchEdgeDetector()
    private var updateSub: (any Cancellable)?
    private var running = false

    public init() {}

    /// Registers the ECS system + components. Call once before opening the scene.
    public static func registerSystems() {
        SceneMovementRootComponent.registerComponent()
        TeleportSurfaceComponent.registerComponent()
        PinchWalkSystem.registerSystem()
    }

    /// Attaches the manager to the movable world root and its scene, and installs
    /// the laser / reticle / orb visuals under `visualParent` (defaults to root's parent).
    public func attach(root: Entity, in content: RealityViewContent, visualParent: Entity? = nil) {
        self.root = root
        self.scene = root.scene

        var comp = root.components[SceneMovementRootComponent.self] ?? SceneMovementRootComponent()
        comp.mode = mode
        comp.walkSpeed = walkSpeed
        comp.groundY = groundY
        root.components.set(comp)

        let host = visualParent ?? root.parent
        if let host {
            host.addChild(laser)
            host.addChild(reticle)
            host.addChild(orb)
        } else {
            content.add(laser); content.add(reticle); content.add(orb)
        }
        refreshVisualVisibility()

        guard let scene else { return }
        updateSub = scene.subscribe(to: SceneEvents.Update.self) { [weak self] (_: SceneEvents.Update) in
            guard let self else { return }
            MainActor.assumeIsolated { self.onFrame() }
        }
    }

    /// Starts ARKit hand + world tracking. Call from a task in the immersive space.
    public func start() async {
        guard !running else { return }
        running = true

        var providers: [any DataProvider] = [worldProvider]
        #if !targetEnvironment(simulator)
        if HandTrackingProvider.isSupported {
            providers.append(handProvider)
        }
        #endif

        do {
            try await session.run(providers)
        } catch {
            running = false
            return
        }

        #if !targetEnvironment(simulator)
        guard HandTrackingProvider.isSupported else { return }
        Task { [weak self] in
            guard let self else { return }
            for await update in self.handProvider.anchorUpdates {
                await self.ingest(update.anchor)
            }
        }
        #endif
    }

    public func stop() {
        running = false
        session.stop()
        updateSub = nil
    }

    // MARK: - Hand ingest

    private func ingest(_ anchor: HandAnchor) {
        guard let state = HandRayMath.rayState(from: anchor) else { return }
        latestHands[state.chirality] = state
    }

    // MARK: - Per frame

    private func onFrame() {
        guard let root, running else { return }
        updatePlayerGround()

        switch mode {
        case .off:
            hideAll()
        case .laserTeleport:
            hideOrb()
            updateLaserTeleport(root: root)
        case .pinchToWalk:
            hideLaser()
            updatePinchToWalk(root: root)
        case .tapToWalk:
            hideLaser()
            updateTapToWalk()
        }
    }

    private func updateTapToWalk() {
        // Destination is driven externally via `walk(to:)`. Hide the orb once the
        // walk completes (remainingShift consumed by PinchWalkSystem).
        if currentRoot()?.remainingShift == nil {
            hideOrb()
        }
    }

    private func updatePlayerGround() {
        guard let root else { return }
        guard let device = worldProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let m = device.originFromAnchorTransform
        let pos = SIMD3<Float>(m.columns.3.x, groundY, m.columns.3.z)
        mutateRoot { $0.playerGroundPosition = pos }
        _ = root
    }

    private func deviceForward() -> (origin: SIMD3<Float>, dir: SIMD3<Float>)? {
        guard let device = worldProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return nil }
        let m = device.originFromAnchorTransform
        let origin = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let fwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        return (origin, simd_normalize(fwd))
    }

    // MARK: - Modes

    private func updateLaserTeleport(root: Entity) {
        guard let hand = latestHands[laserHand], hand.isTracked else { hideLaser(); return }
        let hit = raycastSurface(origin: hand.origin, direction: hand.direction)
        drawLaser(origin: hand.origin, direction: hand.direction, hit: hit?.position)

        let pinched = laserPinch.update(pinch: hand.pinch)
        if pinched, let hit {
            teleport(root: root, to: hit.position)
        }
    }

    private func updatePinchToWalk(root: Entity) {
        guard let gaze = deviceForward() else { hideOrb(); return }
        let hit = raycastSurface(origin: gaze.origin, direction: gaze.dir)
        if let hit {
            setOrb(visible: true, at: hit.position)
        } else {
            setOrb(visible: false, at: .zero)
        }

        // Any tracked hand pinch confirms the gaze target.
        let pinch = max(latestHands[.left]?.pinch ?? 0, latestHands[.right]?.pinch ?? 0)
        let confirmed = gazePinch.update(pinch: pinch)
        if confirmed, let hit {
            beginWalk(root: root, to: hit.position)
        }
    }

    // MARK: - Actions

    private func teleport(root: Entity, to worldPoint: SIMD3<Float>) {
        let player = currentRoot()?.playerGroundPosition ?? .zero
        var shift = player - SIMD3<Float>(worldPoint.x, player.y, worldPoint.z)
        shift.y = 0
        root.position += shift
        mutateRoot {
            $0.playerGroundPosition += SIMD3<Float>(0, 0, 0) // player stays; world moved
            $0.remainingShift = nil
        }
    }

    private func beginWalk(root: Entity, to worldPoint: SIMD3<Float>) {
        let player = currentRoot()?.playerGroundPosition ?? .zero
        var shift = player - SIMD3<Float>(worldPoint.x, player.y, worldPoint.z)
        shift.y = 0
        mutateRoot { $0.remainingShift = shift }
    }

    // MARK: - Public tap-driven API

    /// True while a walk mode is active (gaze or tap driven).
    public var isWalkActive: Bool { mode == .pinchToWalk || mode == .tapToWalk }

    /// Walks the player to a world-space point (typically a SwiftUI
    /// `SpatialTapGesture` hit converted to `.scene` space). Drops the glowing orb
    /// marker there and slides the scene over until the player arrives. No-op
    /// unless a walk mode is active.
    public func walk(to worldPoint: SIMD3<Float>) {
        guard isWalkActive, let root else { return }
        beginWalk(root: root, to: worldPoint)
        setOrb(visible: true, at: worldPoint)
    }

    // MARK: - Raycast

    private struct SurfaceHit { var position: SIMD3<Float> }

    private func raycastSurface(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SurfaceHit? {
        guard let scene else { return nil }
        let results = scene.raycast(origin: origin, direction: direction, length: 30, query: .nearest)
        for r in results where hasSurface(r.entity) {
            return SurfaceHit(position: r.position)
        }
        return nil
    }

    private func hasSurface(_ entity: Entity) -> Bool {
        var e: Entity? = entity
        while let cur = e {
            if cur.components.has(TeleportSurfaceComponent.self) { return true }
            e = cur.parent
        }
        return false
    }

    // MARK: - Visuals

    private func drawLaser(origin: SIMD3<Float>, direction: SIMD3<Float>, hit: SIMD3<Float>?) {
        let end = hit ?? (origin + direction * 8)
        let mid = (origin + end) / 2
        let length = max(simd_length(end - origin), 0.001)
        laser.position = mid
        laser.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(end - origin))
        laser.scale = SIMD3<Float>(1, 1, length)
        laser.components.set(OpacityComponent(opacity: 1))

        if let hit {
            reticle.position = hit + SIMD3<Float>(0, 0.003, 0)
            reticle.components.set(OpacityComponent(opacity: 1))
        } else {
            reticle.components.set(OpacityComponent(opacity: 0))
        }
    }

    private func setOrb(visible: Bool, at position: SIMD3<Float>) {
        if visible {
            orb.position = position + SIMD3<Float>(0, 0.06, 0)
            orb.components.set(OpacityComponent(opacity: 1))
        } else {
            orb.components.set(OpacityComponent(opacity: 0))
        }
    }

    private func hideLaser() {
        laser.components.set(OpacityComponent(opacity: 0))
        reticle.components.set(OpacityComponent(opacity: 0))
    }
    private func hideOrb() { orb.components.set(OpacityComponent(opacity: 0)) }
    private func hideAll() { hideLaser(); hideOrb() }
    private func refreshVisualVisibility() { if mode == .off { hideAll() } }

    // MARK: - Root helpers

    private func currentRoot() -> SceneMovementRootComponent? {
        root?.components[SceneMovementRootComponent.self]
    }
    private func mutateRoot(_ body: (inout SceneMovementRootComponent) -> Void) {
        guard let root, var c = root.components[SceneMovementRootComponent.self] else { return }
        body(&c)
        root.components.set(c)
    }
    private func syncModeToRoot() { mutateRoot { $0.mode = mode } }
}
#endif
