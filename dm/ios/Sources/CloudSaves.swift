import SwiftUI
import Combine
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

private func cloudText(_ key: String) -> String { dm_save_sync_text(key) }

struct CloudSaveChoice: Identifiable {
    let id: String
    let label: String
    let date: String
}
struct LocalCheckpoint:Identifiable {let id,name,date,kind,token:String}

@MainActor final class CloudSaveModel: ObservableObject {
    @Published var status: [AnyHashable: Any] = [:]
    @Published var choices: [CloudSaveChoice] = []
    @Published var busy = false
    @Published var choosingFolder = false
    @Published var conflict = false
    @Published var message = "Cloud sync is not configured."
    @Published var center:[AnyHashable:Any]=[:]
    @Published var checkpoints:[LocalCheckpoint]=[]
    private let engine = DMSaveSync.shared()
    private var token = ""
    private var pendingPlay: (() -> Void)?

    var configured: Bool { status["configured"] as? Bool == true }
    var needsAccess: Bool { status["needsAccess"] as? Bool == true }
    var folder: String { status["folder"] as? String ?? "" }
    var waitingForPlay: Bool { pendingPlay != nil }
    init() { refreshStatus() }
    private func consumeCenter(_ value:[AnyHashable:Any]?) {
        center=value ?? [:]
        checkpoints=(center["history"] as? [[String:Any]] ?? []).compactMap { row in
            guard let id=row["id"] as? String,let name=row["name"] as? String,let date=row["date"] as? String,let kind=row["kind"] as? String,let token=row["token"] as? String else{return nil}
            return LocalCheckpoint(id:id,name:name,date:date,kind:kind,token:token)
        }
    }
    func refreshCenter() {work({try self.engine.saveCenter()},progress:"Reading save status…"){self.consumeCenter($0)}}
    func createCheckpoint(_ name:String) {
        work({try self.engine.createCheckpoint(name);return try self.engine.saveCenter()},progress:"Creating checkpoint…") {
            self.consumeCenter($0);self.message="Checkpoint created on this device."
        }
    }
    func restoreCheckpoint(_ row:LocalCheckpoint) {
        work({try self.engine.restoreCheckpoint(row.id,token:row.token);return try self.engine.saveCenter()},progress:"Restoring checkpoint…") { value in
            self.choices=[];self.conflict=false;self.token="";self.consumeCenter(value)
            self.message="Checkpoint restored. The previous local save is in Save history."
        }
    }
    func deleteCheckpoint(_ row:LocalCheckpoint) {
        work({try self.engine.deleteCheckpoint(row.id);return try self.engine.saveCenter()},progress:"Deleting checkpoint…") {
            self.consumeCenter($0);self.message="Named checkpoint deleted."
        }
    }
    func refreshStatus() { status = engine.status; message = status["message"] as? String ?? "" }
    func playLocal(_ play: @escaping () -> Void) { engine.beginOfflineSession(); play() }
    func startPlay(_ play: @escaping () -> Void) { pendingPlay = play; synchronize() }
    func cancelPlay() { pendingPlay = nil }
    func offline() {
        guard !busy, let play = pendingPlay else { return }
        pendingPlay = nil; engine.beginOfflineSession(); play()
    }
    private func work(_ operation: @escaping () throws -> [AnyHashable: Any]?, progress:String="Checking cloud saves…", then: @escaping ([AnyHashable: Any]?) -> Void) {
        guard !busy else { return }
        busy = true; message = progress
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try operation()
                DispatchQueue.main.async { self.busy = false; self.refreshStatus(); then(result) }
            } catch {
                let failure=error as NSError
                fputs("save sync: operation failed (\(failure.domain), \(failure.code))\n",stderr)
                DispatchQueue.main.async { self.busy = false; self.refreshStatus(); self.message = error.localizedDescription }
            }
        }
    }
    func finishFolderSelection(_ url: URL?) {
        choosingFolder=false
        guard let url else { return }
        // The durable model consumes the result; modal dismissal is not a delivery channel.
        chooseFolder(url)
    }
    func chooseFolder(_ url: URL) {
        guard !busy else { return }
        fputs("save sync: configuring selected folder\n",stderr)
        // Retain the picker's grant until the worker has saved its own bookmark.
        let access=url.startAccessingSecurityScopedResource()
        work({
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try self.engine.selectFolder(url); return nil
        }) { _ in
            // Explicit synchronization keeps gameplay and save replacement out of picker dismissal.
            self.message="Cloud folder connected. Select Sync now to check your saves."
        }
    }
    func disconnect() { guard !busy else { return }; engine.disconnect(); choices = []; conflict = false; refreshStatus() }
    func synchronize() {
        guard configured else { refreshStatus(); return }
        work({ try self.engine.inspect() }) { plan in
            guard let plan else { return }
            self.token = plan["token"] as? String ?? ""
            self.conflict = plan["conflict"] as? Bool == true
            self.choices = (plan["choices"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["id"] as? String, let label = $0["label"] as? String else { return nil }
                let rawDate = $0["date"] as? String ?? ""
                let date = ISO8601DateFormatter().date(from: rawDate).map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
                return CloudSaveChoice(id: id, label: label, date: date)
            }
            if self.conflict { self.message = "Devices have different progress. Choose which complete save to use." }
            else { self.useChoice("") }
        }
    }
    func useChoice(_ id: String) {
        let token = self.token
        work({ try self.engine.prepareChoice(id, token: token); return nil }) { _ in
            self.choices = []; self.conflict = false
            if let play = self.pendingPlay { self.pendingPlay = nil; self.engine.beginSession(); play() }
        }
    }
}

