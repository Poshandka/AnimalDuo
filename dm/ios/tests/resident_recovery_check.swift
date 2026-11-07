// Exercise recovery without allowing an invalid current save into the editor.
import Foundation
import CryptoKit

@main struct ResidentRecoveryCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let source = root.appendingPathComponent("save"), catalogURL = root.appendingPathComponent("catalog.json")
        let catalog = try ResidentCatalog.load(catalogURL)
        var passed = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        func tree(_ folder: URL) throws -> [String:Data] {
            var files = [String:Data]()
            guard let items = fm.enumerator(atPath: folder.path) else { throw ResidentError.path }
            for case let name as String in items {
                let url = folder.appendingPathComponent(name)
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files[name] = try Data(contentsOf: url) }
            }
            return files
        }
        let original = try tree(source)
        func fixture(_ name: String) throws -> (URL, ResidentBackup) {
            let folder = root.appendingPathComponent("cases/\(name)/save")
            try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: folder)
            let saved = try ResidentSave(folder: folder, catalog: catalog).save()
            return (folder, ResidentBackup(url: saved, date: Date()))
        }
        func wait(_ model: ResidentManagerModel) {
            let deadline = Date().addingTimeInterval(30)
            while model.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(!model.busy, "worker completed")
        }
        func open(_ folder: URL) -> ResidentManagerModel {
            let model = ResidentManagerModel(catalogURL: catalogURL, saveURL: folder)
            model.reload(); wait(model); return model
        }
        func corrupt(_ folder: URL) throws {
            let url = folder.appendingPathComponent("main.dat")
            var bytes = try Data(contentsOf: url); bytes[0x120] ^= 1
            try bytes.write(to: url, options: .atomic)
        }
        func preserveCheck(_ folder: URL, _ expected: [String:Data]) throws {
            let directory = folder.deletingLastPathComponent().appendingPathComponent("resident-backups/Unverified")
            let copies = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
            check(copies.count == 1, "one separately preserved unreadable checkpoint")
            check(try tree(copies[0].appendingPathComponent("save")) == expected, "every original file and missing file preserved")
            check(fm.fileExists(atPath: copies[0].appendingPathComponent("resident-backup.json").path), "preservation inventory exists outside payload")
            try Data("{}".utf8).write(to: directory.appendingPathComponent("resident-backup.json"))
            let storage = try ResidentSaveStorage(folder: folder)
            check(!storage.backups.contains { $0.url.lastPathComponent == "Unverified" }, "reserved container is excluded even if metadata exists")
            let stable = try tree(folder)
            for url in [copies[0], directory] {
                do {
                    try storage.restore(ResidentBackup(url: url, date: Date()), catalog: catalog)
                    check(false, "unverified checkpoint is not an allowed restore point")
                } catch { check(error as? ResidentError == .backup, "unverified checkpoint scope refused") }
            }
            check(try tree(folder) == stable, "rejected raw preservation leaves active save intact")
        }
        let cases = ["damaged-main", "truncated-main", "missing-main", "missing-header", "truncated-header", "unsupported-current-version", "missing-pair", "unknown-resident", "metadata-preserved", "empty-current"]
        for name in cases {
            try autoreleasepool {
                let (folder, backup) = try fixture(name)
                let main = folder.appendingPathComponent("main.dat"), header = folder.appendingPathComponent("mainHeader.dat")
                switch name {
                case "damaged-main", "metadata-preserved":
                    try corrupt(folder)
                    if name == "metadata-preserved" { try Data("original metadata must survive".utf8).write(to: folder.appendingPathComponent("resident-backup.json")) }
                case "truncated-main": try Data(original["main.dat"]!.prefix(512)).write(to: main)
                case "missing-main": try fm.removeItem(at: main)
                case "missing-header": try fm.removeItem(at: header)
                case "truncated-header": try Data(original["mainHeader.dat"]!.prefix(100)).write(to: header)
                case "unsupported-current-version":
                    var bytes = original["mainHeader.dat"]!; bytes[14] = 33; try bytes.write(to: header)
                case "missing-pair": try fm.removeItem(at: main); try fm.removeItem(at: header)
                case "unknown-resident":
                    let key = original["mainHeader.dat"]!
                    var plain = try ResidentCipher.transform(original["main.dat"]!, header: key); plain[0x120] = 36
                    for (at, count) in ResidentSave.hashes {
                        let value = ResidentCipher.murmur(plain, at+4, count)
                        for byte in 0..<4 { plain[at+byte] = UInt8(truncatingIfNeeded: value >> (byte*8)) }
                    }
                    try ResidentCipher.transform(plain, header: key).write(to: main)
                case "empty-current":
                    for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) { try fm.removeItem(at: url) }
                default: preconditionFailure("unexpected case")
                }
                let damaged = try tree(folder), model = open(folder)
                check(model.document == nil && model.storage != nil && model.backups.count == 1, "recovery available without editor: \(name)")
                check(model.error != nil && model.message == nil, "unreadable checkpoint has no success message")
                model.restore(backup); wait(model)
                check(model.document != nil && model.error == nil && model.message != nil, "validated reload after recovery: \(name)")
                check(try tree(folder) == original, "complete island restored: \(name)")
                check(model.backups.count == 1 && model.backups[0].id == backup.id, "unverified files excluded from backup picker")
                try preserveCheck(folder, damaged)
            }
        }
        for invalid in ["inventory", "game-hashes", "version"] {
            try autoreleasepool {
                let (folder, backup) = try fixture("invalid-\(invalid)")
                try corrupt(folder)
                let model = open(folder), damaged = try tree(folder)
                if invalid == "version" {
                    let path = backup.url.appendingPathComponent("mainHeader.dat")
                    var data = try Data(contentsOf: path); data[14] = 33; try data.write(to: path)
                } else { try corrupt(backup.url) }
                if invalid != "inventory" {
                    var inventory = [String:String]()
                    for (name, bytes) in try tree(backup.url) where name != "resident-backup.json" {
                        inventory[name] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                    }
                    try JSONEncoder().encode(inventory).write(to: backup.url.appendingPathComponent("resident-backup.json"))
                }
                model.restore(backup); wait(model)
                check(model.error != nil && model.document == nil && model.message == nil, "invalid target rejected: \(invalid)")
                check(try tree(folder) == damaged, "invalid backup leaves all current files intact")
                check(!fm.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent("resident-backups/Unverified").path), "invalid target rejected before preservation or commit")
            }
        }
        let (staleFolder, staleBackup) = try fixture("stale")
        try corrupt(staleFolder)
        let stale = open(staleFolder)
        try Data("newer personal progress".utf8).write(to: staleFolder.appendingPathComponent("personal-fixture.dat"))
        let newer = try tree(staleFolder)
        stale.restore(staleBackup); wait(stale)
        let refusedTree = try tree(staleFolder)
        check(stale.error != nil && stale.message == nil && refusedTree == newer, "stale recovery choice refuses to overwrite newer personal files")
        stale.restore(staleBackup); wait(stale)
        let retriedTree = try tree(staleFolder)
        check(stale.error == nil && stale.document != nil && retriedTree == original, "explicit retry uses the freshly loaded checkpoint")
        try preserveCheck(staleFolder, newer)
        let (failedReloadFolder, _) = try fixture("post-operation-error")
        let failedReload = open(failedReloadFolder)
        failedReload.perform(successMessage: "Saved") { _ in try corrupt(failedReloadFolder) }; wait(failedReload)
        check(failedReload.error != nil && failedReload.document == nil && failedReload.message == nil, "failed post-operation reload never publishes green success")
        for marker in ["symlink", "write.pending"] {
            let (folder, _) = try fixture("unsafe-\(marker)")
            let path = folder.appendingPathComponent(marker)
            if marker == "symlink" { try fm.createSymbolicLink(at: path, withDestinationURL: catalogURL) }
            else { try Data().write(to: path) }
            do { _ = try ResidentSaveStorage(folder: folder); check(false, "unsafe tree rejected") }
            catch { check(error as? ResidentError == .path, "path guard retained: \(marker)") }
        }
        print("resident recovery: \(cases.count) damage cases, \(passed) passed, 0 failed")
    }
}
