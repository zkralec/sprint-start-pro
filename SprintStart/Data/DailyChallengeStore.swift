//
//  DailyChallengeStore.swift
//  SprintStart
//
//  Created by Assistant on 3/9/26.
//

import CloudKit
import Foundation

struct DailyChallengeBadgeLookup {
    let dateKey: String
    let playerIDs: [String]
}

@MainActor
final class DailyChallengeStore: ObservableObject {
    @Published private(set) var currentChallenge: DailyChallenge?
    @Published private(set) var progress: DailyChallengeProgress?
    @Published private(set) var leaderboard: [DailyChallengeLeaderboardEntry] = []
    @Published private(set) var badges: [DailyChallengeBadgeAward] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var lastErrorMessage: String?
#if DEBUG
    @Published private(set) var debugBadgePreview: [DailyChallengeBadgeAward] = []
#endif

    private let defaults: UserDefaults
    private let service: DailyChallengeCloudService

    private enum Keys {
        static let progressPrefix = "dailyChallengeProgress"
        static let lastKnownPlayerID = "dailyChallenge.lastKnownPlayerID"
        static let knownPlayerIDs = "dailyChallenge.knownPlayerIDs"
        static let badgeAwardCache = "dailyChallenge.badgeAwardCache"
    }

    private enum Limits {
        static let badgeLookupCount = 30
    }

    /// The most recently seen Game Center player ID, persisted across cold launches so we can
    /// match the leaderboard entry even before GK authentication resolves.
    var lastKnownPlayerID: String? {
        defaults.string(forKey: Keys.lastKnownPlayerID)
    }

    init(
        defaults: UserDefaults = .standard,
        service: DailyChallengeCloudService = DailyChallengeCloudService()
    ) {
        self.defaults = defaults
        self.service = service
        self.badges = Self.loadCachedBadges(from: defaults)
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

    /// The Game Center player ID saved at submission time — available after cold launch before GC auth resolves.
    var submittedPlayerID: String? { progress?.submittedPlayerID }

    /// The display name saved at submission time — used as a last-resort match if player IDs don't align.
    var submittedPlayerName: String? { progress?.submittedPlayerName }

    var canDiscardAndSubmit: Bool {
        attemptsUsed > 0 && !hasSubmittedToday && remainingAttempts > 0
    }

    func refresh(playerProfile: GameCenterPlayerProfile?) async {
        isLoading = true
        defer { isLoading = false }

        // Persist the player ID as soon as we have it — survives cold launches and backfills
        // entries submitted before submittedPlayerID was added to DailyChallengeProgress.
        rememberPlayerID(playerProfile?.gamePlayerID)

        let dateKey = DailyChallengeSchedule.currentDateKey()
        let challenge = await service.fetchChallenge(for: dateKey)
        currentChallenge = challenge

        var loaded = loadProgress(for: challenge.dateKey, attemptLimit: challenge.attemptLimit)
        // Backfill submittedPlayerID for progress saved before this field existed
        if loaded.didSubmit && loaded.submittedPlayerID == nil, let playerID = playerProfile?.gamePlayerID {
            loaded.submittedPlayerID = playerID
            saveProgress(loaded)
        }
        progress = loaded

        await refreshCompetitionData(
            for: challenge.dateKey,
            badgeLookups: submittedBadgeLookups(playerProfile: playerProfile)
        )
    }

    func refreshLeaderboardOnly(playerProfile: GameCenterPlayerProfile?) async {
        rememberPlayerID(playerProfile?.gamePlayerID)
        guard let currentChallenge else { return }
        await refreshCompetitionData(
            for: currentChallenge.dateKey,
            badgeLookups: submittedBadgeLookups(playerProfile: playerProfile)
        )
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
        progress.submittedPlayerID = playerProfile?.gamePlayerID
        progress.submittedPlayerName = playerProfile?.displayName
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
            // Brief delay so CloudKit finishes indexing before we query rankings
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            rememberPlayerID(playerProfile.gamePlayerID)
            leaderboard = try await service.fetchLeaderboard(for: currentChallenge.dateKey)
            let fetchedBadges = try await service.fetchBadges(
                lookups: submittedBadgeLookups(playerProfile: playerProfile)
            )
            updateBadges(with: fetchedBadges)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = cloudStatusMessage(for: error, defaultMessage: "Could not submit today's score. Please try again.")
        }
    }

    private func refreshCompetitionData(
        for dateKey: String,
        badgeLookups: [DailyChallengeBadgeLookup]
    ) async {
        do {
            leaderboard = try await service.fetchLeaderboard(for: dateKey)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = cloudStatusMessage(for: error)
        }

        do {
            let fetchedBadges = try await service.fetchBadges(lookups: badgeLookups)
            updateBadges(with: fetchedBadges)
        } catch {
            lastErrorMessage = cloudStatusMessage(for: error)
        }
    }

