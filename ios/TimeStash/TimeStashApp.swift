import SwiftUI

@main
struct TimeStashApp: App {
    @StateObject private var store = VaultStore()

    init() {
        // ⚠️ 不要用启动参数 `-hasCompletedOnboarding NO` 来重置引导状态。
        // UserDefaults 的「参数域」优先级最高，**会永久覆盖 App 自己写入的值**
        // → 引导走完了，App 仍认为没走完 → 界面卡在引导页。
        // （2026-11-07 实测：UI 测试走完 4 屏后主界面不出现，就是这个原因。）
        // 正确做法是显式写回持久域。
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
        // 清空所有任务。UI 测试需要干净的起点 ——
        // App Group 容器在 UITest 之间**不会**被清掉，上一轮遗留的
        // 「运行中」任务会让恢复提示弹出来打断流程。
        if ProcessInfo.processInfo.arguments.contains("-resetVaultData") {
            try? VaultRepository().deleteAllTasks()
        }
        // 巡检空态屏用：清库之后连「引导页里的体验任务」残留也一并清掉。
        // （deleteAllTasks 已清任务表；这里额外把 onboarding 标记复原，
        //   防上一轮启动写过 hasCompletedOnboarding=true 被参数域盖不掉。）
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    // Demo data for the store screenshots and the demo
                    // recording. Guarded by a launch argument, so it can never
                    // happen in a real user's app.
                    DemoSeed.seedIfRequested(repository: VaultRepository())
                    store.refresh()
                    // A task that was still running when the app was last
                    // closed — the timer kept counting, so the user gets
                    // asked whether they are still working on it.
                    store.detectRecoverableTask()
                }
        }
    }
}

/// Shows the onboarding the first time, then the three main tabs.
struct RootView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            // DebugShot.forcesOnboarding：巡检要截引导 4 屏 ——
            // 用路由强制停在引导页，不依赖「没走过引导」这个状态。
            if hasCompletedOnboarding || DemoSeed.isSkippingOnboarding && !DebugShot.forcesOnboarding {
                MainTabView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .task { store.refresh() }
    }
}

struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            VaultHomeView()
                .tabItem { Label("tab_vault", systemImage: "shippingbox") }
                .tag(0)

            LedgerView()
                .tabItem { Label("tab_ledger", systemImage: "list.bullet") }
                .tag(1)

            StatsView()
                .tabItem { Label("tab_stats", systemImage: "chart.bar.xaxis") }
                .tag(2)
        }
        .onAppear {
            // 巡检路由：直接落在指定 Tab（见 util/DebugShot.swift）。
            if let idx = DebugShot.tabIndex {
                selection = idx
            }
        }
    }
}
