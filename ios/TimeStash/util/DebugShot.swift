import Foundation

/// **巡检 / 商店截图用的调试路由入口（只影响 DEBUG 构建）。**
///
/// ⚠️ 为什么不用一堆布尔开关（2026-11-10 CommutePilot 实测教训）：
/// 加一屏要改三处（开关表 / 页面清单 / 守卫测试），漏一处就静默失效
/// → sweep「截到别的界面却报告通过」（假绿）。
/// → **一张路由表 + 一个解析器 + 一个守卫测试**。
///
/// ⚠️ 路由值一律从 `ProcessInfo.processInfo.arguments` 直接读，
/// **不要经 UserDefaults** —— 参数域的值会盖掉 App 自己写的持久域值
/// （TimeStashApp.swift 里 -resetOnboarding 的注释就是这个坑）。
enum DebugShot {

    /// 页面清单里允许出现的路由名。
    ///
    /// ⚠️ 新增路由必须同时：① 加进这张表；② 在对应界面真的接上
    /// （否则那一屏截到的是父界面）；③ 写进 `scripts/page_sweep/pages.txt`。
    /// 守卫测试 `DebugShotRouteGuardTests` 会核对 ①③。
    static let knownRoutes: Set<String> = [
        // 引导 4 页
        "onboarding0", "onboarding1", "onboarding2", "onboarding3",
        // 主 Tab 3 个
        "vault", "ledger", "stats",
        // 弹层
        "newTask", "timer", "timerPaused",
        // 恢复弹窗（关 App 时还有任务在计时）
        "resume",
        // 空状态（没有种子数据时的三个 Tab）
        "vaultEmpty", "ledgerEmpty", "statsEmpty",
    ]

    /// 路由参数名。
    static let routeFlag = "-TS_SHOT_ROUTE"

    /// 当前路由（从启动参数解析）。非 DEBUG 构建恒为 nil ——
    /// 正式包不该被启动参数撬开弹层。
    static var route: String? {
        #if DEBUG
        return value(of: routeFlag, in: ProcessInfo.processInfo.arguments)
        #else
        return nil
        #endif
    }

    /// 是否强制显示引导页（截引导 4 屏用）。
    static var forcesOnboarding: Bool {
        guard let r = route else { return false }
        return r.hasPrefix("onboarding")
    }

    /// 引导页页码（0...3）。越界要夹住 —— onboarding9 不能让 tag 指到不存在的页。
    static var onboardingPageIndex: Int {
        onboardingPageIndex(for: route)
    }

    /// 路由名 → 引导页页码（纯函数，便于单测）。
    static func onboardingPageIndex(for route: String?) -> Int {
        guard let r = route, r.hasPrefix("onboarding") else { return 0 }
        return max(0, min(3, Int(r.dropFirst("onboarding".count)) ?? 0))
    }

    /// 主 Tab 下标（vault=0 / ledger=1 / stats=2）。nil = 不干预。
    static var tabIndex: Int? {
        guard let r = route else { return nil }
        switch r {
        case "vault", "vaultEmpty": return 0
        case "ledger", "ledgerEmpty": return 1
        case "stats", "statsEmpty": return 2
        default: return nil
        }
    }

    /// 巡检时是否跳过引导（主界面相关路由都要跳）。
    static var skipsOnboarding: Bool {
        guard let r = route else { return false }
        return !r.hasPrefix("onboarding")
    }

    /// 取 flag 后面的值。
    ///
    /// ⚠️ 下一个 token 以 "-" 开头说明那不是值，是下一个 flag
    /// （`["-TS_SHOT_ROUTE", "-TS_SHOT_TAB"]` → route 不该等于 "-TS_SHOT_TAB"）。
    /// 不这么判的话路由会串到别的开关上，截到别的界面却报告通过。
    static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        if v.isEmpty || v.hasPrefix("-") { return nil }
        return v
    }
}
