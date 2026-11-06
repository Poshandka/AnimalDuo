// Launcher: the settings screen shown before the game starts (front_ios.m dm_show_launcher). Its settings come from the app's dm/launcher.json, which build_ipa.sh writes for this game
// from dm/games/settings.tsv (dm/games/settings.py): each sets an environment variable the host reads when the game starts. A variable an env file set (Documents/env.txt, the bundle's
// dm/env.txt; main.m lists them in DM_ENV_FILE_KEYS) is shown but kept. All settings share one screen, grouped by section. Choices that differ from the game's default are kept
// in UserDefaults; Reset to tested defaults forgets them. DM_LAUNCHER=0 in Documents/env.txt starts the game at once, as an app without launcher.json does
import SwiftUI
import UIKit
import os

private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

private extension LauncherModel {
    func binding(_ s: Setting) -> Binding<String> { Binding(get: { self.values[s.env] ?? s.def }, set: { self.values[s.env] = $0 }) }
}

private struct SettingRow: View {
    let s: Setting
    @ObservedObject var m: LauncherModel

    private var locked: Bool { m.fromFile.contains(s.env) }
    private func settingText(_ key: String) -> String { s.env == "DM_LDN_WAIT_SECONDS" ? dm_local_play_text(key) : key }
    private var note: String {
        locked ? (s.note.isEmpty ? "" : settingText(s.note) + " · ") + "Set by an env file" : settingText(s.note)
    }
    private var rangeValue: Binding<Double> {
        Binding(get: { Double(m.values[s.env] ?? s.def) ?? s.max ?? 1 },
                set: { m.values[s.env] = String(format: "%.2f", $0) })
    }
    private var percentage: String { "\(Int((rangeValue.wrappedValue * 100).rounded())) %" }

    private var settingLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settingText(s.label))
            if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    var body: some View {
        Group {
            switch s.kind {
            case "choice":
                Picker(selection: m.binding(s)) {
                    ForEach(s.options ?? [], id: \.[0]) { Text(settingText($0[1])).tag($0[0]) }
                } label: {
                    settingLabel
                }
                .pickerStyle(.menu)
            case "range":
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        settingLabel
                        Spacer()
                        Text(percentage).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: rangeValue, in: (s.min ?? 0)...(s.max ?? 1), step: s.step ?? 0.05)
                        .accessibilityLabel(s.label)
                        .accessibilityValue(percentage)
                }
            default:
                Toggle(isOn: Binding(get: { (m.values[s.env] ?? s.def) == s.onValue }, set: { m.values[s.env] = $0 ? s.onValue : s.offValue })) {
                    settingLabel
                }
            }
        }
        .disabled(locked)
    }
}

private struct LauncherView: View {
    @ObservedObject var m: LauncherModel
    let play: () -> Void
    @State private var memory = os_proc_available_memory()
    @State private var showResidents = false
    @State private var showControllerTest = false
    @State private var showCloudSaves = false
    @State private var showTouchControls=false
    @State private var showPerformance=false
    @State private var startRequested = false
    @State private var startupChoice: CloudSaveChoice?
    @StateObject private var cloud = CloudSaveModel()

