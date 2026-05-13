import SearchModels

// MARK: - Search.Index ↔ Search.Database

// `Search.Index` already implements every method on `Search.Database`:
// `search`, `getDocumentContent`, `listFrameworks`, `documentCount`, and
// `disconnect`. The declaration below witnesses the conformance so
// Services / MCPSupport / CLI consumers can accept `any Search.Database`
// and have a production `Search.Index` flow through unchanged.
//
// The protocol itself lives in SearchModels; this conformance lives in
// the Search target because it touches the actor.

extension Search.Index: Search.Database {}
