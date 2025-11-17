if #available(macOS 15.0, *) {
    CupertinoMCP.main()
} else {
    fatalError("Cupertino MCP Server requires macOS 15.0 or later")
}
