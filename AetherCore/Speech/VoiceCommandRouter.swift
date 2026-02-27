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

final class VoiceCommandRouter {
    enum RoutingBias {
        case neutral
        case dictationPreferred // Cursor in input field
        case commandPreferred   // Cursor not in input field
        case forceDictation     // Explicit user gesture (Tilt Left)
        case forceCommand      // Explicit user gesture (Tilt Right)
    }

    func route(transcript raw: String, bias: RoutingBias = .neutral) -> VoiceIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(raw) }

        // Normalize for command matching
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        
        os_log("Router: Input [%{public}@] with Bias [%{public}@]. Normalized: [%{public}@]", 
               log: GlobalLogger.router, type: .debug, trimmed, String(describing: bias), s)

        // --- 1. Explicit Overrides (Highest Priority) ---
        if bias == .forceDictation {
            return .dictation(trimmed)
        }
        
        // --- 2. Normalized Force Prefixes ---
        let isForceCommand = s.hasPrefix("指令") || s.hasPrefix("command") || bias == .forceCommand
        let isForceDictation = s.hasPrefix("输入") || s.hasPrefix("input") || s.hasPrefix("type") || s.hasPrefix("写")

        // --- 3. Smart Routing Logic ---
        // If we are in an input field (dictationPreferred) and NOT explicitly forcing a command,
        // we should be very conservative about executing commands.
        if bias == .dictationPreferred && !isForceCommand {
            // Check for high-confidence/low-risk commands even in typing mode
            if s == "undo" || s == "撤销" || s == "撤回" { return .undo }
            if s == "paste" || s == "粘贴" { return .paste }
            
            // Otherwise, everything is treated as dictation in an input field
            if !isForceDictation {
                return .dictation(trimmed)
            }
        }

        // --- 4. Local Command Matching (Standard Workflow) ---
        if s.contains("撤销") || s == "undo" || s.contains("撤回") { return .undo }
        if s.contains("粘贴") || s.contains("paste") { return .paste }
        if s.contains("锁定") || s.contains("lockairpods") || s.contains("lock") { return .lockConnection }
        if s.contains("解锁") || s.contains("unlockairpods") || s.contains("unlock") { return .unlockConnection }
        if s.contains("停止") || s.contains("暂停控制") || s == "stop" || s.contains("stop") { return .stopPointer }
        if s.contains("开始") || s.contains("继续") || s.contains("start") { return .startPointer }
        if s.contains("校准") || s.contains("居中") || s.contains("重置") || s.contains("recenter") { return .recenter }
        if s.contains("打开悬停") || s.contains("开启悬停") || s.contains("dwellon") { return .setDwell(true) }
        if s.contains("关闭悬停") || s.contains("关掉悬停") || s.contains("dwelloff") { return .setDwell(false) }

        if s.contains("右键") || s.contains("rightclick") || s.contains("context") { return .clickRight }
        if s.contains("双击") || s.contains("doubleclick") { return .doubleClick }
        if s.contains("点击") || s.contains("click") || s.contains("单击") { return .clickLeft }

        // Scroll
        if s.contains("向上") || s.contains("up") || s.contains("上滚") { return .scroll(0, -300) }
        if s.contains("向下") || s.contains("down") || s.contains("下滚") { return .scroll(0, 300) }
        if s.contains("到顶") || s.contains("top") { return .scrollToWeb("top") }
        if s.contains("到底") || s.contains("bottom") { return .scrollToWeb("bottom") }
        
        // Drag
        if s.contains("拖") || s.contains("drag") || s.contains("抓住") { return .dragStart }
        if s.contains("放") || s.contains("drop") || s.contains("松开") { return .dragEnd }

        // Pinyin Fallback for Command Matching
        let py = trimmed.pinyin
        if py.contains("youjian") || py.contains("rightclick") { return .clickRight }
        if py.contains("dianji") || py.contains("danji") { return .clickLeft }
        if py.contains("shuangji") { return .doubleClick }
        if py.contains("xiangshang") || py.contains("shanggun") { return .scroll(0, -300) }
        if py.contains("xiangxia") || py.contains("xiagun") { return .scroll(0, 300) }

        // --- 5. Default Fallback ---
        return .dictation(trimmed)
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
