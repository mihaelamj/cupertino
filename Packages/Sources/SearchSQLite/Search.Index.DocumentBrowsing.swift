import SearchModels

// MARK: - Search.DocumentBrowsing

// `Search.Index` already implements both halves of the composed browser
// contract: `Search.DocumentListing` and `Search.DocumentChildrenListing`.
// This witness lets app-facing backend surfaces type against the combined
// protocol without downcasting through the two refinements manually.
extension Search.Index: Search.DocumentBrowsing {}