struct CloudSaves: View {
    @ObservedObject var model: CloudSaveModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CloudSaveChoice?
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            List {
                LocalSaveCenterSections(model:model)
                Section {
                    Text(cloudText("Share one complete island between iPad, iPhone and Mac. Choose an iCloud Drive folder once on each device."))
                    if model.configured { LabeledContent(cloudText("Sync folder"), value: model.folder) }
                    Button(cloudText("Choose iCloud folder")) { model.choosingFolder = true }.disabled(model.busy)
                    if model.configured {
                        Button(cloudText("Sync now")) { model.synchronize() }.disabled(model.busy)
                        Button(cloudText("Use local saves")) { model.disconnect() }.disabled(model.busy || model.waitingForPlay)
                    }
                } footer: {
                    Text(cloudText("Game saves stay local while playing. Each successful save sends a complete checkpoint to the selected folder. Three versions per device are kept."))
                }
                Section {
                    if model.busy { ProgressView(cloudText(model.message)) }
                    Text(cloudText(model.message)).textSelection(.enabled)
                    if model.conflict {
                        ForEach(model.choices) { choice in
                            Button {
                                selected = choice; confirm = true
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(cloudText(choice.label))
                                    if !choice.date.isEmpty { Text(choice.date).font(.footnote).foregroundStyle(.secondary) }
                                }
                            }.disabled(model.busy)
                        }
                    }
                    if model.waitingForPlay {
                        Button(cloudText("Play local for this session")) { model.offline() }.disabled(model.busy)
                    }
                } footer: {
                    Text(cloudText("Play on one device at a time. Save and wait for iCloud Drive to finish before opening the game elsewhere. Different progress is kept for you to choose; it is never merged automatically."))
                }
            }
            .navigationTitle(cloudText("Save center"))
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(cloudText("Done")) { model.cancelPlay(); dismiss() }.disabled(model.busy)
            } }
            #if os(iOS)
            .sheet(isPresented: $model.choosingFolder) {
                VStack(spacing: 0) {
                    HStack {
                        Text(cloudText("Choose iCloud folder")).font(.headline)
                        Spacer()
                        Button(cloudText("Cancel")) { model.finishFolderSelection(nil) }
                    }.padding()
                    Divider()
                    CloudFolderPicker { model.finishFolderSelection($0) }
                }
                .presentationDetents([.large])
            }
            #else
            .fileImporter(isPresented: $model.choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result { model.finishFolderSelection(urls.first) }
                else { model.finishFolderSelection(nil) }
            }
            #endif
            .confirmationDialog(cloudText("Use this complete save?"), isPresented: $confirm, titleVisibility: .visible) {
                Button(cloudText("Use selected save")) { if let selected { model.useChoice(selected.id) } }
            } message: {
                Text(cloudText("Your current local save will be backed up before replacement."))
            }
        }
        .interactiveDismissDisabled(model.busy)
        .onAppear{model.refreshCenter()}
        .onDisappear { if !model.busy && !model.choosingFolder { model.cancelPlay() } }
        #if os(macOS)
        .frame(minWidth: 650, minHeight: 600)
        #else
        .presentationDetents([.large])
        #endif
    }
}

