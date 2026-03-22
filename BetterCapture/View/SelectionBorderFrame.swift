//
//  SelectionBorderFrame.swift
//  BetterCapture
//
//  修复版 - 区域选择边框显示
//

import AppKit
import OSLog

/// 显示区域选择边框的覆盖层
@MainActor
final class SelectionBorderFrame {
    
    private var borderWindow: NSWindow?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture",
        category: "SelectionBorderFrame"
    )
    
    // MARK: - Public Methods
    
    /// 显示选择边框
    /// - Parameter screenRect: 屏幕坐标系中的矩形 (NSScreen 坐标，原点在左下角)
    func show(screenRect: CGRect) {
        dismiss() // 先关闭旧的
        
        // 找到包含该矩形的屏幕
        guard let targetScreen = findScreen(for: screenRect) else {
            logger.error("无法找到包含选择区域的屏幕")
            return
        }
        
        // 创建无边框窗口
        let window = NSWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver // 保持在最上层
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true // 不拦截鼠标事件
        
        // 创建边框视图
        let borderView = BorderFrameView(frame: NSRect(origin: .zero, size: screenRect.size))
        window.contentView = borderView
        
        // 显示窗口
        window.makeKeyAndOrderFront(nil)
        
        self.borderWindow = window
        
        logger.info("显示选择边框: \(screenRect)")
        
        // 3秒后自动淡出
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.animateDismiss()
        }
    }
    
    /// 关闭边框
    func dismiss() {
        if let window = borderWindow {
            window.orderOut(nil)
            borderWindow = nil
            logger.info("关闭选择边框")
        }
    }
    
    // MARK: - Private Methods
    
    private func animateDismiss() {
        guard let window = borderWindow else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.dismiss()
        }
    }
    
    private func findScreen(for rect: CGRect) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.intersects(rect) {
                return screen
            }
        }
        return NSScreen.main
    }
}

// MARK: - Border Frame View

private final class BorderFrameView: NSView {
    
    private let borderWidth: CGFloat = 3.0
    private let cornerLength: CGFloat = 20.0
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 填充半透明背景
        context.setFillColor(NSColor.selectedTextBackgroundColor.withAlphaComponent(0.1).cgColor)
        context.fill(bounds)
        
        // 绘制边框
        context.setLineWidth(borderWidth)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        
        let w = bounds.width
        let h = bounds.height
        let bw = borderWidth
        
        // 左上角
        context.move(to: CGPoint(x: 0, y: cornerLength))
        context.addLine(to: CGPoint(x: 0, y: h - cornerLength))
        context.move(to: CGPoint(x: 0, y: h - bw/2))
        context.addLine(to: CGPoint(x: cornerLength, y: h - bw/2))
        
        // 右上角
        context.move(to: CGPoint(x: w - cornerLength, y: h - bw/2))
        context.addLine(to: CGPoint(x: w, y: h - bw/2))
        context.move(to: CGPoint(x: w - bw/2, y: h - cornerLength))
        context.addLine(to: CGPoint(x: w - bw/2, y: 0))
        
        // 右下角
        context.move(to: CGPoint(x: w - bw/2, y: cornerLength))
        context.addLine(to: CGPoint(x: w - bw/2, y: 0))
        context.move(to: CGPoint(x: w - cornerLength, y: bw/2))
        context.addLine(to: CGPoint(x: 0, y: bw/2))
        
        // 左下角
        context.move(to: CGPoint(x: cornerLength, y: bw/2))
        context.addLine(to: CGPoint(x: 0, y: bw/2))
        context.move(to: CGPoint(x: bw/2, y: cornerLength))
        context.addLine(to: CGPoint(x: bw/2, y: h))
        
        context.strokePath()
        
        // 绘制尺寸标签
        drawSizeLabel(in: context, size: bounds.size)
    }
    
    private func drawSizeLabel(in context: CGContext, size: NSSize) {
        let text = "\(Int(size.width)) × \(Int(size.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemRed
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        // 背景
        let padding: CGFloat = 4
        let bgRect = CGRect(
            x: (size.width - textSize.width) / 2 - padding,
            y: (size.height - textSize.height) / 2 - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(bgRect)
        
        // 文字
        attributedString.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
    }
}
