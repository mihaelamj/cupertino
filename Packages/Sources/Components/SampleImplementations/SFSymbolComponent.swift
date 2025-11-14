import Foundation
import SwiftUI

// sourcery: inComponentsModule
public struct SFSymbolComponent: Component {
    public struct Data: ComponentData {
        public var systemName: String
        public var fontSize: CGFloat
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    struct Content: View {
        var data: Data

        @State var toggled: Bool = false

        var body: some View {
            Image(systemName: data.systemName)
                .font(.system(size: data.fontSize))
                .foregroundColor(toggled ? .blue : .red)
                .onTapGesture {
                    toggled.toggle()
                }
        }
    }

    public func make() -> some View {
        Content(data: data)
    }
}
