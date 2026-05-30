@testable import CLI
import Foundation
import SharedConstants
import Testing

// MARK: - #919 ironclad coverage pin: Doctor's schema-version line formatter

@Suite("#919 ironclad: Doctor.renderSchemaVersionLine")
struct Issue919SchemaVersionLineFormatTests {
    @Test("Label is descriptor.filename, not descriptor.id (search.db, not search)")
    func labelUsesFilename() {
        let line = CLIImpl.Command.Doctor.renderSchemaVersionLine(
            descriptor: .search,
            formatted: "v18",
            journalNote: "wal",
            walNote: "",
            volumeNote: ""
        )
        // Pin: the doctor output addresses databases by their on-disk
        // filename, so users can correlate the line against their
        // ~/.cupertino/ directory listing. A regression that swapped
        // descriptor.filename for descriptor.id would silently change
        // the label from "search.db" to "search" and confuse users.
        #expect(line == "   ✓ search.db: v18, journal=wal")
        #expect(line.contains("search.db"))
        #expect(!line.contains(": search,")) // not the id
    }

    @Test("All 3 historical descriptors render with their canonical filenames")
    func threeHistoricalDescriptorsRender() {
        for (descriptor, expectedFilename) in [
            (Shared.Models.DatabaseDescriptor.search, "search.db"),
            (Shared.Models.DatabaseDescriptor.samples, "samples.db"),
            (Shared.Models.DatabaseDescriptor.packages, "packages.db"),
        ] {
            let line = CLIImpl.Command.Doctor.renderSchemaVersionLine(
                descriptor: descriptor,
                formatted: "v1",
                journalNote: "wal",
                walNote: "",
                volumeNote: ""
            )
            #expect(line.contains(expectedFilename), "\(descriptor.id) should render with \(expectedFilename)")
        }
    }

    @Test("WAL note appends after journal mode, before volume warning")
    func walNoteAppendsCorrectly() {
        let line = CLIImpl.Command.Doctor.renderSchemaVersionLine(
            descriptor: .search,
            formatted: "v18",
            journalNote: "wal",
            walNote: ", wal=4 KB",
            volumeNote: ""
        )
        #expect(line == "   ✓ search.db: v18, journal=wal, wal=4 KB")
    }

    @Test("Volume note appends at the end, after walNote")
    func volumeNoteAppendsAtEnd() {
        let line = CLIImpl.Command.Doctor.renderSchemaVersionLine(
            descriptor: .search,
            formatted: "v18",
            journalNote: "wal",
            walNote: "",
            volumeNote: ", volume=non-local"
        )
        #expect(line == "   ✓ search.db: v18, journal=wal, volume=non-local")
    }

    @Test("All three suffix notes coexist in the documented order")
    func allThreeSuffixesCoexist() {
        let line = CLIImpl.Command.Doctor.renderSchemaVersionLine(
            descriptor: .packages,
            formatted: "v3",
            journalNote: "wal",
            walNote: ", wal=8 MB",
            volumeNote: ", volume=non-local"
        )
        #expect(line == "   ✓ packages.db: v3, journal=wal, wal=8 MB, volume=non-local")
    }

    @Test("Non-wal journal mode renders the documented warning prose")
    func nonWalJournalRendersWarning() {
        let line = CLIImpl.Command.Doctor.renderSchemaVersionLine(
            descriptor: .samples,
            formatted: "v8",
            journalNote: "delete ⚠ (expected wal: run `cupertino save` for this DB)",
            walNote: "",
            volumeNote: ""
        )
        #expect(line.contains("samples.db"))
        #expect(line.contains("journal=delete"))
        #expect(line.contains("expected wal"))
    }

    // MARK: - #1192: journalModeNote accepts rollback (delete) mode

    @Test("wal journal mode carries no warning")
    func journalNoteWAL() {
        #expect(CLIImpl.Command.Doctor.journalModeNote(for: "wal") == "wal")
    }

    @Test("delete journal mode is the read-only distribution mode, no warning")
    func journalNoteDeleteIsHealthy() {
        let note = CLIImpl.Command.Doctor.journalModeNote(for: "delete")
        #expect(note == "delete (read-only distribution mode)")
        #expect(!note.contains("⚠"))
    }

    @Test("an unexpected journal mode is still flagged")
    func journalNoteUnexpectedFlagged() {
        let note = CLIImpl.Command.Doctor.journalModeNote(for: "truncate")
        #expect(note.contains("truncate"))
        #expect(note.contains("⚠"))
    }
}
