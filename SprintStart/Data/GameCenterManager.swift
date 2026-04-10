//
//  GameCenterManager.swift
//  SprintStart
//
//  Created by Assistant on 3/9/26.
//

import Foundation
import GameKit
import UIKit

final class GameCenterAuthenticationSession: Identifiable {
    let id = UUID()
    let viewController: UIViewController

    init(viewController: UIViewController) {
        self.viewController = viewController
    }
}

@MainActor
final class GameCenterManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var playerProfile: GameCenterPlayerProfile?
    @Published var authenticationSession: GameCenterAuthenticationSession?
    @Published var lastErrorMessage: String?

    func refreshState() {
        let localPlayer = GKLocalPlayer.local
        isAuthenticated = localPlayer.isAuthenticated
        if localPlayer.isAuthenticated {
            playerProfile = GameCenterPlayerProfile(
                gamePlayerID: localPlayer.gamePlayerID,
                displayName: localPlayer.displayName
            )
        } else {
            playerProfile = nil
        }
    }

    func authenticateIfNeeded() {
        guard !GKLocalPlayer.local.isAuthenticated else {
            refreshState()
            return
        }

        isAuthenticating = true
        lastErrorMessage = nil

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }

            if let viewController {
                self.authenticationSession = GameCenterAuthenticationSession(viewController: viewController)
                return
            }

            self.isAuthenticating = false
            self.authenticationSession = nil
            self.lastErrorMessage = error?.localizedDescription
            self.refreshState()
        }
    }

    func clearAuthenticationSession() {
        authenticationSession = nil
    }

#if DEBUG
    func debugSignIn(displayName: String = "Debug Runner") {
        isAuthenticating = false
        authenticationSession = nil
        lastErrorMessage = nil
        isAuthenticated = true
        playerProfile = GameCenterPlayerProfile(
            gamePlayerID: "debug-player",
            displayName: displayName
        )
    }

    func debugSignOut() {
        isAuthenticating = false
        authenticationSession = nil
        lastErrorMessage = nil
        isAuthenticated = false
        playerProfile = nil
    }
#endif
}
