//
//  DailyChallengeModels.swift
//  SprintStart
//
//  Created by Assistant on 3/9/26.
//

import Foundation

enum DailyChallengeDifficulty: String, Codable, CaseIterable, Identifiable {
    case playful
    case focused
    case brutal

    var id: Self { self }

    var title: String {
        switch self {
        case .playful: return "Playful"
        case .focused: return "Focused"
        case .brutal: return "Brutal"
        }
    }
}

enum DailyChallengeStartStyle: String, Codable, CaseIterable, Identifiable {
    case starterGun
    case whistle
    case electronic
    case clap
    case visualOnly

    var id: Self { self }
}

enum DailyChallengeVariant: String, Codable, CaseIterable, Identifiable {
    case longBurn
    case fakeThunder
    case tightWindow
    case silentSnap
    case doublePause
    case whistleWhiplash
    case clapChaos
    case rhythmBreaker
    case electronicTrap
    case marathonNerves
    case phantomGun
    case deadSilence
    case flashTrap
    case offBeat
    case echoStart
    case precisionMode
    case chaosMix
    case suddenDeath

    var id: Self { self }

    var title: String {
        switch self {
        case .longBurn: return "Long Burn"
        case .fakeThunder: return "Fake Thunder"
        case .tightWindow: return "Tight Window"
        case .silentSnap: return "Silent Snap"
        case .doublePause: return "Double Pause"
        case .whistleWhiplash: return "Whistle Whiplash"
        case .clapChaos: return "Clap Chaos"
        case .rhythmBreaker: return "Rhythm Breaker"
        case .electronicTrap: return "Electronic Trap"
        case .marathonNerves: return "Marathon Nerves"
        case .phantomGun: return "Phantom Gun"
        case .deadSilence: return "Dead Silence"
        case .flashTrap: return "Flash Trap"
        case .offBeat: return "Off Beat"
        case .echoStart: return "Echo Start"
        case .precisionMode: return "Precision Mode"
        case .chaosMix: return "Chaos Mix"
        case .suddenDeath: return "Sudden Death"
        }
    }
}

struct DailyChallengeRunProfile: Equatable {
    let markDelay: Double
    let setDelay: Double
    let fakeCueOffsets: [Double]
    let startStyle: DailyChallengeStartStyle
    let visualPulseCount: Int
}

struct DailyChallenge: Identifiable, Codable, Equatable {
    let id: String
    let dateKey: String
    let title: String
    let summary: String
    let detail: String
    let difficulty: DailyChallengeDifficulty
    let variant: DailyChallengeVariant
    let attemptLimit: Int
    let markDelayMin: Double
    let markDelayMax: Double
    let setDelayMin: Double
    let setDelayMax: Double
    let fakeCueCount: Int
    let visualPulseCount: Int
    let startStyle: DailyChallengeStartStyle

    var availableAttemptsText: String {
        "\(attemptLimit) attempt" + (attemptLimit == 1 ? "" : "s")
    }

    func makeRunProfile(attemptIndex: Int) -> DailyChallengeRunProfile {
        var generator = DailyChallengeRandomGenerator(seed: DailyChallengeRandomGenerator.stableSeed("\(dateKey)-\(attemptIndex)-\(variant.rawValue)"))
        let markDelay = generator.nextDouble(in: markDelayMin...markDelayMax)
        let setDelay = generator.nextDouble(in: setDelayMin...setDelayMax)

        var fakeCueOffsets: [Double] = []
        if fakeCueCount > 0 {
            for _ in 0..<fakeCueCount {
                fakeCueOffsets.append(generator.nextDouble(in: 0.4...(max(setDelay - 0.2, 0.45))))
            }
            fakeCueOffsets.sort()
        }

        return DailyChallengeRunProfile(
            markDelay: markDelay,
            setDelay: setDelay,
            fakeCueOffsets: fakeCueOffsets,
            startStyle: startStyle,
            visualPulseCount: visualPulseCount
        )
    }

