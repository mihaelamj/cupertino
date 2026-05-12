import Foundation

// MARK: - Resources

/// A resource that can be read by the client
extension MCP.Core.Protocols {
    public struct Resource: Codable, Sendable {
        public let uri: String
        public let name: String
        public let description: String?
        public let mimeType: String?

        public init(
            uri: String,
            name: String,
            description: String? = nil,
            mimeType: String? = nil
        ) {
            self.uri = uri
            self.name = name
            self.description = description
            self.mimeType = mimeType
        }
    }
}

/// A resource template with URI pattern
extension MCP.Core.Protocols {
    public struct ResourceTemplate: Codable, Sendable {
        public let uriTemplate: String
        public let name: String
        public let description: String?
        public let mimeType: String?

        public init(
            uriTemplate: String,
            name: String,
            description: String? = nil,
            mimeType: String? = nil
        ) {
            self.uriTemplate = uriTemplate
            self.name = name
            self.description = description
            self.mimeType = mimeType
        }
    }
}

// MARK: - Resource Requests/Responses

/// List all available resources
extension MCP.Core.Protocols {
    public struct ListResourcesRequest: Codable, Sendable {
        public let method: String = Method.resourcesList
        public let params: Params?

        enum CodingKeys: String, CodingKey {
            case params
        }

        public init(cursor: String? = nil) {
            params = cursor.map { Params(cursor: $0) }
        }

        public struct Params: Codable, Sendable {
            public let cursor: String

            public init(cursor: String) {
                self.cursor = cursor
            }
        }
    }
}

extension MCP.Core.Protocols {
    public struct ListResourcesResult: Codable, Sendable {
        public let resources: [Resource]
        public let nextCursor: String?

        public init(resources: [Resource], nextCursor: String? = nil) {
            self.resources = resources
            self.nextCursor = nextCursor
        }
    }
}

/// Read a specific resource
extension MCP.Core.Protocols {
    public struct ReadResourceRequest: Codable, Sendable {
        public let method: String = Method.resourcesRead
        public let params: Params

        enum CodingKeys: String, CodingKey {
            case params
        }

        public init(uri: String) {
            params = Params(uri: uri)
        }

        public struct Params: Codable, Sendable {
            public let uri: String

            public init(uri: String) {
                self.uri = uri
            }
        }
    }
}

extension MCP.Core.Protocols {
    public struct ReadResourceResult: Codable, Sendable {
        public let contents: [ResourceContents]

        public init(contents: [ResourceContents]) {
            self.contents = contents
        }
    }
}

/// List resource templates
extension MCP.Core.Protocols {
    public struct ListResourceTemplatesRequest: Codable, Sendable {
        public let method: String = Method.resourcesTemplatesList
        public let params: Params?

        enum CodingKeys: String, CodingKey {
            case params
        }

        public init(cursor: String? = nil) {
            params = cursor.map { Params(cursor: $0) }
        }

        public struct Params: Codable, Sendable {
            public let cursor: String

            public init(cursor: String) {
                self.cursor = cursor
            }
        }
    }
}

extension MCP.Core.Protocols {
    public struct ListResourceTemplatesResult: Codable, Sendable {
        public let resourceTemplates: [ResourceTemplate]
        public let nextCursor: String?

        public init(resourceTemplates: [ResourceTemplate], nextCursor: String? = nil) {
            self.resourceTemplates = resourceTemplates
            self.nextCursor = nextCursor
        }
    }
}

/// Subscribe to resource updates
extension MCP.Core.Protocols {
    public struct SubscribeResourceRequest: Codable, Sendable {
        public let method: String = Method.resourcesSubscribe
        public let params: Params

        enum CodingKeys: String, CodingKey {
            case params
        }

        public init(uri: String) {
            params = Params(uri: uri)
        }

        public struct Params: Codable, Sendable {
            public let uri: String

            public init(uri: String) {
                self.uri = uri
            }
        }
    }
}

/// Unsubscribe from resource updates
extension MCP.Core.Protocols {
    public struct UnsubscribeResourceRequest: Codable, Sendable {
        public let method: String = Method.resourcesUnsubscribe
        public let params: Params

        enum CodingKeys: String, CodingKey {
            case params
        }

        public init(uri: String) {
            params = Params(uri: uri)
        }

        public struct Params: Codable, Sendable {
            public let uri: String

            public init(uri: String) {
                self.uri = uri
            }
        }
    }
}

/// Resource updated notification (server → client)
extension MCP.Core.Protocols {
    public struct ResourceUpdatedNotification: Codable, Sendable {
        public let method: String = Method.notificationsResourcesUpdated
        public let params: Params

        enum CodingKeys: String, CodingKey {
            case params
        }

        public init(uri: String) {
            params = Params(uri: uri)
        }

        public struct Params: Codable, Sendable {
            public let uri: String

            public init(uri: String) {
                self.uri = uri
            }
        }
    }
}

/// Resource list changed notification (server → client)
extension MCP.Core.Protocols {
    public struct ResourceListChangedNotification: Codable, Sendable {
        public let method: String = Method.notificationsResourcesListChanged

        enum CodingKeys: String, CodingKey {
            case method
        }

        public init() {}
    }
}

// MARK: - Type Aliases

extension MCP.Core.Protocols {
    public typealias ReadResourceParams = ReadResourceRequest.Params
}
