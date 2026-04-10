//
//  SprintStartApp.swift
//  SprintStart
//
//  Created by Zachary Kralec on 6/10/25.
//

import SwiftUI

@main
struct SprintStartApp: App {
    @StateObject private var appStore = AppSettingsStore()
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var reactionHistoryStore = ReactionHistoryStore()
    @StateObject private var gameCenterManager = GameCenterManager()
    @StateObject private var dailyChallengeStore = DailyChallengeStore()

    @State private var authPresentationToken = UUID()

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .environmentObject(appStore)
                .environmentObject(purchaseManager)
                .environmentObject(reactionHistoryStore)
                .environmentObject(gameCenterManager)
                .environmentObject(dailyChallengeStore)
                .tint(appStore.settings.theme.accentColor)
                .preferredColorScheme(appStore.settings.isDarkMode ? .dark : .light)
                .onAppear {
                    gameCenterManager.authenticateIfNeeded()
                    if !purchaseManager.hasPro {
                        appStore.enforceFreeTierSettings()
                    }
                }
                .onChange(of: purchaseManager.hasPro) {
                    if !purchaseManager.hasPro {
                        appStore.enforceFreeTierSettings()
                    }
                }
                .sheet(item: $gameCenterManager.authenticationSession, onDismiss: {
                    authPresentationToken = UUID()
                    gameCenterManager.clearAuthenticationSession()
                }) { session in
                    PresentedUIKitController(viewController: session.viewController)
                        .id(authPresentationToken)
                }
        }
    }
}
