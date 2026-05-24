import Foundation

// MARK: - Search.SourceRegistry

extension Search {
    /// Composition-root value type holding the production list of
    /// `SourceProvider` conformers. Adding a new source to the live
    /// CLI binary post-#1007 is one `.register(<X>Source())` call at
    /// the composition root (`CLIImpl.makeProductionSourceRegistry`).
    ///
    /// Mirror of `mihaela-analytics/secret-life/Packages/Sources/Import/Importer/ImporterRegistry.swift`
    /// (the audited prior art, 48 conformers). Per-id keyed dict
    /// allows quick lookup at indexer-dispatch time; iteration order
    /// follows insertion order via a backing array for deterministic
    /// printable output across `Search.SourceLookup` and
    /// `Distribution.SetupService` style surfaces.
    public struct SourceRegistry: Sendable {
        public struct Entry: Sendable {
            public let provider: any Search.SourceProvider
            public let isEnabled: Bool

            public init(provider: any Search.SourceProvider, isEnabled: Bool = true) {
                self.provider = provider
                self.isEnabled = isEnabled
            }
        }

        private var entries: [Entry] = []

        public init() {}

        /// Register a provider. Idempotent on `definition.id`: a
        /// re-register replaces the prior entry, preserving its
        /// insertion-order slot AND its prior `isEnabled` flag (unless
        /// `isEnabled:` is passed explicitly). The flag-preservation
        /// avoids silently re-enabling a source that operators
        /// disabled via `setEnabled(false, …)` after a composition
        /// root refresh or hot-reload re-runs the same `register`
        /// calls. Pass `isEnabled: true` to explicitly force-enable
        /// on re-register.
        public mutating func register(
            _ provider: any Search.SourceProvider,
            isEnabled: Bool? = nil
        ) {
            if let existingIndex = entries.firstIndex(where: { $0.provider.definition.id == provider.definition.id }) {
                let preserved = isEnabled ?? entries[existingIndex].isEnabled
                entries[existingIndex] = Entry(provider: provider, isEnabled: preserved)
            } else {
                entries.append(Entry(provider: provider, isEnabled: isEnabled ?? true))
            }
        }

        /// Mutate the enabled flag on an existing entry by id. No-op
        /// when the id is not registered.
        public mutating func setEnabled(_ enabled: Bool, forSourceID sourceID: String) {
            guard let idx = entries.firstIndex(where: { $0.provider.definition.id == sourceID }) else { return }
            entries[idx] = Entry(provider: entries[idx].provider, isEnabled: enabled)
        }

        /// Providers in insertion order, including disabled ones.
        public var all: [any Search.SourceProvider] {
            entries.map(\.provider)
        }

        /// Providers in insertion order, excluding disabled ones.
        public var allEnabled: [any Search.SourceProvider] {
            entries.filter(\.isEnabled).map(\.provider)
        }

        /// Lookup by source id (e.g. `"apple-docs"`). Returns the
        /// provider if registered and enabled; nil otherwise.
        public func provider(for sourceID: String) -> (any Search.SourceProvider)? {
            entries.first(where: { $0.provider.definition.id == sourceID && $0.isEnabled })?.provider
        }

        /// Lookup including disabled providers; for diagnostic surfaces
        /// (Doctor, `cupertino list-sources`) that want to surface
        /// "registered but turned off" entries.
        public func entry(for sourceID: String) -> Entry? {
            entries.first(where: { $0.provider.definition.id == sourceID })
        }

        /// Number of registered providers (enabled + disabled).
        public var count: Int { entries.count }

        /// `true` when zero providers are registered. The composition
        /// root should never reach the indexer-dispatch path with an
        /// empty registry; treat as a configuration error at the door.
        public var isEmpty: Bool { entries.isEmpty }
    }
}
