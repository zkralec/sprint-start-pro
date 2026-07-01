//
//  DailyChallengeView.swift
//  SprintStart
//
//  Created by Assistant on 3/9/26.
//

import AVFoundation
import SwiftUI
import UIKit

struct DailyChallengeView: View {
    @EnvironmentObject private var appStore: AppSettingsStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var gameCenterManager: GameCenterManager
    @EnvironmentObject private var dailyChallengeStore: DailyChallengeStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var isHolding = false
    @State private var sequenceActive = false
    @State private var falseStart = false
    @State private var reactionMS: Int?
    @State private var startCueTime: CFTimeInterval?
    @State private var setWork: DispatchWorkItem?
    @State private var startWork: DispatchWorkItem?
    @State private var fakeCueWorkItems: [DispatchWorkItem] = []
    @State private var flashOpacity = 0.0
    @State private var paywallFeature: ProFeature?
#if DEBUG
    @State private var debugControlsExpanded = false
    @State private var debugBadgePreviewRoute: DebugBadgePreviewRoute?
#endif

    private let synthesizer = AVSpeechSynthesizer()
    @State private var audioPlayer: AVAudioPlayer?
    private let markHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let setHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let startHapticGenerator = UINotificationFeedbackGenerator()
    private let falseStartHapticGenerator = UINotificationFeedbackGenerator()

    private var themeColor: Color { appStore.settings.theme.accentColor }
    private var refreshKey: String {
        "\(gameCenterManager.playerProfile?.gamePlayerID ?? "guest")-\(purchaseManager.hasPro)"
    }
    private var canAttemptChallenge: Bool {
        purchaseManager.hasPro &&
        gameCenterManager.isAuthenticated &&
        !dailyChallengeStore.hasSubmittedToday &&
        dailyChallengeStore.remainingAttempts > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassLayout.sectionSpacing) {
                challengeHeroSection
                challengeStatusSection
                challengeZoneSection
                inlineLeaderboardSection
#if DEBUG
                debugSection
#endif
                Spacer(minLength: 8)
            }
            .padding(GlassLayout.screenPadding)
        }
        .refreshable {
            await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
        }
        .scrollDisabled(isHolding || sequenceActive)
        .navigationTitle("Daily Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    DailyEventHubPage()
                        .environmentObject(appStore)
                        .environmentObject(gameCenterManager)
                        .environmentObject(dailyChallengeStore)
                } label: {
                    Image(systemName: "list.number")
                        .imageScale(.large)
                        .foregroundStyle(themeColor)
                        .accessibilityLabel("Leaderboard & Badges")
                }
                .disabled(isHolding || sequenceActive)
                .opacity((isHolding || sequenceActive) ? 0.45 : 1.0)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                        .imageScale(.large)
                        .foregroundStyle(themeColor)
                        .accessibilityLabel("Settings")
                }
                .disabled(isHolding || sequenceActive)
                .opacity((isHolding || sequenceActive) ? 0.45 : 1.0)
                .accessibilityIdentifier("openSettingsButton")
            }
        }
        .liquidGlassScreenBackground(theme: appStore.settings.theme)
        .task(id: refreshKey) {
            await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if dailyChallengeStore.currentChallenge?.dateKey != DailyChallengeSchedule.currentDateKey() {
                    await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
                } else {
                    await dailyChallengeStore.refreshLeaderboardOnly(playerProfile: gameCenterManager.playerProfile)
                }
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                if dailyChallengeStore.currentChallenge?.dateKey != DailyChallengeSchedule.currentDateKey() {
                    await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
                }
            }
        }
        .onAppear {
            try? AudioSessionManager.shared.configure(appStore.settings.playOverSilent ? .playOverSilent : .respectsSilent)
            prepareHaptics()
            gameCenterManager.refreshState()
        }
        .onChange(of: appStore.settings.playOverSilent) {
            try? AudioSessionManager.shared.configure(appStore.settings.playOverSilent ? .playOverSilent : .respectsSilent)
        }
        .onDisappear {
            cancelSequence()
            resetAttemptUI()
            isHolding = false
        }
        .sheet(item: $paywallFeature) { feature in
            ProPaywallView(feature: feature)
        }
#if DEBUG
        .navigationDestination(item: $debugBadgePreviewRoute) { route in
            switch route {
            case .badgeVault:
                DailyChallengeBadgesPage()
                    .environmentObject(appStore)
                    .environmentObject(gameCenterManager)
                    .environmentObject(dailyChallengeStore)
            }
        }
