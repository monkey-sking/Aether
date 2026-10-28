import Foundation

/// 跨语言 / 口语化的概念同义词表。
///
/// 存在的理由：菜单标题是死的（「清倒废纸篓」），用户和 agent 的说法是活的
/// （「清空废纸篓」/ "empty trash" / "qingdao feizhilou"）。纯字符串匹配在这里
/// 全部落空，必须先映射到同一个「概念」，再判定命中。
///
/// 规则：一个字符串可能命中多个概念，取**最长命中词**对应的概念作为它的概念，
/// 这样可以避免「新建文件夹」和「新建窗口」因为共有「新建」而误判为同一概念。
public enum MenuConcept {

    public struct Concept: Sendable {
        public let id: String
        public let terms: [String]
    }

    public static let all: [Concept] = [
        Concept(id: "save", terms: ["保存", "存储", "save", "存盘"]),
        Concept(id: "saveAs", terms: ["另存为", "存储为", "save as", "另存"]),
        Concept(id: "open", terms: ["打开", "open"]),
        Concept(id: "openWith", terms: ["打开方式", "open with"]),
        Concept(id: "close", terms: ["关闭", "close"]),
        Concept(id: "closeAll", terms: ["全部关闭", "close all"]),
        Concept(id: "quit", terms: ["退出", "quit"]),
        Concept(id: "undo", terms: ["撤销", "回退", "undo"]),
        Concept(id: "redo", terms: ["重做", "恢复", "redo"]),
        Concept(id: "cut", terms: ["剪切", "cut"]),
        Concept(id: "copy", terms: ["拷贝", "复制", "copy"]),
        Concept(id: "paste", terms: ["粘贴", "paste"]),
        Concept(id: "pastePlain", terms: ["粘贴并匹配样式", "纯文本粘贴", "paste and match style"]),
        Concept(id: "selectAll", terms: ["全选", "select all"]),
        Concept(id: "find", terms: ["查找", "搜索", "find", "search"]),
        Concept(id: "findNext", terms: ["查找下一个", "find next"]),
        Concept(id: "replace", terms: ["替换", "replace"]),
        Concept(id: "new", terms: ["新建", "new"]),
        Concept(id: "newFolder", terms: ["新建文件夹", "new folder"]),
        Concept(id: "newWindow", terms: ["新建窗口", "新窗口", "new window"]),
        Concept(id: "newTab", terms: ["新建标签页", "新标签页", "新建标签", "new tab"]),
        Concept(id: "newDocument", terms: ["新建文稿", "新建文档", "new document"]),
        Concept(id: "delete", terms: ["删除", "delete"]),
        Concept(id: "moveToTrash", terms: ["移到废纸篓", "move to trash", "移到垃圾箱"]),
        Concept(id: "emptyTrash", terms: ["清倒废纸篓", "清空废纸篓", "清倒垃圾箱", "empty trash"]),
        Concept(id: "preferences", terms: ["设置", "偏好设置", "选项", "preferences", "settings"]),
        Concept(id: "print", terms: ["打印", "print"]),
        Concept(id: "export", terms: ["导出", "export"]),
        Concept(id: "import", terms: ["导入", "import"]),
        Concept(id: "reload", terms: ["重新载入", "刷新", "reload", "refresh"]),
        Concept(id: "zoomIn", terms: ["放大", "zoom in"]),
        Concept(id: "zoomOut", terms: ["缩小", "zoom out"]),
        Concept(id: "actualSize", terms: ["实际大小", "actual size"]),
        Concept(id: "fullScreen", terms: ["全屏", "进入全屏幕", "full screen", "fullscreen", "enter full screen"]),
        Concept(id: "minimize", terms: ["最小化", "minimize"]),
        Concept(id: "hide", terms: ["隐藏", "hide"]),
        Concept(id: "hideOthers", terms: ["隐藏其他", "hide others"]),
        Concept(id: "showAll", terms: ["全部显示", "显示全部", "show all"]),
        Concept(id: "getInfo", terms: ["显示简介", "简介", "get info"]),
        Concept(id: "rename", terms: ["重新命名", "重命名", "rename"]),
        Concept(id: "duplicate", terms: ["制作替身", "复制为副本", "duplicate"]),
        Concept(id: "compress", terms: ["压缩", "compress"]),
        Concept(id: "goBack", terms: ["返回", "后退", "back"]),
        Concept(id: "goForward", terms: ["前进", "forward"]),
        Concept(id: "home", terms: ["个人收藏", "主页", "home"]),
        Concept(id: "downloads", terms: ["下载", "downloads"]),
        Concept(id: "services", terms: ["服务", "services"]),
        Concept(id: "about", terms: ["关于", "about"]),
        Concept(id: "checkUpdates", terms: ["检查更新", "check for updates"]),
        Concept(id: "file", terms: ["文件", "file"]),
        Concept(id: "edit", terms: ["编辑", "edit"]),
        Concept(id: "view", terms: ["显示", "视图", "view"]),
        Concept(id: "window", terms: ["窗口", "window"]),
        Concept(id: "help", terms: ["帮助", "help"]),
        Concept(id: "tabs", terms: ["标签页", "标签", "tab"]),
        Concept(id: "sidebar", terms: ["边栏", "sidebar"]),
        Concept(id: "toolbar", terms: ["工具栏", "toolbar"]),
        Concept(id: "pathBar", terms: ["路径栏", "显示路径", "path bar"]),
        Concept(id: "statusBar", terms: ["状态栏", "status bar"]),
        Concept(id: "sortBy", terms: ["排序方式", "排序", "sort by"]),
        Concept(id: "iconView", terms: ["图标", "以图标方式", "as icons"]),
        Concept(id: "listView", terms: ["列表", "以列表方式", "as list"]),
        Concept(id: "columnView", terms: ["分栏", "以分栏方式", "as columns"]),
        Concept(id: "galleryView", terms: ["画廊", "gallery"]),
        Concept(id: "quickLook", terms: ["快速查看", "预览", "quick look"]),
        Concept(id: "share", terms: ["共享", "share"]),
        Concept(id: "burn", terms: ["刻录", "burn"]),
        Concept(id: "systemSettings", terms: ["系统设置", "系统偏好设置", "system settings", "system preferences"]),
        Concept(id: "forceQuit", terms: ["强制退出", "force quit"]),
        Concept(id: "lockScreen", terms: ["锁定屏幕", "锁屏", "lock screen"]),
        Concept(id: "sleep", terms: ["睡眠", "sleep"]),
        Concept(id: "restart", terms: ["重新启动", "重启", "restart"]),
        Concept(id: "shutdown", terms: ["关机", "shut down"]),
        Concept(id: "logOut", terms: ["退出登录", "注销", "log out"]),
        Concept(id: "spotlight", terms: ["聚焦", "spotlight"]),
        Concept(id: "network", terms: ["网络", "network"]),
        Concept(id: "bookmarks", terms: ["书签", "bookmark"]),
        Concept(id: "history", terms: ["历史记录", "历史", "history"]),
        Concept(id: "readerMode", terms: ["阅读器", "阅读模式", "reader mode"]),
        Concept(id: "developerTools", terms: ["开发者工具", "开发人员工具", "developer tools"]),
        Concept(id: "extensions", terms: ["扩展程序", "扩展", "extensions"]),
        Concept(id: "taskManager", terms: ["任务管理器", "task manager"]),
        Concept(id: "incognito", terms: ["无痕式窗口", "无痕", "incognito"]),
    ]

    /// 返回一个字符串命中的概念 id（取最长命中词）。无命中返回 nil。
    public static func conceptID(for text: String) -> String? {
        let normalized = MenuText.normalize(text)
        guard !normalized.isEmpty else { return nil }

        var best: (id: String, length: Int)?
        for concept in all {
            for term in concept.terms {
                let normalizedTerm = MenuText.normalize(term)
                guard !normalizedTerm.isEmpty else { continue }
                if MenuText.containsAsTerm(normalized, normalizedTerm) {
                    if normalizedTerm.count > (best?.length ?? 0) {
                        best = (concept.id, normalizedTerm.count)
                    }
                }
            }
        }
        return best?.id
    }
}
