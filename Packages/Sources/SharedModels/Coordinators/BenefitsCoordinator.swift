import Foundation

@MainActor
public protocol BenefitsCoordinator: AnyObject {
    func showBenefitsList()
    func showBenefitDetails(benefitId: UUID)
    func requestBankAccount(for benefitId: UUID)
}
