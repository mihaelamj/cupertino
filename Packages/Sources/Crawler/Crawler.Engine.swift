import CoreProtocols
import Foundation

// MARK: - Crawler.Engine

extension Crawler {
    /// Protocol every concrete crawler conforms to. Combines content fetching
    /// and transformation behind a single interface so a dispatcher can drive
    /// any crawler (`Crawler.AppleDocs`, `Crawler.AppleArchive`, `Crawler.HIG`,
    /// `Crawler.Evolution`, `Crawler.WebKit.Engine`, `Core.JSONParser.Engine`)
    /// uniformly.
    ///
    /// The protocol itself lives in `CoreProtocols` as `Core.Protocols.CrawlerEngine`
    /// because parser-side engines (`Core.JSONParser.Engine`) conform too, and
    /// CoreProtocols is the lowest-leaf target everyone can see. This typealias
    /// promotes the natural read site `Crawler.Engine` while keeping the
    /// dependency graph honest.
    public typealias Engine = Core.Protocols.CrawlerEngine
}
