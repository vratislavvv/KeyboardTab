import AppKit

/// The switcher panel — mimics the system input-source HUD, with flags.
final class HUDPanel: NSPanel {
    private let listView = HUDListView()
    private let blur = NSVisualEffectView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantLight)
        // A mask image (not a layer corner radius) is what the window server uses for the
        // shape and shadow of a borderless window, so the corners stay truly transparent.
        blur.maskImage = HUDPanel.roundedMask(radius: HUDListView.cornerRadius)

        listView.autoresizingMask = [.width, .height]
        blur.addSubview(listView)
        contentView = blur
    }

    func show(items: [InputSource], selected: Int) {
        listView.items = items
        listView.selected = selected
        let size = listView.preferredSize()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        setFrame(NSRect(origin: origin, size: size), display: true)
        listView.frame = blur.bounds
        listView.needsDisplay = true
        alphaValue = 1
        orderFrontRegardless()
        invalidateShadow()
    }

    /// Stretchable rounded-rect mask: only the straight middle part stretches.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    func update(selected: Int) {
        listView.selected = selected
        listView.needsDisplay = true
    }

    func dismiss(animated: Bool = true) {
        guard isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            })
        } else {
            orderOut(nil)
        }
    }
}

final class HUDListView: NSView {
    static let cornerRadius: CGFloat = 26
    private let padding: CGFloat = 20
    private let rowHeight: CGFloat = 60
    private let minWidth: CGFloat = 247
    private let flagGap: CGFloat = 12
    private let textInset: CGFloat = 28

    var items: [InputSource] = []
    var selected = 0

    override var isFlipped: Bool { true }

    private func attrs(selected: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: selected ? 23 : 22, weight: .regular),
            .foregroundColor: NSColor.black.withAlphaComponent(selected ? 0.88 : 0.62),
        ]
    }

    private var flagAttrs: [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: 28)] }

    private func contentWidth(_ item: InputSource, selected: Bool) -> CGFloat {
        let flag = (item.flag as NSString).size(withAttributes: flagAttrs).width
        let text = (item.name as NSString).size(withAttributes: attrs(selected: selected)).width
        return flag + flagGap + text
    }

    func preferredSize() -> NSSize {
        let widest = items.map { contentWidth($0, selected: true) }.max() ?? 0
        let width = max(minWidth, ceil(widest) + 2 * (padding + textInset))
        return NSSize(width: width, height: CGFloat(items.count) * rowHeight + 2 * padding)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Slight gray tint like the system HUD.
        NSColor(white: 0.55, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()

        for (i, item) in items.enumerated() {
            let row = NSRect(x: padding, y: padding + CGFloat(i) * rowHeight,
                             width: bounds.width - 2 * padding, height: rowHeight)
            let isSel = i == selected
            if isSel {
                NSColor.black.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: row, xRadius: 13, yRadius: 13).fill()
            }

            let textAttrs = attrs(selected: isSel)
            let flagSize = (item.flag as NSString).size(withAttributes: flagAttrs)
            let textSize = (item.name as NSString).size(withAttributes: textAttrs)
            let total = flagSize.width + flagGap + textSize.width
            var x = row.midX - total / 2

            (item.flag as NSString).draw(
                at: NSPoint(x: x, y: row.midY - flagSize.height / 2), withAttributes: flagAttrs)
            x += flagSize.width + flagGap
            (item.name as NSString).draw(
                at: NSPoint(x: x, y: row.midY - textSize.height / 2), withAttributes: textAttrs)
        }
    }
}
