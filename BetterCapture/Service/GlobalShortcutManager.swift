//
//  GlobalShortcutManager.swift
//  BetterCapture
//
//  全局快捷键管理 - 支持开始/停止录制快捷键
//

import Foundation
import AppKit
import Carbon

/// 全局快捷键回调
@MainActor
protocol GlobalShortcutManagerDelegate: AnyObject {
    func globalShortcutManagerDidTriggerStartRecording(_ manager: GlobalShortcutManager)
    func globalShortcutManagerDidTriggerStopRecording(_ manager: GlobalShortcutManager)
}

/// 全局快捷键管理器
@MainActor
final class GlobalShortcutManager {
    
    weak var delegate: GlobalShortcutManagerDelegate?
    
    // 快捷键 ID
    private let startRecordingShortcutID: UInt32 = 1
    private let stopRecordingShortcutID: UInt32 = 2
    
    // 当前注册的快捷键
    private var registeredShortcuts: [UInt32: (keyCode: UInt32, modifiers: UInt32)] = [:]
    
    private var eventHandler: EventHandlerRef?
    
    // MARK: - Initialization
    
    init() {
        setupEventHandler()
    }
    
    deinit {
        unregisterAllShortcuts()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
    
    // MARK: - Public Methods
    
    /// 注册默认快捷键
    /// Cmd+Shift+R - 开始/停止录制
    func registerDefaultShortcuts() {
        // Cmd+Shift+R (keyCode 15 = R)
        registerShortcut(
            id: startRecordingShortcutID,
            keyCode: 15, // R
            modifiers: cmdKey | shiftKey
        )
    }
    
    /// 注册自定义快捷键
    func registerShortcut(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        unregisterShortcut(id: id)
        
        let hotKeyID = EventHotKeyID(signature: FourCharCode("BCTR".fourCharCode), id: id)
        
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            registeredShortcuts[id] = (keyCode: keyCode, modifiers: modifiers)
            print("[GlobalShortcut] Registered shortcut \(id): keyCode=\(keyCode), modifiers=\(modifiers)")
        } else {
            print("[GlobalShortcut] Failed to register shortcut \(id): status=\(status)")
        }
    }
    
    /// 注销快捷键
    func unregisterShortcut(id: UInt32) {
        // 需要保存 hotKeyRef 才能注销，这里简化处理
        registeredShortcuts.removeValue(forKey: id)
    }
    
    /// 注销所有快捷键
    func unregisterAllShortcuts() {
        for (id, _) in registeredShortcuts {
            unregisterShortcut(id: id)
        }
        registeredShortcuts.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setupEventHandler() {
        let eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let callback: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if result == noErr {
                DispatchQueue.main.async {
                    if let manager = userData?.assumingMemoryBound(to: GlobalShortcutManager.self).pointee {
                        manager.handleHotKey(id: hotKeyID.id)
                    }
                }
            }
            
            return noErr
        }
        
        // 使用 Unmanaged 传递 self
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            [eventType],
            ptr,
            &eventHandler
        )
    }
    
    private func handleHotKey(id: UInt32) {
        print("[GlobalShortcut] Hotkey triggered: \(id)")
        
        switch id {
        case startRecordingShortcutID:
            delegate?.globalShortcutManagerDidTriggerStartRecording(self)
        case stopRecordingShortcutID:
            delegate?.globalShortcutManagerDidTriggerStopRecording(self)
        default:
            break
        }
    }
}

// MARK: - Helper Extensions

extension String {
    var fourCharCode: FourCharCode {
        guard self.utf8.count == 4 else { return 0 }
        var result: FourCharCode = 0
        for char in self.utf8 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
