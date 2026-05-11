# cupertino-tui

Terminal UI for browsing and managing Cupertino documentation.

## Synopsis

```bash
cupertino-tui [options]
```

## Options

| Option | Description |
|--------|-------------|
| [--version / -v](option (--)/version.md) | Show version information |

## Description

A full-screen terminal interface for navigating Apple and Swift documentation offline. Provides an interactive way to browse packages, archives, and configure settings without using command-line arguments.

## Views

### Home

The main menu with quick stats and navigation:

- **Packages** - Browse the Swift packages catalog (9,700+ entries in search.db, 183 Apple-official packages with source files in packages.db)
- **Library** - View artifact collections
- **Archive** - Browse classic Apple programming guides
- **Settings** - Configure Cupertino

### Packages View

Browse and search the Swift package catalog:

- Search packages by name
- View package details (stars, description, license)
- Mark packages for download

### Archive View

Browse legacy Apple programming guides:

- Core Animation Programming Guide
- Quartz 2D Programming Guide
- Key-Value Coding Programming Guide
- And more...

### Settings View

Configure Cupertino options:

- Output directories
- Download preferences

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `k` | Navigate up |
| `↓` / `j` | Navigate down |
| `Enter` | Select item |
| `1-4` | Quick select menu item |
| `/` | Search (in applicable views) |
| `h` / `Esc` | Go back / Home |
| `q` | Quit |

## Example

```bash
# Launch the TUI
cupertino-tui
```

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       Cupertino Documentation Manager                        │
│                 Navigate Apple & Swift documentation offline                 │
├──────────────────────────────────────────────────────────────────────────────┤
│ Quick Stats                                                                  │
│ • 28 pkgs • 0 dl • 28.42 GB                                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│ Select a view:                                                               │
│ > * 1. Packages - Browse 9699 Swift packages                                 │
│   * 2. Library - 5 artifact collections                                      │
│   * 3. Archive - 46 classic Apple guides                                     │
│   * 4. Settings - Configure Cupertino                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│ ↑↓/jk:Navigate  Enter/1-4:Select  q:Quit                                     │
└──────────────────────────────────────────────────────────────────────────────┘
```

## See Also

- [cupertino fetch](../../commands/fetch/) - Download documentation
- [cupertino search](../../commands/search/) - Search from CLI
