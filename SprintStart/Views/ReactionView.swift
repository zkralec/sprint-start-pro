//
//  ReactionView.swift
//  SprintStart
//
//  Created by Assistant on 3/7/26.
//

import SwiftUI
import AVFoundation
import UIKit

struct ReactionView: View {
    @State private var isHolding = false
    @State private var sequenceActive = false
    @State private var falseStart = false
    @State private var reactionMS: Int?
    @State private var startCueTime: CFTimeInterval?
    @State private var starterSound: AVAudioPlayer?

    @State private var setWork: DispatchWorkItem?
    @State private var startWork: DispatchWorkItem?
    @State private var paywallFeature: ProFeature?
    @State private var shouldShowUpgradePrompt = false

    @EnvironmentObject var appStore: AppSettingsStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var reactionHistoryStore: ReactionHistoryStore

    private let synthesizer = AVSpeechSynthesizer()
    private let markHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let setHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let startHapticGenerator = UINotificationFeedbackGenerator()
    private let falseStartHapticGenerator = UINotificationFeedbackGenerator()

    private var themeColor: Color { appStore.settings.theme.accentColor }
    private var primaryButtonTint: Color {
        if appStore.settings.theme == .blackWhite {
            return .black
        }
        return themeColor
    }
    private var proLockedControls: Bool {
        !purchaseManager.hasPro
    }
    private var interactionLocked: Bool {
        proLockedControls || isHolding || sequenceActive
    }
    private var resetReactionDisabled: Bool {
        isHolding || sequenceActive
    }
    private var resetDefaultsDisabled: Bool {
        appStore.starter.timingLocked || isHolding || sequenceActive
    }
    private var bottomButtonsAppearDisabled: Bool {
        !purchaseManager.hasPro
    }
    private var recordedReactionValues: [Int] {
        reactionHistoryStore.entries.compactMap(\.reactionMS)
    }
    private var averageReactionValue: Int? {
        guard !recordedReactionValues.isEmpty else { return nil }
        return Int(Double(recordedReactionValues.reduce(0, +)) / Double(recordedReactionValues.count))
    }
    private var bestReactionValue: Int? {
        recordedReactionValues.min()
    }
    private var totalTrackedReps: Int {
        recordedReactionValues.count
    }
    private var hasHistoryEntries: Bool {
        !reactionHistoryStore.entries.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassLayout.sectionSpacing) {

                lockableSummarySection

                ZStack {
                    Color.clear
                        .liquidGlassCard()
                        .overlay(contentOverlay)
                        .overlay(reactionTouchOverlay)
                }
                .frame(height: 338)
                .contentShape(Rectangle())
                .accessibilityLabel("Reaction zone")
                .accessibilityHint(reactionAccessibilityHint)

                lockableTimingSection

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        handleResetReactionTap()
                    } label: {
                        Label("Reset Reaction", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(tint: primaryButtonTint))
                    .disabled(resetReactionDisabled)
                    .opacity((resetReactionDisabled || bottomButtonsAppearDisabled) ? 0.55 : 1.0)
                    .saturation((resetReactionDisabled || bottomButtonsAppearDisabled) ? 0.78 : 1.0)

                    Button {
                        handleResetDefaultsTap()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(tint: .red))
                    .disabled(resetDefaultsDisabled)
                    .opacity((resetDefaultsDisabled || bottomButtonsAppearDisabled) ? 0.55 : 1.0)
                    .saturation((resetDefaultsDisabled || bottomButtonsAppearDisabled) ? 0.78 : 1.0)
                    .accessibilityIdentifier("resetDefaultsButtonReaction")
                }

