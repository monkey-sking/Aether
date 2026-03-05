import Foundation
import os.log
import Cocoa

enum VoiceIntent: Equatable {
    case clickLeft
    case clickRight
    case doubleClick
    case startPointer
    case stopPointer
    case recenter
    case setDwell(Bool)
    case scroll(Int, Int) // dx, dy
    case scrollToWeb(String) // "top", "bottom"
    case dragStart
    case dragEnd
    case undo
    case paste
    case lockConnection
    case unlockConnection
    case dictation(String)
    case unknown(String)
}

extension VoiceIntent: Sendable {}

enum VoiceCommandConfidence: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: VoiceCommandConfidence, rhs: VoiceCommandConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct VoiceCommandDecision {
    let intent: VoiceIntent
    let confidence: VoiceCommandConfidence
    let reason: String
}

final class VoiceCommandRouter {
    enum RoutingBias {
        case neutral
        case dictationPreferred // Cursor in input field
        case commandPreferred   // Cursor not in input field
        case forceDictation     // Explicit user gesture (Tilt Left)
        case forceCommand      // Explicit user gesture (Tilt Right)
    }

    func route(transcript raw: String, bias: RoutingBias = .neutral) -> VoiceIntent {
        routeDetailed(transcript: raw, bias: bias).intent
    }

    func routeDetailed(transcript raw: String, bias: RoutingBias = .neutral) -> VoiceCommandDecision {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return VoiceCommandDecision(intent: .unknown(raw), confidence: .low, reason: "empty")
        }

        // Normalize for command matching
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        
        os_log("Router: Input [%{public}@] with Bias [%{public}@]. Normalized: [%{public}@]", 
               log: GlobalLogger.router, type: .debug, trimmed, String(describing: bias), s)

