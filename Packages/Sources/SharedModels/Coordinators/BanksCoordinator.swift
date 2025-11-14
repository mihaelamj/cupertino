import Foundation

@MainActor
public protocol BanksCoordinator: AnyObject {
    func showSelectBank()
    func showAddBank()
    func showChangeBank(bankId: UUID)
    func bankAccountSelected(_ bankId: UUID)
}
