import Foundation
// MARK: - AirPods Detection Utility

extension Notification.Name {
    static let AirPodsStateChanged = Notification.Name("AirPodsStateChanged")
}

enum AirPodSide: String {
    case both
    case left
    case right
    case none
}

final class AirPodsDetector {
    static let shared = AirPodsDetector()
    
    private init() {
        startPolling()
    }
    
    private var pollingTimer: Timer?
    
    private func startPolling() {
        // Keep this conservative: AirPods side detection is only a UI/headset hint,
        // so it should not add noticeable startup or steady-state overhead.
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollIfNeeded()
        }
        // Ensure it runs even if UI is busy
        RunLoop.main.add(pollingTimer!, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pollIfNeeded(forceFast: true)
        }
    }
    
    private var lastState: AirPodSide = .none
    private var pendingTarget: AirPodSide?
    private var pendingSince: Date = .distantPast
    private let startupAt: Date = Date()
    private var startupSawBothHint = false
    private var recentRegistrySamples: [(time: Date, side: AirPodSide)] = []
    private var recentPlcmSamples: [(time: Date, side: AirPodSide)] = []
    private var lastPlcmLine: String = ""
    private var lastPlcmPollAt: Date = .distantPast
    private let evidenceWindowShort: TimeInterval = 2.0
    private let evidenceWindowLong: TimeInterval = 2.0
    private let registryUnionWindow: TimeInterval = 0.85
    private let plcmPollInterval: TimeInterval = 8.0
    private let startupGuardWindow: TimeInterval = 4.0
    private let startupSlowRefreshDelay: TimeInterval = 8.0
    private let startupPlcmRefreshDelay: TimeInterval = 2.0
    private let upToBothDelay: TimeInterval = 0.3
    private let bothToSingleDelay: TimeInterval = 0.6
    private let singleToNoneDelay: TimeInterval = 1.2
    private let sideSwitchDelay: TimeInterval = 0.15
    private let singleOverrideWindow: TimeInterval = 1.0
    private let singleSideLockWindow: TimeInterval = 0.7
    private let fastBothBlockWindow: TimeInterval = 1.0
    private var singleOverrideUntil: Date = .distantPast
    private var singleOverrideSide: AirPodSide = .none
    private var singleSideLockUntil: Date = .distantPast
    private var f1FastBlockedUntil: Date = .distantPast
    private let verboseDecisionLogs = false
    
    // Logger (Reverted to NSLog for stability)
    private func logDebug(_ message: String) {
        let lower = message.lowercased()
        let isTransition = message.hasPrefix("State Transition(")
        let isError = lower.contains("failed") || lower.contains("error")
        if !verboseDecisionLogs && !isTransition && !isError {
            return
        }
        let logStr = "\(Date()): \(message)\n"
        NSLog("[AirPodsDetector] %@", message)
        if let data = logStr.data(using: .utf8) {
            let tracePath = "/tmp/aether_decision_trace.txt"
            if !FileManager.default.fileExists(atPath: tracePath) {
                FileManager.default.createFile(atPath: tracePath, contents: nil)
            }
            if let fileHandle = FileHandle(forWritingAtPath: tracePath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            }
        }
    }
    
    // V9.0: Registry Presence Check
    // "Active/In-Ear" AirPods appear in IORegistry. "Idle/On-Desk" ones do not.
    private static func checkRegistryPresence(leftSerial: String?, rightSerial: String?) -> AirPodSide? {
        guard leftSerial != nil || rightSerial != nil else { return nil }
        
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-k", "SerialNumber", "-l"] // Only list entries with SerialNumbers
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let normalizedOutput = output.lowercased()
            
            let isLeftPresent: Bool = {
                if let l = leftSerial?.lowercased(), normalizedOutput.contains(l) { return true }
                return false
            }()
            
            let isRightPresent: Bool = {
                if let r = rightSerial?.lowercased(), normalizedOutput.contains(r) { return true }
                return false
            }()
            
            // Definitive logic from explicit serial matches.
            if isLeftPresent && isRightPresent { return .both }
            if isLeftPresent { return .left }
            if isRightPresent { return .right }
            
            // Serial exists but neither side is present in IORegistry.
            return AirPodSide.none
            
        } catch {
            return nil
        }
    }

    private var isRefreshingFast = false
    private var isRefreshingSlow = false
    private let fastInterval: TimeInterval = 1.0
    private let slowInterval: TimeInterval = 120.0
    private var lastFastTime: Date = .distantPast
    private var lastSlowTime: Date = .distantPast
    
    // Cache
    private var cachedLeftSerial: String?
    private var cachedRightSerial: String?

    private static func normalizedSerial(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func pruneRegistrySamples(now: Date) {
        recentRegistrySamples.removeAll { now.timeIntervalSince($0.time) > evidenceWindowLong }
        recentPlcmSamples.removeAll { now.timeIntervalSince($0.time) > evidenceWindowLong }
    }

    private func recordRegistrySample(_ side: AirPodSide, now: Date) {
        guard side == .left || side == .right || side == .both || side == .none else { return }
        recentRegistrySamples.append((time: now, side: side))
        pruneRegistrySamples(now: now)
    }

    private func recordPlcmSample(_ side: AirPodSide, now: Date) {
        guard side == .left || side == .right || side == .both else { return }
        recentPlcmSamples.append((time: now, side: side))
        pruneRegistrySamples(now: now)
    }

    private func count(_ samples: [(time: Date, side: AirPodSide)], within window: TimeInterval, side: AirPodSide, now: Date) -> Int {
        samples.reduce(0) { partial, sample in
            guard now.timeIntervalSince(sample.time) <= window else { return partial }
            return sample.side == side ? partial + 1 : partial
        }
    }

    private func has(_ samples: [(time: Date, side: AirPodSide)], within window: TimeInterval, side: AirPodSide, now: Date) -> Bool {
        samples.contains { now.timeIntervalSince($0.time) <= window && $0.side == side }
    }

    private func strongestSingleSide(now: Date) -> AirPodSide? {
        let leftScore =
            count(recentRegistrySamples, within: evidenceWindowShort, side: .left, now: now) +
            count(recentPlcmSamples, within: evidenceWindowShort, side: .left, now: now) * 2
        let rightScore =
            count(recentRegistrySamples, within: evidenceWindowShort, side: .right, now: now) +
            count(recentPlcmSamples, within: evidenceWindowShort, side: .right, now: now) * 2
        if leftScore == rightScore { return nil }
        return leftScore > rightScore ? .left : .right
    }

    private func deriveTargetState(now: Date) -> (state: AirPodSide, rule: String, bothEvidence: Bool) {
        pruneRegistrySamples(now: now)

        let regLeftShort = count(recentRegistrySamples, within: evidenceWindowShort, side: .left, now: now)
        let regRightShort = count(recentRegistrySamples, within: evidenceWindowShort, side: .right, now: now)
        let plcmLeftShort = count(recentPlcmSamples, within: evidenceWindowShort, side: .left, now: now)
        let plcmRightShort = count(recentPlcmSamples, within: evidenceWindowShort, side: .right, now: now)
        let hasRegLeftUnion = has(recentRegistrySamples, within: registryUnionWindow, side: .left, now: now)
        let hasRegRightUnion = has(recentRegistrySamples, within: registryUnionWindow, side: .right, now: now)
        let hasRegBothShort = has(recentRegistrySamples, within: evidenceWindowShort, side: .both, now: now)
        let regBothCountShort = count(recentRegistrySamples, within: evidenceWindowShort, side: .both, now: now)
        let plcmBothCountShort = count(recentPlcmSamples, within: evidenceWindowShort, side: .both, now: now)
        let plcmBothStrong = plcmBothCountShort >= 2
        let mixedBoth = plcmBothCountShort >= 1 && (hasRegBothShort || (hasRegLeftUnion && hasRegRightUnion))
        let registryBothStrong = regBothCountShort >= 2 || (regLeftShort >= 2 && regRightShort >= 2)
        let bothEvidence = plcmBothStrong || mixedBoth || registryBothStrong

        if now < singleOverrideUntil && (singleOverrideSide == .left || singleOverrideSide == .right) {
            let canBreakSingleOverride = plcmBothCountShort >= 2 || (plcmBothCountShort >= 1 && now >= f1FastBlockedUntil)
            if canBreakSingleOverride {
                singleOverrideUntil = .distantPast
                singleOverrideSide = .none
            } else {
                // R0 is allowed to keep same-side or move from none/both to single,
                // but side-to-side flips should come from explicit Plcm single evidence only.
                if (lastState == .left || lastState == .right) && singleOverrideSide != lastState {
                    return (lastState, "R0-side-flip-blocked", false)
                }
                return (singleOverrideSide, "R0-single-override", false)
            }
        }
        if bothEvidence {
            startupSawBothHint = true
            return (.both, "R1-both-evidence", true)
        }

        let leftSignal = regLeftShort >= 2 || plcmLeftShort >= 1
        let rightSignal = regRightShort >= 2 || plcmRightShort >= 1

        if leftSignal != rightSignal {
            let candidate: AirPodSide = leftSignal ? .left : .right
            if lastState == .both {
                let candidateStrength = candidate == .left
                    ? (regLeftShort + plcmLeftShort * 2)
                    : (regRightShort + plcmRightShort * 2)
                let oppositeStrength = candidate == .left
                    ? (regRightShort + plcmRightShort * 2)
                    : (regLeftShort + plcmLeftShort * 2)

                // When currently in BOTH, require stronger one-sided proof and no opposite-side freshness.
                if oppositeStrength > 0 {
                    return (.both, "R2c-hold-both-opposite-signal", false)
                }
                if candidateStrength < 4 {
                    return (.both, "R2d-hold-both-weak-single", false)
                }
            }
            return (candidate, "R2-single-evidence", false)
        }

        if let strong = strongestSingleSide(now: now), leftSignal || rightSignal {
            return (strong, "R2b-single-score", false)
        }

        let latestRegistryAt = recentRegistrySamples.last?.time ?? .distantPast
        let latestPlcmAt = recentPlcmSamples.last?.time ?? .distantPast
        let quietFor = min(now.timeIntervalSince(latestRegistryAt), now.timeIntervalSince(latestPlcmAt))
        if quietFor >= singleToNoneDelay {
            return (.none, "R3-quiet-none", false)
        }

        return (lastState, "R4-hold", false)
    }

    private enum PlcmSample {
        case both(line: String)
        case single(side: AirPodSide, line: String)
    }

    private static func fetchLatestPlcmSample() -> PlcmSample? {
        let task = Process()
        task.launchPath = "/usr/bin/log"
        task.arguments = [
            "show",
            "--last", "12s",
            "--style", "compact",
            "--predicate", "process == \"bluetoothd\" AND eventMessage CONTAINS \"Plcm\""
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return nil }
            let lines = output.components(separatedBy: .newlines)
            for line in lines.reversed() {
                let lower = line.lowercased()
                guard lower.contains("plcm") else { continue }
                if lower.contains("p inear") && lower.contains("s inear") {
                    return .both(line: line)
                }
                if lower.contains("p inear") || lower.contains("s inear") {
                    if lower.contains("prim left") {
                        return .single(side: .left, line: line)
                    }
                    if lower.contains("prim right") {
                        return .single(side: .right, line: line)
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func updateBothStateFromBluetoothLog() {
        let now = Date()
        if now.timeIntervalSince(startupAt) < startupPlcmRefreshDelay { return }
        if now.timeIntervalSince(lastPlcmPollAt) < plcmPollInterval { return }
        lastPlcmPollAt = now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let sample = Self.fetchLatestPlcmSample()
            DispatchQueue.main.async {
                guard let sample else { return }
                switch sample {
                case .both(let line):
                    guard line != self.lastPlcmLine else { return }
                    self.lastPlcmLine = line
                    let now = Date()
                    self.recordPlcmSample(.both, now: now)
                    self.observeState(.both, source: "bluetoothd-plcm", authoritative: true)
                case .single(let side, let line):
                    guard line != self.lastPlcmLine else { return }
                    self.lastPlcmLine = line
                    let now = Date()
                    self.recordPlcmSample(side, now: now)
                    self.singleOverrideSide = side
                    self.singleOverrideUntil = now.addingTimeInterval(self.singleOverrideWindow)
                    self.observeState(side, source: "bluetoothd-plcm-single", authoritative: true)
                }
            }
        }
    }
    
    private func pollIfNeeded(forceFast: Bool = false) {
        let now = Date()

        if !isRefreshingFast && (forceFast || now.timeIntervalSince(lastFastTime) > fastInterval) {
            refreshFast()
        }

        guard now.timeIntervalSince(startupAt) >= startupSlowRefreshDelay else { return }
        if !isRefreshingSlow && now.timeIntervalSince(lastSlowTime) > slowInterval {
            refreshSlow()
        }
    }

    // Non-blocking accessor. Also nudges a fresh poll so UI and auto-start logic
    // do not stay stuck on an old state longer than the fast polling interval.
    func currentSide() -> AirPodSide {
        DispatchQueue.main.async { [weak self] in
            self?.pollIfNeeded(forceFast: false)
        }
        return lastState
    }
    
    private func refreshFast() {
        guard !isRefreshingFast else { return }
        isRefreshingFast = true
        
        // Use cached serials for the fast check
        let lSer = cachedLeftSerial
        let rSer = cachedRightSerial
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let registrySide = Self.checkRegistryPresence(leftSerial: lSer, rightSerial: rSer)

            DispatchQueue.main.async {
                if let registrySide {
                    self.recordRegistrySample(registrySide, now: Date())
                    self.observeState(registrySide, source: "registry", authoritative: false)
                }
                self.updateBothStateFromBluetoothLog()
                self.lastFastTime = Date()
                self.isRefreshingFast = false
            }
        }
    }
    
    private func refreshSlow() {
        guard !isRefreshingSlow else { return }
        isRefreshingSlow = true
        let cachedLeft = cachedLeftSerial
        let cachedRight = cachedRightSerial
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var leftSerial: String?
            var rightSerial: String?
            var hasLeftBattery = false
            var hasRightBattery = false
            
            let profilerTask = Process()
            profilerTask.launchPath = "/usr/sbin/system_profiler"
            profilerTask.arguments = ["SPBluetoothDataType"]
            profilerTask.environment = [
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8"
            ]
            let profilerPipe = Pipe()
            profilerTask.standardOutput = profilerPipe
            
            do {
                try profilerTask.run()
                let data = profilerPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let sections = output.components(separatedBy: "Connected:")
                    for section in sections {
                        let lines = section.components(separatedBy: .newlines)
                        for line in lines {
                            if line.contains("Serial Number (Left):") {
                                leftSerial = Self.normalizedSerial(line.components(separatedBy: ":").last)
                            }
                            if line.contains("Serial Number (Right):") {
                                rightSerial = Self.normalizedSerial(line.components(separatedBy: ":").last)
                            }
                            if line.contains("Left Battery Level:") { hasLeftBattery = true }
                            if line.contains("Right Battery Level:") { hasRightBattery = true }
                        }
                    }
                }
                let mergedLeft = leftSerial ?? cachedLeft
                let mergedRight = rightSerial ?? cachedRight
                let registrySide = Self.checkRegistryPresence(leftSerial: mergedLeft, rightSerial: mergedRight)
                
                // Update Cache & State based on battery if registry is ambiguous
                DispatchQueue.main.async {
                    if let l = leftSerial { self.cachedLeftSerial = l }
                    if let r = rightSerial { self.cachedRightSerial = r }
                    self.logDebug("Profiler Cache Updated: L=\(self.cachedLeftSerial ?? "nil"), R=\(self.cachedRightSerial ?? "nil"), hasL=\(hasLeftBattery), hasR=\(hasRightBattery)")
                    self.updateBothStateFromBluetoothLog()

                    // Re-check registry immediately after refreshing serial cache.
                    if let registrySide {
                        self.recordRegistrySample(registrySide, now: Date())
                        self.observeState(registrySide, source: "registry-after-profiler", authoritative: false)
                    } else {
                        // Battery fields are weak signals: only trust one-sided hints.
                        if hasLeftBattery != hasRightBattery {
                            self.observeState(hasLeftBattery ? .left : .right, source: "battery-hint", authoritative: false)
                        } else if !hasLeftBattery && !hasRightBattery {
                            self.observeState(.none, source: "battery-empty", authoritative: false)
                        } else {
                            self.logDebug("Profiler battery state ambiguous; keeping last state")
                        }
                    }
                    self.lastSlowTime = Date()
                    self.isRefreshingSlow = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logDebug("Slow Profiler Failed")
                    self.lastSlowTime = Date()
                    self.isRefreshingSlow = false
                }
                return
            }
        }
    }
            
    
    private func observeState(_ observedState: AirPodSide, source: String, authoritative: Bool) {
        DispatchQueue.main.async {
            let now = Date()
            // Fast lane: authoritative Plcm BOTH should reflect almost immediately on HUD.
            if authoritative && source == "bluetoothd-plcm" && self.lastState != .both {
                let plcmBothStrongNow = self.count(self.recentPlcmSamples, within: 1.0, side: .both, now: now) >= 2
                if now < self.f1FastBlockedUntil && !plcmBothStrongNow {
                    self.logDebug("Rule F1-fast-plcm-both blocked until \(self.f1FastBlockedUntil)")
                    return
                }
                self.singleSideLockUntil = .distantPast
                self.applyState(.both, source: "\(source)|F1-fast")
                return
            }

            // Fast lane: authoritative Plcm single should win when BOTH is no longer fresh.
            if authoritative &&
                source == "bluetoothd-plcm-single" &&
                (observedState == .left || observedState == .right) {
                let recentPlcmBoth = self.has(self.recentPlcmSamples, within: 0.25, side: .both, now: now)
                let single: AirPodSide = observedState

                // From BOTH -> SINGLE: small guard, but do not get stuck in BOTH.
                if self.lastState == .both && !recentPlcmBoth {
                    if self.pendingTarget != single {
                        self.pendingTarget = single
                        self.pendingSince = now
                        self.logDebug("Pending \(single.rawValue) via F3-both-to-single-plcm wait=0.20s")
                        return
                    }
                    if now.timeIntervalSince(self.pendingSince) >= 0.20 {
                        self.singleOverrideSide = single
                        self.singleOverrideUntil = now.addingTimeInterval(self.singleOverrideWindow)
                        self.singleSideLockUntil = now.addingTimeInterval(self.singleSideLockWindow)
                        self.f1FastBlockedUntil = now.addingTimeInterval(self.fastBothBlockWindow)
                        self.applyState(single, source: "\(source)|F3-fast")
                        return
                    }
                }

                // From NONE -> SINGLE: keep tiny guard.
                if self.lastState == .none {
                    if self.pendingTarget != single {
                        self.pendingTarget = single
                        self.pendingSince = now
                        self.logDebug("Pending \(single.rawValue) via F2-fast-plcm-single wait=0.25s")
                        return
                    }
                    if now.timeIntervalSince(self.pendingSince) >= 0.20 {
                        self.singleSideLockUntil = now.addingTimeInterval(self.singleSideLockWindow)
                        self.f1FastBlockedUntil = now.addingTimeInterval(self.fastBothBlockWindow)
                        self.applyState(single, source: "\(source)|F2-fast")
                        return
                    }
                }
            }

            // Fallback using fused windows and hysteresis.
            let resolved = self.deriveTargetState(now: now)
            let target = resolved.state

            if now.timeIntervalSince(self.startupAt) <= self.startupGuardWindow &&
                (target == .left || target == .right) &&
                self.startupSawBothHint {
                self.logDebug("Rule S0-startup-guard hold single=\(target.rawValue) src=\(source)")
                return
            }

            if target == self.lastState {
                self.pendingTarget = nil
                return
            }

            if now < self.singleSideLockUntil &&
                (self.lastState == .left || self.lastState == .right) &&
                (target == .left || target == .right) &&
                target != self.lastState {
                let allowAuthoritativeFlip = authoritative &&
                    source == "bluetoothd-plcm-single" &&
                    observedState == target
                if !allowAuthoritativeFlip {
                    self.logDebug("Rule L1-side-lock hold \(self.lastState.rawValue), reject \(target.rawValue) from \(source)")
                    return
                }
            }

            var requiredDelay = self.sideSwitchDelay
            if target == .both {
                requiredDelay = self.upToBothDelay
            } else if self.lastState == .both && (target == .left || target == .right) {
                requiredDelay = self.bothToSingleDelay
            } else if target == .none {
                requiredDelay = self.singleToNoneDelay
            } else if self.lastState == .none && (target == .left || target == .right) {
                requiredDelay = authoritative ? 0.4 : 0.6
            }

            if self.pendingTarget != target {
                self.pendingTarget = target
                self.pendingSince = now
                self.logDebug("Pending \(target.rawValue) via \(resolved.rule) from \(source), wait=\(String(format: "%.1f", requiredDelay))s")
                return
            }
            if now.timeIntervalSince(self.pendingSince) < requiredDelay {
                return
            }

            self.applyState(target, source: "\(source)|\(resolved.rule)")
        }
    }
    private func applyState(_ newState: AirPodSide, source: String) {
        DispatchQueue.main.async {
            if self.lastState != newState {
                self.logDebug("State Transition(\(source)): \(self.lastState) -> \(newState)")
                self.lastState = newState
                self.pendingTarget = nil
                if newState == .left || newState == .right {
                    self.singleSideLockUntil = Date().addingTimeInterval(self.singleSideLockWindow)
                    self.f1FastBlockedUntil = Date().addingTimeInterval(self.fastBothBlockWindow)
                } else if newState == .both {
                    self.singleSideLockUntil = .distantPast
                }
                // Proactively notify the system to refresh UI
                NotificationCenter.default.post(name: .AirPodsStateChanged, object: newState)
            }
        }
    }
}
