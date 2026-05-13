import Foundation
import SharedConstants

// MARK: - Shared.Utils.SQL

/// SQL string builders shared across Search and SampleIndex.
///
/// This namespace deliberately does NOT execute SQL — each call site
/// continues to prepare / step / finalize through its own SQLite3
/// handle. The helpers just centralize the canonical wording of
/// frequently-typed queries so the project doesn't accumulate ten
/// near-identical literal strings.
extension Shared.Utils {
    public enum SQL {
        /// Returns the canonical `SELECT COUNT(*) FROM <table>;` query.
        ///
        /// Used by `Search.Index.documentCount()`, `Sample.Index.Database.projectCount()`,
        /// and the half-dozen other row-count fetches across the search-
        /// and sample-index targets. Single-source-of-truth wording means
        /// any future change (e.g. `SELECT COUNT(1)` for SQLite3 query-
        /// planner reasons) is a one-line edit.
        ///
        /// `table` is interpolated raw — callers are responsible for
        /// passing a fixed table-name literal, not user input.
        public static func countRows(in table: String) -> String {
            "SELECT COUNT(*) FROM \(table);"
        }
    }
}
