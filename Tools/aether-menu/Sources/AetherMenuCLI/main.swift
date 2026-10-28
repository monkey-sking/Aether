import Foundation
import AetherMenuKit

// aether-menu —— 把任意运行中的 macOS App 的菜单栏变成 agent 可检索的命令目录。
//
// 子命令：
//   list   列出某个 App 的全部菜单命令
//   match  用一句自然语言（中文/英文/拼音）找到对应命令
//   apps   列出当前可作为目标的应用
//
// 设计边界：本工具只负责「发现 + 解析出快捷键」，不负责「执行」。
// 执行交给 Computer Use 的 hotkey / invoke_menu，避免重复造轮子。

let usage = """
用法:
  aether-menu apps
  aether-menu list  [--app <名称|bundle-id|pid>] [--json] [--all]
  aether-menu match <查询词...> [--app <名称|bundle-id|pid>] [--json] [--limit N]
  aether-menu exec  <查询词...> [--app <名称|bundle-id|pid>] [--json] [--dry-run]

说明:
  --app      目标应用，省略时取当前前台 App
  --json     输出 JSON（便于程序/agent 消费）
  --all      不做噪音过滤（含服务、最近使用、Apple 菜单全量）
  --limit    最多返回多少条匹配（默认 10）
  --dry-run  exec 只解析不执行

退出码:
  0 成功  1 参数/环境错误  2 无匹配  3 执行失败

示例:
  aether-menu match 新建文件夹 --app Finder
  aether-menu match "empty trash" --app com.apple.finder
  aether-menu match xjwjj --app Finder --json
  aether-menu exec 显示简介 --app Finder --dry-run
  aether-menu list --app Safari --json | jq '.[] | select(.shortcut != null)'
"""

struct Arguments {
    var command: String = ""
    var positional: [String] = []
    var appQuery: String?
    var json = false
    var includeAll = false
    var limit = 10
    var dryRun = false
}

func parseArguments(_ raw: [String]) throws -> Arguments {
    var args = Arguments()
    var index = 0
    var positionals: [String] = []

    while index < raw.count {
        let token = raw[index]
        switch token {
        case "--json":
            args.json = true
        case "--all":
            args.includeAll = true
        case "--dry-run":
            args.dryRun = true
        case "--app":
            guard index + 1 < raw.count else {
                throw CLIError.message("--app 后面需要跟应用名/bundle-id/pid")
            }
            args.appQuery = raw[index + 1]
            index += 1
        case "--limit":
            guard index + 1 < raw.count, let value = Int(raw[index + 1]), value > 0 else {
                throw CLIError.message("--limit 需要一个正整数")
            }
            args.limit = value
            index += 1
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            positionals.append(token)
        }
        index += 1
    }

    guard let command = positionals.first else {
        throw CLIError.message("缺少子命令")
    }
    args.command = command
    args.positional = Array(positionals.dropFirst())
    return args
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}

func encode<T: Encodable>(_ value: T) throws -> String {
    let data = try makeEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? "[]"
}

struct MatchOutput: Encodable {
    struct Item: Encodable {
        let path: [String]
        let title: String
        let shortcut: String?
        let enabled: Bool
        let score: Double
        let reason: String
        let confidence: String
    }
    let query: String
    let app: String
    let bundleIdentifier: String
    let candidateCount: Int
    let results: [Item]
}

struct ExecOutput: Encodable {
    let query: String
    let app: String
    let bundleIdentifier: String
    let matched: MatchOutput.Item?
    let pressed: Bool
    let detail: String
    let dryRun: Bool
}

struct ListOutput: Encodable {
    struct App: Encodable {
        let name: String
        let bundleIdentifier: String
        let processIdentifier: Int32
    }
    let app: App
    let count: Int
    let commands: [MenuCommand]
}

func resolveTarget(_ query: String?) throws -> MenuCatalog.AppTarget {
    if let query {
        guard let target = MenuCatalog.resolveApp(query) else {
            throw CLIError.message("未找到正在运行的应用: \(query)\n提示: 用 `aether-menu apps` 查看可选目标")
        }
        return target
    }
    guard let frontmost = MenuCatalog.frontmostApp() else {
        throw CLIError.message("无法确定当前前台应用")
    }
    return frontmost
}

