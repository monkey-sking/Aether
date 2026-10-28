import XCTest
@testable import AetherMenuKit

final class MenuTextTests: XCTestCase {

    func testNormalizeStripsEllipsisAndQuotes() {
        XCTAssertEqual(MenuText.normalize("设置…"), "设置")
        XCTAssertEqual(MenuText.normalize("设置..."), "设置")
        XCTAssertEqual(MenuText.normalize("拷贝\u{201C}DSH NEXT.app\u{201D}"), "拷贝dsh next.app")
        XCTAssertEqual(MenuText.normalize("  New   Folder  "), "new folder")
    }

    func testPinyinFullAndInitials() {
        let form = MenuText.pinyin("新建文件夹")
        XCTAssertEqual(form.full, "xinjianwenjianjia")
        XCTAssertEqual(form.initials, "xjwjj")

        let english = MenuText.pinyin("New Folder")
        XCTAssertEqual(english.initials.lowercased(), "nf")
    }

    func testSubsequence() {
        XCTAssertTrue(MenuText.isSubsequence("xjwj", of: "xinjianwenjianjia"))
        XCTAssertFalse(MenuText.isSubsequence("z", of: "xinjian"))
    }

    func testLooksDynamic() {
        XCTAssertTrue(MenuText.looksDynamic("撤销拷贝\u{201C}foo.txt\u{201D}"))
        XCTAssertFalse(MenuText.looksDynamic("新建文件夹"))
    }
}

final class MenuConceptTests: XCTestCase {

    func testLongestTermWins() {
        // 「新建文件夹」不能被「新建」这个更泛的词抢走概念
        XCTAssertEqual(MenuConcept.conceptID(for: "新建文件夹"), "newFolder")
        XCTAssertEqual(MenuConcept.conceptID(for: "新建窗口"), "newWindow")
        XCTAssertEqual(MenuConcept.conceptID(for: "新建标签页"), "newTab")
    }

    func testColloquialMapsToMenuWording() {
        // 用户说「清空」，菜单写「清倒」
        XCTAssertEqual(MenuConcept.conceptID(for: "清空废纸篓"), "emptyTrash")
        XCTAssertEqual(MenuConcept.conceptID(for: "清倒废纸篓…"), "emptyTrash")
    }

    func testCrossLanguage() {
        XCTAssertEqual(MenuConcept.conceptID(for: "empty trash"), "emptyTrash")
        XCTAssertEqual(MenuConcept.conceptID(for: "get info"), "getInfo")
        XCTAssertEqual(MenuConcept.conceptID(for: "显示简介"), "getInfo")
        XCTAssertEqual(MenuConcept.conceptID(for: "select all"), "selectAll")
    }

    func testUnknownReturnsNil() {
        XCTAssertNil(MenuConcept.conceptID(for: "zzzz"))
    }

    func testAsciiTermRequiresWordBoundary() {
        // 真实回归：Chrome 书签「SnapSave - 1080p ...」曾被「保存」以 concept:save 命中
        XCTAssertFalse(MenuText.containsAsTerm("snapsave - 1080p", "save"))
        // 该标题不含其它概念词，修复后应得不到 save 概念
        XCTAssertNotEqual(MenuConcept.conceptID(for: "SnapSave - 1080p"), "save")
        XCTAssertTrue(MenuText.containsAsTerm("save page as", "save"))
        XCTAssertTrue(MenuText.containsAsTerm("页面存储为…", "存储为"))
    }
}

final class MenuMatcherTests: XCTestCase {

    private func command(
        _ path: [String],
        shortcut: String? = nil,
        enabled: Bool = true
    ) -> MenuCommand {
        MenuCommand(
            path: path,
            title: path.last ?? "",
            shortcut: shortcut,
            enabled: enabled,
            bundleIdentifier: "test.bundle",
            processIdentifier: 1
        )
    }

    private let catalog: [MenuCommand] = [
        MenuCommand(path: ["文件", "新建文件夹"], title: "新建文件夹", shortcut: "shift+cmd+n", enabled: true, bundleIdentifier: "t", processIdentifier: 1),
        MenuCommand(path: ["文件", "新建窗口"], title: "新建窗口", shortcut: "cmd+n", enabled: true, bundleIdentifier: "t", processIdentifier: 1),
        MenuCommand(path: ["文件", "使用“Wake”新建文件夹"], title: "使用“Wake”新建文件夹", shortcut: "ctrl+cmd+n", enabled: true, bundleIdentifier: "t", processIdentifier: 1),
        MenuCommand(path: ["访达", "清倒废纸篓…"], title: "清倒废纸篓…", shortcut: "shift+cmd+delete", enabled: true, bundleIdentifier: "t", processIdentifier: 1),
        MenuCommand(path: ["编辑", "撤销拷贝“a.txt”"], title: "撤销拷贝“a.txt”", shortcut: "cmd+z", enabled: true, bundleIdentifier: "t", processIdentifier: 1),
        MenuCommand(path: ["文件", "显示简介"], title: "显示简介", shortcut: "cmd+i", enabled: false, bundleIdentifier: "t", processIdentifier: 1),
        MenuCommand(path: ["显示", "进入全屏幕"], title: "进入全屏幕", shortcut: nil, enabled: true, bundleIdentifier: "t", processIdentifier: 1),
    ]

