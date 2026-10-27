import XCTest
@testable import Mos_Debug

final class ButtonUtilsCacheTests: XCTestCase {

    func testInvalidateCache_causesFreshLoad() {
        ButtonUtils.shared.invalidateCache()
        let bindings = ButtonUtils.shared.getButtonBindings()
        XCTAssertNotNil(bindings)
    }

    func testGetButtonBindings_preparesCustomCache() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let loaded = ButtonUtils.shared.getButtonBindings()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].cachedCustomCode, 56)
        XCTAssertEqual(loaded[0].cachedCustomModifiers, 0)

        // Cleanup
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
    }

    /// 绑定变更经 Options 订阅自动失效缓存 (无需手动 invalidateCache)
    func testBindingMutationInvalidatesCacheViaSubscription() {
        let saved = Options.shared.buttons.binding
        defer {
            Options.shared.buttons.binding = saved
            ButtonUtils.shared.invalidateCache()
        }

        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings().count, 1)

        Options.shared.buttons.binding = []
        XCTAssertTrue(ButtonUtils.shared.getButtonBindings().isEmpty,
                      "binding 置空后缓存应经订阅自动失效")
    }
}

/// 分应用按钮绑定 (Application.buttons): nil 表示继承全局, 非 nil 时完全替代全局绑定
final class PerAppButtonBindingTests: XCTestCase {

    private func makeBinding(code: UInt16, action: String) -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: 0, displayComponents: ["🖱\(code + 1)"], deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: true)
    }

    private var savedGlobal: [ButtonBinding] = []

    override func setUp() {
        super.setUp()
        savedGlobal = Options.shared.buttons.binding
    }

    override func tearDown() {
        ButtonUtils.shared.targetApplicationOverrideForTests = nil
        Options.shared.buttons.binding = savedGlobal
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    func testEffectiveBindings_noApplication_usesGlobal() {
        Options.shared.buttons.binding = [makeBinding(code: 3, action: "missionControl")]
        XCTAssertEqual(ButtonUtils.effectiveBindings(for: nil), Options.shared.buttons.binding)
    }

    func testEffectiveBindings_inheritingApplication_usesGlobal() {
        Options.shared.buttons.binding = [makeBinding(code: 3, action: "missionControl")]
        let app = Application(path: "/Applications/Test.app")
        XCTAssertNil(app.buttons)
        XCTAssertEqual(ButtonUtils.effectiveBindings(for: app), Options.shared.buttons.binding)
    }

    func testEffectiveBindings_customApplication_replacesGlobal() {
        Options.shared.buttons.binding = [makeBinding(code: 3, action: "missionControl")]
        let app = Application(path: "/Applications/Test.app")
        let own = OPTIONS_BUTTONS_DEFAULT()
        own.binding = [makeBinding(code: 4, action: "custom::56:0")]
        app.buttons = own
        XCTAssertEqual(ButtonUtils.effectiveBindings(for: app), own.binding)
    }

    func testCustomApplicationWithEmptyList_disablesAllBindings() {
        Options.shared.buttons.binding = [makeBinding(code: 3, action: "missionControl")]
        let app = Application(path: "/Applications/Test.app")
        app.buttons = OPTIONS_BUTTONS_DEFAULT()
        XCTAssertTrue(ButtonUtils.effectiveBindings(for: app).isEmpty)
    }

    func testButtonUtilsResolvesBindingsForTargetApplication() {
        Options.shared.buttons.binding = [makeBinding(code: 3, action: "missionControl")]
        let app = Application(path: "/Applications/Test.app")
        let own = OPTIONS_BUTTONS_DEFAULT()
        own.binding = [makeBinding(code: 4, action: "custom::56:0")]
        app.buttons = own

        ButtonUtils.shared.targetApplicationOverrideForTests = .some(app)
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings().map { $0.triggerEvent.code }, [4])
        XCTAssertTrue(ButtonUtils.shared.getButtonBindings(for: .mouse, code: 3).isEmpty)
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings(for: .mouse, code: 4).count, 1)

        // 切换到未配置的应用 → 回落到全局
        ButtonUtils.shared.targetApplicationOverrideForTests = .some(nil)
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings().map { $0.triggerEvent.code }, [3])
    }

    /// per-app 绑定变更经 .application 订阅自动失效缓存
    func testPerAppMutationInvalidatesCacheViaSubscription() {
        let app = Application(path: "/Applications/Test.app")
        let own = OPTIONS_BUTTONS_DEFAULT()
        app.buttons = own
        ButtonUtils.shared.targetApplicationOverrideForTests = .some(app)
        XCTAssertTrue(ButtonUtils.shared.getButtonBindings().isEmpty)

        own.binding = [makeBinding(code: 4, action: "custom::56:0")]
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings().count, 1,
                       "per-app 绑定变更后缓存应经 .application 订阅自动失效")
    }

    /// 关闭继承时复制全局绑定, 之后两者互不影响
    func testMakeApplicationButtons_copiesGlobalIndependently() {
        Options.shared.buttons.binding = [makeBinding(code: 3, action: "missionControl")]
        let own = PreferencesButtonsWithApplicationViewController.makeApplicationButtons(copying: Options.shared.buttons)
        XCTAssertFalse(own === Options.shared.buttons)
        XCTAssertEqual(own.binding, Options.shared.buttons.binding)

        own.binding.append(makeBinding(code: 4, action: "custom::56:0"))
        XCTAssertEqual(Options.shared.buttons.binding.count, 1)
    }

    /// per-app 按钮绑定随应用列表持久化 (Codable 往返)
    func testApplicationButtonsCodableRoundTrip() throws {
        let app = Application(path: "/Applications/Test.app")
        let own = OPTIONS_BUTTONS_DEFAULT()
        own.binding = [makeBinding(code: 4, action: "custom::56:0")]
        app.buttons = own

        let decoded = try JSONDecoder().decode(Application.self, from: JSONEncoder().encode(app))
        XCTAssertEqual(decoded.buttons?.binding, own.binding)

        let inheriting = try JSONDecoder().decode(Application.self, from: JSONEncoder().encode(Application(path: "/x")))
        XCTAssertNil(inheriting.buttons)
    }
}