    static func fallback(for dateKey: String) -> DailyChallenge {
        let variants = DailyChallengeVariant.allCases
        let seed = DailyChallengeRandomGenerator.stableSeed(dateKey)
#if DEBUG
        let variant = DailyChallengeSchedule.debugVariantOverride ?? variants[seed % variants.count]
#else
        let variant = variants[seed % variants.count]
#endif

        switch variant {
        case .longBurn:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Long Burn",
                summary: "A stretched out hold that tests patience.",
                detail: "The set-to-start gap drags on much longer than normal. Stay still and trust the final cue.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 5,
                markDelayMin: 1.6,
                markDelayMax: 2.8,
                setDelayMin: 3.5,
                setDelayMax: 5.8,
                fakeCueCount: 0,
                visualPulseCount: 1,
                startStyle: .starterGun
            )
        case .fakeThunder:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Fake Thunder",
                summary: "Decoy pulses try to trick your release.",
                detail: "You will get false cue flashes before the real start. False starts still burn an attempt.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 8,
                markDelayMin: 1.2,
                markDelayMax: 2.2,
                setDelayMin: 2.2,
                setDelayMax: 3.6,
                fakeCueCount: 2,
                visualPulseCount: 2,
                startStyle: .starterGun
            )
        case .tightWindow:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Tight Window",
                summary: "Short, nasty, and fast.",
                detail: "The real start comes quickly. There is not much time to settle in.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 6,
                markDelayMin: 1.0,
                markDelayMax: 1.8,
                setDelayMin: 0.8,
                setDelayMax: 1.4,
                fakeCueCount: 0,
                visualPulseCount: 1,
                startStyle: .electronic
            )
        case .silentSnap:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Silent Snap",
                summary: "No audio on the real start.",
                detail: "Only the screen pulse marks the real start. Great for breaking audio dependence.",
                difficulty: .playful,
                variant: variant,
                attemptLimit: 4,
                markDelayMin: 1.2,
                markDelayMax: 2.0,
                setDelayMin: 1.8,
                setDelayMax: 3.1,
                fakeCueCount: 0,
                visualPulseCount: 3,
                startStyle: .visualOnly
            )
        case .doublePause:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Double Pause",
                summary: "Two awkward pauses before the real pop.",
                detail: "The tempo feels broken on purpose. Keep your discipline through the dead air.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 6,
                markDelayMin: 2.2,
                markDelayMax: 3.0,
                setDelayMin: 2.6,
                setDelayMax: 4.2,
                fakeCueCount: 1,
                visualPulseCount: 1,
                startStyle: .whistle
            )
        case .whistleWhiplash:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Whistle Whiplash",
                summary: "Sharp whistle, volatile delay.",
                detail: "The whistle hits with a wide random window, so every rep feels slightly off rhythm.",
                difficulty: .playful,
                variant: variant,
                attemptLimit: 5,
                markDelayMin: 1.4,
                markDelayMax: 2.3,
                setDelayMin: 1.2,
                setDelayMax: 3.8,
                fakeCueCount: 0,
                visualPulseCount: 1,
                startStyle: .whistle
            )
        case .clapChaos:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Clap Chaos",
                summary: "An oddball hand-clap start with decoys.",
                detail: "The hand clap feels different enough to throw off your normal timing rhythm.",
                difficulty: .playful,
                variant: variant,
                attemptLimit: 7,
                markDelayMin: 1.0,
                markDelayMax: 2.0,
                setDelayMin: 1.4,
                setDelayMax: 2.8,
                fakeCueCount: 1,
                visualPulseCount: 2,
                startStyle: .clap
            )
        case .rhythmBreaker:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Rhythm Breaker",
                summary: "Everything feels slightly wrong on purpose.",
                detail: "The cadence stretches, compresses, and flashes in a way that punishes anticipation.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 9,
                markDelayMin: 1.8,
                markDelayMax: 2.8,
                setDelayMin: 1.6,
                setDelayMax: 4.8,
                fakeCueCount: 2,
                visualPulseCount: 2,
                startStyle: .electronic
            )
        case .electronicTrap:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Electronic Trap",
                summary: "Clean beep, ugly timing.",
                detail: "The electronic start is crisp, but the fake visual pulses make it hard to trust your eyes.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 7,
                markDelayMin: 1.1,
                markDelayMax: 1.9,
                setDelayMin: 1.5,
                setDelayMax: 3.0,
                fakeCueCount: 2,
                visualPulseCount: 1,
                startStyle: .electronic
            )
        case .marathonNerves:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Marathon Nerves",
                summary: "Huge delay range with extra attempts.",
                detail: "A grinder challenge with long holds and more swings at a clean rep.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 10,
                markDelayMin: 2.0,
                markDelayMax: 3.2,
                setDelayMin: 3.8,
                setDelayMax: 6.5,
                fakeCueCount: 1,
                visualPulseCount: 2,
                startStyle: .starterGun
            )
        case .phantomGun:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Phantom Gun",
                summary: "An early bang fires. It isn't the real one.",
                detail: "Visual pulses strike hard before the actual gun. Anticipators will burn attempts fast.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 7,
                markDelayMin: 1.4,
                markDelayMax: 2.2,
                setDelayMin: 2.8,
                setDelayMax: 4.5,
                fakeCueCount: 3,
                visualPulseCount: 3,
                startStyle: .starterGun
            )
        case .deadSilence:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Dead Silence",
                summary: "No audio. Not even a hint.",
                detail: "The real start is a single flash with zero sound. Harder than Silent Snap — there is nothing to hear at all.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 4,
                markDelayMin: 1.8,
                markDelayMax: 3.2,
                setDelayMin: 3.0,
                setDelayMax: 6.0,
                fakeCueCount: 0,
                visualPulseCount: 1,
                startStyle: .visualOnly
            )
        case .flashTrap:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Flash Trap",
                summary: "The screen fires multiple times. Only one counts.",
                detail: "Fake flashes hit hard and fast before the real electronic beep. Trust the sound, not your eyes.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 8,
                markDelayMin: 1.2,
                markDelayMax: 2.0,
                setDelayMin: 1.6,
                setDelayMax: 3.2,
                fakeCueCount: 3,
                visualPulseCount: 4,
                startStyle: .electronic
            )
        case .offBeat:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Off Beat",
                summary: "The rhythm feels set up. Then it isn't.",
                detail: "Mark and set land at a consistent pace, then the real start arrives somewhere completely unexpected. Cadence readers will blow it.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 6,
                markDelayMin: 2.0,
                markDelayMax: 2.6,
                setDelayMin: 0.9,
                setDelayMax: 4.2,
                fakeCueCount: 1,
                visualPulseCount: 1,
                startStyle: .clap
            )
        case .echoStart:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Echo Start",
                summary: "Two decoy cues, then the real thing.",
                detail: "Two electronic pulses fire close together before the final real start. Only the last one releases the clock.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 6,
                markDelayMin: 1.6,
                markDelayMax: 2.4,
                setDelayMin: 2.0,
                setDelayMax: 3.6,
                fakeCueCount: 2,
                visualPulseCount: 2,
                startStyle: .electronic
            )
        case .precisionMode:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Precision Mode",
                summary: "Short window. No tricks. Pure reaction.",
                detail: "Fast mark, fast set, clean gun. No fake cues, no deception. Just the tightest possible reaction test.",
                difficulty: .focused,
                variant: variant,
                attemptLimit: 5,
                markDelayMin: 0.8,
                markDelayMax: 1.2,
                setDelayMin: 0.5,
                setDelayMax: 0.9,
                fakeCueCount: 0,
                visualPulseCount: 1,
                startStyle: .starterGun
            )
        case .chaosMix:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Chaos Mix",
                summary: "Everything at once. Good luck.",
                detail: "Wide timing variance, multiple fakes, multi-flash pulses, and a whistle that arrives when it wants. Full chaos.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 10,
                markDelayMin: 1.0,
                markDelayMax: 3.0,
                setDelayMin: 1.0,
                setDelayMax: 5.0,
                fakeCueCount: 3,
                visualPulseCount: 3,
                startStyle: .whistle
            )
        case .suddenDeath:
            return DailyChallenge(
                id: dateKey,
                dateKey: dateKey,
                title: "Sudden Death",
                summary: "One attempt. Make it count.",
                detail: "No second chances today. A single clean starter gun is all you get. False start ends your run immediately.",
                difficulty: .brutal,
                variant: variant,
                attemptLimit: 1,
                markDelayMin: 1.4,
                markDelayMax: 2.2,
                setDelayMin: 1.6,
                setDelayMax: 3.4,
                fakeCueCount: 0,
                visualPulseCount: 1,
                startStyle: .starterGun
            )
        }
    }
}

