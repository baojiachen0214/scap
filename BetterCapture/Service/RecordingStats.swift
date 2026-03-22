//
//  RecordingStats.swift
//  BetterCapture
//
//  录制统计信息 - 码率、预计文件大小、磁盘空间
//

import Foundation
import OSLog

/// 录制统计信息
@MainActor
@Observable
final class RecordingStats {
    
    // MARK: - Published Properties
    
    /// 当前瞬时码率 (bps)
    private(set) var currentBitrate: Int64 = 0
    
    /// 平均码率 (bps)
    private(set) var averageBitrate: Int64 = 0
    
    /// 预计文件大小 (字节)
    private(set) var estimatedFileSize: Int64 = 0
    
    /// 剩余磁盘空间 (字节)
    private(set) var availableDiskSpace: Int64 = 0
    
    /// 预计剩余录制时间 (秒)
    private(set) var estimatedRemainingTime: TimeInterval = 0
    
    /// 录制帧率
    private(set) var actualFrameRate: Double = 0
    
    /// 丢帧数
    private(set) var droppedFrames: Int = 0
    
    // MARK: - Private Properties
    
    private var bytesWritten: Int64 = 0
    private var lastUpdateTime: Date?
    private var lastBytesWritten: Int64 = 0
    private var bitrateHistory: [Int64] = []
    private let maxHistorySize = 30 // 30秒历史
    
    private var frameCount: Int = 0
    private var lastFrameTime: Date?
    private var frameTimeHistory: [TimeInterval] = []
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture",
        category: "RecordingStats"
    )
    
    // MARK: - Public Methods
    
    /// 开始记录
    func startRecording() {
        bytesWritten = 0
        lastUpdateTime = Date()
        lastBytesWritten = 0
        bitrateHistory.removeAll()
        frameCount = 0
        lastFrameTime = nil
        frameTimeHistory.removeAll()
        droppedFrames = 0
        
        updateDiskSpace()
    }
    
    /// 更新写入字节数
    func updateBytesWritten(_ bytes: Int64) {
        bytesWritten = bytes
        
        let now = Date()
        
        // 计算瞬时码率
        if let lastTime = lastUpdateTime {
            let timeDelta = now.timeIntervalSince(lastTime)
            if timeDelta > 0 {
                let bytesDelta = bytesWritten - lastBytesWritten
                let bitrate = Int64(Double(bytesDelta * 8) / timeDelta)
                currentBitrate = bitrate
                
                // 添加到历史
                bitrateHistory.append(bitrate)
                if bitrateHistory.count > maxHistorySize {
                    bitrateHistory.removeFirst()
                }
                
                // 计算平均码率
                averageBitrate = bitrateHistory.reduce(0, +) / Int64(bitrateHistory.count)
            }
        }
        
        lastUpdateTime = now
        lastBytesWritten = bytesWritten
        
        // 更新预计文件大小
        updateEstimatedFileSize()
        
        // 更新剩余时间
        updateRemainingTime()
    }
    
    /// 记录帧
    func recordFrame(dropped: Bool = false) {
        let now = Date()
        
        if dropped {
            droppedFrames += 1
            return
        }
        
        frameCount += 1
        
        if let lastTime = lastFrameTime {
            let frameTime = now.timeIntervalSince(lastTime)
            frameTimeHistory.append(frameTime)
            if frameTimeHistory.count > 30 {
                frameTimeHistory.removeFirst()
            }
            
            // 计算实际帧率
            let avgFrameTime = frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
            if avgFrameTime > 0 {
                actualFrameRate = 1.0 / avgFrameTime
            }
        }
        
        lastFrameTime = now
    }
    
    /// 停止记录
    func stopRecording() {
        lastUpdateTime = nil
    }
    
    // MARK: - Formatters
    
    /// 格式化的码率 (如 "6.5 Mbps")
    var formattedBitrate: String {
        formatBitrate(currentBitrate)
    }
    
    /// 格式化的平均码率
    var formattedAverageBitrate: String {
        formatBitrate(averageBitrate)
    }
    
    /// 格式化的预计文件大小
    var formattedEstimatedSize: String {
        formatFileSize(estimatedFileSize)
    }
    
    /// 格式化的磁盘空间
    var formattedAvailableSpace: String {
        formatFileSize(availableDiskSpace)
    }
    
    /// 格式化的剩余时间
    var formattedRemainingTime: String {
        if estimatedRemainingTime < 60 {
            return "\(Int(estimatedRemainingTime))s"
        } else if estimatedRemainingTime < 3600 {
            return "\(Int(estimatedRemainingTime / 60))m"
        } else {
            return String(format: "%.1fh", estimatedRemainingTime / 3600)
        }
    }
    
    /// 格式化的实际帧率
    var formattedFrameRate: String {
        String(format: "%.1f FPS", actualFrameRate)
    }
    
    // MARK: - Private Methods
    
    private func updateEstimatedFileSize() {
        // 基于当前码率预测文件大小
        // 假设录制时长为当前已录制时长的2倍 (预留空间)
        // 或者简单预测：当前大小 + (平均码率 * 剩余时间)
        estimatedFileSize = bytesWritten
    }
    
    private func updateRemainingTime() {
        if averageBitrate > 0 && availableDiskSpace > bytesWritten {
            let remainingBytes = availableDiskSpace - bytesWritten
            estimatedRemainingTime = Double(remainingBytes * 8) / Double(averageBitrate)
        } else {
            estimatedRemainingTime = 0
        }
    }
    
    private func updateDiskSpace() {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            availableDiskSpace = Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            logger.error("无法获取磁盘空间: \(error.localizedDescription)")
        }
    }
    
    private func formatBitrate(_ bps: Int64) -> String {
        if bps >= 1_000_000_000 {
            return String(format: "%.2f Gbps", Double(bps) / 1_000_000_000)
        } else if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.0f kbps", Double(bps) / 1_000)
        } else {
            return "\(bps) bps"
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
