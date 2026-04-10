//
//  SessionHistoryView.swift
//  SprintStart
//
//  Created by Assistant on 3/8/26.
//

import SwiftUI
import Charts

struct SessionHistoryView: View {
    private static let recentAttemptsPreviewCount = 5
    private static let expandedAttemptsCount = 25
    private static let attemptRowSpacing: CGFloat = 8

    private enum HistoryRange: String, CaseIterable, Identifiable {
        case day
        case week
        case month
        case year
        case all

        var id: Self { self }

        var title: String {
            switch self {
            case .day: return "1D"
            case .week: return "1W"
            case .month: return "1M"
            case .year: return "1Y"
            case .all: return "All"
            }
        }

        func lowerBound(from now: Date) -> Date? {
            let calendar = Calendar.current
            switch self {
            case .day:
                return calendar.date(byAdding: .day, value: -1, to: now)
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .month:
                return calendar.date(byAdding: .month, value: -1, to: now)
            case .year:
                return calendar.date(byAdding: .year, value: -1, to: now)
            case .all:
                return nil
            }
        }
    }

    @EnvironmentObject private var appStore: AppSettingsStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var reactionHistoryStore: ReactionHistoryStore

    @State private var selectedRange: HistoryRange = .month
    @State private var isAttemptsExpanded = false
    @State private var showsSwipeTip = false
    @State private var paywallFeature: ProFeature?
    @AppStorage("sessionHistorySwipeTipDismissed") private var hasDismissedSwipeTip = false

    private struct ChartPoint: Identifiable {
        let id: UUID
        let attemptNumber: Int
        let date: Date
        let reactionMS: Int
    }

    private var allEntries: [ReactionHistoryEntry] {
        reactionHistoryStore.entries.sorted { $0.date < $1.date }
    }

    private var filteredEntries: [ReactionHistoryEntry] {
        guard let lowerBound = selectedRange.lowerBound(from: .now) else { return allEntries }
        return allEntries.filter { $0.date >= lowerBound }
    }

    private var reactionEntries: [ReactionHistoryEntry] {
        filteredEntries.filter { !$0.falseStart && $0.reactionMS != nil }
    }

    private var chartPoints: [ChartPoint] {
        reactionEntries.enumerated().compactMap { index, entry in
            guard let reactionMS = entry.reactionMS else { return nil }
            return ChartPoint(
                id: entry.id,
                attemptNumber: index + 1,
                date: entry.date,
                reactionMS: reactionMS
            )
        }
    }

    private var falseStartCount: Int {
        filteredEntries.filter(\.falseStart).count
    }

    private var recentAttemptsPreview: [ReactionHistoryEntry] {
        Array(filteredEntries.suffix(Self.recentAttemptsPreviewCount).reversed())
    }
    private var expandedAttemptsPreview: [ReactionHistoryEntry] {
        Array(filteredEntries.suffix(Self.expandedAttemptsCount).reversed())
    }
    private var overflowAttemptsPreview: [ReactionHistoryEntry] {
        Array(expandedAttemptsPreview.dropFirst(Self.recentAttemptsPreviewCount))
    }

    private var selectedRangeLowerBound: Date? {
        selectedRange.lowerBound(from: .now)
    }

    private var averageReaction: Int? {
        let results = reactionEntries.compactMap(\.reactionMS)
        guard !results.isEmpty else { return nil }
        return Int(Double(results.reduce(0, +)) / Double(results.count))
    }

