// Hardware checks before guest boot. Comparison tests isolate player startup and
// parameter ordering; API acceptance is never reported as physical output.
import SwiftUI
import Combine
import GameController
import CoreHaptics

enum ControllerHapticsProbe: String, CaseIterable {
    case finite = "A: One-shot baseline"
    case continuous = "B: Continuous event"
    case dynamic = "C: Dynamic parameters"
    case muted = "D: Previous muted startup"
    case prestart = "E: Parameters before startup"
    #if CONTROLLER_GAME_BACKEND
    case backend = "F: Actual game adapter"
    #endif

    var sendsParameters: Bool { self == .dynamic || self == .muted || self == .prestart }
    var duration: TimeInterval { self == .finite ? 1 : TimeInterval(GCHapticDurationInfinite) }
    var parameters: [CHHapticDynamicParameter] {
        [CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 1, relativeTime: 0),
         CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: 0, relativeTime: 0)]
    }
}

@MainActor final class ControllerHapticsTestModel: ObservableObject {
    @Published var controllers: [GCController] = []
    @Published var selection = 0
    @Published var busy = false
    @Published var message = "Choose a test. Each effect lasts one second."
    @Published var canReport = false
    @Published var comparison = false
    @Published var comparisonResults: [(probe: ControllerHapticsProbe, felt: Bool)] = []
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var finish: Task<Void, Never>?
    private var lastTest = ""
    private var lastProbe = ControllerHapticsProbe.finite
    private var comparisonLocality = GCHapticsLocality.default
    private var generation = UUID()

    var controller: GCController? { controllers.indices.contains(selection) ? controllers[selection] : nil }
    var localities: [GCHapticsLocality] { (controller?.haptics?.supportedLocalities ?? []).sorted { $0.rawValue < $1.rawValue } }
    var localityNames: String { localities.map(\.rawValue).joined(separator: ", ") }

    func refresh() {
        stop()
        controllers = GCController.controllers()
        if !controllers.indices.contains(selection) { selection = 0 }
        message = controllers.isEmpty ? "Connect your controller, then return here." : "Choose a test. Each effect lasts one second."
        log("connected=\(controllers.count)")
        for (i, c) in controllers.enumerated() {
            let names = (c.haptics?.supportedLocalities ?? []).map(\.rawValue).sorted().joined(separator: ", ")
            log("controller=\(i) name=\(c.vendorName ?? "unknown") category=\(c.productCategory) localities=\(names)")
        }
    }
    static func testPattern(_ probe: ControllerHapticsProbe = .finite) throws -> CHHapticPattern {
        // The baseline is hardware bounded; continuous comparisons are explicitly
        // stopped after one second and on every lifecycle/cancellation path.
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        ], relativeTime: 0, duration: probe.duration)
        return try CHHapticPattern(events: [event], parameters: [])
    }
    func run(_ locality: GCHapticsLocality) {
        stop()
        start(locality, probe: .finite)
    }
    func startComparison() {
        stop()
        comparisonResults = []
        comparison = true
        comparisonLocality = localities.contains(.default) ? .default : (localities.first ?? .default)
        log("comparison started locality=\(comparisonLocality.rawValue)")
        start(comparisonLocality, probe: .finite)
    }
    private func start(_ locality: GCHapticsLocality, probe: ControllerHapticsProbe) {
        stopOutput()
        guard let c = controller, let haptics = c.haptics,
              haptics.supportedLocalities.contains(locality) else {
            message = "This controller does not expose that vibration output."
            comparison = false
            log("unavailable locality=\(locality.rawValue)"); return
        }
        lastTest = locality.rawValue
        lastProbe = probe
        #if CONTROLLER_GAME_BACKEND
        if probe == .backend {
            ControllerProbeStartGameAdapter(c)
            lastTest = "game split/default route"
            awaitReport(c, probe: probe)
            return
        }
        #endif
        var stage = "create engine"
        do {
            guard let e = haptics.createEngine(withLocality: locality) else {
                message = "The system could not create a controller haptics engine."
                comparison = false
                log("create engine failed locality=\(locality.rawValue)"); return
            }
            engine = e
            e.playsHapticsOnly = true
            let target = locality.rawValue
            e.stoppedHandler = { reason in
                fputs("controller self-test: engine stopped locality=\(target) reason=\(reason.rawValue)\n", stderr)
            }
            e.resetHandler = { fputs("controller self-test: engine reset locality=\(target)\n", stderr) }
            stage = "create pattern"
            let pattern = try Self.testPattern(probe)
            stage = "start engine"; try e.start()
            stage = "create standard player"
            player = try e.makePlayer(with: pattern)
            if probe == .prestart {
                stage = "send parameters before start"
                try player?.sendParameters(probe.parameters, atTime: CHHapticTimeImmediate)
            }
            if probe == .muted { player?.isMuted = true }
            stage = "start player"; try player?.start(atTime: CHHapticTimeImmediate)
            if probe.sendsParameters && probe != .prestart {
                stage = "send parameters after start"
                try player?.sendParameters(probe.parameters, atTime: CHHapticTimeImmediate)
            }
            if probe == .muted { player?.isMuted = false }
            awaitReport(c, probe: probe)
        } catch {
            let e = error as NSError
            releaseOutput()
            comparison = false
            message = residentText("Vibration test failed") + ": \(e.domain) \(e.code)\n\(e.localizedDescription)"
            log("failed stage=\(stage) locality=\(locality.rawValue) domain=\(e.domain) code=\(e.code) message=\(e.localizedDescription)")
        }
    }
    private func awaitReport(_ c: GCController, probe: ControllerHapticsProbe) {
        busy = true
        message = comparison ? residentText(probe.rawValue) + "\n" + residentText("Playing for one second…") : "Playing for one second…"
        log("request submitted name=\(c.vendorName ?? "unknown") category=\(c.productCategory) locality=\(lastTest) probe=\(probe.rawValue) intensity=1 event-duration=\(probe.duration) stop-after=1")
        let token = generation
        finish = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.releaseOutput()
            self.message = (self.comparison ? residentText(probe.rawValue) + "\n" : "") + residentText("Did the controller vibrate during this test?")
            self.canReport = true
            self.log("finished locality=\(self.lastTest) probe=\(probe.rawValue); physical output requires user confirmation")
        }
    }
    func stop() {
        comparison = false
        stopOutput()
    }
    private func stopOutput() {
        generation = UUID()
        finish?.cancel(); finish = nil
        releaseOutput(); canReport = false
    }
    private func releaseOutput() {
        #if CONTROLLER_GAME_BACKEND
        ControllerProbeStopGameAdapter()
        #endif
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop(completionHandler: nil); engine = nil
        busy = false
    }
    func report(_ felt: Bool) {
        guard canReport else { return }
        log("user report locality=\(lastTest) probe=\(lastProbe.rawValue) felt=\(felt)")
        message = felt ? "Recorded: vibration felt." : "Recorded: no vibration felt."
        canReport = false
        if comparison {
            comparisonResults.append((lastProbe, felt))
            let probes = ControllerHapticsProbe.allCases
            if let i = probes.firstIndex(of: lastProbe), i + 1 < probes.count {
                start(comparisonLocality, probe: probes[i + 1])
            } else {
                comparison = false
                message = "Comparison complete. Results are saved in log.txt."
                log("comparison complete " + comparisonResults.map { "\($0.probe.rawValue)=\($0.felt)" }.joined(separator: "; "))
            }
        }
    }
    private func log(_ value: String) { fputs("controller self-test: t=\(ProcessInfo.processInfo.systemUptime) \(value)\n", stderr) }
}

