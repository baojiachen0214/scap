//
//  KeystrokeDisplay.swift
//  BetterCapture
//
//  录制时显示按键
//

import Foundation
import AppKit
import Carbon

/// 按键显示管理器
@MainActor
final class KeystrokeDisplay: ObservableObject {
    
    @Published var isEnabled = false
    @Published var currentKeys: [String] = []
    
    private var displayWindow: NSWindow?
    private var keyMonitor: Any?
    private var activeKeys: Set<String> = []
    private var clearTimer: Timer?
    
    private let maxDisplayKeys = 5
    
    // MARK: - Public Methods
    
    func startDisplay() {
        guard displayWindow == nil else { return }
        
        // 创建显示窗口
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        
        let view = KeystrokeView()
        window.contentView = view
        
        displayWindow = window
        
        // 开始监控键盘
        startMonitoring()
        
        // 显示窗口
        window.makeKeyAndOrderFront(nil)
        
        // 动画进入
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }
    }
    
    func stopDisplay() {
        stopMonitoring()
        
        guard let window = displayWindow else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.displayWindow = nil
        }
    }
    
    /// 设置窗口位置
    func setPosition(_ position: KeystrokePosition) {
        guard let window = displayWindow, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let padding: CGFloat = 20
        
        var origin: NSPoint
        
        switch position {
        case .topLeft:
            origin = NSPoint(x: screenFrame.minX + padding, y: screenFrame.maxY - windowSize.height - padding)
        case .topRight:
            origin = NSPoint(x: screenFrame.maxX - windowSize.width - padding, y: screenFrame.maxY - windowSize.height - padding)
        case .bottomLeft:
            origin = NSPoint(x: screenFrame.minX + padding, y: screenFrame.minY + padding)
        case .bottomRight:
            origin = NSPoint(x: screenFrame.maxX - windowSize.width - padding, y: screenFrame.minY + padding)
        case .center:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
        }
        
        window.setFrameOrigin(origin)
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }
    }
    
    private func stopMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let keyName = keyCodeToString(event.keyCode)
        
        if event.type == .keyDown {
            activeKeys.insert(keyName)
        } else {
            activeKeys.remove(keyName)
        }
        
        updateDisplay()
    }
    
    private func updateDisplay() {
        currentKeys = Array(activeKeys).suffix(maxDisplayKeys)
        
        // 重置清除定时器
        clearTimer?.invalidate()
        if !activeKeys.isEmpty {
            clearTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.activeKeys.removeAll()
                    self?.currentKeys.removeAll()
                }
            }
        }
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // 常用键映射
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Esc", 55: "Cmd", 56: "Shift",
            57: "Caps", 58: "Option", 59: "Ctrl", 60: "Shift", 61: "Option",
            62: "Ctrl", 63: "Fn", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12", 105: "←", 106: "→", 125: "↓", 126: "↑"
        ]
        
        return keyMap[keyCode] ?? "Key \(keyCode)"
    }
}

/// 按键显示位置
enum KeystrokePosition: String, CaseIterable, Identifiable {
    case topLeft = "左上"
    case topRight = "右上"
    case bottomLeft = "左下"
    case bottomRight = "右下"
    case center = "居中"
    
    var id: String { rawValue }
}

// MARK: - Keystroke View

private final class KeystrokeView: NSView {
    
    private var keys: [String] = []
    
    func updateKeys(_ keys: [String]) {
        self.keys = keys
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 绘制背景
        let bgRect = bounds.insetBy(dx: 4, dy: 4)
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.addPath(CGPath(roundedRect: bgRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        
        // 绘制按键
        let keySize: CGFloat = 44
        let spacing: CGFloat = 8
        let startX = (bounds.width - (CGFloat(keys.count) * keySize + CGFloat(max(0, keys.count - 1)) * spacing)) / 2
        let y = (bounds.height - keySize) / 2
        
        for (index, key) in keys.enumerated() {
            let x = startX + CGFloat(index) * (keySize + spacing)
            drawKey(key, at: CGRect(x: x, y: y, width: keySize, height: keySize), in: context)
        }
    }
    
    private func drawKey(_ key: String, at rect: CGRect, in context: CGContext) {
        // 按键背景
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        
        // 按键文字
        let text = key
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        attributedString.draw(in: textRect)
    }
}
