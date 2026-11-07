// ACNH 3.0.3 resident save editor. No game process is running while this is open.
// Format facts: kwsch/NHSE (MainSaveOffsets30, Villager2, VillagerHouse2,
// FileHashRevision, Encryption), with localized phrase layout verified against
// this game's S00 Smmh and language accessors. AES-CTR uses CommonCrypto; Murmur3
// and xor128 below implement the published algorithms. Catalog names/attributes
// come from the user's RomFS. Optional NHSE resident/house templates are packaged
// separately under GPL-3.0, with their license and source supplied with the build.
import Foundation
import CommonCrypto
import CryptoKit
import Darwin
import zlib

struct ResidentAnimal: Codable, Identifiable, Equatable {
    let id, name, english, phrase: String
    let species, variant, personality: Int
    var template: String? = nil
    var phrases: [String]? = nil
}

struct ResidentCatalog: Codable {
    let schema, version: String
    let animals: [ResidentAnimal]
    var byID: [String: ResidentAnimal] { Dictionary(uniqueKeysWithValues: animals.map { ($0.id, $0) }) }

    static func load(_ url: URL) throws -> ResidentCatalog {
        let c = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard c.schema == "nxnative-acnh-residents/2", c.version == "3.0.3", c.animals.count == 417,
              Set(c.animals.map(\.id)).count == c.animals.count,
              c.animals.allSatisfy({ animal in
                  (0..<35).contains(animal.species) && (0..<256).contains(animal.variant) && (0..<8).contains(animal.personality) &&
                  validPhrase(animal.phrase) && (animal.phrases.map {
                      $0.count == 11 && $0.allSatisfy(validPhrase) && $0[9] == animal.phrase
                  } ?? true)
              })
        else { throw ResidentError.catalog }
        return c
    }
    private static func validPhrase(_ phrase: String) -> Bool {
        !phrase.isEmpty && phrase.utf16.count <= 21 && phrase.unicodeScalars.allSatisfy { $0.value >= 32 }
    }
}

enum ResidentError: String, Error, LocalizedError {
    case catalog = "The resident catalog is missing or incompatible."
    case version = "This editor supports only Animal Crossing 3.0.3 saves."
    case damaged = "The save failed its integrity check. No changes were written."
    case changed = "The save changed since it was opened. Close and reopen the manager."
    case invalid = "This resident selection is invalid."
    case duplicate = "This animal already lives on the island."
    case full = "The island already has 10 animal residents."
    case plot = "Place an empty housing plot in the game before adding a resident."
    case minimum = "Keep the two starting residents until the island has progressed further."
    case moving = "Finish the current move or building relocation in the game first."
    case crypto = "The save could not be decrypted or encrypted."
    case path = "The save directory contains unsupported links or unfinished game writes."
    case backup = "The backup is incomplete or has changed."
    var errorDescription: String? { rawValue }
}

struct ResidentSlot: Identifiable {
    let id: Int
    let animal: ResidentAnimal?
    let plot: Int?
    let moving: Bool
    let phrase: String
}

private extension Data {
    func word(_ at: Int) -> UInt32 {
        UInt32(self[at]) | UInt32(self[at+1]) << 8 | UInt32(self[at+2]) << 16 | UInt32(self[at+3]) << 24
    }
    func half(_ at: Int) -> Int { Int(self[at]) | Int(self[at+1]) << 8 }
    mutating func put(_ value: UInt32, _ at: Int) {
        for i in 0..<4 { self[at+i] = UInt8(truncatingIfNeeded: value >> (8*i)) }
    }
}

