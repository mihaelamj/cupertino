⏺ Detailed TUI Instructions for cupertino-curator

  Architecture

  Package.swift additions:
  // In macOSOnlyProducts:
  .executable(name: "cupertino-curator", targets: ["Curator"]),

  // In cupertinoTargets:
  let curatorTarget = Target.executableTarget(
	  name: "Curator",
	  dependencies: [
		  "Shared",
		  "Resources",
		  .product(name: "ArgumentParser", package: "swift-argument-parser"),
	  ]
  )

  File Structure

  Sources/Curator/
  ├── main.swift              # Entry point
  ├── CuratorApp.swift        # Main application logic
  ├── TUI/
  │   ├── Screen.swift        # Terminal control & ANSI codes
  │   ├── Colors.swift        # Color definitions
  │   ├── Input.swift         # Keyboard input handling
  │   └── Layout.swift        # Box drawing & layout
  ├── Models/
  │   ├── PackageListState.swift   # App state
  │   └── PackageEntry.swift       # Package + selection status
  └── Views/
	  ├── HeaderView.swift    # Title bar
	  ├── PackageListView.swift  # Main list
	  ├── StatusBarView.swift    # Bottom bar with keybindings
	  └── SearchView.swift    # Search overlay

  Core Components

  1. Screen.swift - Terminal Control

  import Foundation

  actor Screen {
	  // ANSI escape codes
	  static let ESC = "\u{001B}["
	  static let clearScreen = "\(ESC)2J"
	  static let hideCursor = "\(ESC)?25l"
	  static let showCursor = "\(ESC)?25h"
	  static let home = "\(ESC)H"

	  // Terminal size
	  func getSize() -> (rows: Int, cols: Int) {
		  // Use ioctl TIOCGWINSZ
		  var w = winsize()
		  if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
			  return (Int(w.ws_row), Int(w.ws_col))
		  }
		  return (24, 80)
	  }

	  // Raw mode (no buffering, no echo)
	  func enableRawMode() -> termios {
		  var original = termios()
		  tcgetattr(STDIN_FILENO, &original)

		  var raw = original
		  raw.c_lflag &= ~(UInt(ECHO | ICANON | ISIG | IEXTEN))
		  raw.c_iflag &= ~(UInt(IXON | ICRNL | BRKINT | INPCK | ISTRIP))
		  raw.c_oflag &= ~(UInt(OPOST))
		  raw.c_cflag |= UInt(CS8)

		  tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
		  return original
	  }

	  func disableRawMode(_ original: termios) {
		  var orig = original
		  tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
	  }

	  // Cursor positioning
	  func moveTo(row: Int, col: Int) -> String {
		  "\(Screen.ESC)\(row);\(col)H"
	  }

	  // Rendering
	  func render(_ content: String) {
		  print(Screen.clearScreen + Screen.home + content, terminator: "")
		  fflush(stdout)
	  }
  }

  2. Input.swift - Keyboard Handling

  enum Key {
	  case up, down, left, right
	  case space, tab, enter, escape
	  case char(Character)
	  case ctrl(Character)
	  case unknown
  }

  class Input {
	  func readKey() -> Key? {
		  var buffer = [UInt8](repeating: 0, count: 3)
		  let count = read(STDIN_FILENO, &buffer, 3)

		  if count == 1 {
			  switch buffer[0] {
			  case 27: return .escape  // ESC
			  case 32: return .space
			  case 9: return .tab
			  case 13: return .enter
			  case 3: return .ctrl("c")
			  case 65...90: return .ctrl(Character(UnicodeScalar(buffer[0])))
			  case 97...122: return .char(Character(UnicodeScalar(buffer[0])))
			  default: return .unknown
			  }
		  }

		  // Arrow keys: ESC [ A/B/C/D
		  if count == 3 && buffer[0] == 27 && buffer[1] == 91 {
			  switch buffer[2] {
			  case 65: return .up
			  case 66: return .down
			  case 67: return .right
			  case 68: return .left
			  default: return .unknown
			  }
		  }

		  return .unknown
	  }
  }

  3. Layout.swift - Box Drawing

  struct Box {
	  // Box drawing characters (UTF-8)
	  static let topLeft = "┌"
	  static let topRight = "┐"
	  static let bottomLeft = "└"
	  static let bottomRight = "┘"
	  static let horizontal = "─"
	  static let vertical = "│"
	  static let teeDown = "┬"
	  static let teeUp = "┴"

	  static func draw(width: Int, height: Int, title: String? = nil) -> String {
		  var result = ""

		  // Top border
		  result += topLeft
		  if let title = title {
			  let titleText = " \(title) "
			  let remaining = width - 2 - titleText.count
			  result += String(repeating: horizontal, count: remaining / 2)
			  result += titleText
			  result += String(repeating: horizontal, count: remaining - remaining / 2)
		  } else {
			  result += String(repeating: horizontal, count: width - 2)
		  }
		  result += topRight + "\n"

		  // Middle (empty lines)
		  for _ in 0..<(height - 2) {
			  result += vertical + String(repeating: " ", count: width - 2) + vertical + "\n"
		  }

		  // Bottom border
		  result += bottomLeft + String(repeating: horizontal, count: width - 2) + bottomRight + "\n"

		  return result
	  }
  }

  4. PackageListState.swift - App State

  struct PackageEntry {
	  let package: SwiftPackagesCatalog.Package
	  var isSelected: Bool
  }

  enum SortMode: String {
	  case stars = "Stars ▼"
	  case name = "Name ▲"
	  case recent = "Recent ▼"
  }

  class PackageListState {
	  var packages: [PackageEntry] = []
	  var cursor: Int = 0
	  var scrollOffset: Int = 0
	  var sortMode: SortMode = .stars
	  var searchQuery: String = ""
	  var showOnlySelected: Bool = false

	  var visiblePackages: [PackageEntry] {
		  var filtered = packages

		  // Apply search filter
		  if !searchQuery.isEmpty {
			  filtered = filtered.filter { entry in
				  entry.package.name.localizedCaseInsensitiveContains(searchQuery) ||
				  entry.package.description?.localizedCaseInsensitiveContains(searchQuery) == true
			  }
		  }

		  // Apply selection filter
		  if showOnlySelected {
			  filtered = filtered.filter { $0.isSelected }
		  }

		  // Apply sort
		  switch sortMode {
		  case .stars:
			  return filtered.sorted { $0.package.stars > $1.package.stars }
		  case .name:
			  return filtered.sorted { $0.package.name < $1.package.name }
		  case .recent:
			  return filtered.sorted { ($0.package.updatedAt ?? "") > ($1.package.updatedAt ?? "") }
		  }
	  }

	  func toggleCurrent() {
		  let visible = visiblePackages
		  if cursor < visible.count {
			  if let index = packages.firstIndex(where: { $0.package.url == visible[cursor].package.url }) {
				  packages[index].isSelected.toggle()
			  }
		  }
	  }

	  func moveCursor(delta: Int, pageSize: Int) {
		  let visible = visiblePackages
		  cursor = max(0, min(cursor + delta, visible.count - 1))

		  // Auto-scroll
		  if cursor < scrollOffset {
			  scrollOffset = cursor
		  } else if cursor >= scrollOffset + pageSize {
			  scrollOffset = cursor - pageSize + 1
		  }
	  }
  }

  5. PackageListView.swift - Main List Rendering

  struct PackageListView {
	  func render(state: PackageListState, width: Int, height: Int) -> String {
		  var result = ""
		  let visible = state.visiblePackages
		  let pageSize = height - 4  // Account for header, footer
		  let page = visible.dropFirst(state.scrollOffset).prefix(pageSize)

		  for (index, entry) in page.enumerated() {
			  let absoluteIndex = state.scrollOffset + index
			  let isCurrentLine = absoluteIndex == state.cursor

			  // Selection indicator
			  let checkbox = entry.isSelected ? "[★]" : "[ ]"

			  // Format: [★] owner/repo    ⭐ 89,855
			  let name = "\(entry.package.owner)/\(entry.package.repo)"
			  let stars = formatStars(entry.package.stars)
			  let padding = width - checkbox.count - name.count - stars.count - 10

			  var line = checkbox + " " + name
			  line += String(repeating: " ", count: max(1, padding))
			  line += stars

			  // Highlight current line
			  if isCurrentLine {
				  line = Colors.invert + line + Colors.reset
			  }

			  result += line + "\n"

			  // Description on second line
			  if let desc = entry.package.description?.prefix(width - 5) {
				  result += "    " + String(desc) + "\n"
			  } else {
				  result += "\n"
			  }
		  }

		  return result
	  }

	  private func formatStars(_ stars: Int) -> String {
		  "⭐ " + NumberFormatter.localizedString(from: NSNumber(value: stars), number: .decimal)
	  }
  }

  6. Main Application Loop

  @main
  struct CuratorApp {
	  static func main() async throws {
		  // Load packages
		  let catalog = try SwiftPackagesCatalog.load()
		  let priorityPackages = try? PriorityPackagesCatalog.load()

		  let state = PackageListState()
		  state.packages = catalog.packages.map { pkg in
			  let isSelected = priorityPackages?.packages.contains { $0.url == pkg.url } ?? false
			  return PackageEntry(package: pkg, isSelected: isSelected)
		  }

		  let screen = Screen()
		  let input = Input()
		  let originalTermios = screen.enableRawMode()

		  print(Screen.hideCursor, terminator: "")

		  defer {
			  screen.disableRawMode(originalTermios)
			  print(Screen.showCursor)
		  }

		  var running = true
		  while running {
			  // Render
			  let (rows, cols) = screen.getSize()
			  var output = ""
			  output += HeaderView.render(state: state, width: cols)
			  output += PackageListView().render(state: state, width: cols, height: rows - 2)
			  output += StatusBarView.render(width: cols)

			  screen.render(output)

			  // Handle input
			  if let key = input.readKey() {
				  switch key {
				  case .up, .char("k"):
					  state.moveCursor(delta: -1, pageSize: rows - 4)
				  case .down, .char("j"):
					  state.moveCursor(delta: 1, pageSize: rows - 4)
				  case .space, .tab:
					  state.toggleCurrent()
				  case .char("g"):
					  openGitHub(state.visiblePackages[state.cursor].package)
				  case .char("s"):
					  cycleSortMode(state)
				  case .char("/"):
					  enterSearchMode(state)
				  case .char("w"):
					  try saveSelection(state)
				  case .char("q"), .ctrl("c"):
					  running = false
				  default:
					  break
				  }
			  }
		  }
	  }

	  private static func openGitHub(_ package: SwiftPackagesCatalog.Package) {
		  Process.run("open", arguments: [package.url])
	  }

	  private static func saveSelection(_ state: PackageListState) throws {
		  let selected = state.packages.filter { $0.isSelected }
		  // Save to priority-packages.json
	  }
  }

  Key Features to Implement

  1. Page-by-page navigation - Use scrollOffset and calculate visible window
  2. Search mode - Overlay that captures input until Enter/Escape
  3. GitHub opening - Use Process to run open command
  4. Save to priority-packages.json - Use existing JSONCoding utilities
  5. Status indicators - Show selection count, page number

  Colors & Styling

  struct Colors {
	  static let reset = "\u{001B}[0m"
	  static let bold = "\u{001B}[1m"
	  static let invert = "\u{001B}[7m"
	  static let gray = "\u{001B}[90m"
	  static let green = "\u{001B}[32m"
	  static let blue = "\u{001B}[34m"
	  static let yellow = "\u{001B}[33m"
  }

  Testing

  Start simple - render static list first, then add:
  1. Navigation (up/down)
  2. Selection (space)
  3. GitHub opening (g)
  4. Search (/)
  5. Save (w)

  This gives you a fully functional TUI curator tool!