    func testExactBeatsOthers() {
        let results = MenuMatcher.match("新建文件夹", in: catalog)
        XCTAssertEqual(results.first?.command.title, "新建文件夹")
        XCTAssertEqual(results.first?.reason, "exact")
        XCTAssertGreaterThanOrEqual(results.first?.score ?? 0, 0.99)
    }

    func testDynamicTitleIsPenalized() {
        let results = MenuMatcher.match("新建文件夹", in: catalog)
        // 「使用“Wake”新建文件夹」含动态实体名，必须排在精确项之后
        let dynamicIndex = results.firstIndex { $0.command.title.contains("Wake") }
        let exactIndex = results.firstIndex { $0.command.title == "新建文件夹" }
        XCTAssertNotNil(dynamicIndex)
        XCTAssertNotNil(exactIndex)
        XCTAssertLessThan(exactIndex!, dynamicIndex!)
    }

    func testColloquialQueryMatchesMenuWording() {
        let results = MenuMatcher.match("清空废纸篓", in: catalog)
        XCTAssertEqual(results.first?.command.title, "清倒废纸篓…")
        XCTAssertTrue(results.first?.reason.hasPrefix("concept") ?? false)
    }

    func testEnglishQueryMatchesChineseMenu() {
        let results = MenuMatcher.match("get info", in: catalog)
        XCTAssertEqual(results.first?.command.title, "显示简介")
    }

    func testPinyinFullMatch() {
        let results = MenuMatcher.match("xinjianwenjianjia", in: catalog)
        XCTAssertEqual(results.first?.command.title, "新建文件夹")
        XCTAssertEqual(results.first?.reason, "pinyin")
    }

    func testInitialsMatch() {
        let results = MenuMatcher.match("xjwjj", in: catalog)
        XCTAssertEqual(results.first?.command.title, "新建文件夹")
        XCTAssertEqual(results.first?.reason, "initials-exact")
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(MenuMatcher.match("", in: catalog).isEmpty)
        XCTAssertTrue(MenuMatcher.match("   ", in: catalog).isEmpty)
    }

    func testLimitIsRespected() {
        let results = MenuMatcher.match("新建", in: catalog, limit: 1)
        XCTAssertEqual(results.count, 1)
    }

    func testConfidenceTiers() {
        let high = MatchResult(command: catalog[0], score: 0.95, reason: "exact")
        XCTAssertEqual(high.confidence, .high)
        let medium = MatchResult(command: catalog[0], score: 0.70, reason: "pinyin")
        XCTAssertEqual(medium.confidence, .medium)
        let low = MatchResult(command: catalog[0], score: 0.40, reason: "subsequence")
        XCTAssertEqual(low.confidence, .low)
    }
}

final class ShortcutParsingTests: XCTestCase {

    func testCommandOnly() {
        // 0 = 仅 Command
        XCTAssertEqual(
            MenuCatalog.shortcutText(char: ",", modifiers: 0, virtualKey: nil),
            "cmd+,"
        )
    }

    func testOptionCommand() {
        // 2 = Option（实测自「隐藏其他」⌥⌘H）
        XCTAssertEqual(
            MenuCatalog.shortcutText(char: "H", modifiers: 2, virtualKey: nil),
            "opt+cmd+h"
        )
    }

    func testControlCommand() {
        // 4 = Control（实测自「锁屏」⌃⌘Q）
        XCTAssertEqual(
            MenuCatalog.shortcutText(char: "Q", modifiers: 4, virtualKey: nil),
            "ctrl+cmd+q"
        )
    }

    func testShiftControlCommand() {
        XCTAssertEqual(
            MenuCatalog.shortcutText(char: "A", modifiers: 5, virtualKey: nil),
            "ctrl+shift+cmd+a"
        )
    }

    func testVirtualKeyWinsOverChar() {
        XCTAssertEqual(
            MenuCatalog.shortcutText(char: "", modifiers: 2, virtualKey: 53),
            "opt+cmd+escape"
        )
    }

    func testNoShortcut() {
        XCTAssertNil(MenuCatalog.shortcutText(char: "", modifiers: nil, virtualKey: nil))
    }
}
