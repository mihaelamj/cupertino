# --authenticate

Launch visible browser for authentication (code type only)

## Synopsis

```bash
cupertino fetch --type code --authenticate
```

## Description

Opens a visible Safari browser window to allow signing in with your Apple ID. Required for downloading Apple sample code.

## Applies To

Only works with `--type code`. Not needed for packages.

## How It Works

1. Launches Safari browser window
2. Navigates to Apple Developer sample code page
3. You sign in with your Apple ID
4. Browser authenticates with Apple's servers
5. Cupertino downloads sample code ZIP files
6. Browser closes when complete

## Examples

### Fetch Sample Code with Authentication
```bash
cupertino fetch --type code --authenticate
```

### Fetch Limited Sample Code
```bash
cupertino fetch --type code --authenticate --limit 50
```

### Custom Output Directory
```bash
cupertino fetch --type code --authenticate --output-dir ./samples
```

## Requirements

- Valid Apple ID
- macOS with Safari
- Internet connection
- Apple Developer account (free tier works)

## Security

- Uses Safari's standard authentication
- Credentials are handled by Safari, not Cupertino
- Session is temporary and browser-based
- No credentials are stored by Cupertino

## Notes

- **Required** for `--type code`
- Not needed for `--type packages`
- Browser window will be visible during download
- Download continues after authentication
