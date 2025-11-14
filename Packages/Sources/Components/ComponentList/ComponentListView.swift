import Foundation
import SharedComponents
import SwiftUI

public struct ComponentListView: View {
    public init(model: ComponentListModel) {
        self.model = model
    }

    @ObserveInjection private var iO
    var model: ComponentListModel

    public var body: some View {
        List {
            Text("\(model.components.count) Components Loaded:")
            ForEach(model.components) { component in
                component.contentView
            }
        }
    }
}
