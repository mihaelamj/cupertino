import SwiftUI

@MainActor
public protocol AppCoordinator: AnyObject {
    // Root flow management
    func start()

    // Feature navigation
    func showAuth()
    func showMainApp()
    func logout()
}