private struct LocalSaveCenterSections:View {
    @ObservedObject var model:CloudSaveModel
    @State private var checkpointName=""
    @State private var pendingRestore:LocalCheckpoint?
    @State private var pendingDelete:LocalCheckpoint?
    private var locked:Bool {model.busy || model.waitingForPlay || model.center["playing"] as? Bool==true}
    var body:some View {
        Group {
            Section {
                LabeledContent(cloudText("Last game save"),value:date(model.center["localSavedAt"] as? String ?? ""))
                LabeledContent(cloudText("Files in current save"),value:String(model.center["fileCount"] as? Int ?? 0))
                TextField(cloudText("Checkpoint name"),text:$checkpointName)
                Button(cloudText("Create checkpoint")){model.createCheckpoint(checkpointName);checkpointName=""}
                    .disabled(locked).accessibilityIdentifier("save-center.create")
            } header: {Text(cloudText("Local save"))} footer: {Text(cloudText("A named checkpoint contains the complete island and stays on this device. Restore before starting the game; your current save is backed up first."))}
            if !model.checkpoints.isEmpty {
                Section(cloudText("Save history")) {
                    ForEach(model.checkpoints){row in
                        VStack(alignment:.leading,spacing:6) {
                            Text(cloudText(row.name)).font(.headline)
                            Text(date(row.date)).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(cloudText("Restore")){pendingRestore=row}.disabled(locked)
                                if row.kind=="manual"{Button(cloudText("Delete"),role:.destructive){pendingDelete=row}.disabled(locked)}
                            }.buttonStyle(.bordered)
                        }.accessibilityIdentifier("save-center.checkpoint."+row.id)
                    }
                }
            }
            Section {
                LabeledContent(cloudText("Last folder publication"),value:date(model.center["publishedAt"] as? String ?? ""))
                Text(cloudText(model.center["uploadState"] as? String ?? "No checkpoint published yet"))
                Button(cloudText("Refresh save status")){model.refreshCenter()}.disabled(model.busy)
            } header: {Text(cloudText("Cross-device handoff"))} footer: {Text(cloudText("Writing a checkpoint to the folder is separate from uploading it. An uploaded file does not confirm that another device has read it."))}
        }
        .alert(cloudText("Restore this complete island?"),isPresented:Binding(get:{pendingRestore != nil},set:{if !$0{pendingRestore=nil}})) {
            Button(cloudText("Cancel"),role:.cancel){pendingRestore=nil}
            Button(cloudText("Restore"),role:.destructive){if let row=pendingRestore{model.restoreCheckpoint(row)};pendingRestore=nil}
        } message: {Text(cloudText("Your current local save will be backed up before replacement."))}
        .alert(cloudText("Delete this named checkpoint?"),isPresented:Binding(get:{pendingDelete != nil},set:{if !$0{pendingDelete=nil}})) {
            Button(cloudText("Cancel"),role:.cancel){pendingDelete=nil}
            Button(cloudText("Delete"),role:.destructive){if let row=pendingDelete{model.deleteCheckpoint(row)};pendingDelete=nil}
        }
    }
    private func date(_ text:String)->String {
        guard let date=ISO8601DateFormatter().date(from:text) else{return cloudText("Not recorded yet")}
        return DateFormatter.localizedString(from:date,dateStyle:.short,timeStyle:.short)
    }
}

#if os(iOS)
// A document-provider directory grant is opened in place, never copied as an import.
// The outer sheet owns dismissal and keeps Cancel available if Apple's view service fails.
private struct CloudFolderPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker=UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection=false
        picker.delegate=context.coordinator
        picker.modalPresentationStyle = .formSheet
        fputs("save sync: folder chooser opened (public.folder, open in place)\n",stderr)
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (URL?) -> Void
        private var finished=false
        init(_ completion: @escaping (URL?) -> Void) { self.completion=completion }
        private func finish(_ url: URL?) {
            guard !finished else { return };finished=true
            fputs(url == nil ? "save sync: folder chooser cancelled\n":"save sync: folder chooser returned a directory\n",stderr)
            completion(url)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
    }
}
#endif