#endif

    }

    private var challengeHeroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                AppIconTile(systemName: "trophy.fill", tint: themeColor, size: 48, cornerRadius: 16)
                Spacer()
                if dailyChallengeStore.currentChallenge != nil {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        AppFeaturePill(text: "Resets \(DailyChallengeSchedule.resetDescription(from: context.date))")
                    }
                }
            }

            if let challenge = dailyChallengeStore.currentChallenge {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(challenge.summary)
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                }

                Text(challenge.detail)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
                    AppFeaturePill(text: challenge.difficulty.title)
                    AppFeaturePill(text: challenge.availableAttemptsText)
                }
            } else {
                VStack(spacing: 10) {
                    Text("Loading…")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                    ProgressView()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .liquidGlassCard()
    }

    private var challengeStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PROGRESS")
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                statusStat(
                    title: "Best",
                    value: dailyChallengeStore.bestReactionMS.map { "\($0) ms" } ?? "--",
                    accent: themeColor,
                    prominent: true
                )
                statusStat(
                    title: "Used",
                    value: "\(dailyChallengeStore.attemptsUsed)",
                    accent: .primary
                )
                statusStat(
                    title: "Left",
                    value: "\(dailyChallengeStore.remainingAttempts)",
                    accent: dailyChallengeStore.remainingAttempts > 0 ? .primary : .secondary
                )
            }
        }
        .liquidGlassCard()
    }

    private var challengeZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color.clear
                    .liquidGlassCard()
                    .overlay(challengeZoneFlashOverlay)
                    .overlay(challengeZoneContent)
                    .overlay(challengeZoneTouchOverlay)
            }
            .frame(height: dailyChallengeStore.hasSubmittedToday ? 160 : 320)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: dailyChallengeStore.hasSubmittedToday)
            .contentShape(Rectangle())

            if dailyChallengeStore.canDiscardAndSubmit {
                VStack(spacing: 6) {
                    Button {
                        Task {
                            await dailyChallengeStore.discardRemainingAttemptsAndSubmit(
                                playerProfile: gameCenterManager.playerProfile
                            )
                        }
                    } label: {
                        Label("Submit Best", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(tint: themeColor))

                    Text("Ends today's run and locks in your best time.")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if let lastErrorMessage = dailyChallengeStore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var challengeZoneContent: some View {
        VStack(spacing: 12) {
            if !purchaseManager.hasPro {
                lockedZonePrompt(
                    title: "Pro Required",
                    subtitle: "Unlock to compete in daily challenges."
                )
            } else if !gameCenterManager.isAuthenticated {
                lockedZonePrompt(
                    title: "Connect Game Center",
                    subtitle: "Required for leaderboard entries."
                )
            } else if dailyChallengeStore.hasSubmittedToday {
                VStack(spacing: 6) {
                    Text("You're In")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.secondary)
                    Text(dailyChallengeStore.bestReactionMS.map { "\($0) ms" } ?? "--")
                        .font(AppTypography.metric)
                        .foregroundStyle(themeColor)
                    if let rank = playerLeaderboardEntry?.rank {
                        Text("Ranked #\(rank) today")
                            .font(AppTypography.bodyStrong)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Awaiting ranking…")
                            .font(AppTypography.body)
                            .foregroundStyle(.tertiary)
                    }
                    Text("Resets at midnight EST.")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            } else if let ms = reactionMS {
                Text("\(ms) ms")
                    .font(AppTypography.metric)
                    .foregroundStyle(themeColor)
            } else if falseStart {
                Text("False Start")
                    .font(AppTypography.metricCompact)
                    .foregroundStyle(.red)
            } else if isHolding {
                Text("Hold… wait for it")
                    .font(AppTypography.screenTitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.title2)
                        .foregroundStyle(themeColor.opacity(0.6))
                    Text("Press & hold to start")
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private var challengeZoneTouchOverlay: some View {
        Group {
            if canAttemptChallenge {
                TouchCaptureView { count in
                    if count > 0 {
                        if !isHolding {
                            isHolding = true
                            beginChallengeSequence()
                        }
                    } else if isHolding {
                        isHolding = false
                        handleRelease()
                    }
                }
            } else if !purchaseManager.hasPro {
                Button {
                    paywallFeature = .dailyChallenge
                } label: {
                    Rectangle()
                        .fill(.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if !gameCenterManager.isAuthenticated {
                Button {
                    gameCenterManager.authenticateIfNeeded()
                } label: {
                    Rectangle()
                        .fill(.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var challengeZoneFlashOverlay: some View {
        RoundedRectangle(cornerRadius: GlassLayout.cardCornerRadius, style: .continuous)
            .fill(themeColor.opacity(flashOpacity))
            .allowsHitTesting(false)
    }

    private var inlineLeaderboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOP TODAY")
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.secondary)
                Spacer()
                if !dailyChallengeStore.leaderboard.isEmpty {
                    let count = dailyChallengeStore.leaderboard.count
                    Text("\(count) runner\(count == 1 ? "" : "s")")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 14)

            if dailyChallengeStore.leaderboard.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "flag.2.crossed")
                        .foregroundStyle(.tertiary)
                    Text("No scores yet — be first.")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            } else {
                let top3 = Array(dailyChallengeStore.leaderboard.prefix(3))
                VStack(spacing: 0) {
                    ForEach(Array(top3.enumerated()), id: \.element.id) { idx, entry in
                        topTodayRow(entry)
                        if idx < top3.count - 1 {
                            Divider().padding(.horizontal, 2)
                        }
                    }
                }

                if let yourEntry = playerLeaderboardEntry, yourEntry.rank > 3 {
                    Divider().padding(.vertical, 2)
                    topTodayRow(yourEntry)
                }
            }

            NavigationLink {
                DailyChallengeLeaderboardPage()
                    .environmentObject(appStore)
                    .environmentObject(gameCenterManager)
                    .environmentObject(dailyChallengeStore)
            } label: {
                Text("See Full Leaderboard")
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(themeColor)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }



#if DEBUG
    private enum DebugBadgePreviewRoute: Identifiable {
        case badgeVault

        var id: String {
            switch self {
            case .badgeVault:
                return "badgeVault"
            }
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $debugControlsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Variant")
                            .font(AppTypography.secondaryStrong)
                        Spacer()
                        Picker("Variant", selection: Binding(
                            get: { dailyChallengeStore.currentChallenge?.variant ?? .longBurn },
                            set: { variant in
                                dailyChallengeStore.debugForceVariant(variant)
                                resetAttemptUI()
                                isHolding = false
                            }
                        )) {
                            ForEach(DailyChallengeVariant.allCases) { variant in
                                Text(variant.title).tag(variant)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(themeColor)
                    }
                    .padding(.horizontal, 4)

                    // ID diagnostic — helps spot GK ID mismatches after kill/reopen
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GC playerID: \(gameCenterManager.playerProfile?.gamePlayerID ?? "nil")")
                        Text("submittedPlayerID: \(dailyChallengeStore.submittedPlayerID ?? "nil")")
                        Text("lastKnownPlayerID: \(dailyChallengeStore.lastKnownPlayerID ?? "nil")")
                        Text("submittedName: \(dailyChallengeStore.submittedPlayerName ?? "nil")")
                        let matched = playerLeaderboardEntry != nil
                        Text("entry matched: \(matched ? "✓" : "✗")")
                            .foregroundStyle(matched ? .green : .red)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        Button(gameCenterManager.isAuthenticated ? "Mock Sign Out" : "Mock Sign In") {
                            if gameCenterManager.isAuthenticated {
                                gameCenterManager.debugSignOut()
                            } else {
                                gameCenterManager.debugSignIn()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Refresh") {
                            Task {
                                await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 10) {
                        Button("Reset Progress") {
                            dailyChallengeStore.debugResetTodayProgress()
                            resetAttemptUI()
                            isHolding = false
                        }
                        .buttonStyle(.bordered)

                        Button("Wipe My Entry") {
                            Task {
                                await dailyChallengeStore.debugWipeMyCloudKitEntry(playerProfile: gameCenterManager.playerProfile)
                                resetAttemptUI()
                                isHolding = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button("Wipe All Entries") {
                            Task {
                                await dailyChallengeStore.debugWipeAllCloudKitEntries()
                                dailyChallengeStore.debugResetTodayProgress()
                                resetAttemptUI()
                                isHolding = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button("Add 138 ms") {
                            dailyChallengeStore.debugAddAttempt(reactionMS: 138, falseStart: false)
                        }
                        .buttonStyle(.bordered)

                        Button("Add False Start") {
                            dailyChallengeStore.debugAddAttempt(reactionMS: nil, falseStart: true)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 10) {
                        Button("Mark Submitted") {
                            dailyChallengeStore.debugMarkSubmitted()
                        }
                        .buttonStyle(.bordered)

                        Button("Sample Leaderboard") {
                            dailyChallengeStore.debugLoadSampleLeaderboard(playerProfile: gameCenterManager.playerProfile)
                        }
                        .buttonStyle(.bordered)

                        Button("Sample Badges") {
                            dailyChallengeStore.debugLoadSampleBadges()
                            debugBadgePreviewRoute = .badgeVault
                        }
                        .buttonStyle(.bordered)

                        Button("Badge Gallery") {
                            dailyChallengeStore.debugLoadBadgeGallery()
                            debugBadgePreviewRoute = .badgeVault
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 10) {
                        Button("Tomorrow") {
                            DailyChallengeSchedule.debugNowOverride = Date().addingTimeInterval(60 * 60 * 24)
                            Task {
                                await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Back To Today") {
                            DailyChallengeSchedule.debugNowOverride = nil
                            Task {
                                await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Clear Samples") {
                            dailyChallengeStore.debugClearAwardsAndLeaderboard()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            } label: {
                AppSectionHeader(
                    systemName: "ladybug",
                    tint: themeColor,
                    title: "Debug Controls",
                    summary: "Local tools for testing Game Center, attempts, reset timing, leaderboard, and badges."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }
#endif

    private func statusStat(title: String, value: String, accent: Color, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .system(size: 22, weight: .bold, design: .rounded) : AppTypography.cardTitle)
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appInsetPanel(tint: themeColor, cornerRadius: 18)
    }

    private func lockedZonePrompt(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeColor)

            VStack(spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyStrong)
                Text(subtitle)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(purchaseManager.hasPro ? "Tap to connect" : "Tap to unlock")
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.75), in: Capsule())
        }
        .padding(24)
    }

    private var playerLeaderboardEntry: DailyChallengeLeaderboardEntry? {
        let board = dailyChallengeStore.leaderboard
        guard !board.isEmpty, dailyChallengeStore.hasSubmittedToday else { return nil }

        // Tier 1: match by player ID — try live GC profile, then persisted ID, then last-known ID
        let playerID = gameCenterManager.playerProfile?.gamePlayerID
            ?? dailyChallengeStore.submittedPlayerID
            ?? dailyChallengeStore.lastKnownPlayerID
        if let playerID, let entry = board.first(where: { $0.playerID == playerID }) {
            return entry
        }

        // Tier 2: name-based fallback (handles debug-vs-real-GK ID mismatches in test sessions)
        let playerName = gameCenterManager.playerProfile?.displayName
            ?? dailyChallengeStore.submittedPlayerName
        if let playerName, let entry = board.first(where: { $0.playerName == playerName }) {
            return entry
        }

        return nil
    }

    private func topTodayRow(_ entry: DailyChallengeLeaderboardEntry) -> some View {
        let isSelf = entry.playerID == gameCenterManager.playerProfile?.gamePlayerID
        let rankTint: Color
        switch entry.rank {
        case 1: rankTint = .yellow
        case 2: rankTint = Color(white: 0.62)
        case 3: rankTint = .orange
        default: rankTint = isSelf ? themeColor : .secondary
        }

        return HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text("\(entry.rank)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(rankTint)
                    .frame(width: 20, alignment: .center)
                if entry.rank <= 3 {
                    Image(systemName: entry.rank == 1 ? "crown.fill" : "medal.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(rankTint)
                }
            }
            .frame(width: 38, alignment: .leading)

            Text(entry.playerName)
                .font(isSelf ? AppTypography.bodyStrong : AppTypography.body)
                .foregroundStyle(isSelf ? themeColor : .primary)
                .lineLimit(1)

            if isSelf {
                Text("You")
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(themeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeColor.opacity(0.14), in: Capsule())
            }

            Spacer(minLength: 8)

            Text("\(entry.bestReactionMS) ms")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isSelf ? themeColor : .primary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }

    private func badgeColor(for badge: DailyChallengeBadge) -> Color {
        switch badge {
        case .gold:
            return .yellow
        case .silver:
            return .gray
        case .bronze:
            return .orange
        }
    }

    private func beginChallengeSequence() {
        guard let challenge = dailyChallengeStore.currentChallenge else { return }

        falseStart = false
        reactionMS = nil
        sequenceActive = true
        startCueTime = nil

        let profile = challenge.makeRunProfile(attemptIndex: dailyChallengeStore.attemptsUsed)
        prepareHaptics()
        speak("On your marks")
        if appStore.settings.hapticsEnabled {
            markHapticGenerator.impactOccurred()
            markHapticGenerator.prepare()
        }

        let setItem = DispatchWorkItem {
            guard sequenceActive else { return }
            speak("Set")
            if appStore.settings.hapticsEnabled {
                setHapticGenerator.impactOccurred()
                setHapticGenerator.prepare()
            }
        }
        setWork = setItem
        DispatchQueue.main.asyncAfter(deadline: .now() + profile.markDelay, execute: setItem)

        fakeCueWorkItems = profile.fakeCueOffsets.map { offset in
            let fakeCue = DispatchWorkItem {
                guard sequenceActive else { return }
                flashZone(times: max(profile.visualPulseCount, 1))
                if appStore.settings.hapticsEnabled {
                    setHapticGenerator.impactOccurred(intensity: 0.65)
                    setHapticGenerator.prepare()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + profile.markDelay + offset, execute: fakeCue)
            return fakeCue
        }

        let startItem = DispatchWorkItem {
            guard sequenceActive else { return }
            startCueTime = CACurrentMediaTime()
            playStartSignal(style: profile.startStyle, flashes: max(profile.visualPulseCount, 1))
        }
        startWork = startItem
        DispatchQueue.main.asyncAfter(deadline: .now() + profile.markDelay + profile.setDelay, execute: startItem)
    }

    private func handleRelease() {
        guard sequenceActive else { return }

        if let startCueTime {
            let releaseTime = CACurrentMediaTime()
            let reactionSeconds = max(0, releaseTime - startCueTime)
            let milliseconds = Int(reactionSeconds * 1000.0)
            if reactionSeconds < 0.1 {
                registerFalseStart()
            } else {
                reactionMS = milliseconds
                finishAttempt(reactionMS: milliseconds, falseStart: false)
            }
        } else {
            registerFalseStart()
        }
    }

    private func registerFalseStart() {
        falseStart = true
        reactionMS = nil
        announceFalseStart()
        if appStore.settings.hapticsEnabled {
            falseStartHapticGenerator.notificationOccurred(.error)
            falseStartHapticGenerator.prepare()
        }
        finishAttempt(reactionMS: nil, falseStart: true)
    }

    private func finishAttempt(reactionMS: Int?, falseStart: Bool) {
        sequenceActive = false
        cancelSequence()
        Task {
            await dailyChallengeStore.recordAttempt(
                reactionMS: reactionMS,
                falseStart: falseStart,
                playerProfile: gameCenterManager.playerProfile
            )
        }
    }

    private func cancelSequence() {
        setWork?.cancel()
        startWork?.cancel()
        fakeCueWorkItems.forEach { $0.cancel() }
        setWork = nil
        startWork = nil
        fakeCueWorkItems = []
    }

    private func resetAttemptUI() {
        falseStart = false
        reactionMS = nil
        startCueTime = nil
        sequenceActive = false
    }

    private func speak(_ phrase: String) {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: appStore.settings.voice.languageCode)
        synthesizer.speak(utterance)
    }

    private func announceFalseStart() {
        synthesizer.stopSpeaking(at: .immediate)
        speak("False start")
    }

    private func prepareHaptics() {
        markHapticGenerator.prepare()
        setHapticGenerator.prepare()
        startHapticGenerator.prepare()
        falseStartHapticGenerator.prepare()
    }

    private func playStartSignal(style: DailyChallengeStartStyle, flashes: Int) {
        flashZone(times: max(flashes, 1))

        if appStore.settings.hapticsEnabled {
            startHapticGenerator.notificationOccurred(.success)
            startHapticGenerator.prepare()
        }

        guard let soundName = soundFileName(for: style),
              let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else {
            return
        }

        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }

    private func soundFileName(for style: DailyChallengeStartStyle) -> String? {
        switch style {
        case .starterGun:
            return ["starter_gun_1", "starter_gun_2", "starter_gun_3", "starter_gun_4"].randomElement()
        case .whistle:
            return ["whistle_1", "whistle_2", "whistle_3", "whistle_4"].randomElement()
        case .electronic:
            return "electronic_starter_1"
        case .clap:
            return "clap_1"
        case .visualOnly:
            return nil
        }
    }

    private func flashZone(times: Int) {
        for index in 0..<times {
            let offset = Double(index) * 0.09
            DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                withAnimation(.easeOut(duration: 0.08)) {
                    flashOpacity = 0.3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeIn(duration: 0.12)) {
                        flashOpacity = 0
                    }
                }
            }
        }
    }
}

private struct DailyEventHubPage: View {
    @EnvironmentObject private var appStore: AppSettingsStore
    @EnvironmentObject private var gameCenterManager: GameCenterManager
    @EnvironmentObject private var dailyChallengeStore: DailyChallengeStore

    private enum Tab: String, CaseIterable, Identifiable {
        case leaderboard = "Leaderboard"
        case badges = "Badges"
        var id: Self { self }
    }

    @State private var selectedTab: Tab = .leaderboard

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, GlassLayout.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 10)

            if selectedTab == .leaderboard {
                DailyChallengeLeaderboardPage()
                    .environmentObject(appStore)
                    .environmentObject(gameCenterManager)
                    .environmentObject(dailyChallengeStore)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                DailyChallengeBadgesPage()
                    .environmentObject(appStore)
                    .environmentObject(gameCenterManager)
                    .environmentObject(dailyChallengeStore)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .liquidGlassScreenBackground(theme: appStore.settings.theme)
    }
}

private struct DailyChallengeLeaderboardPage: View {
    @EnvironmentObject private var appStore: AppSettingsStore
    @EnvironmentObject private var gameCenterManager: GameCenterManager
    @EnvironmentObject private var dailyChallengeStore: DailyChallengeStore

    private var themeColor: Color { appStore.settings.theme.accentColor }

    private var entries: [DailyChallengeLeaderboardEntry] {
        Array(dailyChallengeStore.leaderboard.prefix(50))
    }

    private var podiumEntries: [DailyChallengeLeaderboardEntry] {
        entries.filter { $0.rank <= 3 }.sorted { $0.rank < $1.rank }
    }

    private var fieldEntries: [DailyChallengeLeaderboardEntry] {
        entries.filter { $0.rank > 3 }
    }

    private var playerEntry: DailyChallengeLeaderboardEntry? {
        guard let playerID = gameCenterManager.playerProfile?.gamePlayerID else { return nil }
        return entries.first { $0.playerID == playerID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassLayout.sectionSpacing) {
                summaryCard

                if entries.isEmpty {
                    emptyLeaderboardCard
                } else {
                    podiumCard
                    if !fieldEntries.isEmpty {
                        standingsCard
                    }
                }
            }
            .padding(GlassLayout.screenPadding)
        }
        .refreshable {
            await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .liquidGlassScreenBackground(theme: appStore.settings.theme)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                AppIconTile(systemName: "list.number", tint: themeColor, size: 48, cornerRadius: 16)
                Spacer()
                if let count = entries.isEmpty ? nil : entries.count {
                    Text("\(count) runner\(count == 1 ? "" : "s")")
                        .font(AppTypography.captionStrong)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Global Leaderboard")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Best valid time wins. Top 3 earns the podium.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                summaryPill(
                    title: "Leader",
                    value: entries.first.map { "\($0.bestReactionMS) ms" } ?? "--",
                    detail: entries.first?.playerName,
                    tint: entries.first?.badge.map(badgeColor(for:)) ?? themeColor
                )

                summaryPill(
                    title: "Your Place",
                    value: playerEntry.map { "#\($0.rank)" } ?? "--",
                    detail: playerEntry.map { "\($0.bestReactionMS) ms" },
                    tint: playerEntry?.badge.map(badgeColor(for:)) ?? themeColor
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .liquidGlassCard()
    }

    // MARK: - Empty

    private var emptyLeaderboardCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "flag.2.crossed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Scores Yet")
                    .font(AppTypography.cardTitle)
                Text("Be the first to post a time today.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .liquidGlassCard()
    }

    // MARK: - Podium

    private var podiumCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSectionHeader(
                systemName: "trophy.fill",
                tint: themeColor,
                title: "Podium",
                summary: podiumEntries.count < 3
                    ? "\(podiumEntries.count) of 3 spots claimed"
                    : "Today's fastest three"
            )

            HStack(alignment: .bottom, spacing: 10) {
                podiumSlot(rank: 2)
                podiumSlot(rank: 1)
                podiumSlot(rank: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    @ViewBuilder
    private func podiumSlot(rank: Int) -> some View {
        let isChampion = rank == 1
        let slotHeight: CGFloat = rank == 1 ? 248 : rank == 2 ? 210 : 180

        if let entry = podiumEntries.first(where: { $0.rank == rank }) {
            let tint = entry.badge.map(badgeColor(for:)) ?? themeColor

            VStack(spacing: 0) {
                // Medal icon header
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: isChampion ? 44 : 36, height: isChampion ? 44 : 36)
                    Image(systemName: isChampion ? "crown.fill" : "medal.fill")
                        .font(isChampion ? .title2.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .padding(.top, 14)

                Spacer(minLength: 8)

                // Content
                VStack(spacing: 6) {
                    Text(entry.playerName)
                        .font(AppTypography.bodyStrong)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("\(entry.bestReactionMS) ms")
                        .font(isChampion ? AppTypography.metricCompact : AppTypography.cardTitle)
                        .foregroundStyle(tint)

                    Text(entry.badge?.title ?? "Podium")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(tint.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: slotHeight, alignment: .top)
            .appInsetPanel(tint: tint, cornerRadius: 22)
            .overlay(alignment: .top) {
                if isCurrentPlayer(entry) {
                    Text("You")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tint, in: Capsule())
                        .offset(y: -12)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(isChampion ? .title3 : .subheadline)
                    .foregroundStyle(.quaternary)
                Text(rankOrdinal(rank))
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: slotHeight)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
    }

    // MARK: - Standings

    private var standingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                systemName: "line.3.horizontal.decrease.circle",
                tint: themeColor,
                title: "Full Field",
                summary: playerEntry != nil
                    ? "Your row is highlighted"
                    : "\(fieldEntries.count) more behind the podium"
            )

            LazyVStack(spacing: 8) {
                ForEach(fieldEntries) { entry in
                    leaderboardRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    private func leaderboardRow(_ entry: DailyChallengeLeaderboardEntry) -> some View {
        let tint = entry.badge.map(badgeColor(for:)) ?? themeColor
        let isSelf = isCurrentPlayer(entry)

        return HStack(spacing: 12) {
            // Rank badge
            Text("#\(entry.rank)")
                .font(AppTypography.captionStrong)
                .foregroundStyle(isSelf ? .white : tint)
                .frame(width: 38, height: 28)
                .background(
                    (isSelf ? themeColor : tint.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                )

            // Name + badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.playerName)
                        .font(AppTypography.bodyStrong)
                        .lineLimit(1)
                    if isSelf {
                        Text("You")
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(themeColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(themeColor.opacity(0.14), in: Capsule())
                    }
                }
                if let leaderTime = entries.first?.bestReactionMS, entry.rank > 1 {
                    Text("+\(entry.bestReactionMS - leaderTime) ms")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            // Time
            Text("\(entry.bestReactionMS) ms")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isSelf ? themeColor : .primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appInsetPanel(tint: isSelf ? themeColor : tint, cornerRadius: 16)
    }

    // MARK: - Helpers

    private func summaryPill(title: String, value: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppTypography.cardTitle)
                .foregroundStyle(tint)
            if let detail {
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appInsetPanel(tint: tint, cornerRadius: 18)
    }

    private func rankOrdinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "#\(rank)"
        }
    }

    private func isCurrentPlayer(_ entry: DailyChallengeLeaderboardEntry) -> Bool {
        entry.playerID == gameCenterManager.playerProfile?.gamePlayerID
    }

    private func badgeColor(for badge: DailyChallengeBadge) -> Color {
        switch badge {
        case .gold: return .yellow
        case .silver: return .gray
        case .bronze: return .orange
        }
    }
}

private struct DailyChallengeBadgesPage: View {
    @EnvironmentObject private var appStore: AppSettingsStore
    @EnvironmentObject private var gameCenterManager: GameCenterManager
    @EnvironmentObject private var dailyChallengeStore: DailyChallengeStore

    private var themeColor: Color { appStore.settings.theme.accentColor }

    private var shouldRequireAuthentication: Bool {
#if DEBUG
        dailyChallengeStore.debugBadgePreview.isEmpty && dailyChallengeStore.badges.isEmpty
#else
        true
#endif
    }

    /// Only show badges from completed days — current day positions aren't final yet.
    private var earnedBadges: [DailyChallengeBadgeAward] {
        let todayKey = DailyChallengeSchedule.currentDateKey()
#if DEBUG
        let source = dailyChallengeStore.debugBadgePreview.isEmpty
            ? dailyChallengeStore.badges
            : dailyChallengeStore.debugBadgePreview
#else
        let source = dailyChallengeStore.badges
#endif
        return source.filter { $0.dateKey != todayKey }
    }

    private var goldAwards: [DailyChallengeBadgeAward] {
        earnedBadges.filter { $0.badge == .gold }
    }

    private var silverAwards: [DailyChallengeBadgeAward] {
        earnedBadges.filter { $0.badge == .silver }
    }

    private var bronzeAwards: [DailyChallengeBadgeAward] {
        earnedBadges.filter { $0.badge == .bronze }
    }

    private var sortedAwards: [DailyChallengeBadgeAward] {
        earnedBadges.sorted {
            if $0.dateKey == $1.dateKey {
                return badgePriority($0.badge) < badgePriority($1.badge)
            }
            return $0.dateKey > $1.dateKey
        }
    }

    private var featuredAward: DailyChallengeBadgeAward? {
        sortedAwards.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassLayout.sectionSpacing) {
                vaultHeroCard

                if shouldRequireAuthentication && !gameCenterManager.isAuthenticated {
                    lockedCard
                } else if earnedBadges.isEmpty {
                    emptyVaultCard
                } else {
                    if let featuredAward {
                        featuredBadgeSection(featuredAward)
                    }
                    if sortedAwards.count > 1 {
                        showcaseSection
                    }
                    medalTierSection(title: "Gold", icon: "crown.fill", awards: goldAwards)
                    medalTierSection(title: "Silver", icon: "medal.fill", awards: silverAwards)
                    medalTierSection(title: "Bronze", icon: "medal.fill", awards: bronzeAwards)
                }
            }
            .padding(GlassLayout.screenPadding)
        }
        .refreshable {
            await dailyChallengeStore.refresh(playerProfile: gameCenterManager.playerProfile)
        }
        .navigationTitle("Badge Vault")
        .navigationBarTitleDisplayMode(.inline)
        .liquidGlassScreenBackground(theme: appStore.settings.theme)
    }

    // MARK: - Hero

    private var vaultHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                AppIconTile(systemName: "shield.lefthalf.filled", tint: themeColor, size: 48, cornerRadius: 16)
                Spacer()
                if !earnedBadges.isEmpty {
                    Text("\(earnedBadges.count) earned")
                        .font(AppTypography.captionStrong)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Badge Vault")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Podium collectibles with challenge-specific crests, finishes, and event details.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                vaultStatPill(
                    title: "Gold",
                    value: "\(goldAwards.count)",
                    icon: "crown.fill",
                    tint: .yellow
                )
                vaultStatPill(
                    title: "Silver",
                    value: "\(silverAwards.count)",
                    icon: "medal.fill",
                    tint: .gray
                )
                vaultStatPill(
                    title: "Bronze",
                    value: "\(bronzeAwards.count)",
                    icon: "medal.fill",
                    tint: .orange
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .liquidGlassCard()
    }

    // MARK: - Empty / Locked

    private var lockedCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Connect Game Center")
                    .font(AppTypography.cardTitle)
                Text("Sign in so your vault stays with you.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .liquidGlassCard()
    }

    private var emptyVaultCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "medal.star")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Badges Yet")
                    .font(AppTypography.cardTitle)
                Text("Place top 3 in a daily challenge. Each podium finish mints a custom badge after reset.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .liquidGlassCard()
    }

    // MARK: - Showcase

    private func featuredBadgeSection(_ award: DailyChallengeBadgeAward) -> some View {
        let theme = badgeTheme(for: award)

        return VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(
                systemName: "sparkles.rectangle.stack.fill",
                tint: theme.baseTint,
                title: "Featured Badge",
                summary: "Latest podium finish"
            )

            HStack(spacing: 18) {
                badgeEmblem(theme: theme, size: 130)

                VStack(alignment: .leading, spacing: 10) {
                    Text(award.challengeTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(theme.motifLabel.uppercased())
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(theme.baseTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.baseTint.opacity(0.12), in: Capsule())

                    HStack(spacing: 10) {
                        detailChip(title: award.badge.title, value: placementLabel(for: award.badge), tint: theme.baseTint)
                        detailChip(title: "Time", value: "\(award.bestReactionMS) ms", tint: theme.highlight)
                    }

                    Text(formattedDate(for: award.dateKey))
                        .font(AppTypography.secondaryStrong)
                        .foregroundStyle(.secondary)

                    Text("Earned in \(award.challengeTitle), finished \(placementLabel(for: award.badge).lowercased()) with a \(award.bestReactionMS) ms reaction.")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(featuredBackground(theme: theme))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(theme.baseTint.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    private var showcaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                systemName: "sparkles",
                tint: themeColor,
                title: "Recent Pulls",
                summary: "Latest minted badges"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sortedAwards.dropFirst().prefix(6)) { award in
                        showcaseTile(award)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    private func showcaseTile(_ award: DailyChallengeBadgeAward) -> some View {
        let theme = badgeTheme(for: award)

        return VStack(spacing: 0) {
            badgeEmblem(theme: theme, size: 76)
                .padding(.top, 16)

            Spacer(minLength: 10)

            VStack(spacing: 6) {
                Text(award.challengeTitle)
                    .font(AppTypography.bodyStrong)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(award.bestReactionMS) ms")
                    .font(AppTypography.metricCompact)
                    .foregroundStyle(theme.baseTint)

                Text(formattedDate(for: award.dateKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(.tertiary)

                    placementPill(for: award.badge, theme: theme)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .frame(width: 160)
        .frame(minHeight: 210)
        .background(badgeCardBackground(theme: theme))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.baseTint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Medal Tiers

    @ViewBuilder
    private func medalTierSection(title: String, icon: String, awards: [DailyChallengeBadgeAward]) -> some View {
        if !awards.isEmpty {
            let sampleTheme = badgeTheme(for: awards[0])

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(sampleTheme.baseTint.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sampleTheme.baseTint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AppTypography.cardTitle)
                        Text("\(awards.count) collectible\(awards.count == 1 ? "" : "s")")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVStack(spacing: 8) {
                    ForEach(awards) { award in
                        badgeRow(award)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard()
        }
    }

    private func badgeRow(_ award: DailyChallengeBadgeAward) -> some View {
        let theme = badgeTheme(for: award)

        return HStack(spacing: 12) {
            badgeEmblem(theme: theme, size: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(award.challengeTitle)
                    .font(AppTypography.bodyStrong)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(award.bestReactionMS) ms")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.baseTint)

                    Text(formattedDate(for: award.dateKey))
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(theme.motifLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            placementPill(for: award.badge, theme: theme)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(badgeCardBackground(theme: theme))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.baseTint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    private func vaultStatPill(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appInsetPanel(tint: tint, cornerRadius: 16)
    }

    private func badgeTheme(for award: DailyChallengeBadgeAward) -> BadgeTheme {
        let motif = BadgeMotif(title: award.challengeTitle)

        switch award.badge {
        case .gold:
            return BadgeTheme(
                tier: .gold,
                baseTint: Color(red: 0.91, green: 0.72, blue: 0.18),
                highlight: Color(red: 1.0, green: 0.94, blue: 0.67),
                shadow: Color(red: 0.44, green: 0.30, blue: 0.08),
                motif: motif
            )
        case .silver:
            return BadgeTheme(
                tier: .silver,
                baseTint: Color(red: 0.67, green: 0.72, blue: 0.78),
                highlight: Color(red: 0.90, green: 0.94, blue: 0.98),
                shadow: Color(red: 0.34, green: 0.39, blue: 0.47),
                motif: motif
            )
        case .bronze:
            return BadgeTheme(
                tier: .bronze,
                baseTint: Color(red: 0.73, green: 0.45, blue: 0.24),
                highlight: Color(red: 0.93, green: 0.72, blue: 0.50),
                shadow: Color(red: 0.40, green: 0.22, blue: 0.12),
                motif: motif
            )
        }
    }

    @ViewBuilder
    private func badgeEmblem(theme: BadgeTheme, size: CGFloat) -> some View {
        ZStack {
            emblemBase(theme: theme, size: size)

            Circle()
                .fill(theme.highlight.opacity(0.10))
                .frame(width: size * 0.66, height: size * 0.66)

            Image(systemName: theme.motif.primarySymbol)
                .font(.system(size: size * 0.30, weight: .black, design: .rounded))
                .foregroundStyle(theme.highlight)

            Image(systemName: theme.motif.secondarySymbol)
                .font(.system(size: size * 0.14, weight: .bold, design: .rounded))
                .foregroundStyle(theme.baseTint)
                .offset(x: size * 0.24, y: size * 0.24)
        }
        .shadow(color: theme.shadow.opacity(0.12), radius: 10, y: 4)
    }

    @ViewBuilder
    private func emblemBase(theme: BadgeTheme, size: CGFloat) -> some View {
        switch theme.tier {
        case .gold:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.highlight.opacity(0.92), theme.baseTint, theme.shadow.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size * 1.08)
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(theme.highlight.opacity(0.7), lineWidth: 2)
                    .frame(width: size * 0.90, height: size * 0.98)
            }
        case .silver:
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.highlight.opacity(0.96), theme.baseTint, theme.shadow.opacity(0.86)],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: size * 0.62
                        )
                    )
                    .frame(width: size, height: size)
                Circle()
                    .stroke(theme.highlight.opacity(0.8), lineWidth: 2)
                    .frame(width: size * 0.84, height: size * 0.84)
            }
        case .bronze:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.highlight.opacity(0.90), theme.baseTint, theme.shadow.opacity(0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.88, height: size * 0.88)
                    .rotationEffect(.degrees(45))
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .stroke(theme.highlight.opacity(0.7), lineWidth: 2)
                    .frame(width: size * 0.62, height: size * 0.62)
                    .rotationEffect(.degrees(45))
            }
        }
    }

    private func featuredBackground(theme: BadgeTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.shadow.opacity(0.10),
                            theme.baseTint.opacity(0.08),
                            theme.highlight.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(theme.highlight.opacity(0.06))
                .frame(width: 220, height: 220)
                .offset(x: 110, y: -70)
            Circle()
                .fill(theme.baseTint.opacity(0.06))
                .frame(width: 180, height: 180)
                .offset(x: -110, y: 70)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.55))
        }
    }

    private func badgeCardBackground(theme: BadgeTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.baseTint.opacity(0.10),
                            theme.highlight.opacity(0.06),
                            theme.shadow.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.72))
        }
    }

    private func detailChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.82))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func placementPill(for badge: DailyChallengeBadge, theme: BadgeTheme) -> some View {
        Text(placementLabel(for: badge))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(legibleBadgeTextColor(for: theme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(placementPillBackground(for: theme), in: Capsule())
    }

    private func legibleBadgeTextColor(for theme: BadgeTheme) -> Color {
        switch theme.tier {
        case .gold:
            return theme.baseTint
        case .silver:
            return theme.baseTint
        case .bronze:
            return theme.highlight
        }
    }

    private func placementPillBackground(for theme: BadgeTheme) -> Color {
        switch theme.tier {
        case .gold, .bronze:
            return theme.baseTint.opacity(0.14)
        case .silver:
            return theme.baseTint.opacity(0.20)
        }
    }

    private func placementLabel(for badge: DailyChallengeBadge) -> String {
        switch badge {
        case .gold: return "1st Overall"
        case .silver: return "2nd Overall"
        case .bronze: return "3rd Overall"
        }
    }

    private func badgePriority(_ badge: DailyChallengeBadge) -> Int {
        switch badge {
        case .gold: return 0
        case .silver: return 1
        case .bronze: return 2
        }
    }

    private func formattedDate(for dateKey: String) -> String {
        Self.displayDateFormatter.string(from: Self.storageDateFormatter.date(from: dateKey) ?? .now)
    }

    private static let storageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = DailyChallengeSchedule.fixedEST
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = DailyChallengeSchedule.fixedEST
        return formatter
    }()
}

private struct BadgeTheme {
    let tier: BadgeTier
    let baseTint: Color
    let highlight: Color
    let shadow: Color
    let motif: BadgeMotif

    var motifLabel: String { motif.label }
}

private enum BadgeTier {
    case gold
    case silver
    case bronze
}

private struct BadgeMotif {
    let primarySymbol: String
    let secondarySymbol: String
    let label: String

    init(title: String) {
        let normalized = title.lowercased()

        if normalized.contains("burn") || normalized.contains("marathon") {
            primarySymbol = "flame.fill"
            secondarySymbol = "timer"
            label = "Endurance Crest"
        } else if normalized.contains("silent") || normalized.contains("dead silence") {
            primarySymbol = "sparkles"
            secondarySymbol = "eye.fill"
            label = "Silent Flash Crest"
        } else if normalized.contains("thunder") || normalized.contains("phantom") {
            primarySymbol = "bolt.fill"
            secondarySymbol = "waveform.path.ecg"
            label = "Shock Pulse Crest"
        } else if normalized.contains("whistle") {
            primarySymbol = "wind"
            secondarySymbol = "speaker.wave.2.fill"
            label = "Whistle Surge Crest"
        } else if normalized.contains("clap") {
            primarySymbol = "hands.clap.fill"
            secondarySymbol = "burst.fill"
            label = "Impact Crest"
        } else if normalized.contains("electronic") || normalized.contains("echo") {
            primarySymbol = "dot.radiowaves.left.and.right"
            secondarySymbol = "cpu.fill"
            label = "Signal Crest"
        } else if normalized.contains("precision") || normalized.contains("tight") {
            primarySymbol = "scope"
            secondarySymbol = "target"
            label = "Precision Crest"
        } else if normalized.contains("flash") {
            primarySymbol = "sun.max.fill"
            secondarySymbol = "bolt.circle.fill"
            label = "Flash Trap Crest"
        } else if normalized.contains("off beat") || normalized.contains("rhythm") {
            primarySymbol = "metronome.fill"
            secondarySymbol = "waveform"
            label = "Rhythm Break Crest"
        } else if normalized.contains("chaos") {
            primarySymbol = "hurricane"
            secondarySymbol = "exclamationmark.circle.fill"
            label = "Chaos Crest"
        } else if normalized.contains("sudden death") {
            primarySymbol = "flag.checkered.2.crossed"
            secondarySymbol = "bolt.heart.fill"
            label = "Final Heat Crest"
        } else {
            primarySymbol = "figure.run"
            secondarySymbol = "medal.fill"
            label = "Sprint Crest"
        }
    }
}

struct PresentedUIKitController: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        DailyChallengeView()
            .environmentObject(AppSettingsStore())
            .environmentObject(PurchaseManager())
            .environmentObject(GameCenterManager())
            .environmentObject(DailyChallengeStore())
    }
}
