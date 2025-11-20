# TUI App Behavior Analysis (Swift)

## 1. Input / Key Handling

### Observations
- Regular character input works normally.
- Special keys (arrows, etc.) sometimes lag or fail.
- Occasional “eaten” keystrokes or delayed processing.

### Likely Causes
- Terminal is in cooked mode instead of raw mode.
- Termios flags (`ICANON`, `ECHO`) not fully disabled.
- `VMIN`/`VTIME` not configured correctly.
- Escape sequences not fully parsed.

### Suggested Swift Implementation
```swift
import Darwin

final class TerminalInput {
    private var original = termios()
    private var raw = termios()

    init() {
        tcgetattr(STDIN_FILENO, &original)
        raw = original

        raw.c_lflag &= ~(UInt(ECHO | ICANON))
        raw.c_cc.16 = 1 // VMIN
        raw.c_cc.17 = 0 // VTIME

        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    deinit {
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
    }

    func readKey() -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: 8)
        let n = read(STDIN_FILENO, &buf, buf.count)
        guard n > 0 else { return nil }
        return Array(buf.prefix(n))
    }
}
```

---

## 2. Rendering / Flicker / Jumps

### Observations
- Frequent full-screen clears.
- Flicker between frames.
- Cursor jumps caused by newlines.
- Entire screen redraws on small changes.

### Likely Causes
- Clearing screen with `ESC[2J` every update.
- No diffing of virtual screen.
- Cursor visibility not consistently disabled.
- No dedicated rendering pipeline.

### Minimal Improvement
```swift
func beginFrame() {
    print("\u{001B}[?25l", terminator: "") // hide cursor
    print("\u{001B}[H", terminator: "")    // go home
}

func endFrame() {
    print("\u{001B}[?25h", terminator: "") // show cursor
    fflush(stdout)
}
```

### Better Rendering Approach
- Maintain in-memory screen model.
- Compare frame-to-frame.
- Only update changed lines:
```swift
func write(line: Int, content: String) {
    let cmd = "\u{001B}[\(line);1H\(content)"
    FileHandle.standardOutput.write(Data(cmd.utf8))
}
```

---

## 3. Event Loop / Responsiveness

### Observations
- UI sometimes freezes briefly.
- Occasional “catch up” behavior.

### Likely Causes
- Event loop doing blocking work.
- Input, state, and render are coupled.
- No polling mechanism.

### Recommended Loop Structure
```swift
struct AppState { var needsRedraw = true }

final class App {
    private var state = AppState()
    private let input = TerminalInput()

    func run() {
        var running = true
        while running {
            if let bytes = input.readKey() {
                let key = Key.parse(from: bytes)
                running = handle(key: key)
            }

            if state.needsRedraw {
                renderer.render(state)
                state.needsRedraw = false
            }

            usleep(10000) // avoid CPU spin
        }
    }
}
```

---

## 4. Useful Terminal Features

### Alternate Screen Buffer
```text
ESC[?1049h   # enter
ESC[?1049l   # exit
```

### Window Resize Handling
```swift
signal(SIGWINCH) { _ in
    // handle resize
}
```

### Cursor+Style Helpers
- Hide/show cursor.
- Move cursor via `ESC[row;colH`.
- Use ANSI colors/styling wrappers.

---

## Summary

Your TUI is already functional.  
The main issues come from:

1. **Incomplete raw mode configuration**
2. **Over-aggressive full-screen clearing**
3. **Lack of a structured update/render loop**
4. **No diff-based rendering**

With proper termios setup + a small renderer abstraction + clean event loop, it will behave like a real “native-feeling” TUI.

