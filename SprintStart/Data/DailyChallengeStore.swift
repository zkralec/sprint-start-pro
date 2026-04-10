//
//  DailyChallengeStore.swift
//  SprintStart
//
//  Created by Assistant on 3/9/26.
//

import CloudKit
import Foundation

@MainActor
final class DailyChallengeStore: ObservableObject {
    @Published private(set) var currentChallenge: DailyChallenge?
    @Published private(set) var progress: DailyChallengeProgress?
    @Published private(set) var leaderboard: [DailyChallengeLeaderboardEntry] = []
    @Published private(set) var badges: [DailyChallengeBadgeAward] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let service: DailyChallengeCloudService

    private enum Keys {
        static let progressPrefix = "dailyChallengeProgress"
    }

    init(
        defaults: UserDefaults = .standard,
        service: DailyChallengeCloudService = DailyChallengeCloudService()
    ) {
        self.defaults = defaults
        self.service = service
    }

    var attemptsUsed: Int {
        progress?.attempts.count ?? 0
    }

    var remainingAttempts: Int {
        guard let currentChallenge else { return 0 }
        return max(currentChallenge.attemptLimit - attemptsUsed, 0)
    }

    var bestReactionMS: Int? {
        progress?.bestReactionMS
    }

    var hasSubmittedToday: Bool {
        progress?.didSubmit ?? false
    }

    var canDiscardAndSubmit: Bool {
        attemptsUsed > 0 && !hasSubmittedToday && remainingAttempts > 0
    }

    func refresh(playerProfile: GameCenterPlayerProfile?) async {
        isLoading = true
        defer { isLoading = false }

        let dateKey = DailyChallengeSchedule.currentDateKey()
        let challenge = await service.fetchChallenge(for: dateKey)
        currentChallenge = challenge
        progress = loadProgress(for: challenge.dateKey, attemptLimit: challenge.attemptLimit)

        async let leaderboardTask = service.fetchLeaderboard(for: challenge.dateKey)
        async let badgesTask = service.fetchBadges(for: playerProfile?.gamePlayerID)

        leaderboard = await leaderboardTask
        badges = await badgesTask
    }

    func recordAttempt(
        reactionMS: Int?,
        falseStart: Bool,
        playerProfile: GameCenterPlayerProfile?
    ) async {
        guard var progress else { return }
        guard let currentChallenge else { return }
        guard !progress.didSubmit else { return }
        guard progress.attempts.count < currentChallenge.attemptLimit else { return }

        progress.attempts.append(
            DailyChallengeAttempt(reactionMS: reactionMS, falseStart: falseStart)
        )
        self.progress = progress
        saveProgress(progress)

        if progress.attempts.count >= currentChallenge.attemptLimit {
            await submitCurrentRun(playerProfile: playerProfile)
        }
    }

    func discardRemainingAttemptsAndSubmit(playerProfile: GameCenterPlayerProfile?) async {
        guard canDiscardAndSubmit else { return }
        await submitCurrentRun(playerProfile: playerProfile)
    }

    private func submitCurrentRun(playerProfile: GameCenterPlayerProfile?) async {
        guard let currentChallenge else { return }
        guard var progress else { return }
        guard !progress.didSubmit else { return }

        progress.didSubmit = true
        progress.submittedBestReactionMS = progress.bestReactionMS
        self.progress = progress
        saveProgress(progress)

        guard let playerProfile else {
            lastErrorMessage = "Sign in to Game Center to submit your result."
            return
        }

        guard let bestReactionMS = progress.bestReactionMS else {
            lastErrorMessage = "No valid reaction to submit today."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await service.submit(
                challenge: currentChallenge,
                playerProfile: playerProfile,
                progress: progress,
                bestReactionMS: bestReactionMS
            )
            leaderboard = await service.fetchLeaderboard(for: currentChallenge.dateKey)
            badges = await service.fetchBadges(for: playerProfile.gamePlayerID)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Could not submit today's score. Please try again."
        }
    }

