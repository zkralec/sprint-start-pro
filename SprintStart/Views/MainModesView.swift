//
//  MainModesView.swift
//  SprintStart
//
//  Created by Assistant on 3/8/26.
//

import SwiftUI

struct MainModesView: View {
    @EnvironmentObject var appStore: AppSettingsStore
    @State private var selectedMode: AppMode = .standard

    var body: some View {
        TabView(selection: $selectedMode) {
            NavigationStack {
                StarterView()
            }
            .tabItem {
                Label(AppMode.standard.title, systemImage: AppMode.standard.systemImage)
            }
            .tag(AppMode.standard)

            NavigationStack {
                ReactionView()
            }
            .tabItem {
                Label(AppMode.reaction.title, systemImage: AppMode.reaction.systemImage)
            }
            .tag(AppMode.reaction)

            NavigationStack {
                DailyChallengeView()
            }
            .tabItem {
                Label(AppMode.dailyChallenge.title, systemImage: AppMode.dailyChallenge.systemImage)
            }
            .tag(AppMode.dailyChallenge)
        }
        .tint(appStore.settings.theme.accentColor)
        .toolbar(.visible, for: .tabBar)
        .onAppear {
            selectedMode = appStore.settings.lastMode
        }
        .onChange(of: selectedMode) {
            appStore.settings.lastMode = selectedMode
        }
    }
}

#Preview {
    MainModesView()
        .environmentObject(AppSettingsStore())
        .environmentObject(PurchaseManager())
        .environmentObject(ReactionHistoryStore())
        .environmentObject(GameCenterManager())
        .environmentObject(DailyChallengeStore())
}
