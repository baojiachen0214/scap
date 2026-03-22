//
//  UpdaterService.swift
//  BetterCapture
//
//  修复版 - 稳定的自动更新服务
//

import Foundation
import Sparkle
import OSLog

/// Sparkle 自动更新服务
@MainActor
@Observable
final class UpdaterService {
    
    // MARK: - Properties
    
    /// 是否可以检查更新
    private(set) var canCheckForUpdates = false
    
    /// 自动检查更新
    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }
    
    /// 上次检查更新时间
    var lastUpdateCheckDate: Date? {
        updater?.lastUpdateCheckDate
    }
    
    /// Sparkle 控制器
    private var controller: SPUStandardUpdaterController?
    
    /// Sparkle 更新器
    private var updater: SPUUpdater? {
        controller?.updater
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture", category: "UpdaterService")
    
    // MARK: - Initialization
    
    init() {
        setupUpdater()
    }
    
    // MARK: - Setup
    
    private func setupUpdater() {
        // 延迟初始化以确保主运行循环已启动
        DispatchQueue.main.async { [weak self] in
            self?.initializeController()
        }
    }
    
    private func initializeController() {
        do {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            
            // 监听更新器状态
            setupObservation()
            
            logger.info("Sparkle 更新器初始化成功")
            
        } catch {
            logger.error("Sparkle 更新器初始化失败: \(error.localizedDescription)")
        }
    }
    
    private func setupObservation() {
        // 使用定时器检查状态，避免 KVO 问题
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkUpdaterState()
            }
        }
    }
    
    private func checkUpdaterState() {
        guard let updater = updater else {
            canCheckForUpdates = false
            return
        }
        
        canCheckForUpdates = updater.canCheckForUpdates
        
        // 如果还不能检查，继续等待
        if !canCheckForUpdates {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.checkUpdaterState()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// 手动检查更新
    func checkForUpdates() {
        guard let updater = updater, updater.canCheckForUpdates else {
            logger.warning("更新器未就绪，无法检查更新")
            return
        }
        
        updater.checkForUpdates()
        logger.info("开始检查更新")
    }
    
    /// 检查更新并显示 UI
    func checkForUpdatesInBackground() {
        guard let updater = updater else { return }
        updater.checkForUpdatesInBackground()
    }
    
    /// 重置自动检查间隔
    func resetUpdateCycle() {
        guard let updater = updater else { return }
        updater.resetUpdateCycle()
    }
}
