import Foundation
import SearchModels

extension Search.Index {
    /// Split a CamelCase / PascalCase identifier into recall-aiding components
    /// (#77).
    ///
    /// Walks the identifier and groups consecutive runs of uppercase letters
    /// as one acronym unit, then treats the last cap of an acronym run as
    /// the head of the next word if followed by lowercase. Mirrors the
    /// rule lock in the issue spec:
    ///
    /// - `LazyVGrid`     → `{Lazy, VGrid, Grid}` (single-letter `V` dropped by
    ///   min-length 3)
    /// - `URLSession`    → `{URL, Session}`
    /// - `JSONDecoder`   → `{JSON, Decoder}`
    /// - `HTTPSCookieStorage` → `{HTTPS, Cookie, Storage}`
    /// - `XMLParser`     → `{XML, Parser}`
    ///
    /// Caller is responsible for inserting the original identifier into the
    /// same recall column if they want both forms to match — this function
    /// only returns the SPLITS, not the original. The splitter is acronym-
    /// aware on purpose: the naive case-boundary regex would mis-split
    /// `URLSession` into `{U, R, L, Session}` (every cap a boundary) which
    /// adds no recall value and floods the index with garbage one-letter
    /// tokens.
    ///
    /// Defensive limits per the spec:
    ///
    /// - **min component length 3** drops `V`, `UI`, `IO`, `2D` (single-/
    ///   two-letter fragments rarely improve recall and cost index space).
    /// - **per-call dedupe** so `JSONJSON` doesn't write two `JSON` rows.
    /// - **no stopword list** — `View`, `Manager`, `Controller`, `Delegate`
    ///   are legitimate query terms and real API-family anchors.
    ///
    /// Returns an empty array when the input has nothing splittable
    /// (single word, all-lower, all-digits, empty). Callers should treat
    /// `empty → keep existing symbols column unchanged`.
    // swiftlint:disable:next function_body_length
    static func splitCamelCaseIdentifier(_ identifier: String) -> [String] {
        let raw = identifier.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }

        // Walk the string once. State: current run buffer + whether the
        // run is in an "uppercase acronym" or "regular word" phase.
        var parts: [String] = []
        var buffer: [Character] = []
        var prevWasUpper = false
        var prevWasLetter = false

        func flush() {
            if !buffer.isEmpty {
                parts.append(String(buffer))
                buffer.removeAll(keepingCapacity: true)
            }
        }

        for (index, char) in raw.enumerated() {
            let isUpper = char.isUppercase
            let isLetter = char.isLetter
            let isLower = char.isLowercase

            if !isLetter {
                // Boundary on any non-letter (digit, underscore, dot, etc.).
                flush()
                prevWasUpper = false
                prevWasLetter = false
                continue
            }

            if isUpper {
                // Acronym → next-word boundary: the previous char was upper
                // AND the next char (peek) is lower. Example: `URLSession`
                // walking past the `S` — `L` (upper) precedes, `e` (lower)
                // follows, so the `S` starts a new word and the buffer
                // (`URL`) flushes here.
                let next = index + 1 < raw.count
                    ? raw[raw.index(raw.startIndex, offsetBy: index + 1)]
                    : nil
                let nextIsLower = next?.isLowercase ?? false
                if prevWasUpper, nextIsLower {
                    flush()
                }
                // Regular cap boundary: previous char was lower (or non-
                // letter), so this upper starts a new word. Example:
                // `LazyV` walking past `V` — `y` (lower) precedes, so the
                // `V` starts a fresh word (`y` already flushed `Lazy`).
                if prevWasLetter, !prevWasUpper {
                    flush()
                }
                buffer.append(char)
            } else if isLower {
                buffer.append(char)
            }

            prevWasUpper = isUpper
            prevWasLetter = isLetter
        }
        flush()

        // Per spec: dedupe + min length 3. But before filtering short
        // fragments, fold them forward into the next fragment so the
        // information survives. `LazyVGrid` walks out as `[Lazy, V,
        // Grid]`; bare-filter would drop `V` and emit `[Lazy, Grid]`
        // — usable but loses the `VGrid` acronym a user might query.
        // The spec lists `{LazyVGrid, Lazy, V, Grid, VGrid}` as the
        // produced set (V filtered by R2). The merge-forward rule
        // recovers `VGrid` while still emitting the standalone `Grid`,
        // so both `search("grid")` and `search("vgrid")` find the page.
        // Two-letter fragments (`UI`, `IO`, `2D`) get the same
        // treatment — `UIView` produces `View` standalone AND `UIView`
        // via the merge (which dedupes with the original identifier
        // when present, so no double-index).
        var merged: [String] = []
        var pendingShort = ""
        for part in parts {
            if part.count < 3 {
                pendingShort += part
                continue
            }
            if !pendingShort.isEmpty {
                merged.append(pendingShort + part)
                pendingShort = ""
            }
            merged.append(part)
        }
        // Trailing short fragment with nothing to merge into: drop it.
        // (`A2D` → walks to `A`/`2`/`D`, all short, merged together as
        // `A2D` which equals the original — dedup handles it.)
        if !pendingShort.isEmpty, pendingShort.count >= 3 {
            merged.append(pendingShort)
        }

        // Don't lowercase; the FTS5 unicode61 tokeniser handles case
        // folding at query time, and keeping the original case preserves
        // exact-match signal for acronyms (`URL` matches `URL` and `url`).
        var seen: Set<String> = []
        var result: [String] = []
        for part in merged where part.count >= 3 {
            let lower = part.lowercased()
            if seen.insert(lower).inserted {
                result.append(part)
            }
        }
        return result
    }

    /// Bulk variant: split many identifiers and return the deduped union.
    /// `recomputeSymbolsBlob` calls this once per page.
    static func splitCamelCaseIdentifiers(_ identifiers: some Collection<String>) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for identifier in identifiers {
            for component in splitCamelCaseIdentifier(identifier)
                where seen.insert(component.lowercased()).inserted {
                result.append(component)
            }
        }
        return result
    }
}