                Spacer(minLength: 8)
            }
            .padding(GlassLayout.screenPadding)
        }
        .scrollDisabled(isHolding || sequenceActive)
        .navigationTitle("Reaction Mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                historyToolbarItem
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
        .onAppear {
            try? AudioSessionManager.shared.configure(appStore.settings.playOverSilent ? .playOverSilent : .respectsSilent)
            preloadStarterSound()
            prepareHaptics()
        }
        .onChange(of: appStore.settings.playOverSilent) {
            try? AudioSessionManager.shared.configure(appStore.settings.playOverSilent ? .playOverSilent : .respectsSilent)
        }
        .onChange(of: appStore.settings.starter) {
            preloadStarterSound()
        }
        .onChange(of: appStore.settings.hapticsEnabled) {
            if appStore.settings.hapticsEnabled {
                prepareHaptics()
            }
        }
        .onDisappear {
            cancelSequence()
            resetUI()
            isHolding = false
        }
        .sheet(item: $paywallFeature) { feature in
            ProPaywallView(feature: feature)
        }
    }

    private var summarySection: some View {
        HStack(spacing: 12) {
            summaryStat(title: "Best", value: bestReactionValue.map { "\($0) ms" } ?? "--")
            summaryStat(title: "Average", value: averageReactionValue.map { "\($0) ms" } ?? "--")
            summaryStat(title: "Tracked", value: "\(totalTrackedReps)")
        }
        .liquidGlassCard()
    }

    private var lockableSummarySection: some View {
        summarySection
            .overlay {
                if !purchaseManager.hasPro {
                    Button {
                        paywallFeature = .reactionTracking
                    } label: {
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unlock reaction stats")
                }
            }
    }

    private var lockableTimingSection: some View {
        TimingControlsView(
            markDelay: $appStore.starter.firstDelay,
            startDelay: $appStore.starter.secondDelay,
            variability: $appStore.starter.variability,
            timingLocked: $appStore.starter.timingLocked,
            interactionLocked: interactionLocked
        )
        .overlay {
            if !purchaseManager.hasPro {
                Button {
                    paywallFeature = .reactionTracking
                } label: {
                    Color.clear
                        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlock reaction timing")
            }
        }
    }

    private var lockedReactionPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeColor)

            VStack(spacing: 4) {
                Text("Unlock Reaction Tracking")
                    .font(AppTypography.bodyStrong)
                Text("Press and hold training is available with Pro.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Tap to unlock")
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.75), in: Capsule())
        }
        .padding(24)
    }

    private var contentOverlay: some View {
        VStack(spacing: 12) {
            if !purchaseManager.hasPro {
                lockedReactionPrompt
            } else if let ms = reactionMS {
                Text("Release Reaction: \(ms) ms")
                    .font(AppTypography.metric)
                    .foregroundStyle(themeColor)
            } else if falseStart {
                Text("False Start")
                    .font(AppTypography.metric)
                    .foregroundStyle(.red)
            } else if isHolding {
                Text("Holding... wait for the start")
                    .font(AppTypography.screenTitle)
            } else if shouldShowUpgradePrompt, !purchaseManager.hasPro {
                Text("Track every rep with Pro")
                    .font(AppTypography.screenTitle)
                    .multilineTextAlignment(.center)
            } else {
                Text("Press and hold to arm")
                    .font(AppTypography.screenTitle)
            }

            if let instructionText {
                Text(instructionText)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }

            if purchaseManager.hasPro {
                Text("Timing is based on the app cue and may vary slightly.")
                    .font(AppTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var reactionTouchOverlay: some View {
        if purchaseManager.hasPro {
            TouchCaptureView { count in
                if count > 0 {
                    if !isHolding {
                        isHolding = true
                        beginArmedSequence()
                    }
                } else if isHolding {
                    isHolding = false
                    handleRelease()
                }
            }
        } else {
            Button {
                paywallFeature = .reactionTracking
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var historyToolbarItem: some View {
        if purchaseManager.hasPro {
            NavigationLink(destination: SessionHistoryView()) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .imageScale(.large)
                    .foregroundStyle(themeColor)
                    .accessibilityLabel("Session History")
            }
            .disabled(isHolding || sequenceActive)
            .opacity((isHolding || sequenceActive) ? 0.45 : 1.0)
        } else {
            Button {
                paywallFeature = .general
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .imageScale(.medium)
                    Text("PRO")
                        .font(AppTypography.captionEmphasis)
                }
                .foregroundStyle(themeColor)
                .accessibilityLabel("Session History Pro")
            }
            .disabled(isHolding || sequenceActive)
            .opacity((isHolding || sequenceActive) ? 0.45 : 1.0)
        }
    }

    private var instructionText: String? {
        if !purchaseManager.hasPro {
            return nil
        }
        return "Release on the start cue."
    }

    private var reactionAccessibilityHint: String {
        if purchaseManager.hasPro {
            return "Place one or more fingers to arm. Release on the start cue to train your reaction."
        }
        return "Reaction Mode requires Pro."
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppTypography.cardTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appInsetPanel(tint: themeColor, cornerRadius: 18)
    }

    private func beginArmedSequence() {
        falseStart = false
        reactionMS = nil
        sequenceActive = true
        startCueTime = nil
        shouldShowUpgradePrompt = false
        prepareHaptics()

        speak("On your marks")
        if appStore.settings.hapticsEnabled {
            playMarkHaptic()
        }

        let setItem = DispatchWorkItem {
            guard sequenceActive else { return }
            let setUtterance = AVSpeechUtterance(string: "Set")
            setUtterance.voice = AVSpeechSynthesisVoice(language: appStore.settings.voice.languageCode)
            synthesizer.speak(setUtterance)
            if appStore.settings.hapticsEnabled {
                playSetHaptic()
            }
        }
        setWork = setItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(appStore.starter.firstDelay), execute: setItem)

        let startDelay = appStore.starter.variability.randomStartDelay(baseDelay: appStore.starter.secondDelay)
        let startItem = DispatchWorkItem {
            guard sequenceActive else { return }
            startCueTime = CACurrentMediaTime()
            if let player = starterSound {
                player.prepareToPlay()
                player.play()
            }
            if appStore.settings.hapticsEnabled {
                playStartHaptic()
            }
        }
        startWork = startItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(appStore.starter.firstDelay) + startDelay, execute: startItem)
    }

    private func handleResetReactionTap() {
        guard purchaseManager.hasPro else {
            paywallFeature = .reactionTracking
            return
        }
        cancelSequence()
        resetUI()
    }

    private func handleResetDefaultsTap() {
        guard purchaseManager.hasPro else {
            paywallFeature = .reactionTracking
            return
        }
        cancelSequence()
        resetUI()
        appStore.resetStarterToDefaults()
    }

    private func handleRelease() {
        guard sequenceActive else { return }
        if let cue = startCueTime {
            let release = CACurrentMediaTime()
            let reactionSeconds = max(0, release - cue)
            let ms = Int(reactionSeconds * 1000.0)
            if reactionSeconds < 0.1 {
                falseStart = true
                reactionMS = nil
                announceFalseStart()
                if purchaseManager.hasPro {
                    reactionHistoryStore.addFalseStart()
                }
                if appStore.settings.hapticsEnabled {
                    playFalseStartHaptic()
                }
            } else {
                if purchaseManager.hasPro {
                    reactionMS = ms
                    reactionHistoryStore.addReaction(milliseconds: ms)
                } else {
                    reactionMS = nil
                    shouldShowUpgradePrompt = true
                }
            }
            sequenceActive = false
            cancelSequence()
        } else {
            falseStart = true
            sequenceActive = false
            announceFalseStart()
            if purchaseManager.hasPro {
                reactionHistoryStore.addFalseStart()
            }
            if appStore.settings.hapticsEnabled {
                playFalseStartHaptic()
            }
            cancelSequence()
        }
    }

    private func cancelSequence() {
        setWork?.cancel()
        startWork?.cancel()
        setWork = nil
        startWork = nil
    }

    private func resetUI() {
        falseStart = false
        reactionMS = nil
        startCueTime = nil
        sequenceActive = false
        shouldShowUpgradePrompt = false
    }

    private func preloadStarterSound() {
        if let url = Bundle.main.url(forResource: appStore.settings.starter.fileName, withExtension: "mp3") {
            starterSound = try? AVAudioPlayer(contentsOf: url)
            starterSound?.prepareToPlay()
        } else {
            starterSound = nil
        }
    }

    private func speak(_ phrase: String) {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: appStore.settings.voice.languageCode)
        synthesizer.speak(utterance)
    }

    private func prepareHaptics() {
        markHapticGenerator.prepare()
        setHapticGenerator.prepare()
        startHapticGenerator.prepare()
        falseStartHapticGenerator.prepare()
    }

    private func announceFalseStart() {
        synthesizer.stopSpeaking(at: .immediate)
        speak("False start")
    }

    private func playMarkHaptic() {
        markHapticGenerator.impactOccurred()
        markHapticGenerator.prepare()
    }

    private func playSetHaptic() {
        setHapticGenerator.impactOccurred()
        setHapticGenerator.prepare()
    }

    private func playStartHaptic() {
        startHapticGenerator.notificationOccurred(.success)
        startHapticGenerator.prepare()
    }

    private func playFalseStartHaptic() {
        falseStartHapticGenerator.notificationOccurred(.error)
        falseStartHapticGenerator.prepare()
    }
}

#Preview {
    NavigationStack {
        ReactionView()
            .environmentObject(AppSettingsStore())
            .environmentObject(PurchaseManager())
            .environmentObject(ReactionHistoryStore())
    }
}
