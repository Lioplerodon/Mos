//
//  ButtonUtils.swift
//  Mos
//  按钮绑定工具类 - 获取配置和管理绑定 (带缓存)
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

struct ButtonBindingTriggerKey: Hashable {
    let type: EventType
    let code: UInt16
}

class ButtonUtils {

    // 单例
    static let shared = ButtonUtils()
    init() {
        // 绑定组变更时自动失效缓存 (订阅者为进程级单例, 无需注销)
        // .application: per-app 按钮绑定 (Application.buttons) 与应用列表变更
        Options.shared.observe([.buttons, .application]) { [weak self] _ in
            self?.invalidateCache()
        }
        // 前台应用切换时失效缓存, 下次事件按新应用解析绑定 (避免在事件热路径上查询前台应用)
        frontmostRunningApplication = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostApplicationDidChange(app)
        }
    }

    // MARK: - 分应用支持

    /// 当前前台应用 (由 NSWorkspace 激活通知维护)
    private var frontmostRunningApplication: NSRunningApplication?

    #if DEBUG
    /// 测试钩子: 非 nil 时替代前台应用解析结果 (.some(nil) 表示 "无匹配应用")
    var targetApplicationOverrideForTests: Application?? = nil {
        didSet { isDirty = true }
    }
    #endif

    private func frontmostApplicationDidChange(_ app: NSRunningApplication?) {
        frontmostRunningApplication = app
        isDirty = true
    }

    /// 获取当前前台应用在分应用列表中的配置对象
    /// - Returns: Application 对象, 未添加到列表时返回 nil
    func getTargetApplication() -> Application? {
        #if DEBUG
        if let override = targetApplicationOverrideForTests { return override }
        #endif
        return ScrollUtils.shared.getTargetApplication(from: frontmostRunningApplication)
    }

    /// 解析某个应用实际生效的绑定列表
    /// - app 为 nil 或继承全局 (buttons == nil) 时返回全局绑定
    static func effectiveBindings(for app: Application?) -> [ButtonBinding] {
        return app?.getButtonBindings() ?? Options.shared.buttons.binding
    }

    // MARK: - 缓存

    /// 缓存的绑定列表 (已预解析 custom:: 字段)
    private var cachedBindings: [ButtonBinding] = []
    private var cachedBindingsByTriggerKey: [ButtonBindingTriggerKey: [ButtonBinding]] = [:]
    private var isDirty = true

    // MARK: - 获取按钮绑定配置

    /// 获取当前应用的按钮绑定配置 (带缓存和预解析)
    /// - Returns: 按钮绑定列表
    func getButtonBindings() -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindings
    }

    func getButtonBindings(for type: EventType, code: UInt16) -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindingsByTriggerKey[ButtonBindingTriggerKey(type: type, code: code)] ?? []
    }

    func getBestMatchingBinding(
        for event: InputEvent,
        where predicate: ((ButtonBinding) -> Bool)? = nil
    ) -> ButtonBinding? {
        let candidates = getButtonBindings(for: event.type, code: event.code)
        var bestBinding: ButtonBinding?
        var bestPriority = Int.min

        for binding in candidates {
            guard binding.isEnabled else {
                continue
            }
            if let predicate, !predicate(binding) {
                continue
            }
            guard let priority = binding.triggerEvent.matchPriority(for: event) else {
                continue
            }
            if priority > bestPriority {
                bestBinding = binding
                bestPriority = priority
            }
        }

        return bestBinding
    }

    /// 标记缓存失效 (绑定变更后调用)
    func invalidateCache() {
        assertMainThread()
        isDirty = true
    }

    private func refreshCacheIfNeeded() {
        guard isDirty else { return }

        cachedBindings = Self.effectiveBindings(for: getTargetApplication()).map { binding in
            var b = binding
            b.prepareCustomCache()
            return b
        }

        cachedBindingsByTriggerKey = Dictionary(grouping: cachedBindings) { binding in
            ButtonBindingTriggerKey(
                type: binding.triggerEvent.type,
                code: binding.triggerEvent.code
            )
        }

        isDirty = false
    }
}
