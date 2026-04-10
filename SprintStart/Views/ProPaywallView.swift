//
//  ProPaywallView.swift
//  SprintStart
//
//  Created by Assistant on 3/8/26.
//

import SwiftUI

struct ProPaywallView: View {
    @EnvironmentObject private var appStore: AppSettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    let feature: ProFeature

    @State private var message: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    heroSection
                    valueSection
                    trustSection
                }

                Spacer(minLength: 0)
                actionSection
            }
            .padding(GlassLayout.screenPadding)
            .navigationTitle("Sprint Start Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .liquidGlassScreenBackground(theme: appStore.settings.theme)
        .task {
            if purchaseManager.proProduct == nil {
                await purchaseManager.loadProducts()
            }
        }
        .alert("Unlock Pro", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            AppSectionHeader(
                systemName: "figure.run.circle.fill",
                tint: appStore.settings.theme.accentColor,
                title: "Unlock Pro",
                summary: "Train with deeper tools."
            )

            HStack {
                Label("One-time unlock", systemImage: "checkmark.seal.fill")
                    .font(AppTypography.secondaryStrong)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(priceLabelText)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .appInsetPanel(tint: appStore.settings.theme.accentColor, cornerRadius: 18)
        }
        .frame(maxWidth: .infinity)
        .liquidGlassCard()
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                systemName: "sparkles",
                tint: appStore.settings.theme.accentColor,
                title: "Included",
                summary: "Everything serious training needs."
            )

            HStack(spacing: 8) {
                benefitPill("Reaction")
                benefitPill("History")
                benefitPill("Daily")
                benefitPill("Randomness")
                benefitPill("Themes")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 10) {
                benefitRow(
                    title: "Track reaction timing",
                    detail: "Save reps, spot false starts, and measure improvement over time."
                )
                benefitRow(
                    title: "Review session history",
                    detail: "See trends and recent attempts instead of training blind."
                )
                benefitRow(
                    title: "Compete in daily challenges",
                    detail: "Use limited attempts, submit your best score, and chase podium badges."
                )
                benefitRow(
                    title: "Unlock more control",
                    detail: "Get advanced randomness plus the full sound, voice, and theme setup."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    private var trustSection: some View {
        VStack(spacing: 8) {
            Text("Built for repeat training")
                .font(AppTypography.bodyStrong)

            Text("Pro keeps your reaction work, history, and customization in one place without a subscription.")
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .liquidGlassCard()
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            statusMessageView
            successMessageView

            Button {
                Task {
                    let outcome = await purchaseManager.purchasePro()
                    switch outcome {
                    case .purchased:
                        await handleSuccessfulUnlock("Pro unlocked.")
                    case .cancelled:
                        break
                    case .pending:
                        message = "Purchase is pending approval."
                    case .failed(let errorMessage):
                        message = errorMessage
                    }
                }
            } label: {
                Text("Unlock Pro • \(priceLabelText)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(tint: .black))
            .disabled(!canPurchase)
            .opacity(canPurchase ? 1.0 : 0.6)
            .accessibilityIdentifier("proUnlockButton")

            if showsRetryButton {
                Button {
                    Task {
                        await purchaseManager.loadProducts()
                    }
                } label: {
                    Text("Retry")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("proRetryLoadButton")
            }

            Button {
                Task {
                    let outcome = await purchaseManager.restorePurchases()
                    switch outcome {
                    case .restored:
                        await handleSuccessfulUnlock("Pro restored.")
                    case .nothingToRestore:
                        message = "No previous Pro purchase was found."
                    case .failed(let errorMessage):
                        message = errorMessage
                    }
                }
            } label: {
                Text("Restore Purchases")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("proRestoreButton")

            Text("No subscription.")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .liquidGlassCard()
    }

    @ViewBuilder
    private var statusMessageView: some View {
        switch purchaseManager.productLoadState {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            Text("Loading purchase options…")
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("proIAPStatusMessage")
        case .empty, .failed:
            VStack(spacing: 10) {
                Text("Purchase options are temporarily unavailable.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("proIAPStatusMessage")
            }
        }
    }

    @ViewBuilder
    private var successMessageView: some View {
        if let successMessage {
            Text(successMessage)
                .font(AppTypography.secondaryStrong)
                .foregroundStyle(appStore.settings.theme.accentColor)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private var showsRetryButton: Bool {
        switch purchaseManager.productLoadState {
        case .empty, .failed:
            return true
        case .idle, .loading, .loaded:
            return false
        }
    }

    private var canPurchase: Bool {
        if purchaseManager.isPurchasing || purchaseManager.isLoadingProducts {
            return false
        }

        return purchaseManager.productLoadState == .loaded && purchaseManager.proProduct != nil
    }

    private var priceLabelText: String {
        purchaseManager.proProduct?.displayPrice ?? "Loading price…"
    }

    private func benefitPill(_ text: String) -> some View {
        AppFeaturePill(text: text)
    }

    private func benefitRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppTypography.bodyStrong)
                .foregroundStyle(appStore.settings.theme.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyStrong)
                Text(detail)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appInsetPanel(tint: appStore.settings.theme.accentColor, cornerRadius: 18)
    }

    @MainActor
    private func handleSuccessfulUnlock(_ text: String) async {
        successMessage = text
        try? await Task.sleep(for: .milliseconds(650))
        dismiss()
    }
}

#Preview {
    ProPaywallView(feature: .general)
        .environmentObject(AppSettingsStore())
        .environmentObject(PurchaseManager())
}