enum ResidentCipher {
    static func transform(_ input: Data, header: Data) throws -> Data {
        guard header.count == 0x300 else { throw ResidentError.version }
        func parameter(_ index: Int) -> [UInt8] {
            let seed = header.word(0x100 + Int(header.word(0x100 + index*4) & 127)*4)
            var state = [seed]
            for i in 1...4 { let x = state.last!; state.append(1812433253 &* (x ^ (x >> 30)) &+ UInt32(i)) }
            state.removeFirst()
            func next() -> UInt32 {
                let x = state.removeFirst(); let t = x ^ (x << 11)
                let y = t ^ (t >> 8) ^ state[2] ^ (state[2] >> 19)
                state.append(y); return y
            }
            let rolls = Int(header.word(0x100 + Int(header.word(0x100 + (index+1)*4) & 127)*4) & 15) + 1
            for _ in 0..<(rolls*2) { _ = next() }
            return (0..<16).map { _ in UInt8(next() >> 24) }
        }
        let key = parameter(0), iv = parameter(2)
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                CCPadding(ccNoPadding), v.baseAddress, k.baseAddress, key.count, nil, 0, 0,
                CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
        } }
        guard status == kCCSuccess, let c = cryptor else { throw ResidentError.crypto }
        defer { CCCryptorRelease(c) }
        var output = Data(count: input.count), written = 0
        let result = input.withUnsafeBytes { src in output.withUnsafeMutableBytes { dst in
            CCCryptorUpdate(c, src.baseAddress, src.count, dst.baseAddress, dst.count, &written)
        } }
        guard result == kCCSuccess, written == input.count else { throw ResidentError.crypto }
        return output
    }

    static func murmur(_ data: Data, _ offset: Int, _ count: Int) -> UInt32 {
        func rotate(_ n: UInt32, _ k: UInt32) -> UInt32 { (n << k) | (n >> (32-k)) }
        var h: UInt32 = 0
        for i in stride(from: offset, to: offset+count, by: 4) {
            var k = data.word(i) &* 0xcc9e2d51
            k = rotate(k, 15) &* 0x1b873593
            h = rotate(h ^ k, 13) &* 5 &+ 0xe6546b64
        }
        h ^= UInt32(count); h ^= h >> 16; h = h &* 0x85ebca6b
        h ^= h >> 13; h = h &* 0xc2b2ae35; return h ^ (h >> 16)
    }
}

struct ResidentBackup: Identifiable {
    let url: URL
    let date: Date
    var id: String { url.lastPathComponent }
}

final class ResidentSave {
    // All writes are gated by the exact save version and length, independently of
    // the catalog. An updated game must be investigated before this gate changes.
    static let fileSize = 0x9b0e90, npcBase = 0x120, npcSize = 0x13230
    // S00: localized phrase array has eleven char16[22] strings. CNzh is slot 9;
    // the older NHSE CatchPhrase accessor addresses English (slot 1) only.
    static let phraseBase = 0x10768, phraseSize = 0x2c, phraseCount = 11, chinesePhrase = 9
    // S00 GSaveMemory: player identity, event flags, nickname, eleven greetings,
    // greeting date and other relationship state. Only speech fields reset.
    static let memoryBase = 4, memorySize = 0x5f0, memoryCount = 8
    static let lightMemoryBase = 0x2f84, lightMemorySize = 0x158, lightMemoryCount = 160
    static let houseBase = 0x481d20, houseSize = 0x12e8, buildingBase = 0x32f700
    // S00 GSaveLandOther's GSaveTime, also MainSaveOffsets30.LastSavedTime.
    // Offline additions belong to the island's timeline, not the template donor.
    static let lastSavedTime = 0x97d670, arrivalDate = 0x12674
    static let hashes: [(Int, Int)] = [
        (0x110,0x1e339c),(0x1e34b0,0x3d089c),(0x5b3e60,0x37acc),(0x5eb930,0x3ce5c),
        (0x6288a0,0x37acc),(0x660370,0x3ce5c),(0x69d2e0,0x37acc),(0x6d4db0,0x3ce5c),
        (0x711d20,0x37acc),(0x7497f0,0x3ce5c),(0x786760,0x37acc),(0x7be230,0x3ce5c),
        (0x7fb1a0,0x37acc),(0x832c70,0x3ce5c),(0x86fbe0,0x37acc),(0x8a76b0,0x3ce5c),
        (0x8e4620,0x37acc),(0x91c0f0,0x3ce5c),(0x958f50,0x57f3c)]
    let folder: URL
    let catalog: ResidentCatalog
    private(set) var plain: Data
    private let header: Data
    private let storage: ResidentSaveStorage
    private let lookup: [String: ResidentAnimal]
    private var emptyTemplate: Data?
    private let prefixes = ["ant","bea","brd","bul","cat","cbr","chn","cow","crd","der","dog","duk","elp","flg","goa","gor","ham","hip","hrs","kal","kgr","lon","mnk","mus","ocp","ost","pbr","pgn","pig","rbt","rhn","shp","squ","tig","wol"]

