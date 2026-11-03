import SwiftUI
import VideoToolbox

struct PerformanceSettings:View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("DmPerformanceRecord") private var recording=false
    @AppStorage("DmMotionSmoothing") private var smoothing=false
    @State private var reports:[URL]=[]
    private var smoothingSupported:Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 26.0,macOS 26.0,*) {return VTLowLatencyFrameInterpolationConfiguration.isSupported}
        return false
        #endif
    }
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(dm_save_sync_text("Smooth 30 fps motion"),isOn:$smoothing)
                        .disabled(!smoothingSupported || ProcessInfo.processInfo.environment["DM_PRESENT_SMOOTH"] != nil)
                        .accessibilityIdentifier("performance.smoothing")
                    if !smoothingSupported {Text(dm_save_sync_text("Motion smoothing is unavailable on this device.")).foregroundStyle(.secondary)}
                    if ProcessInfo.processInfo.environment["DM_PRESENT_SMOOTH"] != nil {Text(dm_save_sync_text("Set by an env file")).foregroundStyle(.secondary)}
                } header: {Text(dm_save_sync_text("Motion smoothing"))}
                footer: {Text(dm_save_sync_text("Off by default. Adds intermediate images for smoother motion, using more power. Changes apply at the next game launch. If the device becomes too hot, smoothing stops for the rest of that session; the game continues normally."))}
                Section {
                    Toggle(dm_save_sync_text("Record a 30-minute performance session"),isOn:$recording)
                        .accessibilityIdentifier("performance.record")
                } footer: {Text(dm_save_sync_text("Recording begins when the game picture appears. The report is created immediately and updates every 10 seconds with frame rate, frame times, memory and thermal state, for up to 30 minutes. Share reports below or find this app's performance folder in Files. Changes apply at the next game launch."))}
                Section(dm_save_sync_text("Performance reports")) {
                    if reports.isEmpty{Text(dm_save_sync_text("No performance report yet"))}
                    ForEach(reports,id:\.self){url in ShareLink(item:url){Label(url.lastPathComponent,systemImage:"square.and.arrow.up")}.font(.footnote)}
                    Button(dm_save_sync_text("Refresh")){refresh()}
                }
            }
            .navigationTitle(dm_save_sync_text("Performance settings"))
            .toolbar{ToolbarItem(placement:.confirmationAction){Button(dm_save_sync_text("Done")){dismiss()}}}
            .onAppear{refresh()}
        }
        #if os(iOS)
        .presentationDetents([.large])
        #else
        .frame(minWidth:600,minHeight:400)
        #endif
    }
    private func refresh() {
        guard let path=ProcessInfo.processInfo.environment["DM_ROOT"] else{return}
        let folder=URL(fileURLWithPath:path,isDirectory:true).appendingPathComponent("performance",isDirectory:true)
        reports=Array(((try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="jsonl"}.sorted{$0.lastPathComponent>$1.lastPathComponent}.prefix(20))
    }
}
