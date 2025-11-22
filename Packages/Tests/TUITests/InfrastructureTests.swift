@testable import Core
import Foundation
import Testing
import TestSupport
@testable import TUI

// MARK: - Colors Tests

@Test("Colors module has all ANSI escape codes")
func colorsANSICodes() {
    // Test basic codes exist and are non-empty
    #expect(!Colors.reset.isEmpty, "Reset code should exist")
    #expect(!Colors.bold.isEmpty, "Bold code should exist")
    #expect(!Colors.dim.isEmpty, "Dim code should exist")
    #expect(!Colors.italic.isEmpty, "Italic code should exist")
    #expect(!Colors.underline.isEmpty, "Underline code should exist")
    #expect(!Colors.invert.isEmpty, "Invert code should exist")

    // Test color codes
    #expect(!Colors.black.isEmpty, "Black code should exist")
    #expect(!Colors.red.isEmpty, "Red code should exist")
    #expect(!Colors.green.isEmpty, "Green code should exist")
    #expect(!Colors.yellow.isEmpty, "Yellow code should exist")
    #expect(!Colors.blue.isEmpty, "Blue code should exist")
    #expect(!Colors.magenta.isEmpty, "Magenta code should exist")
    #expect(!Colors.cyan.isEmpty, "Cyan code should exist")
    #expect(!Colors.white.isEmpty, "White code should exist")
    #expect(!Colors.gray.isEmpty, "Gray code should exist")

    // Test bright colors
    #expect(!Colors.brightRed.isEmpty, "Bright red code should exist")
    #expect(!Colors.brightGreen.isEmpty, "Bright green code should exist")
    #expect(!Colors.brightYellow.isEmpty, "Bright yellow code should exist")
    #expect(!Colors.brightBlue.isEmpty, "Bright blue code should exist")
    #expect(!Colors.brightMagenta.isEmpty, "Bright magenta code should exist")
    #expect(!Colors.brightCyan.isEmpty, "Bright cyan code should exist")
    #expect(!Colors.brightWhite.isEmpty, "Bright white code should exist")
}

@Test("Colors codes start with escape sequence")
func colorsEscapeSequence() {
    // All ANSI codes should start with ESC [
    #expect(Colors.reset.hasPrefix("\u{001B}["), "Reset should start with ESC [")
    #expect(Colors.bold.hasPrefix("\u{001B}["), "Bold should start with ESC [")
    #expect(Colors.red.hasPrefix("\u{001B}["), "Red should start with ESC [")
    #expect(Colors.brightCyan.hasPrefix("\u{001B}["), "Bright cyan should start with ESC [")
}

// MARK: - Box Drawing Tests

@Test("Box drawing characters exist")
func boxDrawingCharacters() {
    #expect(!Box.horizontal.isEmpty, "Horizontal line should exist")
    #expect(!Box.vertical.isEmpty, "Vertical line should exist")
    #expect(!Box.topLeft.isEmpty, "Top left corner should exist")
    #expect(!Box.topRight.isEmpty, "Top right corner should exist")
    #expect(!Box.bottomLeft.isEmpty, "Bottom left corner should exist")
    #expect(!Box.bottomRight.isEmpty, "Bottom right corner should exist")
    #expect(!Box.teeRight.isEmpty, "Tee right should exist")
    #expect(!Box.teeLeft.isEmpty, "Tee left should exist")
}

@Test("Box drawing characters are single character")
func boxDrawingSingleCharacter() {
    #expect(Box.horizontal.count == 1, "Horizontal should be single character")
    #expect(Box.vertical.count == 1, "Vertical should be single character")
    #expect(Box.topLeft.count == 1, "Top left should be single character")
    #expect(Box.topRight.count == 1, "Top right should be single character")
    #expect(Box.bottomLeft.count == 1, "Bottom left should be single character")
    #expect(Box.bottomRight.count == 1, "Bottom right should be single character")
    #expect(Box.teeRight.count == 1, "Tee right should be single character")
    #expect(Box.teeLeft.count == 1, "Tee left should be single character")
}

@Test("Box can draw simple frame")
func boxSimpleFrame() {
    // Test drawing a simple 10-character wide frame
    let width = 10
    let topLine = Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight
    let middleLine = Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical
    let bottomLine = Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2) + Box.bottomRight

    #expect(topLine.count == width, "Top line should be correct width")
    #expect(middleLine.count == width, "Middle line should be correct width")
    #expect(bottomLine.count == width, "Bottom line should be correct width")

    #expect(topLine.hasPrefix(Box.topLeft), "Top line should start with top left")
    #expect(topLine.hasSuffix(Box.topRight), "Top line should end with top right")
    #expect(middleLine.hasPrefix(Box.vertical), "Middle line should start with vertical")
    #expect(middleLine.hasSuffix(Box.vertical), "Middle line should end with vertical")
    #expect(bottomLine.hasPrefix(Box.bottomLeft), "Bottom line should start with bottom left")
    #expect(bottomLine.hasSuffix(Box.bottomRight), "Bottom line should end with bottom right")
}

// MARK: - Screen Tests

@Test("Screen constants exist")
func screenConstants() {
    #expect(!Screen.clearScreen.isEmpty, "Clear screen code should exist")
    #expect(!Screen.home.isEmpty, "Home code should exist")
    #expect(!Screen.hideCursor.isEmpty, "Hide cursor code should exist")
    #expect(!Screen.showCursor.isEmpty, "Show cursor code should exist")
}

