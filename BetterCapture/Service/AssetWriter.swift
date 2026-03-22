//
//  AssetWriter.swift
//  BetterCapture
//
//  修复版 - 解决写入失败和线程安全问题
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

/// AssetWriter 错误
enum AssetWriterError: LocalizedError {
    case failedToCreateWriter
    case writerNotReady
    case failedToStartWriting(Error?)
    case noOutputURL
    case noFramesWritten
    case writingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateWriter:
            return "创建写入器失败"
        case .writerNotReady:
            return "写入器未就绪"
        case .failedToStartWriting(let error):
            return "开始写入失败: \(error?.localizedDescription ?? "未知错误")"
        case .noOutputURL:
            return "没有输出 URL"
        case .noFramesWritten:
            return "没有写入任何帧"
        case .writingFailed(let error):
            return "写入失败: \(error.localizedDescription)"
        }
    }
}

/// 负责将捕获的媒体写入磁盘
final class AssetWriter: CaptureEngineSampleBufferDelegate, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    
    private(set) var isWriting = false
    private(set) var outputURL: URL?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture", category: "AssetWriter")
    
    private var hasStartedSession = false
    private var sessionStartTime: CMTime = .zero
    private var lastVideoPresentationTime: CMTime = .invalid
    
    private var videoTrackID: Int32 = 1
    private var systemAudioTrackID: Int32 = 2
    private var microphoneTrackID: Int32 = 3
    
    private let lock = NSLock()
    
    private var frameCount = 0
    private var audioFrameCount = 0
    
    // MARK: - Setup
    
    func setup(url: URL, settings: SettingsStore, videoSize: CGSize) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // 确保输出目录存在
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // 删除已存在的文件
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        
        // 创建 AssetWriter
        let fileType: AVFileType = settings.containerFormat == .mov ? .mov : .mp4
        assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)
        
        guard let assetWriter = assetWriter else {
            throw AssetWriterError.failedToCreateWriter
        }
        
        // 配置视频输入
        let videoSettings = createVideoSettings(from: settings, size: videoSize)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        if let videoInput = videoInput, assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
            
            // 创建像素缓冲区适配器
            let pixelFormat: OSType = (settings.captureHDR && settings.videoCodec.supportsHDR)
                ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                : kCVPixelFormatType_32BGRA
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height)
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
        }
        
        // 配置系统音频输入
        if settings.captureSystemAudio {
            let audioSettings = createAudioSettings(from: settings)
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true
            audioInput?.trackID = systemAudioTrackID
            
            if let audioInput = audioInput, assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            }
        }
        
        // 配置麦克风输入
        if settings.captureMicrophone {
            let micSettings = createAudioSettings(from: settings)
            microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            microphoneInput?.expectsMediaDataInRealTime = true
            microphoneInput?.trackID = microphoneTrackID
            
            if let microphoneInput = microphoneInput, assetWriter.canAdd(microphoneInput) {
                assetWriter.add(microphoneInput)
            }
        }
        
        outputURL = url
        hasStartedSession = false
        sessionStartTime = .zero
        lastVideoPresentationTime = .invalid
        frameCount = 0
        audioFrameCount = 0
        
        logger.info("AssetWriter 配置完成: \(url.lastPathComponent)")
    }
    
    // MARK: - Writing
    
    func startWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard let assetWriter = assetWriter, assetWriter.status == .unknown else {
            throw AssetWriterError.writerNotReady
        }
        
        guard assetWriter.startWriting() else {
            throw AssetWriterError.failedToStartWriting(assetWriter.error)
        }
        
        isWriting = true
        logger.info("AssetWriter 开始写入")
    }
    
    // MARK: - Sample Buffer Handling
    
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        // 检查帧状态
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[String: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[SCStreamFrameInfo.status.rawValue] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return
        }
        
        guard status == .complete else {
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let assetWriter = assetWriter,
              assetWriter.status == .writing,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor else {
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // 在第一个样本上启动会话
        if !hasStartedSession {
            assetWriter.startSession(atSourceTime: presentationTime)
            sessionStartTime = presentationTime
            hasStartedSession = true
            logger.info("会话在 \(presentationTime.seconds) 启动")
        } else {
            // 防止非单调时间戳
            if lastVideoPresentationTime.isValid && presentationTime <= lastVideoPresentationTime {
                return
            }
        }
        
        // 提取像素缓冲区
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // 追加像素缓冲区
        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            lastVideoPresentationTime = presentationTime
            frameCount += 1
            
            if frameCount == 1 {
                logger.info("第一帧视频追加成功")
            } else if frameCount % 60 == 0 {
                logger.debug("已写入 \(frameCount) 帧视频")
            }
        } else if let error = assetWriter.error {
            logger.error("追加视频像素缓冲区失败: \(error.localizedDescription)")
        }
    }
    
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let assetWriter = assetWriter,
              assetWriter.status == .writing,
              let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData else {
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // 如果视频还没启动会话，用音频时间启动
        if !hasStartedSession {
            assetWriter.startSession(atSourceTime: presentationTime)
            sessionStartTime = presentationTime
            hasStartedSession = true
            logger.info("会话从音频在 \(presentationTime.seconds) 启动")
        }
        
        if audioInput.append(sampleBuffer) {
            audioFrameCount += 1
        } else {
            logger.error("追加音频样本缓冲区失败")
        }
    }
    
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputMicrophoneSampleBuffer sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let assetWriter = assetWriter,
              assetWriter.status == .writing,
              let microphoneInput = microphoneInput,
              microphoneInput.isReadyForMoreMediaData else {
            return
        }
        
        if !microphoneInput.append(sampleBuffer) {
            logger.error("追加麦克风样本缓冲区失败")
        }
    }
    
    // MARK: - Finalization
    
    func finishWriting() async throws -> URL {
        // 第一阶段: 标记输入完成
        let (writerToFinish, url): (AVAssetWriter, URL)
        
        do {
            lock.lock()
            
            guard let assetWriter = assetWriter, isWriting else {
                lock.unlock()
                throw AssetWriterError.writerNotReady
            }
            
            guard let url = outputURL else {
                lock.unlock()
                throw AssetWriterError.noOutputURL
            }
            
            logger.info("完成写入 - 状态: \(assetWriter.status.rawValue), 会话已启动: \(hasStartedSession), 视频帧: \(frameCount), 音频帧: \(audioFrameCount)")
            
            guard hasStartedSession else {
                lock.unlock()
                cancel()
                throw AssetWriterError.noFramesWritten
            }
            
            // 标记输入完成
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
            
            writerToFinish = assetWriter
            self.outputURL = nil
            
            lock.unlock()
        }
        
        // 第二阶段: 异步完成写入
        await writerToFinish.finishWriting()
        
        // 第三阶段: 检查结果
        lock.lock()
        defer { lock.unlock() }
        
        guard let url = outputURL ?? writerToFinish.outputURL else {
            throw AssetWriterError.noOutputURL
        }
        
        switch writerToFinish.status {
        case .completed:
            logger.info("写入完成: \(url.lastPathComponent), 共 \(frameCount) 帧视频, \(audioFrameCount) 帧音频")
            
            // 重置状态
            isWriting = false
            assetWriter = nil
            videoInput = nil
            pixelBufferAdaptor = nil
            audioInput = nil
            microphoneInput = nil
            hasStartedSession = false
            frameCount = 0
            audioFrameCount = 0
            
            return url
            
        case .failed:
            if let error = writerToFinish.error {
                throw AssetWriterError.writingFailed(error)
            } else {
                throw AssetWriterError.writingFailed(NSError(domain: "AssetWriter", code: -1))
            }
            
        case .cancelled:
            throw AssetWriterError.writingFailed(NSError(domain: "AssetWriter", code: -2, userInfo: [NSLocalizedDescriptionKey: "写入被取消"]))
            
        default:
            throw AssetWriterError.writingFailed(NSError(domain: "AssetWriter", code: -3, userInfo: [NSLocalizedDescriptionKey: "未知状态: \(writerToFinish.status.rawValue)"]))
        }
    }
    
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        
        logger.info("取消写入")
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        
        assetWriter?.cancelWriting()
        
        // 清理状态
        isWriting = false
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        audioInput = nil
        microphoneInput = nil
        hasStartedSession = false
        frameCount = 0
        audioFrameCount = 0
    }
    
    // MARK: - Helper Methods
    
    private func createVideoSettings(from settings: SettingsStore, size: CGSize) -> [String: Any] {
        var settingsDict: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec.avCodecKey,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        
        // ProRes 不使用压缩属性
        if settings.videoCodec != .proRes422 && settings.videoCodec != .proRes4444 {
            let compressionProperties: [String: Any] = [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate == .native ? 120 : settings.frameRate.rawValue * 2
            ]
            settingsDict[AVVideoCompressionPropertiesKey] = compressionProperties
        }
        
        return settingsDict
    }
    
    private func createAudioSettings(from settings: SettingsStore) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: settings.audioCodec == .aac ? kAudioFormatMPEG4AAC : kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2
        ]
        
        if settings.audioCodec == .aac {
            settings[AVEncoderBitRateKey] = 128000
        }
        
        return settings
    }
}

// MARK: - VideoCodec Extension

extension VideoCodec {
    var avCodecKey: String {
        switch self {
        case .h264:
            return AVVideoCodecType.h264.rawValue
        case .hevc:
            return AVVideoCodecType.hevc.rawValue
        case .proRes422:
            return AVVideoCodecType.proRes422.rawValue
        case .proRes4444:
            return AVVideoCodecType.proRes4444.rawValue
        }
    }
}