    convenience init(folder: URL, catalog: ResidentCatalog) throws {
        try self.init(storage: ResidentSaveStorage(folder: folder), catalog: catalog)
    }
    init(storage: ResidentSaveStorage, catalog: ResidentCatalog) throws {
        self.storage = storage; folder = storage.folder; self.catalog = catalog; lookup = catalog.byID
        header = try Data(contentsOf: folder.appendingPathComponent("mainHeader.dat"))
        let original = try Data(contentsOf: folder.appendingPathComponent("main.dat"))
        guard storage.checkpoint["main.dat"] == ResidentSaveStorage.digest(original),
              storage.checkpoint["mainHeader.dat"] == ResidentSaveStorage.digest(header) else { throw ResidentError.changed }
        guard header.count == 0x300, original.count == Self.fileSize,
              header.word(0) == 0xa0002, header.word(4) == 0xa0028,
              header.half(8) == 2, header.half(10) == 0, header.half(12) == 2, header.half(14) == 34
        else { throw ResidentError.version }
        plain = try ResidentCipher.transform(original, header: header)
        guard plain.prefix(0x100) == header.prefix(0x100) else { throw ResidentError.damaged }
        try Self.checkHashes(plain)
        let reserved = housingReservations
        for i in 0..<10 {
            let a = Self.npcBase+i*Self.npcSize
            if plain[a] == 35 && !reserved.contains(i) { emptyTemplate = plain.subdata(in: a..<a+Self.npcSize); break }
        }
        guard slots.allSatisfy({ plain[Self.npcBase+$0.id*Self.npcSize] == 35 || $0.animal != nil }) else { throw ResidentError.damaged }
        guard Set(slots.compactMap { $0.animal?.id }).count == count else { throw ResidentError.damaged }
        try storage.assertUnchanged()
    }

    static func checkHashes(_ data: Data) throws {
        guard data.count == fileSize else { throw ResidentError.version }
        for (at,n) in hashes where data.word(at) != ResidentCipher.murmur(data, at+4, n) { throw ResidentError.damaged }
    }

