#if os(visionOS)
import SwiftUI

/// Minimal segmented control for switching locomotion modes.
public struct SceneMovementModePicker: View {
    @ObservedObject private var manager: SceneMovementManager

    public init(manager: SceneMovementManager) {
        self.manager = manager
    }

    public var body: some View {
        Picker("Movement", selection: $manager.mode) {
            Text("Off").tag(SceneMovementMode.off)
            Text("Laser Teleport").tag(SceneMovementMode.laserTeleport)
            Text("Pinch to Walk").tag(SceneMovementMode.pinchToWalk)
        }
        .pickerStyle(.segmented)
    }
}
#endif
