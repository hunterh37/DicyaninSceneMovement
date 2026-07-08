#if os(visionOS)
import XCTest
@testable import DicyaninSceneMovement

final class PinchEdgeDetectorTests: XCTestCase {
    func testFiresOnceOnRisingEdge() {
        var d = PinchEdgeDetector(onThreshold: 0.85, offThreshold: 0.6)
        XCTAssertFalse(d.update(pinch: 0.1))
        XCTAssertTrue(d.update(pinch: 0.9))
        XCTAssertFalse(d.update(pinch: 0.95)) // held, no refire
        XCTAssertFalse(d.update(pinch: 0.7))  // above off threshold, still engaged
        XCTAssertFalse(d.update(pinch: 0.4))  // release
        XCTAssertTrue(d.update(pinch: 0.9))   // fires again
    }
}
#endif
