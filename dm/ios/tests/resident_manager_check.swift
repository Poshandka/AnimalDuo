// Exercise the production asynchronous model with synthetic saves and catalogs.
import Foundation

@main struct ResidentManagerCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = root.appendingPathComponent("save")
        let catalog = root.appendingPathComponent("catalog.json")
        let model = ResidentManagerModel(catalogURL: catalog, saveURL: folder)
        var passed = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            passed += 1
        }
        func wait() {
            let deadline = Date().addingTimeInterval(30)
            while model.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(!model.busy, "worker completion")
        }
        model.reload(); wait()
        check(model.document != nil && model.error == nil && model.backups.isEmpty, "initial document and metadata")
        let target = model.document!.catalog.animals[8]
        model.perform { document in
            guard let document else { throw ResidentError.changed }
            try document.replace(slot: 0, with: target); try document.save()
        }
        wait()
        check(model.document?.slots[0].animal == target && model.backups.count == 1, "edited document and new backup publish together")
        let backup = model.backups[0], rootURL = model.document!.backupRoot
        let fm = FileManager.default, detached = rootURL.appendingPathExtension("detached")
        try fm.moveItem(at: rootURL, to: detached)
        for _ in 0..<100 {
            check(model.backups.count == 1 && model.backups[0].id == backup.id, "render reads a stable metadata snapshot")
        }
        try fm.moveItem(at: detached, to: rootURL)
        model.reload(); wait()
        check(model.backups.count == 1, "explicit reload refreshes metadata")
        model.perform { document in
            guard let document else { throw ResidentError.changed }
            try document.restore(backup)
        }
        wait()
        check(model.document?.slots[0].animal?.id == "ant00" && model.backups.count == 2, "restore refreshes document and complete backup list")
        model.perform { _ in throw ResidentError.moving }; wait()
        check(model.error != nil && model.document != nil && model.backups.count == 2, "failed operation retains a coherent snapshot")
        let main = folder.appendingPathComponent("main.dat"), original = try Data(contentsOf: main)
        var corrupt = original; corrupt[0x120] ^= 1
        try corrupt.write(to: main, options: .atomic)
        model.reload(); wait()
        check(model.error != nil && model.document == nil && model.storage != nil && model.backups.count == 2, "failed format reload retains the independent recovery snapshot")
        try original.write(to: main, options: .atomic)
        model.reload(); wait()
        check(model.error == nil && model.document != nil && model.backups.count == 2, "valid checkpoint reload recovers the model")
        print("resident manager: \(passed) passed, 0 failed")
    }
}