struct DailyChallengeAttempt: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let reactionMS: Int?
    let falseStart: Bool

    init(timestamp: Date = .now, reactionMS: Int? = nil, falseStart: Bool) {
        self.id = UUID()
        self.timestamp = timestamp
        self.reactionMS = reactionMS
        self.falseStart = falseStart
    }
}

struct DailyChallengeProgress: Codable, Equatable {
    let challengeDateKey: String
    var attempts: [DailyChallengeAttempt]
    var didSubmit: Bool
    var submittedBestReactionMS: Int?
    /// Persisted so we can match the leaderboard entry after a cold launch before Game Center authenticates.
    var submittedPlayerID: String? = nil
    /// Player's display name at submission time — secondary identifier if IDs mismatch (e.g. debug vs real GK).
    var submittedPlayerName: String? = nil

    var bestReactionMS: Int? {
        attempts.compactMap(\.reactionMS).min()
    }
}

struct DailyChallengeLeaderboardEntry: Identifiable, Equatable {
    let id: String
    let rank: Int
    let playerID: String
    let playerName: String
    let bestReactionMS: Int
    let submittedAt: Date

    var badge: DailyChallengeBadge? {
        DailyChallengeBadge(rank: rank)
    }
}

enum DailyChallengeBadge: String, Codable, Identifiable, CaseIterable {
    case gold
    case silver
    case bronze

