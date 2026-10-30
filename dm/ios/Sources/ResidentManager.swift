// Optional ACNH resident manager, presented before the game owns the save files.
// Its catalog is absent in other game bundles, so they have no resident UI.
import SwiftUI
import Foundation
import Combine

func residentText(_ key: String) -> String {
    let language = Bundle.main.object(forInfoDictionaryKey: "DMLanguage") as? String ?? ""
    let bundle = language.hasPrefix("zh") ? Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init(path:)) : nil
    return (bundle ?? Bundle.main).localizedString(forKey: key, value: key, table: "ResidentMod")
}

let residentSpecies = ["Anteater","Bear","Bird","Bull","Cat","Cub","Chicken","Cow","Alligator","Deer","Dog","Duck","Elephant","Frog","Goat","Gorilla","Hamster","Hippo","Horse","Koala","Kangaroo","Lion","Monkey","Mouse","Octopus","Ostrich","Eagle","Penguin","Pig","Rabbit","Rhino","Sheep","Squirrel","Tiger","Wolf"]
let residentPersonalities = ["Lazy","Jock","Cranky","Smug","Normal","Peppy","Snooty","Big sister"]

private func residentDetails(_ animal: ResidentAnimal, english: Bool = false) -> String {
    var parts = [residentText(residentSpecies[animal.species]), residentText(residentPersonalities[animal.personality])]
    if english { parts.insert(animal.english, at: 0) }
    return parts.joined(separator: " · ")
}

private extension View {
    @ViewBuilder func residentSheetSize() -> some View {
        #if os(macOS)
        self.frame(minWidth: 640, minHeight: 620)
        #else
        self.presentationDetents([.large])
        #endif
    }
}

final class ResidentManagerModel: ObservableObject {
    @Published var document: ResidentSave?
    @Published var busy = false
    @Published var error: String?
    @Published var message: String?
    private let queue = DispatchQueue(label: "nxnative.resident-manager", qos: .userInitiated)
    let catalogURL: URL
    let saveURL: URL
    init(catalogURL: URL, saveURL: URL) { self.catalogURL = catalogURL; self.saveURL = saveURL }
    func reload() { perform { _ in } }
    func perform(_ operation: @escaping (ResidentSave?) throws -> Void) {
        guard !busy else { return }
        busy = true
        let opened = document
        queue.async {
            var failure: String?
            do { try operation(opened) } catch { failure = residentText(error.localizedDescription) }
            var loaded: ResidentSave?
            do { loaded = try ResidentSave(folder: self.saveURL, catalog: ResidentCatalog.load(self.catalogURL)) }
            catch { if failure == nil { failure = residentText(error.localizedDescription) } }
            DispatchQueue.main.async {
                self.document = loaded; self.error = failure; self.busy = false
            }
        }
    }
}

private struct AnimalPickerRequest: Identifiable {
    let id = UUID()
    let slot: Int?
    let plot: Int?
    let browse: Bool
}

private enum ResidentConfirmation: Identifiable {
    case replace(Int, ResidentAnimal), add(Int, ResidentAnimal), remove(Int), restore(ResidentBackup)
    var id: String {
        switch self {
        case .replace(let n, let a): return "replace-\(n)-\(a.id)"
        case .add(let n, let a): return "add-\(n)-\(a.id)"
        case .remove(let n): return "remove-\(n)"
        case .restore(let b): return "restore-\(b.id)"
        }
    }
}

struct ResidentManager: View {
    @StateObject private var model: ResidentManagerModel
    @Environment(\.dismiss) private var dismiss
    @State private var picker: AnimalPickerRequest?
    @State private var confirmation: ResidentConfirmation?
    @State private var pendingConfirmation: ResidentConfirmation?
    @State private var showBackups = false

