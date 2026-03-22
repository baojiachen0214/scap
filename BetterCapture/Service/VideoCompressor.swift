//
//  VideoCompressor.swift
//  BetterCapture
//
//  视频压缩转码 - 录完后转码减小体积
//

import Foundation
import AVFoundation
import OSLog

/// 视频压缩质量选项
enum CompressionQuality: String, CaseIterable, Identifiable {
    case high = "高质量 (原画质 80%)"
    case medium = "中等质量 (原画质 60%)"
    case low = "低质量 (原画质 40%)"
    case veryLow = "极低质量 (适合分享)"
    
    var id: String { rawValue }
    
    /// 目标比特率 (相对于原始)
    var bitrateRatio: Double {
        switch self {
        case .high: return 0.8
        case .medium: return 0.5
        case .low: return 0.3
        case .veryLow: return 0.15
        }
    }
    
    /// CRF 质量值 (x264/x265)
    var crfValue: Int {
        switch self {
        case .high: return 18
        case .medium: return 23
        case .low: return 28
        case .veryLow: return 35
        }
    }
}

/// 视频压缩转码器
@MainActor
final class VideoCompressor: ObservableObject {
    
    @Published var isCompressing = false
    @Published var progress: Double = 0
    @Published var currentTask: CompressionTask?
    
    private var exportSession: AVAssetExportSession?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture",
        category: "VideoCompressor"
    )
    
    // MARK: - Compression Task
    
    struct CompressionTask: Identifiable {
        let id = UUID()
        let inputURL: URL
        let outputURL: URL
        let quality: CompressionQuality
        var status: Status = .pending
        var progress: Double = 0
        
        enum Status {
            case pending
            case compressing
            case completed
            case failed(Error)
        }
    }
    
    // MARK: - Public Methods
    
    /// 压缩视频
    /// - Parameters:
    ///   - inputURL: 输入视频文件
    ///   - quality: 压缩质量
    ///   - outputURL: 可选的输出路径
    /// - Returns: 输出文件 URL
    func compress(
        inputURL: URL,
        quality: CompressionQuality = .medium,
        outputURL: URL? = nil
    ) async throws -> URL {
        let finalOutputURL = outputURL ?? generateOutputURL(for: inputURL, quality: quality)
        
        await MainActor.run {
            isCompressing = true
            progress = 0
        }
        
        defer {
            Task { @MainActor in
                isCompressing = false
            }
        }
        
        let asset = AVAsset(url: inputURL)
        
        // 获取原始视频信息
        let originalBitrate = try await getVideoBitrate(asset: asset)
        let targetBitrate = Int(Double(originalBitrate) * quality.bitrateRatio)
        
        logger.info("开始压缩: \(inputURL.lastPathComponent)")
        logger.info("原始码率: \(originalBitrate / 1000) kbps")
        logger.info("目标码率: \(targetBitrate / 1000) kbps")
        
        // 使用 AVAssetExportSession 进行压缩
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CompressionError.failedToCreateExportSession
        }
        
        self.exportSession = exportSession
        
        exportSession.outputURL = finalOutputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // 配置视频压缩参数
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = try await getVideoSize(asset: asset)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // 使用自定义压缩设置
        let compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]
        
        exportSession.videoComposition = videoComposition
        
        // 监控进度
        let progressTask = Task {
            while exportSession.status == .exporting {
                await MainActor.run {
                    self.progress = Double(exportSession.progress)
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        // 开始导出
        await exportSession.export()
        
        progressTask.cancel()
        
        await MainActor.run {
            self.progress = 1.0
        }
        
        switch exportSession.status {
        case .completed:
            logger.info("压缩完成: \(finalOutputURL.lastPathComponent)")
            
            // 计算压缩比
            let originalSize = try FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int64 ?? 0
            let compressedSize = try FileManager.default.attributesOfItem(atPath: finalOutputURL.path)[.size] as? Int64 ?? 0
            let ratio = Double(compressedSize) / Double(originalSize)
            logger.info("压缩比: \(Int(ratio * 100))% (节省了 \(Int((1-ratio)*100))%)")
            
            return finalOutputURL
            
        case .failed:
            if let error = exportSession.error {
                throw CompressionError.exportFailed(error)
            } else {
                throw CompressionError.unknownError
            }
            
        case .cancelled:
            throw CompressionError.cancelled
            
        default:
            throw CompressionError.unknownError
        }
    }
    
    /// 取消当前压缩任务
    func cancel() {
        exportSession?.cancelExport()
        logger.info("压缩已取消")
    }
    
    /// 批量压缩
    func batchCompress(
        urls: [URL],
        quality: CompressionQuality = .medium
    ) async -> [Result<URL, Error>] {
        var results: [Result<URL, Error>] = []
        
        for url in urls {
            do {
                let outputURL = try await compress(inputURL: url, quality: quality)
                results.append(.success(outputURL))
            } catch {
                results.append(.failure(error))
            }
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func generateOutputURL(for inputURL: URL, quality: CompressionQuality) -> URL {
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let suffix: String
        switch quality {
        case .high: suffix = "_compressed_high"
        case .medium: suffix = "_compressed"
        case .low: suffix = "_compressed_low"
        case .veryLow: suffix = "_compressed_tiny"
        }
        return inputURL.deletingLastPathComponent()
            .appendingPathComponent("\(filename)\(suffix).mp4")
    }
    
    private func getVideoBitrate(asset: AVAsset) async throws -> Int {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return 6_000_000 // 默认 6Mbps
        }
        
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            return 6_000_000
        }
        
        // 获取比特率
        let bitRate = CMVideoFormatDescriptionGetExtension(
            formatDescription,
            extensionKey: "BitRate"
        )
        
        if let bitRate = bitRate, CFGetTypeID(bitRate) == CFNumberGetTypeID() {
            var value: Int32 = 0
            CFNumberGetValue(bitRate as! CFNumber, .intType, &value)
            return Int(value)
        }
        
        // 估算比特率
        let duration = try await asset.load(.duration)
        let fileSize = try FileManager.default.attributesOfItem(atPath: asset.url.path)[.size] as? Int64 ?? 0
        let durationSeconds = CMTimeGetSeconds(duration)
        
        if durationSeconds > 0 {
            return Int(Double(fileSize) * 8 / durationSeconds)
        }
        
        return 6_000_000
    }
    
    private func getVideoSize(asset: AVAsset) async throws -> CGSize {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return CGSize(width: 1920, height: 1080)
        }
        
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // 考虑变换矩阵
        if transform.a == 0 && transform.d == 0 {
            return CGSize(width: size.height, height: size.width)
        }
        
        return size
    }
}

// MARK: - Errors

enum CompressionError: LocalizedError {
    case failedToCreateExportSession
    case exportFailed(Error)
    case cancelled
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateExportSession:
            return "无法创建导出会话"
        case .exportFailed(let error):
            return "导出失败: \(error.localizedDescription)"
        case .cancelled:
            return "压缩已取消"
        case .unknownError:
            return "未知错误"
        }
    }
}
