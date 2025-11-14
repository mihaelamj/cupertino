import Foundation
import SwiftUI

#if canImport(Playbook) && canImport(PlaybookUI)
import Playbook
import PlaybookUI

public enum AppScenarios {
    /// iOS: real Playbook
    public static func build() -> Playbook { Playbook() }
}
#endif