    var id: Self { self }

    init?(rank: Int) {
        switch rank {
        case 1: self = .gold
        case 2: self = .silver
        case 3: self = .bronze
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .gold: return "Gold"
        case .silver: return "Silver"
        case .bronze: return "Bronze"
        }
    }
}

struct DailyChallengeBadgeAward: Codable, Identifiable, Equatable {
    let id: String
    let dateKey: String
    let challengeTitle: String
    let badge: DailyChallengeBadge
    let bestReactionMS: Int
}

struct GameCenterPlayerProfile: Equatable {
    let gamePlayerID: String
    let displayName: String
}

enum DailyChallengeSchedule {
    static let fixedEST = TimeZone(secondsFromGMT: -5 * 60 * 60) ?? .gmt

#if DEBUG
    static var debugNowOverride: Date?
    static var debugVariantOverride: DailyChallengeVariant?
#endif

    static func currentDateKey(now: Date = .now) -> String {
        let referenceDate = effectiveNow(now)
        let formatter = DateFormatter()
        formatter.calendar = challengeCalendar
        formatter.timeZone = fixedEST
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: referenceDate)
    }

    static func nextResetDate(from now: Date = .now) -> Date {
        let referenceDate = effectiveNow(now)
        let calendar = challengeCalendar
        let components = calendar.dateComponents(in: fixedEST, from: referenceDate)
        var next = DateComponents()
        next.timeZone = fixedEST
        next.year = components.year
        next.month = components.month
        next.day = components.day
        next.hour = 24
        next.minute = 0
        next.second = 0
        return calendar.date(from: next) ?? referenceDate.addingTimeInterval(60 * 60)
    }

    static func resetDescription(from now: Date = .now) -> String {
        let referenceDate = effectiveNow(now)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        let interval = max(nextResetDate(from: referenceDate).timeIntervalSince(referenceDate), 0)
        return formatter.string(from: interval) ?? "soon"
    }

    private static var challengeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = fixedEST
        return calendar
    }

    private static func effectiveNow(_ now: Date) -> Date {
#if DEBUG
        debugNowOverride ?? now
#else
        now
#endif
    }
}

private struct DailyChallengeRandomGenerator {
    private var state: UInt64

    init(seed: Int) {
        self.state = UInt64(max(seed, 1))
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let fraction = Double(next() % 10_000) / 10_000.0
        return range.lowerBound + ((range.upperBound - range.lowerBound) * fraction)
    }

    static func stableSeed(_ string: String) -> Int {
        string.utf8.reduce(5381) { partialResult, nextByte in
            ((partialResult << 5) &+ partialResult) &+ Int(nextByte)
        }
    }
}
