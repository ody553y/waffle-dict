import Foundation
import ScreamerCore

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var catalog: [ModelCatalogEntry] = []
    @Published private(set) var catalogSource: ModelCatalogSource = .bundled
    @Published private(set) var remoteUpdateNotice: String?
    @Published private(set) var installedModelIDs: Set<String> = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var activeDownloadID: String?
    @Published private(set) var progressByModelID: [String: Double] = [:]
    @Published private(set) var errorByModelID: [String: String] = [:]

    private let catalogService: ModelCatalogService
    private let downloadService: ModelDownloadService
    private let defaults: UserDefaults
    private let selectedModelIDKey = "selectedModelId"
    private var activeDownloadTask: Task<Void, Never>?

    init(
        catalogService: ModelCatalogService = ModelCatalogService(),
        downloadService: ModelDownloadService? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.catalogService = catalogService
        self.downloadService = downloadService ?? ModelDownloadService(catalogService: catalogService)
        self.defaults = defaults
        self.selectedModelID = defaults.string(forKey: selectedModelIDKey)
        refreshCatalog()
        refreshCatalogFromRemote()
    }

    var installedEntries: [ModelCatalogEntry] {
        catalog.filter { installedModelIDs.contains($0.id) }
    }

    var hasInstalledModels: Bool {
        installedEntries.isEmpty == false
    }

    var resolvedSelectedModelID: String? {
        catalogService.resolveSelectedModelID(currentSelection: selectedModelID)
    }

    var selectedEntry: ModelCatalogEntry? {
        guard let resolvedSelectedModelID else { return nil }
        return catalog.first { $0.id == resolvedSelectedModelID }
    }

    func refreshCatalog() {
        do {
            catalog = try catalogService.loadCatalog()
            catalogSource = .bundled
        } catch {
            catalog = []
            catalogSource = .bundled
        }
        remoteUpdateNotice = nil
        refreshInstalledState()
    }

    func refreshCatalogFromRemote() {
        Task { [weak self] in
            await self?.refreshCatalogAsync()
        }
    }

    func setSelectedModelID(_ id: String?) {
        selectedModelID = id
        persistSelectedModelID(id)
        normalizeSelectedModelID()
    }

    func download(entry: ModelCatalogEntry) {
        guard entry.available else { return }
        guard activeDownloadID == nil else { return }

        errorByModelID[entry.id] = nil
        activeDownloadID = entry.id
        progressByModelID[entry.id] = 0

        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.downloadService.resume(entry: entry) { progress in
                    Task { @MainActor [weak self] in
                        self?.progressByModelID[entry.id] = progress
                    }
                }
                await MainActor.run {
                    self.progressByModelID.removeValue(forKey: entry.id)
                    self.errorByModelID[entry.id] = nil
                    self.activeDownloadID = nil
                    self.refreshInstalledState()
                }
            } catch {
                await MainActor.run {
                    self.progressByModelID.removeValue(forKey: entry.id)
                    self.activeDownloadID = nil
                    if (error as? ModelDownloadError) != .cancelled {
                        self.errorByModelID[entry.id] = error.localizedDescription
                    }
                }
            }
        }
    }

    func removeInstalledModel(id: String) {
        do {
            try catalogService.removeInstalledModel(id: id)
            errorByModelID[id] = nil
        } catch {
            errorByModelID[id] = error.localizedDescription
        }
        refreshInstalledState()
    }

    func isInstalled(_ entry: ModelCatalogEntry) -> Bool {
        installedModelIDs.contains(entry.id)
    }

    func progress(for id: String) -> Double {
        progressByModelID[id] ?? 0
    }

    func errorMessage(for id: String) -> String? {
        errorByModelID[id]
    }

    private func refreshInstalledState() {
        installedModelIDs = Set(catalogService.installedModels())
        normalizeSelectedModelID()
    }

    private func refreshCatalogAsync() async {
        let previousIDs = Set(catalog.map(\.id))
        let result = await catalogService.loadCatalogWithRemoteFallbackResult()
        catalog = result.entries
        catalogSource = result.source

        let newIDs = Set(result.entries.map(\.id)).subtracting(previousIDs)
        remoteUpdateNotice = (result.source == .remote && newIDs.isEmpty == false)
            ? "Updated model catalog"
            : nil

        refreshInstalledState()
    }

    private func normalizeSelectedModelID() {
        let resolved = catalogService.resolveSelectedModelID(currentSelection: selectedModelID)
        if selectedModelID != resolved {
            selectedModelID = resolved
            persistSelectedModelID(resolved)
        }
    }

    private func persistSelectedModelID(_ id: String?) {
        if let id {
            defaults.set(id, forKey: selectedModelIDKey)
        } else {
            defaults.removeObject(forKey: selectedModelIDKey)
        }
    }
}
