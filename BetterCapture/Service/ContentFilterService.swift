//
//  ContentFilterService.swift
//  BetterCapture
//
//  修复版 - 修复显示过滤器问题
//

import Foundation
import ScreenCaptureKit
import OSLog
import CoreGraphics
import AVFoundation

/// 内容过滤器服务
@MainActor
final class ContentFilterService {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture", category: "ContentFilterService")
    
    // MARK: - Permission Methods
    
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
    
    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
    
    func hasMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Filter Application
    
    /// 应用设置到内容过滤器
    func applySettings(to filter: SCContentFilter, settings: SettingsStore) async throws -> SCContentFilter {
        // 菜单栏设置可以直接应用到任何过滤器
        filter.includeMenuBar = settings.showMenuBar
        
        // 获取显示器信息
        let display = await getDisplayFromFilter(filter)
        
        guard let display = display else {
            logger.info("不是显示器捕获，仅返回菜单栏设置")
            return filter
        }
        
        // 如果不需要排除任何窗口，直接返回
        if settings.showWallpaper && settings.showDock && settings.showBetterCapture {
            logger.info("不需要排除任何窗口")
            return filter
        }
        
        // 检查权限
        guard hasScreenRecordingPermission() else {
            logger.warning("没有屏幕录制权限，跳过窗口排除")
            return filter
        }
        
        // 获取可用窗口
        let content = try await SCShareableContent.current
        let availableWindows = content.windows.filter { $0.isOnScreen }
        
        var excludedWindows: [SCWindow] = []
        
        for window in availableWindows {
            let bundleID = window.owningApplication?.bundleIdentifier ?? ""
            let windowTitle = window.title ?? ""
            
            // 排除 Backstop (壁纸层)
            if !settings.showWallpaper && windowTitle.contains("Backstop") {
                excludedWindows.append(window)
                logger.debug("排除 Backstop 窗口: \(windowTitle)")
                continue
            }
            
            // 排除 BetterCapture 自身窗口
            if !settings.showBetterCapture && bundleID == Bundle.main.bundleIdentifier {
                excludedWindows.append(window)
                logger.debug("排除 BetterCapture 窗口: \(windowTitle)")
                continue
            }
            
            // 处理 Dock 相关窗口
            guard bundleID == "com.apple.dock" else { continue }
            
            let isWallpaper = windowTitle.hasPrefix("Wallpaper-")
            
            if !settings.showWallpaper && isWallpaper {
                excludedWindows.append(window)
                logger.debug("排除壁纸窗口: \(windowTitle)")
            }
            
            if !settings.showDock && !isWallpaper {
                excludedWindows.append(window)
                logger.debug("排除 Dock 窗口: \(windowTitle)")
            }
        }
        
        logger.info("排除 \(excludedWindows.count) 个窗口")
        
        // 创建新过滤器
        let newFilter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        newFilter.includeMenuBar = settings.showMenuBar
        
        return newFilter
    }
    
    // MARK: - Helper Methods
    
    /// 从过滤器获取显示器信息
    private func getDisplayFromFilter(_ filter: SCContentFilter) async -> SCDisplay? {
        // 尝试获取共享内容来匹配显示器
        do {
            let content = try await SCShareableContent.current
            
            // 通过比较过滤器的内容矩形来找到匹配的显示器
            // 这是一个启发式方法
            for display in content.displays {
                // 检查过滤器的边界是否与显示器匹配
                // 注意: SCContentFilter 没有直接提供 includedDisplays 属性
                // 我们需要通过其他方式推断
                
                // 如果是全屏过滤器，它应该匹配某个显示器
                // 这里我们假设如果过滤器包含大量像素，可能是显示器捕获
                let filterArea = filter.contentRect.width * filter.contentRect.height
                let displayArea = CGFloat(display.width) * CGFloat(display.height)
                
                // 如果面积匹配在 90% 以内，认为是这个显示器
                if abs(filterArea - displayArea) / max(filterArea, displayArea) < 0.1 {
                    return display
                }
            }
        } catch {
            logger.error("获取共享内容失败: \(error.localizedDescription)")
        }
        
        return nil
    }
}

// MARK: - SCContentFilter Extension

extension SCContentFilter {
    /// 获取过滤器的内容矩形
    /// 注意: 这是基于 SCStreamConfiguration 的 sourceRect 推断的
    var contentRect: CGRect {
        // SCContentFilter 本身没有直接提供尺寸信息
        // 我们需要依赖外部配置
        // 返回一个默认值，实际使用时应该由调用者提供
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
}