    private var residentCatalogURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/resident_catalog.json"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView {
                VStack(spacing: 16) {
                    if let icon = appIcon() {
                        Image(uiImage: icon).resizable().frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .accessibilityHidden(true)
                    }
                    Text((info("CFBundleDisplayName") as? String) ?? "Game")
                        .font(.title.weight(.bold)).multilineTextAlignment(.center)
                    Text("Version \((info("CFBundleShortVersionString") as? String) ?? "")")
                        .font(.callout).foregroundStyle(.secondary)
                    playButton
                    startupStatus
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .frame(width: geometry.size.width / 3, height: geometry.size.height)
                List {
                    Section {
                        Button { cloud.refreshStatus(); showCloudSaves = true } label: {
                            Label(dm_save_sync_text("Save center"), systemImage: "externaldrive")
                        }.disabled(startRequested)
                        Button{showTouchControls=true}label:{Label(companionText("Touch controls"),systemImage:"gamecontroller")}
                        Button{showPerformance=true}label:{Label(dm_save_sync_text("Performance settings"),systemImage:"waveform.path.ecg")}
                    }
                    ForEach(m.sections, id: \.self) { section in
                        Section(section) {
                            ForEach(m.settings.filter { $0.sectionTitle == section }) { SettingRow(s: $0, m: m) }
                        }
                    }
                    if residentCatalogURL != nil {
                        Section("Mods") {
                            Button { showResidents = true } label: {
                                Label(residentText("Island residents"), systemImage: "pawprint.fill")
                            }
                        }
                    }
                    if m.settings.contains(where: { $0.env == "DM_RUMBLE" }) {
                        Section {
                            Button { showControllerTest = true } label: {
                                Label(residentText("Controller vibration test"), systemImage: "gamecontroller")
                            }
                        }
                    }
                    Section {
                        Button("Reset to tested defaults") { m.reset() }
                            .disabled(!m.changed)
                    } footer: {
                        Text("Brings back all settings this game was tested with.")
                    }
                    Section {
                        HStack {
                            Text("Memory available")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .frame(width: geometry.size.width * 2 / 3)
                .disabled(startRequested)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showResidents) {
            if let catalog = residentCatalogURL, let path = ProcessInfo.processInfo.environment["DM_SAVE"] {
                ResidentManager(catalogURL: catalog, saveURL: URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        .sheet(isPresented: $showControllerTest) { ControllerHapticsTest() }
        .sheet(isPresented: $showCloudSaves) { CloudSaves(model: cloud) }
        .sheet(isPresented:$showTouchControls){TouchControlsEditor()}
        .sheet(isPresented:$showPerformance){PerformanceSettings()}
        .task {
            while !Task.isCancelled {
                memory = os_proc_available_memory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder var playButton: some View {
        let button = Button(action: {
            guard !startRequested else { return }
            if !cloud.configured && !cloud.needsAccess { cloud.playLocal(play); return }
            startupChoice=nil;startRequested=true
            // Normal startup stays on this page; only explicit settings actions open a sheet.
            cloud.startPlay { startRequested=false;startupChoice=nil;play() }
        }) { Text(dm_save_sync_text("Start now")).font(.title3.weight(.semibold)).frame(maxWidth: 220) }
            .controlSize(.large).disabled(startRequested)
            .accessibilityIdentifier("launcher.start")
        if #available(iOS 26.0, *) { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.borderedProminent) }
    }

    private func cancelStartup() {
        cloud.cancelPlay();startupChoice=nil;startRequested=false
    }
    @ViewBuilder private var startupStatus: some View {
        if startRequested {
            if cloud.busy {
                ProgressView(dm_save_sync_text("Checking cloud saves…"))
                    .accessibilityIdentifier("launcher.cloud-progress")
            } else {
                VStack(spacing: 10) {
                    Text(dm_save_sync_text(cloud.message)).font(.footnote)
                        .accessibilityIdentifier("launcher.cloud-status")
                    if cloud.conflict {
                        if let choice=startupChoice {
                            Text(dm_save_sync_text("Use this complete save?"))
                            Text(dm_save_sync_text(choice.label)).font(.callout.weight(.semibold))
                            Text(dm_save_sync_text("Your current local save will be backed up before replacement.")).font(.footnote)
                            Button(dm_save_sync_text("Use selected save")) { startupChoice=nil;cloud.useChoice(choice.id) }
                                .accessibilityIdentifier("launcher.cloud-use")
                            Button(dm_save_sync_text("Back")) { startupChoice=nil }
                        } else {
                            ForEach(cloud.choices) { choice in
                                Button { startupChoice=choice } label: {
                                    VStack {
                                        Text(dm_save_sync_text(choice.label))
                                        if !choice.date.isEmpty { Text(choice.date).font(.caption) }
                                    }
                                }.accessibilityIdentifier("launcher.cloud-choice."+choice.id)
                            }
                        }
                    }
                    if cloud.needsAccess {
                        Button(dm_save_sync_text("Cloud saves")) { cancelStartup();showCloudSaves=true }
                    } else {
                        Button(dm_save_sync_text("Retry")) { startupChoice=nil;cloud.synchronize() }
                    }
                    Button(dm_save_sync_text("Play local for this session")) { cloud.offline() }
                        .accessibilityIdentifier("launcher.cloud-offline")
                    Button(dm_save_sync_text("Cancel")) { cancelStartup() }
                        .accessibilityIdentifier("launcher.cloud-cancel")
                }.buttonStyle(.bordered)
            }
        }
    }

    private func appIcon() -> UIImage? {
        if let i = UIImage(named: "AppIcon") { return i }
        guard let icons = info("CFBundleIcons") as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String], let last = files.last else { return nil }
        return UIImage(named: last)
    }
}

// Shows the launcher over the root view controller and calls done once the settings are in the environment; false (done is not called) when there is no launcher
@_cdecl("dm_show_launcher")
public func dmShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) -> Bool {
    if ProcessInfo.processInfo.environment["DM_LAUNCHER"] == "0" { fputs("launcher: off (DM_LAUNCHER=0)\n", stderr); return false }
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url) else { return false }
    guard let file = try? JSONDecoder().decode(SettingsFile.self, from: data), !file.settings.isEmpty else { fputs("[RED] launcher: dm/launcher.json cannot be read; starting the game\n", stderr); return false }
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    let model = LauncherModel(file.settings)
    var host: UIViewController?
    let view = LauncherView(m: model) {
        guard host != nil else { return }
        host = nil
        model.apply()
        dm_launch_transition()
        // The launcher may still present cloud settings. Dismiss from its root
        // presenter so the launcher and every sheet above it leave together.
        fputs("launcher: dismissing startup presentation\n", stderr)
        parent.dismiss(animated: false) {
            fputs("launcher: startup presentation dismissed; starting game\n", stderr)
            done()
        }
    }
    let h = GameHostingController(rootView: view)
    h.orientationOwner = parent
    h.modalPresentationStyle = .fullScreen
    host = h
    parent.present(h, animated: false)
    fputs("launcher: \(file.settings.count) settings shown\n", stderr)
    if file.settings.contains(where: { $0.env == "DM_RUMBLE" }) {
        fputs("launcher: controller vibration self-test available (finite 1-second patterns)\n", stderr)
    }
    return true
}
