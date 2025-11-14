import Foundation
import SwiftUI

// sourcery: inComponentsModule
public struct TextComponent: Component {
    public struct Data: ComponentData {
        public var text: String

        /// Font used for display
        public var fontSize: CGFloat = 64
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public func make() -> some View {
        Text(data.text)
            .font(.system(size: data.fontSize))
    }
}
