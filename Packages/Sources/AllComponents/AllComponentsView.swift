import Components
import Foundation
import SwiftUI

public struct AllComponentsView: View {
    @State private var model: ComponentListModel

    public init() {
        _model = State(initialValue: ComponentListModel(
            registrar: AllComponentsRegistrar()
        ))
    }

    public var body: some View {
        ComponentListView(model: model)
    }
}