@Test("Screen escape sequences are valid")
func screenEscapeSequences() {
    // All screen control codes should start with ESC [
    #expect(Screen.clearScreen.hasPrefix("\u{001B}["), "Clear screen should be ANSI escape")
    #expect(Screen.home.hasPrefix("\u{001B}["), "Home should be ANSI escape")
    #expect(Screen.hideCursor.hasPrefix("\u{001B}["), "Hide cursor should be ANSI escape")
    #expect(Screen.showCursor.hasPrefix("\u{001B}["), "Show cursor should be ANSI escape")
}

// MARK: - Input Key Tests

@Test("Input Key enum cases exist")
func inputKeyCases() {
    // Test that all key cases can be created
    _ = Key.arrowUp
    _ = Key.arrowDown
    _ = Key.arrowLeft
    _ = Key.arrowRight
    _ = Key.enter
    _ = Key.escape
    _ = Key.backspace
    _ = Key.space
    _ = Key.tab
    _ = Key.pageUp
    _ = Key.pageDown
    _ = Key.homeKey
    _ = Key.endKey
    _ = Key.deleteKey

    // Test character keys
    _ = Key.char("a")
    _ = Key.ctrl("c")
    _ = Key.paste("hello")
    _ = Key.unknown

    // Verify they all compile
    #expect(Bool(true), "All key cases should be defined")
}

@Test("Input Key paste case holds string data")
func inputKeyPasteData() {
    let pasteKey = Key.paste("Hello, World!")

    // Use pattern matching to extract the string
    if case let .paste(text) = pasteKey {
        #expect(text == "Hello, World!", "Paste key should hold the correct string")
    } else {
        #expect(Bool(false), "Should be a paste key")
    }
}

@Test("Input Key paste can hold paths")
func inputKeyPastePaths() {
    let path = "/Users/mmj/.cupertino"
    let pasteKey = Key.paste(path)

    if case let .paste(text) = pasteKey {
        #expect(text == path, "Paste key should hold file paths")
        #expect(text.contains("/"), "Path should contain slashes")
    } else {
        #expect(Bool(false), "Should be a paste key")
    }
}

// MARK: - Character Extension Tests

@Test("Character isPrintable allows letters and numbers")
func characterPrintableLettersNumbers() {
    #expect(Character("a").isPrintable, "Lowercase letter should be printable")
    #expect(Character("Z").isPrintable, "Uppercase letter should be printable")
    #expect(Character("0").isPrintable, "Number should be printable")
    #expect(Character("9").isPrintable, "Number should be printable")
}

@Test("Character isPrintable allows path characters")
func characterPrintablePathChars() {
    #expect(Character("/").isPrintable, "Forward slash should be printable")
    #expect(Character("-").isPrintable, "Dash should be printable")
    #expect(Character(".").isPrintable, "Dot should be printable")
    #expect(Character("_").isPrintable, "Underscore should be printable")
    #expect(Character("~").isPrintable, "Tilde should be printable")
    #expect(Character(":").isPrintable, "Colon should be printable")
    #expect(Character("@").isPrintable, "At sign should be printable")
}

@Test("Character isPrintable allows whitespace")
func characterPrintableWhitespace() {
    #expect(Character(" ").isPrintable, "Space should be printable")
}

@Test("Character isPrintable works with full path")
func characterPrintableFullPath() {
    let path = "/Users/mmj/.cupertino/test_dir"
    let allPrintable = path.allSatisfy(\.isPrintable)
    #expect(allPrintable, "All characters in a typical path should be printable")
}

@Test("Character isPrintable works with tilde path")
func characterPrintableTildePath() {
    let path = "~/.cupertino/my_files"
    let allPrintable = path.allSatisfy(\.isPrintable)
    #expect(allPrintable, "Tilde path with underscore should be printable")
}

// MARK: - FilterMode Tests

@Test("FilterMode has all cases")
func filterModeCases() {
    let all = FilterMode.all
    let selected = FilterMode.selected
    let downloaded = FilterMode.downloaded

    #expect(all.rawValue == "All", "All filter should have correct raw value")
    #expect(selected.rawValue == "Selected", "Selected filter should have correct raw value")
    #expect(downloaded.rawValue == "Downloaded", "Downloaded filter should have correct raw value")
}

@Test("FilterMode raw values are human readable")
func filterModeRawValues() {
    #expect(FilterMode.all.rawValue == "All", "All should be human readable")
    #expect(FilterMode.selected.rawValue == "Selected", "Selected should be human readable")
    #expect(FilterMode.downloaded.rawValue == "Downloaded", "Downloaded should be human readable")
}

// MARK: - ViewMode Tests

@Test("ViewMode has all view cases")
func viewModeCases() {
    _ = ViewMode.home
    _ = ViewMode.packages
    _ = ViewMode.library
    _ = ViewMode.settings

    // Verify they compile
    #expect(Bool(true), "All view mode cases should exist")
}

// MARK: - SortMode Tests

@Test("SortMode has all cases")
func sortModeCases() {
    _ = SortMode.stars
    _ = SortMode.name
    _ = SortMode.recent

    // Verify all cases exist
    #expect(Bool(true), "All sort mode cases should exist")
}