    private func animal(_ i: Int) -> ResidentAnimal? {
        let a = Self.npcBase + i*Self.npcSize, species = Int(plain[a])
        guard prefixes.indices.contains(species) else { return nil }
        return lookup[String(format: "%@%02d", prefixes[species], Int(plain[a+1]))]
    }
    var count: Int { (0..<10).filter { animal($0) != nil }.count }
    private func house(_ slot: Int) -> Int? {
        (0..<10).first { plain[Self.houseBase+$0*Self.houseSize+0x1c4] == slot }
    }
    private func placed(_ index: Int) -> Bool {
        (0..<46).contains { plain.half(Self.buildingBase+$0*20) == index+9 }
    }
    private var housingReservations: Set<Int> {
        // NPC1 and NPC2 both refer to NPC slots, independently of the plot index.
        // A pending tenant can be recorded by a house other than its current one.
        Set((0..<10).flatMap { plot in
            let h = Self.houseBase+plot*Self.houseSize
            return [Int(plain[h+0x1c4]), Int(plain[h+0x1c5])].filter { $0 < 10 }
        })
    }
    var slots: [ResidentSlot] {
        (0..<10).map { i in
            let a = Self.npcBase+i*Self.npcSize
            let at = a+Self.phraseBase+Self.chinesePhrase*Self.phraseSize
            let words = (0..<(Self.phraseSize/2)).map { UInt16(plain.half(at+2*$0)) }
            let plot = house(i)
            let pendingHouse = (0..<10).contains { house in
                let h = Self.houseBase+house*Self.houseSize
                return plain[h+0x1c5] == i || (plain[h+0x1c4] == i && plain[h+0x1c5] != 255)
            }
            let pendingMove = plain[a+0x1267a] != 0 || plain.half(a+0x1267c+24*2) != 0 || pendingHouse
            return ResidentSlot(id: i, animal: animal(i), plot: plot, moving: pendingMove,
                                phrase: String(decoding: words.prefix(while: { $0 != 0 }), as: UTF16.self))
        }
    }
    var vacantPlots: [Int] {
        (0..<10).filter { i in
            let h = Self.houseBase+i*Self.houseSize
            return placed(i) && plain[h+0x1c4] == 255 && plain[h+0x1c5] == 255 && plain.word(h+4) == 0
        }
    }
    private func valid(_ target: ResidentAnimal) throws {
        guard lookup[target.id] == target else { throw ResidentError.invalid }
        if slots.contains(where: { $0.animal?.id == target.id }) { throw ResidentError.duplicate }
    }
    private func setIdentity(_ animal: ResidentAnimal, at a: Int) {
        plain[a] = UInt8(animal.species); plain[a+1] = UInt8(animal.variant); plain[a+2] = UInt8(animal.personality)
        setDefaultPhrase(animal, at: a)
        setDefaultAddressing(at: a)
    }
    private func setDefaultPhrase(_ animal: ResidentAnimal, at a: Int) {
        // Reset phrase text and its player-authorship markers, retaining the
        // house, gifts and relationships. Missing translations in legacy
        // CNzh-only catalogs remain uninitialized, as in a fresh game's array.
        let phrases = animal.phrases ?? (0..<Self.phraseCount).map { $0 == Self.chinesePhrase ? animal.phrase : "" }
        let start = a+Self.phraseBase
        plain.replaceSubrange(start..<start+Self.phraseCount*Self.phraseSize,
                              with: Data(count: Self.phraseCount*Self.phraseSize))
        for (language, phrase) in phrases.enumerated() {
            for (i, c) in phrase.utf16.enumerated() {
                let at = start+language*Self.phraseSize+2*i
                plain[at] = UInt8(truncatingIfNeeded: c); plain[at+1] = UInt8(c >> 8)
            }
        }
        for flag in [8, 10] {
            plain[a+0x1267c+flag*2] = 0; plain[a+0x1267c+flag*2+1] = 0
        }
        clearSpeechFlags([0x14], at: a)
    }
    private func clearSpeechFlags(_ flags: [Int], at a: Int) {
        // S00 gives both local and visitor memories the same 256-byte event
        // array at +0x38. Preserve identities, friendship, dates and other flags.
        for (base, size, count) in [(Self.memoryBase, Self.memorySize, Self.memoryCount),
                                    (Self.lightMemoryBase, Self.lightMemorySize, Self.lightMemoryCount)] {
            for player in 0..<count {
                for flag in flags { plain[a+base+player*size+0x38+flag] = 0 }
            }
        }
    }
    private func setDefaultAddressing(at a: Int) {
        for player in 0..<Self.memoryCount {
            let memory = a+Self.memoryBase+player*Self.memorySize
            // char16[10] nickname, 11 char16[48] greetings and GSaveDate.
            // Fresh unused memories in all 417 pinned templates use zero here.
            plain.replaceSubrange(memory+0x138..<memory+0x570, with: Data(count: 0x438))
        }
        // EventFlagsNpcMemoryParam: SetGreeting, InputGreeting, InputNickname
        // and NicknameOriginal. Visitor memories retain the same event markers.
        clearSpeechFlags([3, 0x13, 0x15, 0x1f], at: a)
    }
    func restoreDefaultPhrase(slot: Int) throws {
        guard (0..<10).contains(slot), let current = animal(slot) else { throw ResidentError.invalid }
        guard !slots[slot].moving else { throw ResidentError.moving }
        setDefaultPhrase(current, at: Self.npcBase+slot*Self.npcSize)
    }
    func restoreDefaultAddressing(slot: Int) throws {
        guard (0..<10).contains(slot), animal(slot) != nil else { throw ResidentError.invalid }
        guard !slots[slot].moving else { throw ResidentError.moving }
        setDefaultAddressing(at: Self.npcBase+slot*Self.npcSize)
    }
    func replace(slot: Int, with target: ResidentAnimal) throws {
        guard (0..<10).contains(slot), animal(slot) != nil else { throw ResidentError.invalid }
        guard !slots[slot].moving else { throw ResidentError.moving }
        try valid(target)
        setIdentity(target, at: Self.npcBase+slot*Self.npcSize)
    }
    private func savedDate() throws -> Data {
        let at = Self.lastSavedTime, year = Int(plain.half(at)), month = Int(plain[at+2]), day = Int(plain[at+3])
        guard year > 0, (1...12).contains(month) else { throw ResidentError.damaged }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month-1]).contains(day) else { throw ResidentError.damaged }
        return plain.subdata(in: at..<at+4)
    }
    func add(_ target: ResidentAnimal, plot: Int) throws {
        guard count < 10 else { throw ResidentError.full }
        try valid(target)
        guard vacantPlots.contains(plot),
              let origin = (0..<10).first(where: { animal($0) != nil }) else { throw ResidentError.plot }
        let reserved = housingReservations
        guard let slot = (0..<10).first(where: { animal($0) == nil && !reserved.contains($0) }) else { throw ResidentError.moving }
        let a = Self.npcBase+slot*Self.npcSize, source = Self.npcBase+origin*Self.npcSize
        guard let encoded = target.template, let compressed = Data(base64Encoded: encoded) else { throw ResidentError.catalog }
        var template = Data(count: Self.npcSize+Self.houseSize)
        var size = uLongf(template.count)
        let status = compressed.withUnsafeBytes { source in template.withUnsafeMutableBytes { output in
            uncompress(output.bindMemory(to: UInt8.self).baseAddress, &size, source.bindMemory(to: UInt8.self).baseAddress, uLong(source.count))
        } }
        guard status == Z_OK, size == template.count, template[0] == target.species, template[1] == target.variant,
              template[2] == target.personality else { throw ResidentError.catalog }
        // The template's second memory is unassigned. Its invalid-date sentinels
        // and trailing defaults are required even for a new acquaintance. The
        // first memory can contain its donor's encounters and must not be reused.
        let fresh = template.subdata(in: 4+0x5f0..<4+2*0x5f0)
        guard fresh[0x38..<0x56c].allSatisfy({ $0 == 0 }) else { throw ResidentError.catalog }
        let arrival = try savedDate()
        plain.replaceSubrange(a..<a+Self.npcSize, with: template.prefix(Self.npcSize))
        plain.replaceSubrange(a+Self.arrivalDate..<a+Self.arrivalDate+4, with: arrival)
        // This addition commits an occupied furnished house, not a queued move.
        // Two pinned donors still have MoveType=1; their transaction is not ours.
        plain[a+0x1267a] = 0
        // New encounters use only local player identities, with fresh friendships.
        for p in 0..<8 {
            let m = 4+p*0x5f0
            let identity = plain.subdata(in: source+m..<source+m+0x38)
            plain.replaceSubrange(a+m..<a+m+0x5f0, with: fresh)
            plain.replaceSubrange(a+m..<a+m+0x38, with: identity)
            if identity.word(0) != 0 || identity.word(0x1c) != 0 { plain[a+m+0x38+10] = 25 }
        }
        setIdentity(target, at: a)
        let h = Self.houseBase+plot*Self.houseSize
        plain.replaceSubrange(h..<h+Self.houseSize, with: template.suffix(Self.houseSize))
        plain[h+0x1c4] = UInt8(slot); plain[h+0x1c5] = 255; plain[h+0x1d0] = 255
    }
    func remove(slot: Int) throws {
        guard (0..<10).contains(slot), animal(slot) != nil, let plot = house(slot) else { throw ResidentError.invalid }
        guard count > 2 else { throw ResidentError.minimum }
        guard !slots[slot].moving else { throw ResidentError.moving }
        let a = Self.npcBase+slot*Self.npcSize, h = Self.houseBase+plot*Self.houseSize
        guard plain[h+0x1c5] == 255, placed(plot) else { throw ResidentError.moving }
        if let empty = emptyTemplate { plain.replaceSubrange(a..<a+Self.npcSize, with: empty) }
        plain[a] = 35; plain[a+1] = 0; plain[a+2] = 8; plain[a+0x12678] = 5; plain[a+0x1267a] = 0
        if emptyTemplate == nil { emptyTemplate = plain.subdata(in: a..<a+Self.npcSize) }
        // Keep the physical plot: deleting a resident never erases terrain or a
        // building position. NPC2 is checked above to avoid an in-flight move.
        plain[h+0x1c4] = 255; plain.put(0,h+4); plain.put(2,h)
    }

    static func safeTree(_ url: URL) throws { try ResidentSaveStorage.safeTree(url) }
    var backupRoot: URL { storage.backupRoot }
    var backups: [ResidentBackup] { storage.backups }
    @discardableResult func save() throws -> URL {
        try storage.assertUnchanged()
        var output = plain
        for (at,n) in Self.hashes { output.put(ResidentCipher.murmur(output,at+4,n),at) }
        try Self.checkHashes(output)
        let encrypted = try ResidentCipher.transform(output, header: header)
        guard try ResidentCipher.transform(encrypted, header: header) == output else { throw ResidentError.crypto }
        let copy = try storage.backup()
        try storage.assertUnchanged()
        // Retain the original encryption header: one atomic main.dat replacement
        // cannot leave an old-header/new-key pair after an interrupted write.
        try encrypted.write(to: folder.appendingPathComponent("main.dat"), options: .atomic)
        return copy
    }
    func restore(_ backup: ResidentBackup) throws { _ = try storage.restore(backup, catalog: catalog) }
}