    private func loadProgress(for dateKey: String, attemptLimit: Int) -> DailyChallengeProgress {
        let key = progressKey(for: dateKey)
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DailyChallengeProgress.self, from: data),
           decoded.challengeDateKey == dateKey {
            return decoded
        }

        return DailyChallengeProgress(
            challengeDateKey: dateKey,
            attempts: [],
            didSubmit: false,
            submittedBestReactionMS: nil
        )
    }

    private func saveProgress(_ progress: DailyChallengeProgress) {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: progressKey(for: progress.challengeDateKey))
        }
    }

    private func progressKey(for dateKey: String) -> String {
        "\(Keys.progressPrefix).\(dateKey)"
    }

#if DEBUG
    func debugResetTodayProgress() {
        guard let currentChallenge else { return }
        let progress = DailyChallengeProgress(
            challengeDateKey: currentChallenge.dateKey,
            attempts: [],
            didSubmit: false,
            submittedBestReactionMS: nil
        )
        self.progress = progress
        saveProgress(progress)
        lastErrorMessage = nil
    }

    func debugAddAttempt(reactionMS: Int?, falseStart: Bool) {
        guard var progress else { return }
        guard let currentChallenge else { return }
        guard progress.attempts.count < currentChallenge.attemptLimit else { return }

        progress.attempts.append(
            DailyChallengeAttempt(reactionMS: reactionMS, falseStart: falseStart)
        )
        self.progress = progress
        saveProgress(progress)
        lastErrorMessage = nil
    }

    func debugMarkSubmitted() {
        guard var progress else { return }
        progress.didSubmit = true
        progress.submittedBestReactionMS = progress.bestReactionMS
        self.progress = progress
        saveProgress(progress)
        lastErrorMessage = nil
    }

    func debugLoadSampleLeaderboard(playerProfile: GameCenterPlayerProfile?) {
        let challengeDateKey = currentChallenge?.dateKey ?? DailyChallengeSchedule.currentDateKey()
        let currentPlayerID = playerProfile?.gamePlayerID ?? "debug-player"
        let currentPlayerName = playerProfile?.displayName ?? "Debug Runner"

        leaderboard = [
            DailyChallengeLeaderboardEntry(id: "\(challengeDateKey)-1", rank: 1, playerID: "runner-a", playerName: "Quick Nova", bestReactionMS: 112, submittedAt: .now.addingTimeInterval(-600)),
            DailyChallengeLeaderboardEntry(id: "\(challengeDateKey)-2", rank: 2, playerID: currentPlayerID, playerName: currentPlayerName, bestReactionMS: 118, submittedAt: .now.addingTimeInterval(-420)),
            DailyChallengeLeaderboardEntry(id: "\(challengeDateKey)-3", rank: 3, playerID: "runner-c", playerName: "Lane Rocket", bestReactionMS: 121, submittedAt: .now.addingTimeInterval(-300)),
            DailyChallengeLeaderboardEntry(id: "\(challengeDateKey)-4", rank: 4, playerID: "runner-d", playerName: "Static Bolt", bestReactionMS: 126, submittedAt: .now.addingTimeInterval(-180)),
            DailyChallengeLeaderboardEntry(id: "\(challengeDateKey)-5", rank: 5, playerID: "runner-e", playerName: "Fast Cedar", bestReactionMS: 132, submittedAt: .now.addingTimeInterval(-60))
        ]
    }

    func debugLoadSampleBadges() {
        let challenge = currentChallenge ?? .fallback(for: DailyChallengeSchedule.currentDateKey())
        badges = [
            DailyChallengeBadgeAward(
                id: "\(challenge.dateKey)-gold",
                dateKey: challenge.dateKey,
                challengeTitle: challenge.title,
                badge: .gold,
                bestReactionMS: 116
            ),
            DailyChallengeBadgeAward(
                id: "2026-03-08-silver",
                dateKey: "2026-03-08",
                challengeTitle: "Fake Thunder",
                badge: .silver,
                bestReactionMS: 124
            ),
            DailyChallengeBadgeAward(
                id: "2026-03-07-bronze",
                dateKey: "2026-03-07",
                challengeTitle: "Silent Snap",
                badge: .bronze,
                bestReactionMS: 141
            )
        ]
    }

    func debugClearAwardsAndLeaderboard() {
        leaderboard = []
        badges = []
    }

    func debugForceVariant(_ variant: DailyChallengeVariant) {
        DailyChallengeSchedule.debugVariantOverride = variant
        let dateKey = DailyChallengeSchedule.currentDateKey()
        let challenge = DailyChallenge.fallback(for: dateKey)
        currentChallenge = challenge
        let fresh = DailyChallengeProgress(
            challengeDateKey: dateKey,
            attempts: [],
            didSubmit: false,
            submittedBestReactionMS: nil
        )
        progress = fresh
        saveProgress(fresh)
        lastErrorMessage = nil
    }
