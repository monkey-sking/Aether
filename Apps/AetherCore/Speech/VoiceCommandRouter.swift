import Foundation

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
    func route(transcript raw: String, isTypingMode: Bool = false) -> VoiceIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(raw) }

        // Normalize: lowercase, remove common filler spaces.
        // We keep 'trimmed' for dictation content.
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")

        // --- Context-Aware Routing ---
        
        // 1. Force Command Mode: "指令", "Command"
        // e.g. "指令 点击" -> "点击" logic
        // We don't strip prefix yet for simplicity in matching, but we should probably bypass dictation check.
        let isForceCommand = s.hasPrefix("指令") || s.hasPrefix("command")

        // 2. Force Dictation Mode: "输入", "Type"
        // Already handled by existing check, but let's be explicit.
        let isForceDictation = s.hasPrefix("输入") || s.hasPrefix("Input") || s.hasPrefix("type") || s.hasPrefix("写")
        
        // 3. Typing Mode Default
        if isTypingMode && !isForceCommand {
            // In text field: default to dictation unless user said "Command..."
            // But we might want to check for "Input..." prefix to strip it?
            // Existing logic handles "Input..." stripping. 
            // Here, if just "Hello World", we return .dictation("Hello World")
            if !isForceDictation {
                return .dictation(trimmed)
            }
        }

        if s.contains("撤销") || s == "undo" || s.contains("撤回") {
            return .undo
        }
        if s.contains("粘贴") || s.contains("paste") {
            return .paste
        }
        if s.contains("锁定") || s.contains("lockairpods") || s.contains("lock") {
            return .lockConnection
        }
        if s.contains("解锁") || s.contains("unlockairpods") || s.contains("unlock") {
            return .unlockConnection
        }
        if s.contains("停止") || s.contains("暂停控制") || s == "stop" || s.contains("stop") {
            return .stopPointer
        }
        if s.contains("开始") || s.contains("继续") || s.contains("start") {
            return .startPointer
        }
        if s.contains("校准") || s.contains("居中") || s.contains("重置") || s.contains("recenter") {
            return .recenter
        }
        if s.contains("打开悬停") || s.contains("开启悬停") || s.contains("dwellon") {
            return .setDwell(true)
        }
        if s.contains("关闭悬停") || s.contains("关掉悬停") || s.contains("dwelloff") {
            return .setDwell(false)
        }

        if s.contains("右键") || s.contains("rightclick") || s.contains("context") {
            return .clickRight
        }
        if s.contains("双击") || s.contains("doubleclick") {
            return .doubleClick
        }
        if s.contains("点击") || s.contains("click") || s.contains("单击") {
            return .clickLeft
        }

        // Scroll / Drag
        if s.contains("向上") || s.contains("up") || s.contains("上滚") { return .scroll(0, -300) }
        if s.contains("向下") || s.contains("down") || s.contains("下滚") { return .scroll(0, 300) }
        if s.contains("到顶") || s.contains("top") { return .scrollToWeb("top") }
        if s.contains("到底") || s.contains("bottom") { return .scrollToWeb("bottom") }
        
        if s.contains("拖") || s.contains("drag") || s.contains("抓住") { return .dragStart }
        if s.contains("放") || s.contains("drop") || s.contains("松开") { return .dragEnd }

        if s.contains("写") || s.contains("input") || s.contains("type") || s.contains("输入") {
            // "type hello world" -> "hello world"
            let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
            return .dictation(String(trimmed[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // --- Pinyin Fallback (for Homophones) ---
        // Solves "右键" (You Jian) vs "邮件" (You Jian)
        let py = trimmed.pinyin
        
        if py.contains("youjian") || py.contains("rightclick") { return .clickRight }
        if py.contains("zuo") && (py.contains("hua") || py.contains("yi")) { 
            // "左滑" (zuo hua), "左移" (zuo yi) -> maybe invalid? 
            // Let's stick to known commands.
        }
        
        // Check Pinyin for core commands if exact match failed
        if py.contains("dianji") || py.contains("danji") { return .clickLeft } // 点击/单击
        if py.contains("shuangji") { return .doubleClick } // 双击
        if py.contains("xiangshang") || py.contains("shanggun") { return .scroll(0, -300) } // 向上/上滚
        if py.contains("xiangxia") || py.contains("xiagun") { return .scroll(0, 300) } // 向下/下滚
        
        // Default fallback: treat as dictation for MVP (better UX than "unknown").
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