// File-level checkpoints remain available when the game-format reader rejects
// the current save. Recovery never exposes invalid data to the editing methods.
final class ResidentSaveStorage {
    let folder: URL
    fileprivate let checkpoint: [String:String]
    private let metadataDigest: String?
    init(folder: URL) throws {
        try Self.safeTree(folder)
        self.folder = folder.resolvingSymlinksInPath()
        var files = try Self.inventory(self.folder, includeManifest: true)
        metadataDigest = files.removeValue(forKey: "resident-backup.json")
        checkpoint = files
    }
    static func safeTree(_ url: URL) throws {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey]
        let root = try url.resourceValues(forKeys: keys)
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw ResidentError.path }
        guard let files = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { throw ResidentError.path }
        for case let f as URL in files {
            let v = try f.resourceValues(forKeys: keys)
            if v.isSymbolicLink == true || f.lastPathComponent.contains(".pending") || (v.isRegularFile != true && v.isDirectory != true) { throw ResidentError.path }
        }
    }
    fileprivate func assertUnchanged() throws {
        // A cloud/file-provider update can change personal files independently
        // of main.dat. Every transaction must use one whole-island checkpoint.
        var files = try Self.inventory(folder, includeManifest: true)
        guard files.removeValue(forKey: "resident-backup.json") == metadataDigest,
              files == checkpoint else { throw ResidentError.changed }
    }
    var backupRoot: URL { folder.deletingLastPathComponent().appendingPathComponent("resident-backups", isDirectory: true) }
    fileprivate static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func inventory(_ url: URL, includeManifest: Bool = false) throws -> [String:String] {
        try safeTree(url)
        let root = url.resolvingSymlinksInPath()
        var result: [String:String] = [:]
        // atPath yields relative names directly. URL enumerators can expand /var
        // to /private/var, so dropping a root path's character count is incorrect.
        guard let files = FileManager.default.enumerator(atPath: root.path) else { throw ResidentError.backup }
        for case let relative as String in files {
            let f = root.appendingPathComponent(relative)
            if includeManifest || relative != "resident-backup.json", try f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[relative] = digest(try Data(contentsOf: f))
            }
        }
        return result
    }
    fileprivate func backup(unverified: Bool = false) throws -> URL {
        let fm = FileManager.default
        try assertUnchanged()
        let directory = unverified ? backupRoot.appendingPathComponent("Unverified", isDirectory: true) : backupRoot
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")+"-"+UUID().uuidString.prefix(8))
        let partial = directory.appendingPathComponent(".partial-"+UUID().uuidString)
        defer { try? fm.removeItem(at: partial) }
        // Preserve even a pre-existing metadata file in an unreadable source.
        // Its raw payload stays separate from the preservation manifest.
        let payload = unverified ? partial.appendingPathComponent("save", isDirectory: true) : partial
        if unverified { try fm.createDirectory(at: partial, withIntermediateDirectories: true) }
        try fm.copyItem(at: folder, to: payload)
        var files = try Self.inventory(payload, includeManifest: unverified)
        let preservedInventory = files
        if unverified {
            guard files.removeValue(forKey: "resident-backup.json") == metadataDigest else { throw ResidentError.changed }
        }
        guard files == checkpoint else { throw ResidentError.changed }
        try assertUnchanged()
        try JSONEncoder().encode(preservedInventory).write(to: partial.appendingPathComponent("resident-backup.json"), options: .atomic)
        try fm.moveItem(at: partial, to: destination)
        return destination
    }
    var backups: [ResidentBackup] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "Unverified" }.compactMap { url in
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("resident-backup.json").path) else { return nil }
            let manifest = url.appendingPathComponent("resident-backup.json")
            return ResidentBackup(url: url, date: (try? manifest.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }
    @discardableResult func restore(_ backup: ResidentBackup, catalog: ResidentCatalog) throws -> URL {
        guard !backup.url.lastPathComponent.hasPrefix("."), backup.url.lastPathComponent != "Unverified",
              backup.url.deletingLastPathComponent().resolvingSymlinksInPath().path == backupRoot.resolvingSymlinksInPath().path else {
            fputs("resident manager: backup is outside this island's backup folder\n", stderr); throw ResidentError.backup
        }
        try Self.safeTree(backup.url)
        let expected = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: backup.url.appendingPathComponent("resident-backup.json")))
        let actual = try Self.inventory(backup.url)
        guard actual == expected else {
            fputs("resident manager: backup inventory mismatch: expected \(expected.keys.sorted()), found \(actual.keys.sorted())\n", stderr); throw ResidentError.backup
        }
        _ = try ResidentSave(folder: backup.url, catalog: catalog)
        try assertUnchanged()
        let verified = (try? ResidentSave(storage: self, catalog: catalog)) != nil
        let preserved = try self.backup(unverified: !verified)
        let stage = folder.deletingLastPathComponent().appendingPathComponent(".resident-restore-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: backup.url, to: stage)
        try FileManager.default.removeItem(at: stage.appendingPathComponent("resident-backup.json"))
        guard try Self.inventory(stage) == expected else { throw ResidentError.backup }
        try assertUnchanged()
        guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, folder.path, UInt32(RENAME_SWAP)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return preserved
    }
}