    init(catalogURL: URL, saveURL: URL) {
        _model = StateObject(wrappedValue: ResidentManagerModel(catalogURL: catalogURL, saveURL: saveURL))
    }
    var body: some View {
        NavigationStack {
            managerList
            .navigationTitle(residentText("Island residents"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(residentText("Done")) { dismiss() }.disabled(model.busy) } }
            .disabled(model.busy)
            .overlay { if model.busy { ProgressView(residentText("Working…")).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
            .sheet(item: $picker, onDismiss: presentPendingConfirmation) { request in
                if let save = model.document {
                    ResidentAnimalPicker(catalog: save.catalog, occupied: Set(save.slots.filter { $0.id != request.slot }.compactMap { $0.animal?.id }), browse: request.browse) { animal in
                        picker = nil
                        if let slot = request.slot { pendingConfirmation = .replace(slot, animal) }
                        else if let plot = request.plot { pendingConfirmation = .add(plot, animal) }
                    }
                }
            }
            .sheet(isPresented: $showBackups, onDismiss: presentPendingConfirmation) {
                NavigationStack {
                    List {
                        if let save = model.document, !save.backups.isEmpty {
                            ForEach(save.backups) { backup in
                                Button { showBackups = false; pendingConfirmation = .restore(backup) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(backup.date, format: .dateTime.year().month().day().hour().minute().second())
                                        Text(residentText("Restore this complete island save")).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else { Text(residentText("No backups yet.")) }
                    }
                    .navigationTitle(residentText("Backups and restore"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(residentText("Done")) { showBackups = false } } }
                }
                .residentSheetSize()
            }
            .alert(residentText("Apply this change?"), isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { action in
                Button(residentText("Cancel"), role: .cancel) { confirmation = nil }
                Button(residentText("Back up and apply"), role: .destructive) { apply(action); confirmation = nil }
            } message: { action in Text(description(action)) }
            .task { if model.document == nil { model.reload() } }
        }
        .interactiveDismissDisabled(model.busy)
        .residentSheetSize()
    }
    private var managerList: some View {
        List {
                if let save = model.document {
                    residentSummary(save)
                    Section {
                        ForEach(save.slots) { slot in
                            ResidentIslandRow(slot: slot, canDelete: save.count > 2) {
                                picker = AnimalPickerRequest(slot: slot.id, plot: nil, browse: false)
                            } delete: { confirmation = .remove(slot.id) }
                        }
                    } header: { Text(residentText("On this island")) } footer: {
                        Text(residentText("Replacement keeps the house, decorations and friendship. Deletion leaves an empty plot. Keep at least two residents."))
                    }
                    Section {
                        Button { showBackups = true } label: { Label(residentText("Backups and restore"), systemImage: "clock.arrow.circlepath") }
                    } footer: { Text(residentText("A full save backup is created before every change. Changes apply when you start the game.")) }
                } else if !model.busy {
                    Section { Text(residentText("Start the game and create an island save before using the manager.")).foregroundStyle(.secondary) }
                }
                if let error = model.error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
                if let message = model.message { Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            }
    }
    private func plotLabel(_ index: Int) -> String { residentText("Plot") + " " + String(index + 1) }
    private func residentSummary(_ save: ResidentSave) -> some View {
        Section {
                        HStack {
                            Label(residentText("Animal residents"), systemImage: "pawprint.fill")
                            Spacer()
                            Text("\(save.count) / 10").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button { picker = AnimalPickerRequest(slot: nil, plot: nil, browse: true) } label: {
                            Label(residentText("Browse all 417 animals"), systemImage: "magnifyingglass")
                        }
                        Menu {
                            ForEach(save.vacantPlots, id: \.self) { plot in
                                Button(plotLabel(plot)) { picker = AnimalPickerRequest(slot: nil, plot: plot, browse: false) }
                            }
                        } label: { Label(residentText("Add a resident"), systemImage: "plus.circle.fill") }
                        .disabled(save.count >= 10 || save.vacantPlots.isEmpty)
                    } footer: {
                        Text(residentText(save.count >= 10 ? "The island already has 10 animal residents." : save.vacantPlots.isEmpty ? "Place an empty housing plot in the game before adding a resident." : "New residents use an existing empty housing plot."))
                    }
    }
    private func presentPendingConfirmation() {
        confirmation = pendingConfirmation; pendingConfirmation = nil
    }
    private func description(_ action: ResidentConfirmation) -> String {
        switch action {
        case .replace(let slot, let animal):
            return (model.document?.slots[slot].animal?.name ?? "")+" → "+animal.name+"\n"+residentText("The house, decorations and friendship will be kept.")
        case .add(let plot, let animal): return animal.name+" → "+residentText("Plot")+" \(plot+1)"
        case .remove(let slot): return (model.document?.slots[slot].animal?.name ?? "")+"\n"+residentText("This animal will leave the island. The housing plot remains available.")
        case .restore: return residentText("Restore the entire island, including player progress, to this backup. Your current save will be backed up first.")
        }
    }
    private func apply(_ action: ResidentConfirmation) {
        model.message = nil
        model.perform { document in
            guard let save = document else { throw ResidentError.changed }
            switch action {
            case .replace(let slot, let animal): try save.replace(slot: slot, with: animal); try save.save()
            case .add(let plot, let animal): try save.add(animal, plot: plot); try save.save()
            case .remove(let slot): try save.remove(slot: slot); try save.save()
            case .restore(let backup): try save.restore(backup)
            }
            DispatchQueue.main.async { self.model.message = residentText("Saved. Start the game to see your changes.") }
        }
    }
}

private struct ResidentAnimalPicker: View {
    let catalog: ResidentCatalog
    let occupied: Set<String>
    let browse: Bool
    let choose: (ResidentAnimal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var species = -1
    @State private var personality = -1
    private var filtered: [ResidentAnimal] {
        catalog.animals.filter { animal in
            (species < 0 || animal.species == species) && (personality < 0 || animal.personality == personality) &&
            (query.isEmpty || [animal.name, animal.english, animal.id].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(residentText("Species"), selection: $species) {
                        Text(residentText("All species")).tag(-1)
                        ForEach(residentSpecies.indices, id: \.self) { Text(residentText(residentSpecies[$0])).tag($0) }
                    }
                    Picker(residentText("Personality"), selection: $personality) {
                        Text(residentText("All personalities")).tag(-1)
                        ForEach(residentPersonalities.indices, id: \.self) { Text(residentText(residentPersonalities[$0])).tag($0) }
                    }
                }
                Section("\(filtered.count) / 417") {
                    ForEach(filtered) { animal in
                        Button { if !browse { choose(animal) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(animal.name).font(.headline).foregroundStyle(.primary)
                                    Text(residentDetails(animal, english: true))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if occupied.contains(animal.id) { Text(residentText("On island")).font(.caption).foregroundStyle(.secondary) }
                                else if !browse { Image(systemName: "plus.circle").foregroundStyle(.tint) }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .disabled(!browse && occupied.contains(animal.id))
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: residentText("Search Chinese or English name"))
            .navigationTitle(residentText(browse ? "All animals" : "Choose an animal"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(residentText("Done")) { dismiss() } } }
        }
        .residentSheetSize()
    }
}

private struct ResidentIslandRow: View {
    let slot: ResidentSlot
    let canDelete: Bool
    let replace: () -> Void
    let delete: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Text("\(slot.id + 1)").font(.headline).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 30)
            if let animal = slot.animal {
                VStack(alignment: .leading, spacing: 5) {
                    Text(animal.name).font(.headline)
                    Text(residentDetails(animal)).font(.subheadline).foregroundStyle(.secondary)
                    if slot.moving { Text(residentText("Moving in progress")).font(.caption).foregroundStyle(.orange) }
                }
                Spacer()
                Menu {
                    Button(action: replace) { Label(residentText("Replace"), systemImage: "arrow.triangle.2.circlepath") }
                    Button(role: .destructive, action: delete) { Label(residentText("Delete resident"), systemImage: "trash") }
                        .disabled(!canDelete || slot.plot == nil)
                } label: { Image(systemName: "ellipsis.circle").font(.title2).padding(8) }
                .accessibilityLabel(residentText("Manage") + " " + animal.name)
                .disabled(slot.moving)
            } else { Text(residentText("Empty resident slot")).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}
