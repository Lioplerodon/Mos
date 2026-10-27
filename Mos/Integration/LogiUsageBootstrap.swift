//
//  LogiUsageBootstrap.swift
//  Mos
//
//  Pushes Options state into LogiCenter at app launch.
//  Idempotent. Options 订阅驱动: 绑定/热键/应用列表变更时整体刷新 (installOptionsObservers).
//

import Foundation

enum LogiUsageBootstrap {

    /// 上次推送过 appScroll 用量的 app path, 用于 app 移除后推送空集清理注册表残留
    private static var lastPushedAppPaths: Set<String> = []

    /// 订阅 Options 变更, 集中刷新 Logi 用量 (替代偏好面板各处手动 setUsage)
    static func installOptionsObservers() {
        Options.shared.observe([.buttons, .scroll, .application]) { _ in
            refreshAll()
        }
    }

    static func refreshAll() {
        // 1. Button bindings (直读 Options, 不依赖 ButtonUtils 缓存失效的订阅顺序)
        // 全局绑定 + 所有不继承全局的 per-app 绑定 (Application.buttons) 取并集:
        // divert 是设备级的, 只要任一应用用到该 Logi 按键就需要 divert
        var allBindings = Options.shared.buttons.binding
        let appsForButtons = Options.shared.application.applications
        for i in 0..<appsForButtons.count {
            guard let app = appsForButtons.get(by: i), let appButtons = app.buttons else { continue }
            allBindings.append(contentsOf: appButtons.binding)
        }
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: logiButtonCodes(in: allBindings))

        // 2. Global scroll
        for role in ScrollRole.allCases {
            let codes = globalScrollCodes(role: role)
            LogiCenter.shared.setUsage(source: .globalScroll(role), codes: codes)
        }

        // 3. App scroll
        var currentPaths: Set<String> = []
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i) else { continue }
            currentPaths.insert(app.path)
            for role in ScrollRole.allCases {
                let codes = appScrollCodes(app: app, role: role)
                LogiCenter.shared.setUsage(source: .appScroll(key: app.path, role: role), codes: codes)
            }
        }
        // 3b. 已移除 app 的用量清理
        for stalePath in lastPushedAppPaths.subtracting(currentPaths) {
            for role in ScrollRole.allCases {
                LogiCenter.shared.setUsage(source: .appScroll(key: stalePath, role: role), codes: [])
            }
        }
        lastPushedAppPaths = currentPaths
    }

    static func logiButtonCodes(in bindings: [ButtonBinding]) -> Set<UInt16> {
        return Set(
            bindings
                .filter { $0.isEnabled && $0.triggerEvent.type == .mouse }
                .map { $0.triggerEvent.code }
                .filter { LogiCenter.shared.isLogiCode($0) }
        )
    }

    private static func globalScrollCodes(role: ScrollRole) -> Set<UInt16> {
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return Options.shared.scroll.dash
            case .toggle: return Options.shared.scroll.toggle
            case .block:  return Options.shared.scroll.block
            }
        }()
        guard let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else { return [] }
        return [h.code]
    }

    private static func appScrollCodes(app: Application, role: ScrollRole) -> Set<UInt16> {
        guard !app.inherit else { return [] }
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return app.scroll.dash
            case .toggle: return app.scroll.toggle
            case .block:  return app.scroll.block
            }
        }()
        guard let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else { return [] }
        return [h.code]
    }
}