    private var bestReaction: Int? {
        reactionEntries.compactMap(\.reactionMS).min()
    }
    private var canExpandAttempts: Bool {
        filteredEntries.count > Self.recentAttemptsPreviewCount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassLayout.sectionSpacing) {

                lockableHistorySection(rangePicker)
                lockableHistorySection(statsSection)
                lockableHistorySection(chartSection)
                lockableHistorySection(attemptsSection)
            }
            .padding(GlassLayout.screenPadding)
        }
        .navigationTitle("Reaction History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .liquidGlassScreenBackground(theme: appStore.settings.theme)
        .onAppear {
            if purchaseManager.hasPro && !hasDismissedSwipeTip {
                showsSwipeTip = true
            }
        }
        .onChange(of: purchaseManager.hasPro) {
            showsSwipeTip = purchaseManager.hasPro && !hasDismissedSwipeTip
        }
        .sheet(item: $paywallFeature) { feature in
            ProPaywallView(feature: feature)
        }
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                systemName: "calendar",
                tint: appStore.settings.theme.accentColor,
                title: "Range",
                summary: "Pick a window."
            )

            Picker("History Range", selection: $selectedRange) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
        .liquidGlassCard()
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            historyStat(title: "Best", value: bestReaction.map { "\($0) ms" } ?? "--")
            historyStat(title: "Average", value: averageReaction.map { "\($0) ms" } ?? "--")
            historyStat(title: "False Starts", value: "\(falseStartCount)")
        }
        .liquidGlassCard()
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                systemName: "waveform.path.ecg",
                tint: appStore.settings.theme.accentColor,
                title: "Reaction Trend",
                summary: "See progress."
            )

            if chartPoints.isEmpty {
                chartPlaceholder(
                    title: "No tracked reps yet",
                    subtitle: "Complete a few Reaction Mode reps and your trend line will appear here."
                )
            } else if chartPoints.count == 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(chartPoints[0].reactionMS) ms")
                        .font(AppTypography.metricCompact)
                        .foregroundStyle(appStore.settings.theme.accentColor)
                    Text("You need at least two tracked attempts in this range to see a trend line.")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Attempt", point.attemptNumber),
                        y: .value("Reaction Time", point.reactionMS)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(appStore.settings.theme.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Attempt", point.attemptNumber),
                        y: .value("Reaction Time", point.reactionMS)
                    )
                    .foregroundStyle(appStore.settings.theme.accentColor)
                    .symbolSize(50)
                }
                .frame(height: 240)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: xAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.secondary.opacity(0.25))
                        AxisTick(length: 6, stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.secondary.opacity(0.4))
                        AxisValueLabel(anchor: .top, verticalSpacing: 6) {
                            if let attemptNumber = value.as(Int.self),
                               let point = chartPoint(for: attemptNumber) {
                                VStack(spacing: 2) {
                                    Text("\(attemptNumber)")
                                        .fontWeight(.semibold)
                                    Text(point.date, format: selectedRange == .day ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day())
                                        .foregroundStyle(.secondary)
                                }
                                .font(AppTypography.caption)
                                .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .chartPlotStyle { content in
                    content
                        .background(.ultraThinMaterial.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    private var attemptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                systemName: "list.bullet.rectangle",
                tint: appStore.settings.theme.accentColor,
                title: "Recent Attempts",
                summary: "Latest reps."
            )

            if canExpandAttempts {
                DisclosureGroup(isExpanded: $isAttemptsExpanded) {
                    EmptyView()
                } label: {
                    Text(isAttemptsExpanded ? "Last 25 Attempts" : "Last 5 Attempts")
                        .font(AppTypography.secondaryStrong)
                }
                .tint(appStore.settings.theme.accentColor)
            }

            if filteredEntries.isEmpty {
                Text("No attempts are in this range yet. Try a wider range or complete a few more reps.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            } else {
                if purchaseManager.hasPro && showsSwipeTip {
                    swipeTip
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .top))
                            )
                        )
                }

                VStack(spacing: Self.attemptRowSpacing) {
                    ForEach(recentAttemptsPreview) { entry in
                        attemptSwipeRow(entry)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                )
                            )
                    }
                }

                if isAttemptsExpanded {
                    VStack(spacing: Self.attemptRowSpacing) {
                        ForEach(overflowAttemptsPreview) { entry in
                            attemptSwipeRow(entry)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity.combined(with: .move(edge: .leading))
                                    )
                                )
                        }
                    }
                    .padding(.top, Self.attemptRowSpacing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: filteredEntries.map(\.id))
    }

    private func historyStat(title: String, value: String) -> some View {
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
        .appInsetPanel(tint: appStore.settings.theme.accentColor, cornerRadius: 18)
    }

    private func chartPlaceholder(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.bodyStrong)
            Text(subtitle)
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lockableHistorySection<Content: View>(_ content: Content) -> some View {
        content
            .overlay {
                if !purchaseManager.hasPro {
                    historyLockOverlay
                }
            }
            .opacity(purchaseManager.hasPro ? 1.0 : 0.82)
            .saturation(purchaseManager.hasPro ? 1.0 : 0.72)
    }

    private var historyLockOverlay: some View {
        Button {
            paywallFeature = .sessionHistory
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.55))

                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(appStore.settings.theme.accentColor)
                    Text("Pro")
                        .font(AppTypography.captionEmphasis)
                    Text("Unlock session history")
                        .font(AppTypography.secondaryStrong)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock session history")
    }

    private var swipeTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.draw")
                .foregroundStyle(appStore.settings.theme.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tip")
                    .font(AppTypography.bodyStrong)
                Text("Swipe left on any attempt to delete it.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    showsSwipeTip = false
                }
                hasDismissedSwipeTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss delete tip")
        }
        .padding(12)
        .appInsetPanel(tint: appStore.settings.theme.accentColor, cornerRadius: 18)
    }

    private func attemptSwipeRow(_ entry: ReactionHistoryEntry) -> some View {
        HistoryAttemptSwipeRow(
            tint: appStore.settings.theme.accentColor,
            onDelete: {
                reactionHistoryStore.deleteEntry(id: entry.id)
            }
        ) {
            attemptRow(entry)
        }
    }

    private var xAxisValues: [Int] {
        guard let lastAttempt = chartPoints.last?.attemptNumber else { return [] }
        if chartPoints.count <= 4 {
            return chartPoints.map(\.attemptNumber)
        }

        let midpoint = max(2, Int(round(Double(lastAttempt) / 2.0)))
        let quarter = max(2, Int(round(Double(lastAttempt) / 4.0)))
        let threeQuarter = max(3, Int(round(Double(lastAttempt) * 0.75)))

        return Array(Set([1, quarter, midpoint, threeQuarter, lastAttempt])).sorted()
    }

    private func chartPoint(for attemptNumber: Int) -> ChartPoint? {
        chartPoints.first { $0.attemptNumber == attemptNumber }
    }

    private func attemptRow(_ entry: ReactionHistoryEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.falseStart ? "False Start" : "\(entry.reactionMS ?? 0) ms")
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(entry.falseStart ? .red : .primary)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: entry.falseStart ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(entry.falseStart ? .red : appStore.settings.theme.accentColor)
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryAttemptSwipeRow<Content: View>: View {
    private let maxDragDistance: CGFloat = 132
    private let fullSwipeDeleteThreshold: CGFloat = 112

    let tint: Color
    let onDelete: () -> Void
    private let content: Content

    @State private var offsetX: CGFloat = 0
    @State private var isDeleting = false

    init(
        tint: Color,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.red.opacity(0.82), .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 20)
                        .opacity(deleteProgress)
                        .scaleEffect(0.9 + (deleteProgress * 0.1))
                }
                .opacity(backgroundOpacity)

            content
                .contentShape(Rectangle())
                .offset(x: offsetX)
                .simultaneousGesture(dragGesture)
        }
        .clipped()
        .allowsHitTesting(!isDeleting)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.86), value: offsetX)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let horizontalTranslation = value.translation.width
                let verticalTranslation = value.translation.height

                guard abs(horizontalTranslation) > abs(verticalTranslation) else { return }

                if horizontalTranslation < 0 {
                    offsetX = max(horizontalTranslation, -maxDragDistance)
                } else {
                    offsetX = 0
                }
            }
            .onEnded { value in
                let translation = value.translation.width
                if translation < -fullSwipeDeleteThreshold {
                    triggerDelete()
                } else {
                    offsetX = 0
                }
            }
    }

    private func triggerDelete() {
        isDeleting = true
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
            offsetX = -240
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            onDelete()
        }
    }

    private var deleteProgress: CGFloat {
        min(max(-offsetX / fullSwipeDeleteThreshold, 0), 1)
    }

    private var backgroundOpacity: CGFloat {
        max(0, min((-offsetX / maxDragDistance) * 0.95, 0.95))
    }
}

#Preview {
    NavigationStack {
        SessionHistoryView()
            .environmentObject(AppSettingsStore())
            .environmentObject(PurchaseManager())
            .environmentObject(ReactionHistoryStore())
    }
}
