// The `Crawler.Engine` typealias moved to CrawlerModels (#903) so the
// CrawlerWebKit sibling target — which conforms `Crawler.Engine` via
// `Crawler.WebKit.Engine` — can see it without linking the Crawler
// producer. The typealias itself is a pure name with no behaviour.