#endif
}

actor DailyChallengeCloudService {
    private let container: CKContainer
    private let database: CKDatabase

    private enum Constants {
        static let containerIdentifier = "iCloud.com.zack.sprintstart"
        static let challengeRecordType = "DailyChallenge"
        static let submissionRecordType = "DailyChallengeSubmission"
    }

    init(container: CKContainer = CKContainer(identifier: Constants.containerIdentifier)) {
        self.container = container
        self.database = container.publicCloudDatabase
    }

    func fetchChallenge(for dateKey: String) async -> DailyChallenge {
        let recordID = CKRecord.ID(recordName: dateKey)

        do {
            let results = try await database.records(for: [recordID])
            if case .success(let record) = results[recordID] {
                return dailyChallenge(from: record) ?? .fallback(for: dateKey)
            }
        } catch {
            return .fallback(for: dateKey)
        }

        return .fallback(for: dateKey)
    }

    func fetchLeaderboard(for dateKey: String, limit: Int = 50) async -> [DailyChallengeLeaderboardEntry] {
        let predicate = NSPredicate(format: "challengeDateKey == %@", dateKey)
        let query = CKQuery(recordType: Constants.submissionRecordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: "bestReactionMS", ascending: true),
            NSSortDescriptor(key: "submittedAt", ascending: true)
        ]

        do {
            let results = try await database.records(
                matching: query,
                inZoneWith: nil,
                desiredKeys: nil,
                resultsLimit: limit
            )

            let records = results.matchResults.compactMap { _, result in
                try? result.get()
            }

            return records.enumerated().compactMap { index, record in
                leaderboardEntry(from: record, rank: index + 1)
            }
        } catch {
            return []
        }
    }

    func fetchBadges(for playerID: String?) async -> [DailyChallengeBadgeAward] {
        guard let playerID else { return [] }

        let predicate = NSPredicate(format: "playerID == %@", playerID)
        let query = CKQuery(recordType: Constants.submissionRecordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: "submittedAt", ascending: false)
        ]

        do {
            let results = try await database.records(
                matching: query,
                inZoneWith: nil,
                desiredKeys: nil,
                resultsLimit: 12
            )

            let records = results.matchResults.compactMap { _, result in
                try? result.get()
            }

            var awards: [DailyChallengeBadgeAward] = []
            for record in records {
                guard let dateKey = record["challengeDateKey"] as? String,
                      let title = record["challengeTitle"] as? String,
                      let bestReaction = record["bestReactionMS"] as? Int64 else {
                    continue
                }

                let topEntries = await fetchLeaderboard(for: dateKey, limit: 3)
                if let award = topEntries.first(where: { $0.playerID == playerID })?.badge {
                    awards.append(
                        DailyChallengeBadgeAward(
                            id: "\(dateKey)-\(award.rawValue)",
                            dateKey: dateKey,
                            challengeTitle: title,
                            badge: award,
                            bestReactionMS: Int(bestReaction)
                        )
                    )
                }
            }

            return awards
        } catch {
            return []
        }
    }

    func submit(
        challenge: DailyChallenge,
        playerProfile: GameCenterPlayerProfile,
        progress: DailyChallengeProgress,
        bestReactionMS: Int
    ) async throws {
        let recordID = CKRecord.ID(recordName: "\(challenge.dateKey)-\(playerProfile.gamePlayerID)")
        let record: CKRecord

        do {
            let results = try await database.records(for: [recordID])
            if case .success(let existingRecord) = results[recordID] {
                record = existingRecord
            } else {
                record = CKRecord(recordType: Constants.submissionRecordType, recordID: recordID)
            }
        } catch {
            record = CKRecord(recordType: Constants.submissionRecordType, recordID: recordID)
        }

        record["challengeDateKey"] = challenge.dateKey as CKRecordValue
        record["challengeTitle"] = challenge.title as CKRecordValue
        record["playerID"] = playerProfile.gamePlayerID as CKRecordValue
        record["playerName"] = playerProfile.displayName as CKRecordValue
        record["bestReactionMS"] = bestReactionMS as CKRecordValue
        record["attemptsUsed"] = progress.attempts.count as CKRecordValue
        record["falseStarts"] = progress.attempts.filter(\.falseStart).count as CKRecordValue
        record["submittedAt"] = Date() as CKRecordValue

        try await save(record: record)
    }

    private func dailyChallenge(from record: CKRecord) -> DailyChallenge? {
        guard let dateKey = record.recordID.recordName as String?,
              let title = record["title"] as? String,
              let summary = record["summary"] as? String,
              let detail = record["detail"] as? String,
              let variantRawValue = record["variant"] as? String,
              let variant = DailyChallengeVariant(rawValue: variantRawValue),
              let difficultyRawValue = record["difficulty"] as? String,
              let difficulty = DailyChallengeDifficulty(rawValue: difficultyRawValue),
              let attemptLimitValue = record["attemptLimit"] as? Int64,
              let markDelayMin = record["markDelayMin"] as? Double,
              let markDelayMax = record["markDelayMax"] as? Double,
              let setDelayMin = record["setDelayMin"] as? Double,
              let setDelayMax = record["setDelayMax"] as? Double,
              let fakeCueCountValue = record["fakeCueCount"] as? Int64,
              let visualPulseCountValue = record["visualPulseCount"] as? Int64,
              let startStyleRawValue = record["startStyle"] as? String,
              let startStyle = DailyChallengeStartStyle(rawValue: startStyleRawValue) else {
            return nil
        }

        return DailyChallenge(
            id: dateKey,
            dateKey: dateKey,
            title: title,
            summary: summary,
            detail: detail,
            difficulty: difficulty,
            variant: variant,
            attemptLimit: Int(attemptLimitValue),
            markDelayMin: markDelayMin,
            markDelayMax: markDelayMax,
            setDelayMin: setDelayMin,
            setDelayMax: setDelayMax,
            fakeCueCount: Int(fakeCueCountValue),
            visualPulseCount: Int(visualPulseCountValue),
            startStyle: startStyle
        )
    }

    private func leaderboardEntry(from record: CKRecord, rank: Int) -> DailyChallengeLeaderboardEntry? {
        guard let playerID = record["playerID"] as? String,
              let playerName = record["playerName"] as? String,
              let bestReactionMS = record["bestReactionMS"] as? Int64,
              let submittedAt = record["submittedAt"] as? Date else {
            return nil
        }

        return DailyChallengeLeaderboardEntry(
            id: record.recordID.recordName,
            rank: rank,
            playerID: playerID,
            playerName: playerName,
            bestReactionMS: Int(bestReactionMS),
            submittedAt: submittedAt
        )
    }

    private func save(record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.save(record) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
