import SwiftUI

struct PerformanceSettings:View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("DmPerformanceRecord") private var recording=false
    @State private var reports:[URL]=[]
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(dm_save_sync_text("Record a 30-minute performance session"),isOn:$recording)
                        .accessibilityIdentifier("performance.record")
                } footer: {Text(dm_save_sync_text("Recording begins when the game starts. Every 10 seconds, it records displayed frame rate, frame times, memory and thermal state. The next launch uses this setting."))}
                Section(dm_save_sync_text("Performance reports")) {
                    if reports.isEmpty{Text(dm_save_sync_text("No performance report yet"))}
                    ForEach(reports,id:\.self){url in ShareLink(item:url){Label(url.lastPathComponent,systemImage:"square.and.arrow.up")}.font(.footnote)}
                    Button(dm_save_sync_text("Refresh")){refresh()}
                }
            }
            .navigationTitle(dm_save_sync_text("Performance recording"))
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
