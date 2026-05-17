import ArgumentParser

/// Namespace for the `cupertino-constraints-gen` binary.
///
/// Mirrors the `Release.Command.*` pattern (see `Release.swift`):
/// the root `AsyncParsableCommand` lives at file scope in
/// `ConstraintsGenCLI.swift`; subcommand structs (currently just
/// `Generate`) live under `ConstraintsGen.Command.*`.
///
/// **What this binary does.** Reads `swift symbolgraph-extract`
/// JSON files and emits the filtered constraint table consumed by
/// the cupertino indexer's iteration-3 static-constraints pass
/// (#759). One-shot tool; intended to be re-run when Apple ships a
/// new SDK.
///
/// **Composition root.** Per `gof-di-rules.md` rule 6 the binary
/// name (`cupertino-constraints-gen`) stays clean; the wiring
/// namespace `ConstraintsGenImpl` (in `ConstraintsGenImpl.swift`)
/// holds the live concretes. for now there's only one collaborator
/// (`AppleConstraintsKit.Extractor`) so the *Impl layer is thin, but
/// the namespace is reserved for the same convention every cupertino
/// binary follows.
enum ConstraintsGen {
    /// Subcommand namespace. One entry per generator subcommand;
    /// today there's just `Generate`, but a future `Validate` or
    /// `Diff` subcommand would slot in here.
    enum Command {}
}