    private func cloudStatusMessage(for error: Error, defaultMessage: String = "Leaderboard unavailable right now. Please try again.") -> String {
        guard let ckError = error as? CKError else {
            return defaultMessage
        }

        switch ckError.code {
        case .badContainer, .missingEntitlement, .notAuthenticated:
            return "CloudKit is not available for this build or account."
        case .invalidArguments, .serverRejectedRequest:
            return "Leaderboard query failed in CloudKit. If this only happens in TestFlight, deploy the production CloudKit schema and indexes."
        case .permissionFailure:
            return "CloudKit permission failure. Check the production container configuration."
        default:
            return ckError.localizedDescription.isEmpty ? defaultMessage : ckError.localizedDescription
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

    /// Returns submitted progress entries so badges can be fetched with the player ID that
    /// originally created each CloudKit record.
    private func submittedProgressEntries() -> [DailyChallengeProgress] {
        let prefix = Keys.progressPrefix + "."
        return defaults.dictionaryRepresentation()
            .keys
            .filter { $0.hasPrefix(prefix) }
            .compactMap { key -> DailyChallengeProgress? in
                guard let data = defaults.data(forKey: key) else { return nil }
                return try? JSONDecoder().decode(DailyChallengeProgress.self, from: data)
            }
            .filter { $0.didSubmit }
            .sorted { $0.challengeDateKey > $1.challengeDateKey }
    }

    private func submittedBadgeLookups(playerProfile: GameCenterPlayerProfile?) -> [DailyChallengeBadgeLookup] {
        let fallbackIDs = uniquePlayerIDs([playerProfile?.gamePlayerID] + knownPlayerIDs.map(Optional.some))

        return submittedProgressEntries()
            .prefix(Limits.badgeLookupCount)
            .compactMap { progress in
                let playerIDs = uniquePlayerIDs([progress.submittedPlayerID] + fallbackIDs.map(Optional.some))
                guard !playerIDs.isEmpty else { return nil }
                return DailyChallengeBadgeLookup(dateKey: progress.challengeDateKey, playerIDs: playerIDs)
            }
    }

    private var knownPlayerIDs: [String] {
        if let storedIDs = defaults.stringArray(forKey: Keys.knownPlayerIDs), !storedIDs.isEmpty {
            return storedIDs
        }
        return lastKnownPlayerID.map { [$0] } ?? []
    }

    private func rememberPlayerID(_ playerID: String?) {
        guard let playerID, !playerID.isEmpty else { return }

        let existingIDs = knownPlayerIDs
        defaults.set(playerID, forKey: Keys.lastKnownPlayerID)

        let updatedIDs = uniquePlayerIDs([playerID] + existingIDs.map(Optional.some))
        defaults.set(updatedIDs, forKey: Keys.knownPlayerIDs)
    }

    private func updateBadges(with fetchedAwards: [DailyChallengeBadgeAward]) {
        guard !fetchedAwards.isEmpty else { return }

        badges = mergedBadgeAwards(existing: badges, fetched: fetchedAwards)
        saveCachedBadges(badges)
    }

    private func mergedBadgeAwards(
        existing: [DailyChallengeBadgeAward],
        fetched: [DailyChallengeBadgeAward]
    ) -> [DailyChallengeBadgeAward] {
        var awardsByID: [String: DailyChallengeBadgeAward] = [:]
        for award in existing {
            awardsByID[award.id] = award
        }
        for award in fetched {
            awardsByID[award.id] = award
        }

        return awardsByID.values.sorted {
            if $0.dateKey == $1.dateKey {
                return badgePriority($0.badge) < badgePriority($1.badge)
            }
            return $0.dateKey > $1.dateKey
        }
    }

    private func badgePriority(_ badge: DailyChallengeBadge) -> Int {
        switch badge {
        case .gold: return 0
        case .silver: return 1
        case .bronze: return 2
        }
    }

    private func uniquePlayerIDs(_ playerIDs: [String?]) -> [String] {
        var seen = Set<String>()
        var uniqueIDs: [String] = []

        for playerID in playerIDs {
            guard let playerID, !playerID.isEmpty, !seen.contains(playerID) else { continue }
            seen.insert(playerID)
            uniqueIDs.append(playerID)
        }

        return uniqueIDs
    }

    private static func loadCachedBadges(from defaults: UserDefaults) -> [DailyChallengeBadgeAward] {
        guard let data = defaults.data(forKey: Keys.badgeAwardCache),
              let decoded = try? JSONDecoder().decode([DailyChallengeBadgeAward].self, from: data) else {
            return []
        }

        return decoded
    }

    private func saveCachedBadges(_ badges: [DailyChallengeBadgeAward]) {
        if let data = try? JSONEncoder().encode(badges) {
            defaults.set(data, forKey: Keys.badgeAwardCache)
        }
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
        debugBadgePreview = [
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

    func debugLoadBadgeGallery() {
        let variants = Array(DailyChallengeVariant.allCases.prefix(12))
        debugBadgePreview = variants.enumerated().map { index, variant in
            let badge: DailyChallengeBadge
            switch index % 3 {
            case 0: badge = .gold
            case 1: badge = .silver
            default: badge = .bronze
            }

            let dayOffset = index + 1
            let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: .now) ?? .now
            let dateKey = DailyChallengeSchedule.currentDateKey(now: date)

            return DailyChallengeBadgeAward(
                id: "\(dateKey)-\(badge.rawValue)-\(variant.rawValue)",
                dateKey: dateKey,
                challengeTitle: variant.title,
                badge: badge,
                bestReactionMS: 110 + (index * 5)
            )
        }
    }

    func debugClearAwardsAndLeaderboard() {
        leaderboard = []
        badges = []
        saveCachedBadges([])
#if DEBUG
        debugBadgePreview = []
#endif
    }

    func debugWipeAllCloudKitEntries() async {
        guard let currentChallenge else { return }
        try? await service.deleteAllSubmissions(for: currentChallenge.dateKey)
        leaderboard = []
        lastErrorMessage = nil
    }

    func debugWipeMyCloudKitEntry(playerProfile: GameCenterPlayerProfile?) async {
        guard let currentChallenge else { return }
        let playerID = playerProfile?.gamePlayerID ?? progress?.submittedPlayerID
        if let playerID {
            try? await service.deleteSubmission(for: currentChallenge.dateKey, playerID: playerID)
        }
        // Reset local progress too
        let fresh = DailyChallengeProgress(challengeDateKey: currentChallenge.dateKey, attempts: [], didSubmit: false, submittedBestReactionMS: nil)
        progress = fresh
        saveProgress(fresh)
        leaderboard = (try? await service.fetchLeaderboard(for: currentChallenge.dateKey)) ?? []
        lastErrorMessage = nil
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

    func fetchLeaderboard(for dateKey: String, limit: Int = 50) async throws -> [DailyChallengeLeaderboardEntry] {
        let predicate = NSPredicate(format: "challengeDateKey == %@", dateKey)
        let query = CKQuery(recordType: Constants.submissionRecordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: "bestReactionMS", ascending: true),
            NSSortDescriptor(key: "submittedAt", ascending: true)
        ]

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
    }

    /// Fetches badge awards by looking up each submitted date's record directly by its known
    /// record name, avoiding a QUERYABLE index requirement on the `playerID` field.
    func fetchBadges(lookups: [DailyChallengeBadgeLookup]) async throws -> [DailyChallengeBadgeAward] {
        guard !lookups.isEmpty else { return [] }

        var awards: [DailyChallengeBadgeAward] = []
        var firstError: Error?
        for lookup in lookups {
            do {
                guard let submission = try await fetchSubmissionRecord(for: lookup),
                      let title = submission.record["challengeTitle"] as? String,
                      let bestReaction = submission.record["bestReactionMS"] as? Int64 else {
                    continue
                }

                let topEntries = try await fetchLeaderboard(for: lookup.dateKey, limit: 3)
                if let entry = topEntries.first(where: { $0.playerID == submission.playerID }),
                   let badge = entry.badge {
                    awards.append(
                        DailyChallengeBadgeAward(
                            id: "\(lookup.dateKey)-\(badge.rawValue)",
                            dateKey: lookup.dateKey,
                            challengeTitle: title,
                            badge: badge,
                            bestReactionMS: Int(bestReaction)
                        )
                    )
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
                continue
            }
        }

        if awards.isEmpty, let firstError {
            throw firstError
        }

        return awards
    }

    private func fetchSubmissionRecord(for lookup: DailyChallengeBadgeLookup) async throws -> (playerID: String, record: CKRecord)? {
        for playerID in lookup.playerIDs {
            let recordID = CKRecord.ID(recordName: "\(lookup.dateKey)-\(playerID)")
            let recordResults = try await database.records(for: [recordID])
            if case .success(let record) = recordResults[recordID] {
                return (playerID, record)
            }
        }

        return nil
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

    func deleteAllSubmissions(for dateKey: String) async throws {
        let predicate = NSPredicate(format: "challengeDateKey == %@", dateKey)
        let query = CKQuery(recordType: Constants.submissionRecordType, predicate: predicate)

        let results = try await database.records(matching: query, inZoneWith: nil, desiredKeys: [], resultsLimit: 200)
        let recordIDs = results.matchResults.compactMap { _, result in try? result.get().recordID }

        guard !recordIDs.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    func deleteSubmission(for dateKey: String, playerID: String) async throws {
        let recordID = CKRecord.ID(recordName: "\(dateKey)-\(playerID)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: recordID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
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
