import Foundation

@MainActor
public protocol ProfileCoordinator: AnyObject {
    func showProfile()
    func showPaymentConfirmation()
    func logout()
}
