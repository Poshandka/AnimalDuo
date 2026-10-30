import Foundation
import CoreHaptics

func residentText(_ key: String) -> String { key }

@main struct ControllerHapticsCheck {
    @MainActor static func main() throws {
        // The actual Apple pattern must be finite without relying on a scheduled
        // UI callback to stop the motor after app suspension or dismissal.
        let pattern = try ControllerHapticsTestModel.testPattern()
        precondition(pattern.duration == 1)
        let model = ControllerHapticsTestModel()
        // No selected device: no request may be reported as having played.
        model.run(.default)
        precondition(!model.busy && !model.canReport)
        model.startComparison()
        precondition(!model.comparison && !model.busy && !model.canReport)
        precondition(model.comparisonResults.isEmpty)
        // A response without a completed hardware request must not advance or
        // fabricate a comparison result.
        model.report(true)
        precondition(model.comparisonResults.isEmpty)
        model.stop()
        precondition(!model.comparison && !model.busy && !model.canReport)
        print("finite controller pattern and unavailable-device state: PASS")
    }
}
