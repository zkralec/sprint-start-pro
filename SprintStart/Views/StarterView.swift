//
//  StarterView.swift
//  SprintStart
//
//  Created by Zachary Kralec on 6/10/25.
//

import SwiftUI
import AVFoundation
import UIKit

struct StarterView: View {
    private static let postStartButtonCooldown: TimeInterval = 0.45

    @State private var canStart = true
    @State private var started = false
    @State private var starterSound: AVAudioPlayer?
    @State private var setWork: DispatchWorkItem?
    @State private var startWork: DispatchWorkItem?
    @State private var finishWork: DispatchWorkItem?
    @State private var countdownStartDate: Date?
    @State private var countdownEndDate: Date?

    @EnvironmentObject var appStore: AppSettingsStore

    private let synthesizer = AVSpeechSynthesizer()
    private let markHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let setHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let startHapticGenerator = UINotificationFeedbackGenerator()

    private var themeColor: Color { appStore.settings.theme.accentColor }
    private var primaryButtonTint: Color {
        if appStore.settings.theme == .blackWhite {
            return .black
        }
        return themeColor
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: GlassLayout.sectionSpacing) {

                    TimelineView(.animation(minimumInterval: 0.05, paused: countdownEndDate == nil)) { context in
                        CountdownRing(
                            totalTime: currentCountdownTotalTime,
                            remainingTime: currentRemainingTime(at: context.date),
                            lineWidth: 12,
                            ringColor: themeColor
                        )
                        .frame(height: 330)
                        .padding(.vertical, 4)
                    }

                    TimingControlsView(
                        markDelay: $appStore.starter.firstDelay,
                        startDelay: $appStore.starter.secondDelay,
                        variability: $appStore.starter.variability,
                        timingLocked: $appStore.starter.timingLocked,
                        interactionLocked: started
                    )

                    controlsSection

                    Spacer(minLength: 12)
                }
                .frame(minHeight: geometry.size.height)
                .padding(GlassLayout.screenPadding)
            }
        }
        .navigationTitle("Sprint Start Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                        .imageScale(.large)
                        .foregroundStyle(themeColor)
                        .accessibilityLabel("Settings")
                }
                .disabled(started)
                .opacity(started ? 0.45 : 1.0)
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
            canStart = true
            started = false
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                playStarterSequence()
            } label: {
                Text(started ? "Sequence Running" : "Start")
                    .font(AppTypography.cardTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(tint: primaryButtonTint))
            .disabled(!canStart)
            .opacity(!canStart ? 0.42 : 1.0)
            .saturation(!canStart ? 0.75 : 1.0)
            .accessibilityLabel("Start sequence")

            Button {
                cancelSequence()
                canStart = true
                started = false
                appStore.resetStarterToDefaults()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(tint: .red))
            .disabled(appStore.starter.timingLocked || started)
            .opacity((appStore.starter.timingLocked || started) ? 0.55 : 1.0)
            .saturation((appStore.starter.timingLocked || started) ? 0.78 : 1.0)
            .accessibilityLabel("Reset to defaults")
            .accessibilityIdentifier("resetDefaultsButtonStandard")
        }
    }

    private func playStarterSequence() {
        guard canStart else { return }

        canStart = false
        started = true
        cancelSequence()

        let startDelay = appStore.starter.variability.randomStartDelay(baseDelay: appStore.starter.secondDelay)

        startCountdown()
        prepareHaptics()

        let mark = AVSpeechUtterance(string: "On your marks")
        mark.voice = AVSpeechSynthesisVoice(language: appStore.settings.voice.languageCode)
        synthesizer.speak(mark)
        if appStore.settings.hapticsEnabled {
            playMarkHaptic()
        }

        let setItem = DispatchWorkItem {
            resetCountdown()

            let set = AVSpeechUtterance(string: "Set")
            set.voice = AVSpeechSynthesisVoice(language: appStore.settings.voice.languageCode)
            synthesizer.speak(set)
            if appStore.settings.hapticsEnabled {
                playSetHaptic()
            }

            let startItem = DispatchWorkItem {
                if let player = starterSound {
                    player.prepareToPlay()
                    player.play()
                }

                if appStore.settings.hapticsEnabled {
                    playStartHaptic()
                }

                let finishItem = DispatchWorkItem {
                    canStart = true
                    started = false
                }
                finishWork = finishItem
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.postStartButtonCooldown, execute: finishItem)
            }

            startWork = startItem
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay, execute: startItem)
        }

        setWork = setItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(appStore.starter.firstDelay), execute: setItem)
    }

    private var currentCountdownTotalTime: Double {
        guard let countdownStartDate, let countdownEndDate else {
            return Double(appStore.starter.firstDelay)
        }
        return max(countdownEndDate.timeIntervalSince(countdownStartDate), 0.1)
    }

    private func currentRemainingTime(at date: Date) -> Double {
        guard let countdownEndDate else { return 0 }
        return max(countdownEndDate.timeIntervalSince(date), 0)
    }

    private func startCountdown() {
        countdownStartDate = .now
        countdownEndDate = Date().addingTimeInterval(Double(appStore.starter.firstDelay))
    }

    private func resetCountdown() {
        countdownStartDate = nil
        countdownEndDate = nil
    }

    private func cancelSequence() {
        setWork?.cancel()
        startWork?.cancel()
        finishWork?.cancel()
        setWork = nil
        startWork = nil
        finishWork = nil
        resetCountdown()
    }

    private func preloadStarterSound() {
        guard let soundURL = Bundle.main.url(forResource: appStore.settings.starter.fileName, withExtension: "mp3") else {
            starterSound = nil
            return
        }

        starterSound = try? AVAudioPlayer(contentsOf: soundURL)
        starterSound?.prepareToPlay()
    }

    private func prepareHaptics() {
        markHapticGenerator.prepare()
        setHapticGenerator.prepare()
        startHapticGenerator.prepare()
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
}

private struct CountdownRing: View {
    let totalTime: Double
    let remainingTime: Double
    let lineWidth: CGFloat
    let ringColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: lineWidth)
                .opacity(0.25)
                .foregroundColor(ringColor)

            Circle()
                .trim(from: 0.0, to: CGFloat(remainingTime / max(totalTime, 1)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.1), value: remainingTime)

            Text("\(Int(remainingTime))")
                .font(.system(size: lineWidth * 2.2, weight: .bold, design: .rounded))
                .foregroundColor(ringColor)
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Countdown")
        .accessibilityValue(Text("\(Int(remainingTime)) seconds remaining"))
    }
}

#Preview {
    NavigationStack {
        StarterView()
            .environmentObject(AppSettingsStore())
            .environmentObject(PurchaseManager())
            .environmentObject(ReactionHistoryStore())
    }
}
