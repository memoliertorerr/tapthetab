// Opt-in local soak of the switching and preview-capture policies (`make soak`).
//
// Runs `SoakSimulation` with fictional windows on a virtual clock and reports what it
// exercised, whether every checked contract held, and what this process measured while
// doing it. It opens no windows, asks for no permissions, reads no settings and uses no
// network. The measurements describe this simulation process only, not the app's
// AppKit, Accessibility or ScreenCaptureKit work.

import Dispatch
import Foundation
import TapTheTabSoakSupport
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let usage = """
Usage: TapTheTabSoak [--iterations N] [--seed S] [--windows N] [--steps N]

  --iterations N  switcher sessions to simulate (\(SoakWorkload.sessionRange.lowerBound)–\(SoakWorkload.sessionRange.upperBound), default 400)
  --seed S        workload seed, decimal or 0x-hex (default 0x\(String(SoakWorkload.defaultSeed, radix: 16)))
  --windows N     largest synthetic window catalog (\(SoakWorkload.windowRange.lowerBound)–\(SoakWorkload.windowRange.upperBound), default 120)
  --steps N       most inputs in one session (\(SoakWorkload.stepRange.lowerBound)–\(SoakWorkload.stepRange.upperBound), default 120)
  --help          show this help

iterations × steps may be at most \(SoakWorkload.maxTotalSteps). Ctrl-C stops after the
current session and reports what ran. Exit status: 0 all checks held, 1 a check failed,
130 stopped early, 64 bad arguments.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\n\(usage)\n".utf8))
    exit(64)
}

/// Plain ASCII digits only: no sign, spaces, separators or other scripts' numerals.
func isDigits(_ text: Substring, hex: Bool = false) -> Bool {
    !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
        ("0"..."9").contains(scalar) || (hex && (("a"..."f").contains(scalar) || ("A"..."F").contains(scalar)))
    }
}

func parseInteger(_ text: String, flag: String, range: ClosedRange<Int>) -> Int {
    guard isDigits(text[...]), let value = Int(text), range.contains(value) else {
        fail("\(flag) must be a whole number from \(range.lowerBound) to \(range.upperBound), not '\(text)'")
    }
    return value
}

func parseSeed(_ text: String) -> UInt64 {
    let hex = text.hasPrefix("0x") || text.hasPrefix("0X")
    let digits = hex ? text.dropFirst(2) : text[...]
    let value = isDigits(digits, hex: hex) ? UInt64(digits, radix: hex ? 16 : 10) : nil
    guard let value else {
        fail("--seed must be a 64-bit unsigned number (decimal or 0x-hex), not '\(text)'")
    }
    return value
}

func parseArguments(_ arguments: [String]) -> SoakWorkload {
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let flag = arguments[index]
        if flag == "--help" || flag == "-h" {
            print(usage)
            exit(0)
        }
        guard ["--iterations", "--seed", "--windows", "--steps"].contains(flag) else {
            fail("unknown argument '\(flag)'")
        }
        guard values[flag] == nil else { fail("\(flag) given twice") }
        guard index + 1 < arguments.count else { fail("\(flag) needs a value") }
        values[flag] = arguments[index + 1]
        index += 2
    }
    let defaults = SoakWorkload()
    let sessions = values["--iterations"].map { parseInteger($0, flag: "--iterations", range: SoakWorkload.sessionRange) } ?? defaults.sessions
    let windows = values["--windows"].map { parseInteger($0, flag: "--windows", range: SoakWorkload.windowRange) } ?? defaults.maxWindows
    let steps = values["--steps"].map { parseInteger($0, flag: "--steps", range: SoakWorkload.stepRange) } ?? defaults.maxSteps
    let seed = values["--seed"].map(parseSeed) ?? defaults.seed
    guard sessions.multipliedReportingOverflow(by: steps).partialValue <= SoakWorkload.maxTotalSteps else {
        fail("iterations × steps (\(sessions) × \(steps)) exceeds \(SoakWorkload.maxTotalSteps)")
    }
    return SoakWorkload(seed: seed, sessions: sessions, maxWindows: windows, maxSteps: steps)
}

/// Set from a signal handler queue, read between sessions.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

// MARK: Local process measurements

struct ProcessSample {
    let userSeconds: Double
    let systemSeconds: Double
    /// Peak resident set size of this process so far, in bytes.
    let peakResidentBytes: UInt64?
    /// Current physical footprint (macOS task_info), in bytes; nil where unavailable.
    let footprintBytes: UInt64?
}

func sampleProcess() -> ProcessSample {
    var usage = rusage()
    #if os(Linux)
    // RUSAGE_SELF is 0; glibc declares its type differently depending on feature macros.
    let ok = getrusage(.init(0), &usage) == 0
    #else
    let ok = getrusage(RUSAGE_SELF, &usage) == 0
    #endif
    let user = ok ? Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000 : 0
    let system = ok ? Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000 : 0
    var peak: UInt64?
    if ok, usage.ru_maxrss > 0 {
        #if os(macOS)
        peak = UInt64(usage.ru_maxrss) // bytes on macOS
        #else
        peak = UInt64(usage.ru_maxrss) * 1_024 // kilobytes on Linux
        #endif
    }
    return ProcessSample(userSeconds: user, systemSeconds: system, peakResidentBytes: peak, footprintBytes: physicalFootprint())
}

func physicalFootprint() -> UInt64? {
    #if os(macOS)
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
    #else
    return nil
    #endif
}

func megabytes(_ bytes: UInt64?) -> String {
    guard let bytes else { return "not measured on this platform" }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576)
}

func milliseconds(_ seconds: Double) -> String {
    String(format: "%.0f ms", seconds * 1_000)
}

// MARK: Run

let workload = parseArguments(Array(CommandLine.arguments.dropFirst()))
let stopFlag = StopFlag()
var signalSources: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler { stopFlag.stop() }
    source.resume()
    signalSources.append(source)
}

print("TapTheTab synthetic soak: fictional windows, virtual clock, no real windows or permissions.")
print("seed 0x\(String(workload.seed, radix: 16)) (\(workload.seed)), \(workload.sessions) sessions, up to \(workload.maxWindows) windows and \(workload.maxSteps) inputs per session")

let before = sampleProcess()
let started = DispatchTime.now().uptimeNanoseconds
let report = SoakSimulation.run(workload) { !stopFlag.isStopped }
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
let after = sampleProcess()

func line(_ label: String, _ value: CustomStringConvertible) {
    print("  " + label.padding(toLength: 38, withPad: " ", startingAt: 0) + "\(value)")
}

print("")
print("Workload")
line("sessions completed", "\(report.sessionsCompleted) of \(report.sessionsRequested)\(report.cancelled ? " (stopped early)" : "")")
for scenario in SoakScenario.allCases {
    line("  \(scenario.rawValue)", report.sessionsByScenario[scenario] ?? 0)
}
line("inputs", report.inputs)
line("window actions", report.windowActions)
line("catalog replacements", report.catalogReplacements)
line("windows generated", report.windowsGenerated)
line("largest catalog / session list", "\(report.largestCatalog) / \(report.largestSessionList)")
line("closed before the panel showed", report.sessionsClosedBeforeShowing)
line("simulated events", report.eventsProcessed)
line("virtual time", String(format: "%.1f s", report.virtualSeconds))

print("Large-preview schedule")
line("selection changes reported", "\(report.selectionNotifications) (\(report.cyclingNotifications) while cycling, \(report.deferredSelections) deferred)")
line("capture attempts", "\(report.previewAttempts) (\(report.refreshAttempts) refreshes, \(report.previewSkipped) nothing to capture)")
line("captured / failed", "\(report.previewCaptured) / \(report.previewFailed)")
line("superseded completions ignored", report.supersededCompletions)
line("longest change → attempt", milliseconds(report.longestSelectionToAttempt))
line("longest completion → refresh", milliseconds(report.longestRefreshGap))
line("longest capture → completion", milliseconds(report.longestPreviewCompletion))

print("Simulated native work")
line("screenshot calls started", report.nativeCallsStarted)
line("answered on time / late", "\(report.answeredOnTime) / \(report.answeredLate)")
line("timed out", report.timedOut)
line("failed without a call (saturated)", report.failedWithoutStarting)
line("max outstanding / running", "\(report.maxOutstandingNativeCalls) / \(report.maxRunningNativeCalls)")
line("max started without an answer", report.maxStartsWithoutAnswer)
line("max queued captures", report.maxQueuedCaptures)
line("thumbnails delivered", report.thumbnailsDelivered)
line("window lists fetched / timed out", "\(report.windowListFetches) / \(report.windowListTimeouts)")
line("window lists refused / late", "\(report.windowListRefusals) / \(report.windowListLateAnswers)")
line("results after their session closed", report.closedSessionResultsDropped)

print("Retained large-preview images")
line("stored / older results rejected", "\(report.imagesStored) / \(report.olderResultsRejected)")
line("dropped by retention / pruned", "\(report.imagesDroppedByRetention) / \(report.imagesPruned)")
line("max retained images", report.maxRetainedImages)
line("max retained pixels", report.maxRetainedPixels)
line("retained at the end", report.retainedImagesAtEnd)

print("This process (local evidence only; not the app's AppKit/AX/ScreenCaptureKit cost)")
line("wall-clock time", String(format: "%.3f s", elapsed))
line("CPU user / system", String(format: "%.3f s / %.3f s", after.userSeconds - before.userSeconds, after.systemSeconds - before.systemSeconds))
if elapsed > 0 {
    line("simulated events per second", Int(Double(report.eventsProcessed) / elapsed))
}
line("peak resident set (whole process)", megabytes(after.peakResidentBytes))
line("physical footprint before / after", "\(megabytes(before.footprintBytes)) / \(megabytes(after.footprintBytes))")

print("")
print("digest 0x\(String(report.digest, radix: 16)) (\(report.cancelled ? "partial run; digest depends on stopping point" : "equal seeds and options give equal digests"))")
if report.passed {
    print(report.cancelled ? "PASS: every checked contract held in this partial run" : "PASS: every checked contract held")
} else {
    print("FAIL: \(report.violationCount) violation(s)")
    for violation in report.violations { print("  - \(violation)") }
}
exit(report.passed ? (report.cancelled ? 130 : 0) : 1)
