import Foundation

@MainActor
public protocol AuthCoordinator: AnyObject {
    func showWelcome()
    func showLogin()
    func showRegister()
    func authenticationCompleted()
}
