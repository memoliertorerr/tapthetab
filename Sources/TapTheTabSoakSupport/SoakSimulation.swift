import Foundation
import TapTheTabCore

// A deterministic, virtual-clock soak of the switching and preview-capture policies.
//
// The simulation drives the production `SwitcherSession`, `ItemFilter`,
// `LargePreviewCaptureSchedule`, `PreviewCaptureTarget`, `CaptureWorkLimiter`,
// `PreviewImageRetention` and `PreviewFreshness` with fictional windows, the way the app's
// coordinator, thumbnail service and preview store call them. Native screenshot and
// window-list calls are simulated: they answer after seeded latencies, late, out of order,
// or not for a long time. Nothing touches real windows, permissions, settings or the clock.
//
// It checks contracts the app relies on rather than re-deriving each policy branch:
// bounded native work, the selection settling before a capture during cycling, the final
// selection being captured soon after it rests, a resting preview being refreshed, retained
// images staying bounded. Closed-session delivery guards are modelled and late results counted. The same seed always
// produces the same report, including its digest.
//
// What it does not show: AppKit, Accessibility or ScreenCaptureKit cost and behaviour. The
// glue that mirrors the app's coordinator is a model of it, not the app's code.

/// SplitMix64. Identical on every platform and Swift version, unlike the standard
/// library's generators, so a seed always reproduces the same workload.
public struct SoakRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range` (the modulo bias is negligible for these small ranges).
    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        return range.lowerBound + Int(next() % span)
    }

    public mutating func micros(_ range: ClosedRange<Int64>) -> Int64 {
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        return range.lowerBound + Int64(next() % span)
    }

    /// True with probability `probability`.
    public mutating func chance(_ probability: Double) -> Bool {
        Double(next() >> 11) * 0x1p-53 < probability
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[int(0...(values.count - 1))]
    }
}

/// The kinds of synthetic session the soak cycles through, in order, so every kind runs
/// once the workload has at least `allCases.count` sessions.
public enum SoakScenario: String, CaseIterable, Sendable {
    /// ⇥ tapped or held: bursts of 15–70 ms steps, with pauses and rests between them.
    case rapidCycling
    /// Deliberate steps 150–900 ms apart.
    case slowBrowsing
    /// Typing, deleting and clearing a fuzzy search.
    case search
    /// Windows closing, opening, minimizing and reusing window numbers mid-session.
    case catalogChurn
    /// Native calls answering around and after their timeouts, out of order.
    case lateCompletions
    /// Native calls answering only after many seconds, saturating the work limit.
    case hungCaptures
    /// Long rests so periodic refreshes and failure back-off run.
    case restingRefresh
    /// Open and close within a few milliseconds, often before the panel shows.
    case quickTaps
}

/// The size of a soak run. Values are clamped to the limits; the command-line harness
/// rejects out-of-range input instead.
public struct SoakWorkload: Equatable, Sendable {
    public static let sessionRange = 1...1_000_000
    public static let windowRange = 2...5_000
    public static let stepRange = 1...10_000
    /// Input budget enforced by the CLI, not this value type. Catalog size also affects work;
    /// this is not a wall-clock time limit.
    public static let maxTotalSteps = 50_000_000
    public static let defaultSeed: UInt64 = 0x7AB5_5EED

    public var seed: UInt64
    /// Switcher sessions to open and close.
    public var sessions: Int
    /// The largest synthetic window catalog.
    public var maxWindows: Int
    /// The most inputs in one session.
    public var maxSteps: Int

    public init(seed: UInt64 = SoakWorkload.defaultSeed, sessions: Int = 400, maxWindows: Int = 120, maxSteps: Int = 120) {
        self.seed = seed
        self.sessions = min(max(sessions, Self.sessionRange.lowerBound), Self.sessionRange.upperBound)
        self.maxWindows = min(max(maxWindows, Self.windowRange.lowerBound), Self.windowRange.upperBound)
        self.maxSteps = min(max(maxSteps, Self.stepRange.lowerBound), Self.stepRange.upperBound)
    }
}

/// What one soak run did and whether every checked contract held.
public struct SoakReport: Equatable, Sendable {
    public var seed: UInt64 = 0
    public var sessionsRequested = 0
    public var sessionsCompleted = 0
    /// Stopped early by the caller; the sessions that ran are still checked.
    public var cancelled = false
    public var sessionsByScenario: [SoakScenario: Int] = [:]
    public var eventsProcessed = 0
    /// Simulated time covered by the run, in seconds.
    public var virtualSeconds: Double = 0

    // Catalog and session
    public var windowsGenerated = 0
    public var largestCatalog = 0
    public var largestSessionList = 0
    public var inputs = 0
    public var windowActions = 0
    public var catalogReplacements = 0
    public var sessionsClosedBeforeShowing = 0

    // Large-preview schedule
    public var selectionNotifications = 0
    public var cyclingNotifications = 0
    public var deferredSelections = 0
    public var previewAttempts = 0
    public var previewSkipped = 0
    public var previewCaptured = 0
    public var previewFailed = 0
    public var refreshAttempts = 0
    /// Completions ignored because a newer large-preview capture had started.
    public var supersededCompletions = 0
    /// Longest wait, in seconds, from a selection change to the capture attempt for it.
    public var longestSelectionToAttempt: Double = 0
    /// Longest wait, in seconds, from a finished capture to a resting selection's refresh.
    public var longestRefreshGap: Double = 0
    /// Longest time, in seconds, from a large-preview capture start to its completion.
    public var longestPreviewCompletion: Double = 0

    // Simulated native work
    public var nativeCallsStarted = 0
    public var answeredOnTime = 0
    public var answeredLate = 0
    public var timedOut = 0
    /// Queued captures failed without a native call because the limit was saturated.
    public var failedWithoutStarting = 0
    public var maxOutstandingNativeCalls = 0
    public var maxRunningNativeCalls = 0
    public var maxStartsWithoutAnswer = 0
    public var maxQueuedCaptures = 0
    public var thumbnailsDelivered = 0
    public var windowListFetches = 0
    public var windowListTimeouts = 0
    public var windowListRefusals = 0
    public var windowListLateAnswers = 0
    public var maxOutstandingWindowLists = 0
    /// Answers and completions that arrived after their session closed.
    public var closedSessionResultsDropped = 0

    // Retained large-preview images
    public var imagesStored = 0
    public var olderResultsRejected = 0
    public var imagesDroppedByRetention = 0
    public var imagesPruned = 0
    public var maxRetainedImages = 0
    public var maxRetainedPixels = 0
    public var retainedImagesAtEnd = 0

    // Verdict
    public var violationCount = 0
    /// The first violations, for diagnosis.
    public var violations: [String] = []
    /// FNV-1a over the run's event trace: equal seeds and workloads give equal digests.
    public var digest: UInt64 = 0

    public init() {}

    public var passed: Bool { violationCount == 0 }
}

public enum SoakSimulation {
    /// Runs `workload` to completion, or until `shouldContinue` (asked between sessions)
    /// returns false. Late native answers are always drained before the report is made.
    public static func run(_ workload: SoakWorkload, shouldContinue: () -> Bool = { true }) -> SoakReport {
        run(workload, policies: .production, shouldContinue: shouldContinue)
    }

    static func run(_ workload: SoakWorkload, policies: SoakPolicies, shouldContinue: () -> Bool = { true }) -> SoakReport {
        let simulator = SoakSimulator(workload: workload, policies: policies)
        return simulator.run(shouldContinue: shouldContinue)
    }
}

// MARK: - Policy seams

// The production policies, behind protocols so tests can swap in a deliberately broken
// variant and show that the soak's checks catch it.

protocol SoakCaptureScheduling {
    var needsCaptureRetry: Bool { get }
    mutating func selectionChanged(at now: TimeInterval) -> LargePreviewCaptureSchedule.Decision
    mutating func timerFired(at now: TimeInterval) -> LargePreviewCaptureSchedule.Decision
    mutating func captureFinished(at now: TimeInterval, outcome: LargePreviewCaptureSchedule.Outcome) -> LargePreviewCaptureSchedule.Decision
}

extension LargePreviewCaptureSchedule: SoakCaptureScheduling {}

protocol SoakWorkLimiting {
    var nextDeadline: TimeInterval? { get }
    var isSaturated: Bool { get }
    var canStart: Bool { get }
    mutating func start(at now: TimeInterval) -> Int?
    mutating func finish(_ ticket: Int) -> CaptureWorkLimiter.Finish
    mutating func expire(at now: TimeInterval) -> [Int]
    mutating func abandon(_ ticket: Int) -> Bool
}

extension CaptureWorkLimiter: SoakWorkLimiting {}

protocol SoakImageRetaining {
    mutating func insert(_ key: ItemID, pixels: Int, protecting protected: ItemID?) -> [ItemID]
    mutating func touch(_ key: ItemID)
    mutating func remove(_ key: ItemID)
    mutating func prune(keeping kept: Set<ItemID>) -> [ItemID]
}

extension PreviewImageRetention: SoakImageRetaining where Key == ItemID {}

struct SoakPolicies {
    var makeSchedule: () -> any SoakCaptureScheduling
    var makeLimiter: (_ maxRunning: Int, _ maxAbandoned: Int, _ timeout: TimeInterval) -> any SoakWorkLimiting
    var makeRetention: () -> any SoakImageRetaining

    static var production: SoakPolicies {
        SoakPolicies(
            makeSchedule: { LargePreviewCaptureSchedule(refreshInterval: PreviewFreshness.refreshInterval) },
            makeLimiter: { CaptureWorkLimiter(maxRunning: $0, maxAbandoned: $1, timeout: $2) },
            makeRetention: { PreviewImageRetention<ItemID>() }
        )
    }
}

// MARK: - Simulator

/// The app's values (ThumbnailService and the preview store), restated for the model.
enum SoakAppLimits {
    static let maxRunningCaptures = 4
    static let maxAbandonedCaptures = 4
    static let captureTimeout: TimeInterval = 3
    static let windowListTimeout: TimeInterval = 3
    static let windowListLifetime: TimeInterval = 1.5
    static let thumbnailLongEdge = 360
    static let retainedImages = 3
    static let retainedPixels = 16_000_000
    /// At most this many screenshot calls are ever outstanding (running or abandoned).
    static var maxOutstandingCaptures: Int { maxRunningCaptures + maxAbandonedCaptures - 1 }
}

/// Retain a bounded sample of freed IDs. Old runs accumulated millions of IDs and
/// random removals became progressively more expensive. Keeping the original removal
/// order below the cap preserves existing small-workload digests.
struct SoakWindowNumberPool {
    static let capacity = 65_536
    private var numbers: [UInt32] = []
    var count: Int { numbers.count }
    var isEmpty: Bool { numbers.isEmpty }
    mutating func append(_ number: UInt32) {
        if numbers.count < Self.capacity { numbers.append(number) }
    }
    mutating func remove(at index: Int) -> UInt32 { numbers.remove(at: index) }
}

private enum SoakEvent {
    case open
    case show(token: Int)
    case input(token: Int)
    case finish(token: Int)
    case catalogRefresh(token: Int)
    case previewTimer(id: Int)
    case nativeAnswer(ticket: Int, succeeds: Bool)
    case watchdog
    case windowListAnswer(ticket: Int, succeeds: Bool)
    case windowListTimeout(ticket: Int)

    var code: UInt64 {
        switch self {
        case .open: return 1
        case .show: return 2
        case .input: return 3
        case .finish: return 4
        case .catalogRefresh: return 5
        case .previewTimer: return 6
        case .nativeAnswer: return 7
        case .watchdog: return 8
        case .windowListAnswer: return 9
        case .windowListTimeout: return 10
        }
    }
}

/// A binary heap ordered by time, then by insertion, so equal times stay deterministic.
private struct SoakEventQueue {
    private var heap: [(time: Int64, order: Int, event: SoakEvent)] = []
    private var counter = 0

    var isEmpty: Bool { heap.isEmpty }

    mutating func push(_ event: SoakEvent, at time: Int64) {
        heap.append((time, counter, event))
        counter += 1
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard less(child, parent) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (time: Int64, event: SoakEvent)? {
        guard !heap.isEmpty else { return nil }
        heap.swapAt(0, heap.count - 1)
        let top = heap.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < heap.count, less(left, smallest) { smallest = left }
            if right < heap.count, less(right, smallest) { smallest = right }
            guard smallest != parent else { break }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
        return (top.time, top.event)
    }

    private func less(_ a: Int, _ b: Int) -> Bool {
        heap[a].time != heap[b].time ? heap[a].time < heap[b].time : heap[a].order < heap[b].order
    }
}

private final class SoakCaptureRequest {
    enum Kind {
        case thumbnails
        case largePreview(serial: Int)
    }

    let kind: Kind
    let token: Int
    let pixelSize: Int
    var remaining = 0
    var failed: Set<UInt32> = []

    init(kind: Kind, token: Int, pixelSize: Int) {
        self.kind = kind
        self.token = token
        self.pixelSize = pixelSize
    }
}

private struct SoakJob {
    let windowID: UInt32
    let owner: Int32
    let generation: Int
    let request: SoakCaptureRequest
}

private struct SoakStoredImage {
    let capturedAt: Int64
    let pixels: Int
    let owner: Int32
}

private struct SoakApp {
    let pid: Int32
    let name: String
    let bundleID: String
}

final class SoakSimulator {
    private static let appNames = [
        "Atlas Notes", "Birch Mail", "Cobalt Shell", "Dune Sketch", "Ember Tasks", "Fjord Browser",
        "Garnet Music", "Harbor Chat", "Iris Photos", "Juniper Code", "Kestrel Maps", "Lumen Docs",
        "Marble Sheets", "Nimbus Files", "Opal Calendar", "Pine Reader",
    ]
    private static let titleWords = [
        "Draft", "Inbox", "Notes", "Plan", "Budget", "Sketch", "Report", "Ideas", "Archive",
        "Journal", "Recipe", "Itinerary", "Tasks", "Meeting", "Review", "Summary",
    ]
    private static let searchLetters = Array("aeinorstlcdmpubg ")
    /// The simulated switcher's own process; `ItemFilter` must never list it.
    private static let ownPID: Int32 = 999

    private let workload: SoakWorkload
    private let policies: SoakPolicies
    private var random: SoakRandom
    private var report = SoakReport()
    private var queue = SoakEventQueue()
    private var now: Int64 = 0
    private var digest: UInt64 = 0xCBF2_9CE4_8422_2325
    /// A session ended during the current event: the next one is due.
    private var sessionClosed = false

    // World: every synthetic window and windowless app, most recent first.
    private var world: [SwitcherItem] = []
    private var apps: [SoakApp] = []
    private var nextWindowNumber: UInt32 = 1
    private var freedWindowNumbers = SoakWindowNumberPool()
    private var nextPID: Int32 = 1_000

    // Coordinator model
    private var token = 0
    private var session: SwitcherSession?
    private var scenario: SoakScenario = .rapidCycling
    private var sessionOptions = FilterOptions()
    private var sessionScope: SwitcherScope = .allWindows
    private var sessionContext = FilterContext()
    private var panelVisible = false
    private var showPending = false
    private var stepsLeft = 0
    private var burstStepsLeft = 0
    private var schedule: any SoakCaptureScheduling
    private var timerID = 0
    private var timerPending = false
    private var requestedTarget: PreviewCaptureTarget?
    private var previewSerial = 0
    private var previewStartedAt: [Int: Int64] = [:]
    private var largePreviewPixelSize = 1_200
    private var lastThumbnailRequestIDs: [ItemID] = []

    // Thumbnail-service model
    private var generation = 0
    private var jobs: [SoakJob] = []
    private var jobHead = 0
    private var inFlight: [Int: SoakJob] = [:]
    /// When each running or abandoned native call started (images are stamped with it).
    private var callStartedAt: [Int: Int64] = [:]
    private var captureLimiter: any SoakWorkLimiting
    private var watchdogScheduled = false
    private var windowListLimiter: any SoakWorkLimiting
    private var windowListTicket: Int?
    private var windowList: (owners: [UInt32: Int32], at: Int64)?
    private var windowListWaiters: [([UInt32: Int32]?) -> Void] = []

    // Preview-store model
    private var images: [ItemID: SoakStoredImage] = [:]
    private var retention: any SoakImageRetaining
    private var selectedID: ItemID?

    // Independent bookkeeping for the checks
    private var outstandingCaptures = 0
    private var startsSinceAnswer = 0
    private var outstandingWindowLists = 0
    private var windowListStartsSinceAnswer = 0
    private var lastNotifiedChange: Int64?
    private var settleUntil: Int64?
    private var attemptDueBy: Int64?
    private var refreshDueBy: Int64?
    private var restingSince: Int64?
    private var unfinishedPreviewStarts: [Int64] = []

    init(workload: SoakWorkload, policies: SoakPolicies) {
        self.workload = workload
        self.policies = policies
        random = SoakRandom(seed: workload.seed)
        schedule = policies.makeSchedule()
        captureLimiter = policies.makeLimiter(
            SoakAppLimits.maxRunningCaptures, SoakAppLimits.maxAbandonedCaptures, SoakAppLimits.captureTimeout
        )
        windowListLimiter = policies.makeLimiter(1, 1, SoakAppLimits.windowListTimeout)
        retention = policies.makeRetention()
        report.seed = workload.seed
        report.sessionsRequested = workload.sessions
    }

    func run(shouldContinue: () -> Bool) -> SoakReport {
        queue.push(.open, at: 0)
        // Every input causes a bounded amount of follow-up work; this cap turns a runaway
        // feedback loop (a timer rescheduling itself forever) into a violation.
        let eventLimit = (workload.sessions * (workload.maxSteps + 8) + 64) * 4_000
        while let next = queue.pop() {
            if next.time < now { violate("event scheduled in the past") }
            now = next.time
            report.eventsProcessed += 1
            trace(next.event.code, UInt64(bitPattern: now))
            checkDeadlines()
            dispatch(next.event, shouldContinue: shouldContinue)
            if report.eventsProcessed > eventLimit {
                violate("runaway event loop: more than \(eventLimit) events")
                break
            }
        }
        finishRun()
        return report
    }

    // MARK: Events

    private func dispatch(_ event: SoakEvent, shouldContinue: () -> Bool) {
        switch event {
        case .open:
            openSession()
        case .show(let sessionToken):
            guard sessionToken == token, showPending else { return }
            showPanel()
        case .input(let sessionToken):
            guard sessionToken == token, session != nil else { return }
            handleScriptedInput()
        case .finish(let sessionToken):
            guard sessionToken == token, session != nil else { return }
            finishSession()
        case .catalogRefresh(let sessionToken):
            guard sessionToken == token, session != nil else { return }
            refreshCatalog()
        case .previewTimer(let id):
            guard id == timerID, timerPending else { return }
            timerPending = false
            guard panelVisible else { return }
            perform(schedule.timerFired(at: seconds(now)))
        case .nativeAnswer(let ticket, let succeeds):
            nativeAnswered(ticket: ticket, succeeds: succeeds)
        case .watchdog:
            watchdogScheduled = false
            expireOverdueCaptures()
        case .windowListAnswer(let ticket, let succeeds):
            windowListAnswered(ticket: ticket, succeeds: succeeds)
        case .windowListTimeout(let ticket):
            guard windowListTicket == ticket, windowListLimiter.abandon(ticket) else { return }
            report.windowListTimeouts += 1
            windowListTicket = nil
            finishWindowListWaiters(nil)
        }
        guard sessionClosed else { return }
        sessionClosed = false
        if report.sessionsCompleted < workload.sessions, shouldContinue() {
            queue.push(.open, at: now + random.micros(20_000...3_000_000))
        } else {
            report.cancelled = report.sessionsCompleted < workload.sessions
        }
    }

    // MARK: Session lifecycle

    private func openSession() {
        scenario = SoakScenario.allCases[report.sessionsCompleted % SoakScenario.allCases.count]
        report.sessionsByScenario[scenario, default: 0] += 1
        evolveWorld()

        token += 1
        resetPreviewSchedule()
        sessionOptions = randomOptions()
        sessionScope = random.chance(0.7) ? .allWindows : random.pick([.activeApp, .apps])
        sessionContext = FilterContext(
            activePID: world.first?.pid,
            activeDisplayID: UInt32(random.int(1...3)),
            ownPID: Self.ownPID
        )
        let items = filteredWorld()
        var newSession = SwitcherSession(
            items: items,
            startsOnPrevious: random.chance(0.9),
            locked: random.chance(0.05),
            columns: random.int(1...8),
            wrapsAround: random.chance(0.8)
        )
        if random.chance(0.1) { newSession.handle(.last) }
        session = newSession
        checkSession(newSession)
        report.largestSessionList = max(report.largestSessionList, items.count)

        largePreviewPixelSize = random.int(240...2_400)
        panelVisible = false
        showPending = true
        switch scenario {
        case .quickTaps: stepsLeft = random.int(1...3)
        case .restingRefresh: stepsLeft = random.int(1...max(1, min(workload.maxSteps, 12)))
        default: stepsLeft = random.int(1...workload.maxSteps)
        }
        let showDelay: Int64 = scenario == .quickTaps ? random.micros(30_000...250_000)
            : (random.chance(0.5) ? 0 : random.micros(0...150_000))
        queue.push(.show(token: token), at: now + showDelay)
        queue.push(.input(token: token), at: now + inputGap())
        if scenario == .catalogChurn {
            for _ in 0..<random.int(1...4) {
                queue.push(.catalogRefresh(token: token), at: now + random.micros(10_000...3_000_000))
            }
        }
    }

    private func showPanel() {
        showPending = false
        panelVisible = true
        updatePanel(itemsChanged: true)
        // The large preview first: its capture goes ahead of the cards' thumbnails.
        requestSelectedPreview(force: true)
        requestThumbnails()
    }

    private func close() {
        checkDeadlines()
        if !panelVisible { report.sessionsClosedBeforeShowing += 1 }
        resetPreviewSchedule()
        token += 1
        session = nil
        panelVisible = false
        showPending = false
        cancelPendingCaptures()
        if jobs.count - jobHead != 0 { violate("captures still queued after closing") }
        report.sessionsCompleted += 1
        sessionClosed = true
    }

    private func resetPreviewSchedule() {
        cancelTimer()
        schedule = policies.makeSchedule()
        requestedTarget = nil
        lastNotifiedChange = nil
        settleUntil = nil
        attemptDueBy = nil
        refreshDueBy = nil
        restingSince = nil
        unfinishedPreviewStarts.removeAll()
    }

    private func handleScriptedInput() {
        apply(nextInput())
        guard session != nil else { return }
        stepsLeft -= 1
        if stepsLeft > 0 {
            queue.push(.input(token: token), at: now + inputGap())
        } else {
            queue.push(.finish(token: token), at: now + inputGap())
        }
    }

    private func finishSession() {
        let ending: SwitcherInput
        switch random.int(0...19) {
        case 0...13: ending = .triggerReleased
        case 14...16: ending = .commit
        case 17...18: ending = .cancel
        default: ending = .quickSelect(index: random.int(0...8))
        }
        apply(ending)
        // A locked session, a cleared query or a missing quick-select slot leaves it open.
        if session != nil { apply(.cancel) }
        if session != nil { apply(.commit) }
        if session != nil {
            violate("commit did not end the session")
            close()
        }
    }

    private func apply(_ input: SwitcherInput) {
        guard var current = session else { return }
        let effect = current.handle(input)
        session = current
        report.inputs += 1
        checkSession(current)
        trace(11, UInt64(bitPattern: Int64(current.selectedIndex ?? -1)))
        switch effect {
        case .none, .peek:
            break
        case .refresh:
            if panelVisible {
                updatePanel(itemsChanged: false)
                requestSelectedPreview()
            } else if showPending {
                // Interacting before the show delay ran out shows the panel at once.
                showPanel()
            }
        case .activate(let item):
            if !current.visible.contains(where: { $0.id == item.id }) { violate("activated an item that is not listed") }
            if let index = world.firstIndex(where: { $0.id == item.id }) {
                world.insert(world.remove(at: index), at: 0)
            }
            close()
        case .dismiss:
            close()
        case .perform(let action, let item):
            report.windowActions += 1
            perform(action, on: item)
        }
    }

    /// The coordinator's handling of a window action on the session's own list.
    private func perform(_ action: WindowAction, on item: SwitcherItem) {
        guard var current = session else { return }
        var items = current.items
        switch action {
        case .close:
            items.removeAll { $0.id == item.id }
            removeFromWorld { $0.id == item.id }
        case .quitApp:
            items.removeAll { $0.pid == item.pid }
            removeFromWorld { $0.pid == item.pid }
            apps.removeAll { $0.pid == item.pid }
        case .minimize:
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isMinimized.toggle() }
            if let index = world.firstIndex(where: { $0.id == item.id }) { world[index].isMinimized.toggle() }
        case .hideApp:
            let hidden = !item.isAppHidden
            for index in items.indices where items[index].pid == item.pid { items[index].isAppHidden = hidden }
            for index in world.indices where world[index].pid == item.pid { world[index].isAppHidden = hidden }
        case .closeAppWindows:
            items.removeAll { $0.pid == item.pid && !$0.isWindowless }
            removeFromWorld { $0.pid == item.pid && !$0.isWindowless }
        case .toggleFullscreen, .focus, .moveToNextDisplay, .togglePin:
            break
        }
        current.replaceItems(items)
        session = current
        checkSession(current)
        if panelVisible {
            updatePanel(itemsChanged: true)
            requestSelectedPreview()
        }
    }

    private func refreshCatalog() {
        churnWorld(maxChanges: 4)
        guard var current = session else { return }
        current.replaceItems(filteredWorld())
        session = current
        checkSession(current)
        report.catalogReplacements += 1
        report.largestSessionList = max(report.largestSessionList, current.items.count)
        if panelVisible {
            updatePanel(itemsChanged: true)
            if current.visible.map(\.id) != lastThumbnailRequestIDs { requestThumbnails() }
            requestSelectedPreview()
        }
    }

    // MARK: Inputs

    private func nextInput() -> SwitcherInput {
        let count = session?.visible.count ?? 0
        let roll = random.int(0...99)
        switch scenario {
        case .search:
            switch roll {
            case 0...44:
                let title = Array(session?.selectedItem?.displayTitle.lowercased() ?? "")
                if !title.isEmpty, random.chance(0.4) { return .type(String(random.pick(title))) }
                return .type(String(random.pick(Self.searchLetters)))
            case 45...64: return .deleteBackward
            case 65...72: return .cancel
            default: return random.chance(0.7) ? .next : .previous
            }
        case .catalogChurn:
            if roll < 25 {
                return .action(random.pick([.close, .minimize, .hideApp, .quitApp, .closeAppWindows, .togglePin]))
            }
            return navigation(roll: random.int(0...99), count: count)
        default:
            return navigation(roll: roll, count: count)
        }
    }

    private func navigation(roll: Int, count: Int) -> SwitcherInput {
        switch roll {
        case 0...49: return .next
        case 50...64: return .previous
        case 65...68: return .moveDown
        case 69...72: return .moveUp
        case 73...76: return .moveRight
        case 77...80: return .moveLeft
        case 81...83: return .first
        case 84...86: return .last
        case 87...96: return .select(index: random.int(0...max(0, count - 1)))
        default: return .lockOpen
        }
    }

    private func inputGap() -> Int64 {
        switch scenario {
        case .rapidCycling:
            // Bursts of a few quick steps, each followed by a short pause or by a rest to
            // look at the final selection's preview.
            if burstStepsLeft > 0 {
                burstStepsLeft -= 1
                return random.micros(15_000...70_000)
            }
            burstStepsLeft = random.int(1...5)
            return random.chance(0.5) ? random.micros(150_000...700_000) : random.micros(1_200_000...3_000_000)
        case .slowBrowsing: return random.micros(150_000...900_000)
        case .search: return random.micros(40_000...250_000)
        case .catalogChurn: return random.micros(30_000...600_000)
        case .lateCompletions: return random.micros(20_000...400_000)
        case .hungCaptures: return random.micros(20_000...300_000)
        case .restingRefresh: return random.micros(1_500_000...20_000_000)
        case .quickTaps: return random.micros(0...60_000)
        }
    }

    // MARK: Large preview (the coordinator's scheduling)

    private func requestSelectedPreview(force: Bool = false) {
        guard let current = session else { return }
        let target = current.selectedItem.map {
            PreviewCaptureTarget(id: $0.id, pixelSize: largePreviewPixelSize, owner: $0.pid)
        }
        guard force || (target?.requiresCapture(after: requestedTarget) ?? (requestedTarget != nil)) else {
            // Same window: the refresh keeps it fresh; retry one that had nothing to capture.
            if target != nil, !timerPending, schedule.needsCaptureRetry, panelVisible {
                perform(schedule.timerFired(at: seconds(now)))
            }
            return
        }
        requestedTarget = target
        cancelTimer()
        guard target != nil else {
            attemptDueBy = nil
            refreshDueBy = nil
            restingSince = nil
            return
        }
        noteSelectionNotified()
        let decision = schedule.selectionChanged(at: seconds(now))
        if case .wait = decision { report.deferredSelections += 1 }
        perform(decision)
    }

    private func perform(_ decision: LargePreviewCaptureSchedule.Decision) {
        switch decision {
        case .none:
            trace(20, 0)
        case .captureNow:
            trace(21, 0)
            cancelTimer()
            startLargePreviewCapture()
        case .wait(let delay):
            trace(22, UInt64(bitPattern: micros(delay)))
            cancelTimer()
            timerID += 1
            timerPending = true
            queue.push(.previewTimer(id: timerID), at: now + max(1, micros(delay)))
        }
    }

    private func cancelTimer() {
        timerPending = false
        timerID += 1
    }

    private func startLargePreviewCapture() {
        report.previewAttempts += 1
        if let settleUntil, seconds(now) < seconds(settleUntil) - 1e-6 {
            violate("capture started \(format(seconds(settleUntil) - seconds(now))) s before cycling settled")
        }
        if let changed = lastNotifiedChange, attemptDueBy != nil {
            report.longestSelectionToAttempt = max(report.longestSelectionToAttempt, seconds(now - changed))
        } else if let resting = restingSince {
            report.refreshAttempts += 1
            report.longestRefreshGap = max(report.longestRefreshGap, seconds(now - resting))
        }
        attemptDueBy = nil
        refreshDueBy = nil
        restingSince = nil

        guard let current = session, let item = current.selectedItem, case .window(let number) = item.id,
              !item.isMinimized, !item.isAppHidden else {
            report.previewSkipped += 1
            unfinishedPreviewStarts.removeAll()
            perform(schedule.captureFinished(at: seconds(now), outcome: .skipped))
            return
        }
        // One capture at a time: an unfinished one must have reached the schedule's timeout.
        for start in unfinishedPreviewStarts where seconds(now - start) < LargePreviewCaptureSchedule.captureTimeout - 1e-6 {
            violate("a second large-preview capture started \(format(seconds(now - start))) s after the first")
        }
        unfinishedPreviewStarts = [now]
        previewSerial += 1
        previewStartedAt = [previewSerial: now]
        let request = SoakCaptureRequest(
            kind: .largePreview(serial: previewSerial),
            token: token,
            pixelSize: max(largePreviewPixelSize, SoakAppLimits.thumbnailLongEdge)
        )
        capture([number], request: request, priority: true)
    }

    private func largePreviewFinished(_ request: SoakCaptureRequest, serial: Int) {
        guard request.token == token else {
            report.closedSessionResultsDropped += 1
            return
        }
        if !request.failed.isEmpty { previewCaptureFailed(request.failed) }
        guard serial == previewSerial else {
            report.supersededCompletions += 1
            return
        }
        if let started = previewStartedAt[serial] {
            report.longestPreviewCompletion = max(report.longestPreviewCompletion, seconds(now - started))
        }
        unfinishedPreviewStarts.removeAll()
        let outcome: LargePreviewCaptureSchedule.Outcome = request.failed.isEmpty ? .captured : .failed
        if outcome == .captured { report.previewCaptured += 1 } else { report.previewFailed += 1 }
        // A preview left open must not freeze: the resting selection is tried again.
        // (A selection change still waiting for its attempt has the stricter deadline; with
        // nothing selected there is nothing to refresh, and the next selection is attempted
        // as a change.)
        if attemptDueBy == nil, session?.selectedItem != nil {
            refreshDueBy = now + micros(PreviewFreshness.maxRefreshInterval + 0.005)
            restingSince = now
        }
        perform(schedule.captureFinished(at: seconds(now), outcome: outcome))
    }

    private func noteSelectionNotified() {
        report.selectionNotifications += 1
        if let last = lastNotifiedChange, seconds(now) - seconds(last) >= 0,
           seconds(now) - seconds(last) < LargePreviewCaptureSchedule.cyclingInterval {
            report.cyclingNotifications += 1
            settleUntil = now + micros(LargePreviewCaptureSchedule.settleDelay)
        } else {
            settleUntil = nil
        }
        lastNotifiedChange = now
        // The final selection is attempted once it settles, or once a running capture
        // reaches the schedule's timeout, whichever is later.
        let bound = LargePreviewCaptureSchedule.settleDelay + LargePreviewCaptureSchedule.captureTimeout + 0.005
        attemptDueBy = now + micros(bound)
        refreshDueBy = nil
        restingSince = nil
    }

    private func checkDeadlines() {
        // A watchdog must expire running calls even after their session closes. Check
        // independently of the limiter's expire result, allowing its 10 ms timer floor.
        for ticket in inFlight.keys.sorted() {
            if let started = callStartedAt[ticket],
               now - started > micros(SoakAppLimits.captureTimeout + 0.015) {
                violate("running screenshot exceeded watchdog deadline")
            }
        }
        guard session != nil else { return }
        if let due = attemptDueBy, now > due {
            violate("selection not attempted within \(format(seconds(due - (lastNotifiedChange ?? due)))) s of changing")
            attemptDueBy = nil
        }
        if let due = refreshDueBy, now > due {
            violate("resting preview not refreshed within \(format(PreviewFreshness.maxRefreshInterval)) s")
            refreshDueBy = nil
        }
    }

    // MARK: Thumbnails (the coordinator's request)

    private func requestThumbnails() {
        guard let current = session else { return }
        lastThumbnailRequestIDs = current.visible.map(\.id)
        var ids: [UInt32] = []
        for ranked in current.visible {
            guard case .window(let number) = ranked.id, !ranked.item.isMinimized, !ranked.item.isAppHidden else { continue }
            ids.append(number)
        }
        let request = SoakCaptureRequest(kind: .thumbnails, token: token, pixelSize: SoakAppLimits.thumbnailLongEdge)
        capture(ids, request: request, priority: false)
    }

    // MARK: Thumbnail service model

    private func capture(_ windowIDs: [UInt32], request: SoakCaptureRequest, priority: Bool) {
        guard !windowIDs.isEmpty else {
            complete(request)
            return
        }
        let requestGeneration = generation
        let wanted = Set(windowIDs)
        withWindowList(covering: wanted) { [self] owners in
            guard generation == requestGeneration else { return }
            var listed: [UInt32] = []
            var seen: Set<UInt32> = []
            for id in windowIDs where owners?[id] != nil && seen.insert(id).inserted { listed.append(id) }
            request.failed = wanted.subtracting(listed)
            guard !listed.isEmpty, let owners else {
                complete(request)
                return
            }
            request.remaining = listed.count
            let newJobs = listed.map { SoakJob(windowID: $0, owner: owners[$0] ?? 0, generation: requestGeneration, request: request) }
            if priority {
                if jobHead >= newJobs.count {
                    jobHead -= newJobs.count
                    jobs.replaceSubrange(jobHead..<(jobHead + newJobs.count), with: newJobs)
                } else {
                    jobs.insert(contentsOf: newJobs, at: jobHead)
                }
            } else {
                jobs.append(contentsOf: newJobs)
            }
            report.maxQueuedCaptures = max(report.maxQueuedCaptures, jobs.count - jobHead)
            pump()
        }
    }

    private func pump() {
        defer {
            scheduleWatchdog()
            if jobHead > 4_096, jobHead * 2 > jobs.count {
                jobs.removeFirst(jobHead)
                jobHead = 0
            }
        }
        while jobHead < jobs.count {
            if captureLimiter.isSaturated {
                // Screenshots stopped answering: fail what waits instead of leaving it queued.
                let waiting = jobs[jobHead...]
                jobs.removeAll()
                jobHead = 0
                for job in waiting where job.generation == generation {
                    report.failedWithoutStarting += 1
                    fail(job)
                }
                return
            }
            guard captureLimiter.canStart else { return }
            let job = jobs[jobHead]
            jobHead += 1
            guard job.generation == generation else { continue }
            guard let ticket = captureLimiter.start(at: seconds(now)) else {
                report.failedWithoutStarting += 1
                fail(job)
                continue
            }
            inFlight[ticket] = job
            callStartedAt[ticket] = now
            startNativeCapture(ticket: ticket)
        }
    }

    private func startNativeCapture(ticket: Int) {
        report.nativeCallsStarted += 1
        outstandingCaptures += 1
        startsSinceAnswer += 1
        report.maxOutstandingNativeCalls = max(report.maxOutstandingNativeCalls, outstandingCaptures)
        report.maxRunningNativeCalls = max(report.maxRunningNativeCalls, inFlight.count)
        report.maxStartsWithoutAnswer = max(report.maxStartsWithoutAnswer, startsSinceAnswer)
        if outstandingCaptures > SoakAppLimits.maxOutstandingCaptures {
            violate("\(outstandingCaptures) screenshot calls outstanding (limit \(SoakAppLimits.maxOutstandingCaptures))")
        }
        if startsSinceAnswer > SoakAppLimits.maxOutstandingCaptures {
            violate("\(startsSinceAnswer) screenshot calls started without any answer")
        }
        if inFlight.count > SoakAppLimits.maxRunningCaptures {
            violate("\(inFlight.count) screenshot calls running at once")
        }
        let (latency, succeeds) = nativeLatency()
        queue.push(.nativeAnswer(ticket: ticket, succeeds: succeeds), at: now + latency)
        trace(30, UInt64(ticket))
    }

    private func nativeAnswered(ticket: Int, succeeds: Bool) {
        outstandingCaptures -= 1
        startsSinceAnswer = 0
        let finish = captureLimiter.finish(ticket)
        let job = inFlight.removeValue(forKey: ticket)
        let startedAt = callStartedAt.removeValue(forKey: ticket) ?? now
        defer { pump() }
        switch finish {
        case .late:
            // Its caller was already told it failed.
            report.answeredLate += 1
            return
        case .unknown:
            violate("a screenshot answer was unknown to the limiter")
            return
        case .onTime:
            report.answeredOnTime += 1
        }
        guard let job else {
            violate("an on-time answer had no running capture")
            return
        }
        guard job.generation == generation else {
            report.closedSessionResultsDropped += 1
            return
        }
        guard succeeds, let current = world.first(where: { $0.id == .window(job.windowID) }), current.pid == job.owner else {
            fail(job)
            return
        }
        deliver(job, capturedAt: startedAt)
        finishOne(job, captured: true)
    }

    private func expireOverdueCaptures() {
        let overdue = captureLimiter.expire(at: seconds(now))
        report.timedOut += overdue.count
        for ticket in overdue {
            guard let job = inFlight.removeValue(forKey: ticket), job.generation == generation else { continue }
            fail(job)
        }
        pump()
    }

    private func scheduleWatchdog() {
        guard !watchdogScheduled, let deadline = captureLimiter.nextDeadline else { return }
        watchdogScheduled = true
        queue.push(.watchdog, at: max(now + 10_000, micros(deadline)))
    }

    private func fail(_ job: SoakJob) {
        finishOne(job, captured: false)
    }

    private func finishOne(_ job: SoakJob, captured: Bool) {
        let request = job.request
        if !captured { request.failed.insert(job.windowID) }
        request.remaining -= 1
        if request.remaining == 0 { complete(request) }
    }

    private func complete(_ request: SoakCaptureRequest) {
        switch request.kind {
        case .thumbnails:
            guard request.token == token else {
                report.closedSessionResultsDropped += 1
                return
            }
            if !request.failed.isEmpty { previewCaptureFailed(request.failed) }
        case .largePreview(let serial):
            largePreviewFinished(request, serial: serial)
        }
    }

    private func deliver(_ job: SoakJob, capturedAt: Int64) {
        switch job.request.kind {
        case .thumbnails:
            report.thumbnailsDelivered += 1
        case .largePreview:
            guard job.request.token == token else {
                report.closedSessionResultsDropped += 1
                return
            }
            // The panel ignores an image from a previous owner of the window number.
            if let item = session?.items.first(where: { $0.id == .window(job.windowID) }), item.pid != job.owner { return }
            let longEdge = job.request.pixelSize
            let pixels = random.chance(0.03) ? 7_000 * 5_000 : longEdge * Int(Double(longEdge) * (0.4 + 0.6 * Double(random.int(0...100)) / 100))
            store(SoakStoredImage(capturedAt: capturedAt, pixels: pixels, owner: job.owner), for: .window(job.windowID))
        }
    }

    private func withWindowList(covering ids: Set<UInt32>, _ body: @escaping ([UInt32: Int32]?) -> Void) {
        if let list = windowList, seconds(now - list.at) < SoakAppLimits.windowListLifetime,
           ids.allSatisfy({ list.owners[$0] != nil }) {
            body(list.owners)
            return
        }
        windowListWaiters.append(body)
        guard windowListTicket == nil else { return }
        guard let ticket = windowListLimiter.start(at: seconds(now)) else {
            // An earlier fetch never answered: fail now rather than pile up more.
            report.windowListRefusals += 1
            finishWindowListWaiters(nil)
            return
        }
        report.windowListFetches += 1
        outstandingWindowLists += 1
        windowListStartsSinceAnswer += 1
        report.maxOutstandingWindowLists = max(report.maxOutstandingWindowLists, outstandingWindowLists)
        if outstandingWindowLists > 1 || windowListStartsSinceAnswer > 1 {
            violate("\(outstandingWindowLists) window-list fetches outstanding")
        }
        windowListTicket = ticket
        let (latency, succeeds) = windowListLatency()
        queue.push(.windowListAnswer(ticket: ticket, succeeds: succeeds), at: now + latency)
        queue.push(.windowListTimeout(ticket: ticket), at: now + micros(SoakAppLimits.windowListTimeout))
    }

    private func windowListAnswered(ticket: Int, succeeds: Bool) {
        outstandingWindowLists -= 1
        windowListStartsSinceAnswer = 0
        let finish = windowListLimiter.finish(ticket)
        guard finish == .onTime, windowListTicket == ticket else {
            report.windowListLateAnswers += 1
            return
        }
        var owners: [UInt32: Int32]?
        if succeeds {
            var listed: [UInt32: Int32] = [:]
            for item in world {
                if case .window(let number) = item.id { listed[number] = item.pid }
            }
            owners = listed
            windowList = (listed, now)
        }
        windowListTicket = nil
        finishWindowListWaiters(owners)
    }

    private func finishWindowListWaiters(_ owners: [UInt32: Int32]?) {
        let waiters = windowListWaiters
        windowListWaiters.removeAll()
        for waiter in waiters { waiter(owners) }
    }

    private func cancelPendingCaptures() {
        generation += 1
        jobs.removeAll()
        jobHead = 0
        windowListWaiters.removeAll()
    }

    private func nativeLatency() -> (Int64, Bool) {
        let roll = random.int(0...99)
        switch scenario {
        case .lateCompletions:
            let latency: Int64 = roll < 25 ? random.micros(5_000...90_000)
                : roll < 55 ? random.micros(300_000...2_900_000) : random.micros(3_050_000...12_000_000)
            return (latency, random.chance(0.85))
        case .hungCaptures:
            let latency: Int64 = roll < 15 ? random.micros(5_000...90_000) : random.micros(3_500_000...20_000_000)
            return (latency, random.chance(0.5))
        default:
            let latency: Int64 = roll < 80 ? random.micros(5_000...90_000)
                : roll < 93 ? random.micros(90_000...900_000)
                : roll < 98 ? random.micros(900_000...2_900_000) : random.micros(3_050_000...9_000_000)
            return (latency, random.chance(scenario == .restingRefresh ? 0.6 : 0.96))
        }
    }

    private func windowListLatency() -> (Int64, Bool) {
        let slow: Double
        switch scenario {
        case .hungCaptures: slow = 0.4
        case .lateCompletions: slow = 0.1
        default: slow = 0.02
        }
        let latency = random.chance(slow) ? random.micros(3_200_000...15_000_000) : random.micros(3_000...60_000)
        return (latency, random.chance(0.98))
    }

    // MARK: Preview store model

    private func updatePanel(itemsChanged: Bool) {
        guard let current = session else { return }
        if itemsChanged {
            let ids = Set(current.items.map(\.id))
            for id in retention.prune(keeping: ids) where images.removeValue(forKey: id) != nil {
                report.imagesPruned += 1
            }
            // A window number that now belongs to another app takes its images with it.
            var owners: [ItemID: Int32] = [:]
            for item in current.items { owners[item.id] = item.pid }
            for id in sortedImageIDs() {
                guard let image = images[id], let owner = owners[id], owner != image.owner else { continue }
                removeImage(id)
            }
        }
        let selected = current.selectedItem?.id
        if let selected, selected != selectedID { retention.touch(selected) }
        selectedID = selected
        checkRetention(newest: nil, protected: nil)
    }

    private func store(_ image: SoakStoredImage, for id: ItemID) {
        let existing = images[id].map { seconds($0.capturedAt) }
        guard PreviewFreshness.replaces(seconds(image.capturedAt), existing: existing) else {
            report.olderResultsRejected += 1
            return
        }
        images[id] = image
        report.imagesStored += 1
        for dropped in retention.insert(id, pixels: image.pixels, protecting: selectedID) where images.removeValue(forKey: dropped) != nil {
            report.imagesDroppedByRetention += 1
        }
        checkRetention(newest: id, protected: selectedID)
    }

    private func previewCaptureFailed(_ ids: Set<UInt32>) {
        for number in ids.sorted() {
            let id = ItemID.window(number)
            guard let image = images[id],
                  !PreviewFreshness.survivesFailedRefresh(capturedAt: seconds(image.capturedAt), now: seconds(now)) else { continue }
            removeImage(id)
        }
    }

    private func removeImage(_ id: ItemID) {
        guard images.removeValue(forKey: id) != nil else { return }
        retention.remove(id)
        report.imagesPruned += 1
    }

    /// `newest` and `protected`: the image just stored and the selection it protected.
    /// Those two may exceed the pixel budget together; nothing else may.
    private func checkRetention(newest: ItemID?, protected: ItemID?) {
        let count = images.count
        let pixels = images.values.reduce(0) { $0 + $1.pixels }
        report.maxRetainedImages = max(report.maxRetainedImages, count)
        report.maxRetainedPixels = max(report.maxRetainedPixels, pixels)
        if count > SoakAppLimits.retainedImages {
            violate("\(count) large-preview images retained (limit \(SoakAppLimits.retainedImages))")
        }
        if let newest, pixels > SoakAppLimits.retainedPixels,
           images.keys.contains(where: { $0 != newest && $0 != protected }) {
            violate("\(pixels) retained pixels with droppable images (budget \(SoakAppLimits.retainedPixels))")
        }
        trace(40, UInt64(count))
    }

    private func sortedImageIDs() -> [ItemID] {
        images.keys.sorted { Self.order($0) < Self.order($1) }
    }

    private static func order(_ id: ItemID) -> Int64 {
        switch id {
        case .window(let number): return Int64(number)
        case .app(let pid): return -1 - Int64(pid)
        }
    }

    // MARK: Session and filter checks

    private func checkSession(_ current: SwitcherSession) {
        let visibleIDs = current.visible.map(\.id)
        if Set(visibleIDs).count != visibleIDs.count { violate("a window is listed twice") }
        let itemIDs = Set(current.items.map(\.id))
        if visibleIDs.contains(where: { !itemIDs.contains($0) }) { violate("a listed window is not in the session") }
        if let index = current.selectedIndex {
            if !current.visible.indices.contains(index) { violate("selection \(index) outside \(current.visible.count) rows") }
        } else if !current.visible.isEmpty {
            violate("nothing selected in a non-empty list")
        }
        if current.query.trimmingCharacters(in: .whitespaces).isEmpty, visibleIDs != current.items.map(\.id) {
            violate("an empty query does not list every item in order")
        }
    }

    private func filteredWorld() -> [SwitcherItem] {
        let filtered = ItemFilter.apply(world, options: sessionOptions, scope: sessionScope, context: sessionContext)
        // Documented filter guarantees: order kept, own process and excluded apps never listed.
        var remaining = filtered[...]
        for item in world where remaining.first?.id == item.id { remaining = remaining.dropFirst() }
        if !remaining.isEmpty { violate("filtering reordered the windows") }
        if filtered.contains(where: { $0.pid == Self.ownPID }) { violate("the switcher's own window was listed") }
        let excluded = Set(sessionOptions.excludedBundleIDs.map { $0.lowercased() })
        if filtered.contains(where: { $0.bundleID.map { excluded.contains($0.lowercased()) } ?? false }) {
            violate("an excluded app was listed")
        }
        if !sessionOptions.showMinimized, filtered.contains(where: \.isMinimized) { violate("a minimized window was listed") }
        return filtered
    }

    private func randomOptions() -> FilterOptions {
        var options = FilterOptions(
            showMinimized: random.chance(0.8),
            showHiddenApps: random.chance(0.8),
            showWindowlessApps: random.chance(0.2),
            currentSpaceOnly: random.chance(0.3),
            currentDisplayOnly: random.chance(0.15),
            showOtherSpaces: random.chance(0.3)
        )
        if random.chance(0.2), !apps.isEmpty {
            options.excludedBundleIDs = [random.pick(apps).bundleID.uppercased()]
        }
        return options
    }

    // MARK: World

    private func evolveWorld() {
        if world.isEmpty || random.chance(0.25) {
            regenerateWorld()
        } else {
            churnWorld(maxChanges: 6)
        }
        report.largestCatalog = max(report.largestCatalog, world.count)
    }

    private func regenerateWorld() {
        for item in world {
            if case .window(let number) = item.id { freedWindowNumbers.append(number) }
        }
        world.removeAll()
        apps.removeAll()
        let roll = random.int(0...99)
        let upper = roll < 60 ? min(20, workload.maxWindows) : roll < 90 ? min(80, workload.maxWindows) : workload.maxWindows
        let windowCount = random.int(min(2, upper)...upper)
        for _ in 0..<random.int(1...min(Self.appNames.count, max(1, windowCount))) { launchApp() }
        for _ in 0..<windowCount { openWindow() }
        // A few running apps without windows.
        for app in apps where random.chance(0.1) && !world.contains(where: { $0.pid == app.pid }) {
            world.append(SwitcherItem(id: .app(pid: app.pid), pid: app.pid, appName: app.name, bundleID: app.bundleID))
        }
        if random.chance(0.1) {
            world.insert(makeWindow(pid: Self.ownPID, name: "Switcher Self", bundleID: "org.example.self"), at: 0)
        }
    }

    private func churnWorld(maxChanges: Int) {
        for _ in 0..<random.int(0...maxChanges) {
            switch random.int(0...5) {
            case 0, 1:
                if !world.isEmpty {
                    let index = random.int(0...(world.count - 1))
                    let item = world[index]
                    removeFromWorld { $0.id == item.id }
                }
            case 2, 3:
                if world.count < workload.maxWindows { openWindow() }
            case 4:
                if !world.isEmpty { world[random.int(0...(world.count - 1))].isMinimized.toggle() }
            default:
                if !world.isEmpty {
                    let pid = world[random.int(0...(world.count - 1))].pid
                    let hidden = random.chance(0.5)
                    for index in world.indices where world[index].pid == pid { world[index].isAppHidden = hidden }
                }
            }
        }
        report.largestCatalog = max(report.largestCatalog, world.count)
    }

    @discardableResult
    private func launchApp() -> SoakApp {
        let name = random.pick(Self.appNames)
        let app = SoakApp(
            pid: nextPID,
            name: name,
            bundleID: "org.example." + name.lowercased().replacingOccurrences(of: " ", with: "")
        )
        nextPID += 1
        apps.append(app)
        return app
    }

    private func openWindow() {
        let app = apps.isEmpty || random.chance(0.05) ? launchApp() : random.pick(apps)
        // A new window opens in front.
        world.insert(makeWindow(pid: app.pid, name: app.name, bundleID: app.bundleID), at: random.chance(0.7) ? 0 : world.count)
    }

    private func makeWindow(pid: Int32, name: String, bundleID: String) -> SwitcherItem {
        let number: UInt32
        // The window server reuses numbers; the next owner is usually another app.
        if !freedWindowNumbers.isEmpty, random.chance(0.3) {
            number = freedWindowNumbers.remove(at: random.int(0...(freedWindowNumbers.count - 1)))
        } else {
            number = nextWindowNumber
            nextWindowNumber += 1
        }
        report.windowsGenerated += 1
        return SwitcherItem(
            id: .window(number),
            pid: pid,
            appName: name,
            bundleID: bundleID,
            title: "\(random.pick(Self.titleWords)) \(random.int(1...99))",
            isMinimized: random.chance(0.1),
            isFullscreen: random.chance(0.05),
            isOnActiveSpace: random.chance(0.85),
            displayID: UInt32(random.int(1...3))
        )
    }

    private func removeFromWorld(where shouldRemove: (SwitcherItem) -> Bool) {
        for item in world where shouldRemove(item) {
            if case .window(let number) = item.id { freedWindowNumbers.append(number) }
        }
        world.removeAll(where: shouldRemove)
    }

    // MARK: Finishing

    private func finishRun() {
        report.virtualSeconds = seconds(now)
        report.retainedImagesAtEnd = images.count
        // Every simulated call answers eventually, so nothing may remain counted.
        if outstandingCaptures != 0 { violate("\(outstandingCaptures) screenshot calls never answered") }
        if !inFlight.isEmpty { violate("\(inFlight.count) captures still marked running") }
        if captureLimiter.isSaturated || !captureLimiter.canStart {
            violate("the screenshot limit stayed blocked after every call answered")
        }
        if windowListLimiter.isSaturated || !windowListLimiter.canStart {
            violate("the window-list limit stayed blocked after every fetch answered")
        }
        if session != nil { violate("a session was left open") }
        if report.retainedImagesAtEnd > SoakAppLimits.retainedImages {
            violate("\(report.retainedImagesAtEnd) images retained after the run")
        }
        trace(99, UInt64(report.sessionsCompleted))
        report.digest = digest
    }

    // MARK: Helpers

    private func violate(_ message: String) {
        report.violationCount += 1
        guard report.violations.count < 20 else { return }
        report.violations.append("session \(report.sessionsCompleted + 1) [\(scenario.rawValue)] t=\(format(seconds(now))) s: \(message)")
    }

    private func trace(_ kind: UInt64, _ value: UInt64) {
        for word in [kind, value] {
            for shift in stride(from: 0, to: 64, by: 8) {
                digest ^= (word >> UInt64(shift)) & 0xFF
                digest = digest &* 0x0000_0100_0000_01B3
            }
        }
    }

    private func seconds(_ micros: Int64) -> TimeInterval {
        Double(micros) / 1_000_000
    }

    private func micros(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1_000_000).rounded(.up))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