        // --- 1. Explicit Overrides (Highest Priority) ---
        if bias == .forceDictation {
            return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "forced-dictation-bias")
        }
        
        // --- 2. Normalized Force Prefixes ---
        let isForceCommand = s.hasPrefix("指令") || s.hasPrefix("command") || bias == .forceCommand
        let isForceDictation = s.hasPrefix("输入") || s.hasPrefix("input") || s.hasPrefix("type") || s.hasPrefix("写")

        if isForceDictation {
            let payload = stripDictationPrefix(from: trimmed)
            return VoiceCommandDecision(intent: .dictation(payload.isEmpty ? trimmed : payload), confidence: .high, reason: "forced-dictation-prefix")
        }

        // --- 3. Smart Routing Logic ---
        // If we are in an input field (dictationPreferred) and NOT explicitly forcing a command,
        // we should be very conservative about executing commands.
        if bias == .dictationPreferred && !isForceCommand {
            // Check for high-confidence/low-risk commands even in typing mode
            if s == "undo" || s == "撤销" || s == "撤回" {
                return VoiceCommandDecision(intent: .undo, confidence: .high, reason: "typing-safe-undo")
            }
            if s == "paste" || s == "粘贴" {
                return VoiceCommandDecision(intent: .paste, confidence: .high, reason: "typing-safe-paste")
            }
            
            // Otherwise, everything is treated as dictation in an input field
            if !isForceDictation {
                return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "typing-preferred")
            }
        }

        // --- 4. Local Command Matching (Standard Workflow) ---
        if s == "undo" || s == "撤销" || s == "撤回" {
            return VoiceCommandDecision(intent: .undo, confidence: .high, reason: "exact-undo")
        }
        if s.contains("撤销") || s.contains("撤回") || s.contains("undo") {
            return VoiceCommandDecision(intent: .undo, confidence: .medium, reason: "contains-undo")
        }
        if s == "paste" || s == "粘贴" {
            return VoiceCommandDecision(intent: .paste, confidence: .high, reason: "exact-paste")
        }
        if s.contains("粘贴") || s.contains("paste") {
            return VoiceCommandDecision(intent: .paste, confidence: .medium, reason: "contains-paste")
        }
        if s == "lock" || s == "lockairpods" || s == "锁定" {
            return VoiceCommandDecision(intent: .lockConnection, confidence: .high, reason: "exact-lock")
        }
        if s.contains("锁定") || s.contains("lockairpods") || s.contains("lock") {
            return VoiceCommandDecision(intent: .lockConnection, confidence: .medium, reason: "contains-lock")
        }
        if s == "unlock" || s == "unlockairpods" || s == "解锁" {
            return VoiceCommandDecision(intent: .unlockConnection, confidence: .high, reason: "exact-unlock")
        }
        if s.contains("解锁") || s.contains("unlockairpods") || s.contains("unlock") {
            return VoiceCommandDecision(intent: .unlockConnection, confidence: .medium, reason: "contains-unlock")
        }
        if s == "stop" || s == "停止" || s == "暂停控制" {
            return VoiceCommandDecision(intent: .stopPointer, confidence: .high, reason: "exact-stop")
        }
        if s.contains("停止") || s.contains("暂停控制") || s.contains("stop") {
            return VoiceCommandDecision(intent: .stopPointer, confidence: .medium, reason: "contains-stop")
        }
        if s == "start" || s == "开始" || s == "继续" {
            return VoiceCommandDecision(intent: .startPointer, confidence: .high, reason: "exact-start")
        }
        if s.contains("开始") || s.contains("继续") || s.contains("start") {
            return VoiceCommandDecision(intent: .startPointer, confidence: .medium, reason: "contains-start")
        }
        if s == "recenter" || s == "校准" || s == "居中" || s == "重置" {
            return VoiceCommandDecision(intent: .recenter, confidence: .high, reason: "exact-recenter")
        }
        if s.contains("校准") || s.contains("居中") || s.contains("重置") || s.contains("recenter") {
            return VoiceCommandDecision(intent: .recenter, confidence: .medium, reason: "contains-recenter")
        }
        if s == "dwellon" || s == "打开悬停" || s == "开启悬停" {
            return VoiceCommandDecision(intent: .setDwell(true), confidence: .high, reason: "exact-dwell-on")
        }
        if s.contains("打开悬停") || s.contains("开启悬停") || s.contains("dwellon") {
            return VoiceCommandDecision(intent: .setDwell(true), confidence: .medium, reason: "contains-dwell-on")
        }
        if s == "dwelloff" || s == "关闭悬停" || s == "关掉悬停" {
            return VoiceCommandDecision(intent: .setDwell(false), confidence: .high, reason: "exact-dwell-off")
        }
        if s.contains("关闭悬停") || s.contains("关掉悬停") || s.contains("dwelloff") {
            return VoiceCommandDecision(intent: .setDwell(false), confidence: .medium, reason: "contains-dwell-off")
        }

        if s == "右键" || s == "rightclick" || s == "context" {
            return VoiceCommandDecision(intent: .clickRight, confidence: .high, reason: "exact-right-click")
        }
        if s.contains("右键") || s.contains("rightclick") || s.contains("context") {
            return VoiceCommandDecision(intent: .clickRight, confidence: .medium, reason: "contains-right-click")
        }
        if s == "双击" || s == "doubleclick" {
            return VoiceCommandDecision(intent: .doubleClick, confidence: .high, reason: "exact-double-click")
        }
        if s.contains("双击") || s.contains("doubleclick") {
            return VoiceCommandDecision(intent: .doubleClick, confidence: .medium, reason: "contains-double-click")
        }
        if s == "点击" || s == "click" || s == "单击" {
            return VoiceCommandDecision(intent: .clickLeft, confidence: .high, reason: "exact-click")
        }
        if s.contains("点击") || s.contains("click") || s.contains("单击") {
            return VoiceCommandDecision(intent: .clickLeft, confidence: .medium, reason: "contains-click")
        }

        // Scroll
        if s == "向上" || s == "up" || s == "上滚" {
            return VoiceCommandDecision(intent: .scroll(0, -300), confidence: .high, reason: "exact-scroll-up")
        }
        if s.contains("向上") || s.contains("up") || s.contains("上滚") {
            return VoiceCommandDecision(intent: .scroll(0, -300), confidence: .medium, reason: "contains-scroll-up")
        }
        if s == "向下" || s == "down" || s == "下滚" {
            return VoiceCommandDecision(intent: .scroll(0, 300), confidence: .high, reason: "exact-scroll-down")
        }
        if s.contains("向下") || s.contains("down") || s.contains("下滚") {
            return VoiceCommandDecision(intent: .scroll(0, 300), confidence: .medium, reason: "contains-scroll-down")
        }
        if s == "到顶" || s == "top" {
            return VoiceCommandDecision(intent: .scrollToWeb("top"), confidence: .high, reason: "exact-scroll-top")
        }
        if s.contains("到顶") || s.contains("top") {
            return VoiceCommandDecision(intent: .scrollToWeb("top"), confidence: .medium, reason: "contains-scroll-top")
        }
        if s == "到底" || s == "bottom" {
            return VoiceCommandDecision(intent: .scrollToWeb("bottom"), confidence: .high, reason: "exact-scroll-bottom")
        }
        if s.contains("到底") || s.contains("bottom") {
            return VoiceCommandDecision(intent: .scrollToWeb("bottom"), confidence: .medium, reason: "contains-scroll-bottom")
        }
        
        // Drag
        if s == "拖" || s == "drag" || s == "抓住" {
            return VoiceCommandDecision(intent: .dragStart, confidence: .high, reason: "exact-drag-start")
        }
        if s.contains("拖") || s.contains("drag") || s.contains("抓住") {
            return VoiceCommandDecision(intent: .dragStart, confidence: .medium, reason: "contains-drag-start")
        }
        if s == "放" || s == "drop" || s == "松开" {
            return VoiceCommandDecision(intent: .dragEnd, confidence: .high, reason: "exact-drag-end")
        }
        if s.contains("放") || s.contains("drop") || s.contains("松开") {
            return VoiceCommandDecision(intent: .dragEnd, confidence: .medium, reason: "contains-drag-end")
        }

        // Pinyin Fallback for Command Matching
        let py = trimmed.pinyin
        if py.contains("youjian") || py.contains("rightclick") {
            return VoiceCommandDecision(intent: .clickRight, confidence: .low, reason: "pinyin-right-click")
        }
        if py.contains("dianji") || py.contains("danji") {
            return VoiceCommandDecision(intent: .clickLeft, confidence: .low, reason: "pinyin-click")
        }
        if py.contains("shuangji") {
            return VoiceCommandDecision(intent: .doubleClick, confidence: .low, reason: "pinyin-double-click")
        }
        if py.contains("xiangshang") || py.contains("shanggun") {
            return VoiceCommandDecision(intent: .scroll(0, -300), confidence: .low, reason: "pinyin-scroll-up")
        }
        if py.contains("xiangxia") || py.contains("xiagun") {
            return VoiceCommandDecision(intent: .scroll(0, 300), confidence: .low, reason: "pinyin-scroll-down")
        }

        // --- 5. Default Fallback ---
        if isForceCommand {
            return VoiceCommandDecision(intent: .unknown(trimmed), confidence: .low, reason: "forced-command-no-match")
        }
        return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .low, reason: "fallback-dictation")
    }

    private func stripDictationPrefix(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        let prefixes = ["输入", "写", "input", "type"]

        for prefix in prefixes {
            if lowercase.hasPrefix(prefix) {
                let dropCount = prefix.count
                let suffix = trimmed.dropFirst(dropCount).trimmingCharacters(in: .whitespacesAndNewlines)
                return String(suffix)
            }
        }

        return trimmed
    }
}

// MARK: - Pinyin Helper
extension String {
    var pinyin: String {
        // "你好" -> "nǐ hǎo" -> "ni hao" -> "nihao"
        return self
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? self.lowercased()
    }
}