func main() {
    do {
        let args = try parseArguments(Array(CommandLine.arguments.dropFirst()))

        guard AX.isTrusted else {
            FileHandle.standardError.write(
                Data("需要辅助功能（Accessibility）权限才能读取菜单栏。\n".utf8)
            )
            _ = AX.requestTrust()
            exit(1)
        }

        switch args.command {
        case "apps":
            let targets = MenuCatalog.allRunningApps()
            if args.json {
                let payload = targets.map {
                    ListOutput.App(
                        name: $0.displayName,
                        bundleIdentifier: $0.bundleIdentifier,
                        processIdentifier: $0.processIdentifier
                    )
                }
                print(try encode(payload))
            } else {
                for target in targets {
                    print("\(target.displayName)\t\(target.bundleIdentifier)\tpid=\(target.processIdentifier)")
                }
            }

        case "list":
            let target = try resolveTarget(args.appQuery)
            let options = args.includeAll
                ? MenuCatalog.Options(
                    includeAppleMenu: true,
                    includeServices: true,
                    includeRecentItems: true,
                    excludeDynamicWindowTitles: false
                )
                : MenuCatalog.Options.default
            let commands = MenuCatalog.commands(for: target, options: options)

            if args.json {
                let payload = ListOutput(
                    app: .init(
                        name: target.displayName,
                        bundleIdentifier: target.bundleIdentifier,
                        processIdentifier: target.processIdentifier
                    ),
                    count: commands.count,
                    commands: commands
                )
                print(try encode(payload))
            } else {
                print("\(target.displayName) | \(commands.count) 条命令")
                for command in commands {
                    let shortcut = command.shortcut.map { "  [\($0)]" } ?? ""
                    let disabled = command.enabled ? "" : "  (disabled)"
                    print("  \(command.displayPath)\(shortcut)\(disabled)")
                }
            }

        case "match":
            let query = args.positional.joined(separator: " ")
            guard !query.isEmpty else {
                throw CLIError.message("match 需要一个查询词")
            }
            let target = try resolveTarget(args.appQuery)
            let commands = MenuCatalog.commands(for: target)
            let results = MenuMatcher.match(query, in: commands, limit: args.limit)

            if args.json {
                let payload = MatchOutput(
                    query: query,
                    app: target.displayName,
                    bundleIdentifier: target.bundleIdentifier,
                    candidateCount: commands.count,
                    results: results.map {
                        MatchOutput.Item(
                            path: $0.command.path,
                            title: $0.command.title,
                            shortcut: $0.command.shortcut,
                            enabled: $0.command.enabled,
                            score: (($0.score * 1000).rounded() / 1000),
                            reason: $0.reason,
                            confidence: $0.confidence.rawValue
                        )
                    }
                )
                print(try encode(payload))
            } else {
                print("查询「\(query)」@ \(target.displayName)｜候选 \(commands.count) 条｜命中 \(results.count) 条")
                for result in results {
                    let score = String(format: "%.2f", result.score)
                    let shortcut = result.command.shortcut ?? "—"
                    let disabled = result.command.enabled ? "" : " (disabled)"
                    print("  \(score)  \(result.command.displayPath)  [\(shortcut)]\(disabled)  <\(result.reason)>")
                }
            }

            if results.isEmpty { exit(2) }

        case "exec":
            let query = args.positional.joined(separator: " ")
            guard !query.isEmpty else {
                throw CLIError.message("exec 需要一个查询词")
            }
            let target = try resolveTarget(args.appQuery)
            let commands = MenuCatalog.commands(for: target)
            let results = MenuMatcher.match(query, in: commands, limit: 1)

            guard let best = results.first else {
                if args.json {
                    let payload = ExecOutput(
                        query: query,
                        app: target.displayName,
                        bundleIdentifier: target.bundleIdentifier,
                        matched: nil,
                        pressed: false,
                        detail: "没有匹配到任何菜单命令",
                        dryRun: args.dryRun
                    )
                    print(try encode(payload))
                } else {
                    FileHandle.standardError.write(Data("没有匹配到任何菜单命令: \(query)\n".utf8))
                }
                exit(2)
            }

            let matchedItem = MatchOutput.Item(
                path: best.command.path,
                title: best.command.title,
                shortcut: best.command.shortcut,
                enabled: best.command.enabled,
                score: ((best.score * 1000).rounded() / 1000),
                reason: best.reason,
                confidence: best.confidence.rawValue
            )

            let outcome: MenuExecutor.Outcome
            if args.dryRun {
                outcome = .success("dry-run：已解析，未执行")
            } else {
                outcome = MenuExecutor.press(path: best.command.path, in: target)
            }

            if args.json {
                let payload = ExecOutput(
                    query: query,
                    app: target.displayName,
                    bundleIdentifier: target.bundleIdentifier,
                    matched: matchedItem,
                    pressed: outcome.pressed,
                    detail: outcome.detail,
                    dryRun: args.dryRun
                )
                print(try encode(payload))
            } else {
                let mark = outcome.pressed ? "OK" : "FAIL"
                print("\(mark)  \(best.command.displayPath)  [\(best.command.shortcut ?? "—")]  score=\(String(format: "%.2f", best.score))")
                print("     \(outcome.detail)")
            }

            if !outcome.pressed { exit(3) }

        default:
            throw CLIError.message("未知子命令: \(args.command)")
        }
    } catch {
        FileHandle.standardError.write(Data("\(error)\n\n\(usage)\n".utf8))
        exit(1)
    }
}

main()
