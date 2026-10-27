//
//  PreferencesButtonsWithApplicationViewController.swift
//  Mos
//  分应用按钮绑定窗口容器 (对应滚动的 PreferencesScrollingWithApplicationViewController)
//  顶部为应用信息与 "继承全局设置" 开关, 下方嵌入按钮设置界面 (storyboard: buttons)
//

import Cocoa

class PreferencesButtonsWithApplicationViewController: NSViewController {

    // 布局
    private static let headerHeight: CGFloat = 38
    private static let headerMargin: CGFloat = 20
    private static let contentSize = NSSize(width: 450, height: 321)

    // Target application
    private let targetApplication: Application
    private var contentViewController: PreferencesButtonsViewController?
    /// 弹窗关闭回调 (用于刷新应用列表中该行的状态)
    var onDismiss: (() -> Void)?
    // UI Elements
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let inheritCheckBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(application: Application) {
        targetApplication = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let headerTotal = Self.headerHeight + Self.headerMargin * 2
        let size = NSSize(width: Self.contentSize.width, height: Self.contentSize.height + headerTotal)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        view = root
        preferredContentSize = size

        // 顶部信息栏
        let header = NSBox()
        header.boxType = .custom
        header.borderWidth = 1
        header.cornerRadius = 6
        header.borderColor = NSColor.gridColor
        header.fillColor = .clear
        header.titlePosition = .noTitle
        header.contentViewMargins = .zero
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        iconView.image = targetApplication.getIcon()
        iconView.toolTip = targetApplication.path
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameField.stringValue = targetApplication.getName()
        nameField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        inheritCheckBox.title = NSLocalizedString("app_buttons_inherit_global", comment: "Per-app buttons popover: inherit global button bindings checkbox")
        inheritCheckBox.imagePosition = .imageRight
        inheritCheckBox.controlSize = .small
        inheritCheckBox.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        inheritCheckBox.target = self
        inheritCheckBox.action = #selector(inheritGlobalSettingClick(_:))
        inheritCheckBox.translatesAutoresizingMaskIntoConstraints = false

        let headerContent: NSView = header.contentView ?? header
        headerContent.addSubview(iconView)
        headerContent.addSubview(nameField)
        headerContent.addSubview(inheritCheckBox)

        // 按钮设置界面 (复用 storyboard 中的 buttons 场景)
        let content = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.buttons) as PreferencesButtonsViewController
        content.currentTargetApplication = targetApplication
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content.view)
        contentViewController = content

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.headerMargin),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.headerMargin),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.headerMargin),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            iconView.leadingAnchor.constraint(equalTo: headerContent.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: inheritCheckBox.leadingAnchor, constant: -8),

            inheritCheckBox.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor, constant: -10),
            inheritCheckBox.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),

            content.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Self.headerMargin),
            content.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.view.widthAnchor.constraint(equalToConstant: Self.contentSize.width),
            content.view.heightAnchor.constraint(equalToConstant: Self.contentSize.height),
        ])

        syncViewWithOptions()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDismiss?()
    }

    // 继承
    // 关闭继承: 以全局绑定的副本作为该应用的初始配置
    // 开启继承: 删除该应用的自定义绑定 (buttons = nil 即继承全局), 有差异时先确认
    // 缓存失效与 Logi divert 用量同步由 Options 订阅 (.application) 自动完成
    @objc private func inheritGlobalSettingClick(_ sender: NSButton) {
        let wantsInherit = sender.state == .on
        if wantsInherit {
            if let own = targetApplication.buttons,
               own.binding != Options.shared.buttons.binding,
               !confirmDiscardCustomBindings(count: own.binding.count) {
                syncViewWithOptions()
                return
            }
            targetApplication.buttons = nil
        } else {
            targetApplication.buttons = Self.makeApplicationButtons(copying: Options.shared.buttons)
        }
        syncViewWithOptions()
        contentViewController?.loadOptionsToView()
    }

    /// 以全局按钮配置的副本创建分应用按钮配置 (独立容器, 修改不影响全局)
    static func makeApplicationButtons(copying global: OPTIONS_BUTTONS_DEFAULT) -> OPTIONS_BUTTONS_DEFAULT {
        let own = OPTIONS_BUTTONS_DEFAULT()
        own.binding = global.binding
        return own
    }

    private func confirmDiscardCustomBindings(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("app_buttons_inherit_confirm_title", comment: "Per-app buttons: confirm discarding custom bindings when re-enabling inherit")
        alert.informativeText = String(
            format: NSLocalizedString("app_buttons_inherit_confirm_message", comment: "Per-app buttons: explains that %d custom bindings for this app will be removed"),
            count
        )
        alert.addButton(withTitle: NSLocalizedString("app_buttons_inherit_confirm_ok", comment: "Per-app buttons: confirm button to discard custom bindings"))
        alert.addButton(withTitle: NSLocalizedString("app_buttons_inherit_confirm_cancel", comment: "Per-app buttons: cancel button"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func syncViewWithOptions() {
        inheritCheckBox.state = targetApplication.buttons == nil ? .on : .off
    }
}