struct ControllerHapticsTest: View {
    @StateObject private var model = ControllerHapticsTestModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.controllers.isEmpty {
                        Text(residentText("No controller connected"))
                    } else {
                        Picker(residentText("Controller"), selection: $model.selection) {
                            ForEach(model.controllers.indices, id: \.self) { i in
                                Text("\(i + 1). \(model.controllers[i].vendorName ?? "Controller")").tag(i)
                            }
                        }.disabled(model.busy || model.comparison)
                        if let c = model.controller {
                            LabeledContent(residentText("Controller type"), value: c.productCategory)
                            Text(model.localityNames.isEmpty ? residentText("No vibration outputs reported") : model.localityNames)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button(residentText("Refresh controllers")) { model.refresh() }.disabled(model.busy || model.comparison)
                }
                Section {
                    Text(residentText(model.message)).textSelection(.enabled)
                    if model.canReport {
                        Button(residentText("I felt vibration")) { model.report(true) }
                        Button(residentText("I felt no vibration")) { model.report(false) }
                    }
                    if model.busy || model.comparison {
                        Button(residentText("Stop vibration"), role: .destructive) { model.stop() }
                    }
                } footer: {
                    Text(residentText("Results are written to log.txt. An accepted request does not confirm physical vibration."))
                }
                Section {
                    Button(residentText("Start game vibration comparison")) { model.startComparison() }
                        .disabled(model.busy || model.comparison || model.localities.isEmpty)
                    ForEach(model.comparisonResults.indices, id: \.self) { i in
                        let result = model.comparisonResults[i]
                        LabeledContent(residentText(result.probe.rawValue), value: residentText(result.felt ? "Vibration felt" : "No vibration felt"))
                    }
                } footer: {
                    Text(residentText("Keep Bluetooth connected. After each one-second test, record whether you felt vibration to continue."))
                }
                Section {
                    testButton("Test normal vibration", .default)
                    testButton("Test left motor", .leftHandle)
                    testButton("Test right motor", .rightHandle)
                } footer: {
                    Text(residentText("Each test runs at full strength for one second, independently of game rumble settings."))
                }
            }
            .navigationTitle(residentText("Controller vibration test"))
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(residentText("Done")) { model.stop(); dismiss() }
            } }
        }
        .onAppear { model.refresh() }
        .onDisappear { model.stop() }
        .onChange(of: model.selection) { _, _ in model.stop() }
        .onChange(of: scenePhase) { _, value in if value != .active { model.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in model.refresh() }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 620)
        #else
        .presentationDetents([.large])
        #endif
    }
    private func testButton(_ title: String, _ locality: GCHapticsLocality) -> some View {
        Button(residentText(title)) { model.run(locality) }
            .disabled(model.busy || model.comparison || !model.localities.contains(locality))
    }
}
