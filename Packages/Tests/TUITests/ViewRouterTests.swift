@testable import Core
import Foundation
import Testing
import TestSupport
@testable import TUI

// MARK: - ViewRouter Tests

@MainActor
@Test("ViewRouter handles home to packages transition via number key")
func viewRouterHomeToPackagesNumber() {
    let state = AppState()
    state.viewMode = .home

    let result = ViewRouter.handleViewTransition(key: .char("1"), state: state, homeCursor: 0)

    #expect(result == .packages, "Pressing '1' from home should navigate to packages")
}

@MainActor
@Test("ViewRouter handles home to library transition via number key")
func viewRouterHomeToLibraryNumber() {
    let state = AppState()
    state.viewMode = .home

    let result = ViewRouter.handleViewTransition(key: .char("2"), state: state, homeCursor: 0)

    #expect(result == .library, "Pressing '2' from home should navigate to library")
}

@MainActor
@Test("ViewRouter handles home to archive transition via number key")
func viewRouterHomeToArchiveNumber() {
    let state = AppState()
    state.viewMode = .home

    let result = ViewRouter.handleViewTransition(key: .char("3"), state: state, homeCursor: 0)

    #expect(result == .archive, "Pressing '3' from home should navigate to archive")
}

@MainActor
@Test("ViewRouter handles home to settings transition via number key")
func viewRouterHomeToSettingsNumber() {
    let state = AppState()
    state.viewMode = .home

    let result = ViewRouter.handleViewTransition(key: .char("4"), state: state, homeCursor: 0)

    #expect(result == .settings, "Pressing '4' from home should navigate to settings")
}

@MainActor
@Test("ViewRouter handles home enter navigation based on cursor")
func viewRouterHomeEnterNavigation() {
    let state = AppState()
    state.viewMode = .home

    // Cursor at 0 -> packages
    var result = ViewRouter.handleViewTransition(key: .enter, state: state, homeCursor: 0)
    #expect(result == .packages, "Enter with cursor at 0 should go to packages")

    // Cursor at 1 -> library
    result = ViewRouter.handleViewTransition(key: .enter, state: state, homeCursor: 1)
    #expect(result == .library, "Enter with cursor at 1 should go to library")

    // Cursor at 2 -> archive
    result = ViewRouter.handleViewTransition(key: .enter, state: state, homeCursor: 2)
    #expect(result == .archive, "Enter with cursor at 2 should go to archive")

    // Cursor at 3 -> settings
    result = ViewRouter.handleViewTransition(key: .enter, state: state, homeCursor: 3)
    #expect(result == .settings, "Enter with cursor at 3 should go to settings")
}

@MainActor
@Test("ViewRouter returns nil for non-navigation keys in home view")
func viewRouterHomeNonNavigation() {
    let state = AppState()
    state.viewMode = .home

    let result = ViewRouter.handleViewTransition(key: .char("x"), state: state, homeCursor: 0)

    #expect(result == nil, "Non-navigation keys should return nil")
}

@MainActor
@Test("ViewRouter handles library back to home via h key")
func viewRouterLibraryBackH() {
    let state = AppState()
    state.viewMode = .library

    let result = ViewRouter.handleViewTransition(key: .char("h"), state: state, homeCursor: 0)

    #expect(result == .home, "Pressing 'h' from library should navigate to home")
}

@MainActor
@Test("ViewRouter handles library back to home via escape")
func viewRouterLibraryBackEscape() {
    let state = AppState()
    state.viewMode = .library

    let result = ViewRouter.handleViewTransition(key: .escape, state: state, homeCursor: 0)

    #expect(result == .home, "Pressing escape from library should navigate to home")
}

@MainActor
@Test("ViewRouter handles settings back to home")
func viewRouterSettingsBack() {
    let state = AppState()
    state.viewMode = .settings
    state.isEditingSettings = false

    let resultH = ViewRouter.handleViewTransition(key: .char("h"), state: state, homeCursor: 0)
    #expect(resultH == .home, "Pressing 'h' from settings should navigate to home")

    let resultEscape = ViewRouter.handleViewTransition(key: .escape, state: state, homeCursor: 0)
    #expect(resultEscape == .home, "Pressing escape from settings should navigate to home")
}

@MainActor
@Test("ViewRouter blocks navigation when editing settings")
func viewRouterSettingsEditingBlocked() {
    let state = AppState()
    state.viewMode = .settings
    state.isEditingSettings = true

    let result = ViewRouter.handleViewTransition(key: .char("h"), state: state, homeCursor: 0)

    #expect(result == nil, "Navigation should be blocked when editing settings")
}

@MainActor
@Test("ViewRouter handles packages back to home")
func viewRouterPackagesBack() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = false

    let resultH = ViewRouter.handleViewTransition(key: .char("h"), state: state, homeCursor: 0)
    #expect(resultH == .home, "Pressing 'h' from packages should navigate to home")

    let resultEscape = ViewRouter.handleViewTransition(key: .escape, state: state, homeCursor: 0)
    #expect(resultEscape == .home, "Pressing escape from packages should navigate to home")
}

@MainActor
@Test("ViewRouter blocks navigation when searching packages")
func viewRouterPackagesSearchingBlocked() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = true

    let result = ViewRouter.handleViewTransition(key: .char("h"), state: state, homeCursor: 0)

    #expect(result == nil, "Navigation should be blocked when searching")
}

@MainActor
@Test("ViewRouter returns nil for non-navigation keys in all views")
func viewRouterNonNavigationKeys() {
    let state = AppState()

    // Test in each view
    for viewMode in [ViewMode.home, .library, .settings, .packages] {
        state.viewMode = viewMode
        state.isSearching = false
        state.isEditingSettings = false

        let result = ViewRouter.handleViewTransition(key: .arrowUp, state: state, homeCursor: 0)
        #expect(result == nil, "Arrow keys should not trigger navigation in \(viewMode)")
    }
}
