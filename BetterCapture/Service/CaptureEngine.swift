//
//  CaptureEngine.swift
//  BetterCapture
//
//  修复版 - 解决录屏启动失败问题
//

import Foundation
import ScreenCaptureKit
import OSLog

/// 捕获引擎错误
enum CaptureError: LocalizedError {
    case noContentFilterSelected
    case screenRecordingPermissionDenied
    case microphonePermissionDenied
    case failedToCreateStream
    case streamStartFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noContentFilterSelected:
            return "未选择录制内容"
        case .screenRecordingPermissionDenied:
            return "屏幕录制权限被拒绝"
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝"
        case .failedToCreateStream:
            return "创建录制流失败"
        case .streamStartFailed(let error):
            return "启动录制失败: \(error.localizedDescription)"
        }
    }
}

/// 捕获引擎代理
@MainActor
protocol CaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: CaptureEngine, didUpdateFilter filter: SCContentFilter)
    func captureEngine(_ engine: CaptureEngine, didStopWithError error: Error?)
    func captureEngineDidCancelPicker(_ engine: CaptureEngine)
    func captureEngine(_ engine: CaptureEngine, presenterOverlayDidChange isActive: Bool)
}

/// 样本缓冲区代理
protocol CaptureEngineSampleBufferDelegate: AnyObject, Sendable {
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer)
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer)
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputMicrophoneSampleBuffer sampleBuffer: CMSampleBuffer)
}

/// 修复后的捕获引擎
@MainActor
final class CaptureEngine: NSObject {
    
    weak var delegate: CaptureEngineDelegate?
    
    /// 样本缓冲区代理 - 在捕获队列上调用
    weak var sampleBufferDelegate: CaptureEngineSampleBufferDelegate? {
        didSet {
            // 确保在设置代理时同步到捕获队列
            videoSampleQueue.async { [weak self] in
                self?.unsafeSampleBufferDelegate = oldValue
            }
        }
    }
    
    /// 非隔离的代理引用 - 仅在捕获队列上使用
    private nonisolated(unsafe) var unsafeSampleBufferDelegate: CaptureEngineSampleBufferDelegate?
    
    private(set) var contentFilter: SCContentFilter?
    private(set) var isCapturing = false
    private(set) var isPresenterOverlayActive = false
    
    private var stream: SCStream?
    private let picker = SCContentSharingPicker.shared
    private let contentFilterService = ContentFilterService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture", category: "CaptureEngine")
    
    // 样本缓冲区处理队列
    private let videoSampleQueue = DispatchQueue(label: "com.bettercapture.videoSampleQueue", qos: .userInteractive)
    private let audioSampleQueue = DispatchQueue(label: "com.bettercapture.audioSampleQueue", qos: .userInteractive)
    private let microphoneSampleQueue = DispatchQueue(label: "com.bettercapture.microphoneSampleQueue", qos: .userInteractive)
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupPicker()
    }
    
    deinit {
        picker.remove(self)
    }
    
    // MARK: - Picker Management
    
    private func setupPicker() {
        picker.add(self)
        
        var config = SCContentSharingPickerConfiguration()
        config.allowsChangingSelectedContent = true
        config.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
        
        if let bundleID = Bundle.main.bundleIdentifier {
            config.excludedBundleIDs = [bundleID]
        }
        
        picker.defaultConfiguration = config
    }
    
    func presentPicker() {
        picker.isActive = true
        picker.present()
    }
    
    // MARK: - Stream Management
    
    func startCapture(with settings: SettingsStore, videoSize: CGSize, sourceRect: CGRect? = nil) async throws {
        guard let filter = contentFilter else {
            throw CaptureError.noContentFilterSelected
        }
        
        // 检查权限
        let hasPermission = contentFilterService.hasScreenRecordingPermission()
        logger.info("屏幕录制权限检查: \(hasPermission)")
        
        guard hasPermission else {
            contentFilterService.requestScreenRecordingPermission()
            throw CaptureError.screenRecordingPermissionDenied
        }
        
        // 检查麦克风权限
        if settings.captureMicrophone {
            let hasMicPermission = contentFilterService.hasMicrophonePermission()
            logger.info("麦克风权限检查: \(hasMicPermission)")
            
            if !hasMicPermission {
                let granted = await contentFilterService.requestMicrophonePermission()
                if !granted {
                    throw CaptureError.microphonePermissionDenied
                }
            }
        }
        
        // 应用内容过滤器设置
        logger.info("应用内容过滤器设置...")
        let filteredContent = try await contentFilterService.applySettings(to: filter, settings: settings)
        logger.info("内容过滤器已应用")
        
        // 创建流配置
        let streamConfig = createStreamConfiguration(from: settings, contentSize: videoSize, sourceRect: sourceRect)
        
        // 创建流
        stream = SCStream(filter: filteredContent, configuration: streamConfig, delegate: self)
        
        guard let stream = stream else {
            throw CaptureError.failedToCreateStream
        }
        
        // 同步设置非隔离代理
        self.unsafeSampleBufferDelegate = sampleBufferDelegate
        
        do {
            // 添加视频输出
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoSampleQueue)
            logger.info("已添加屏幕输出")
            
            // 添加系统音频输出
            if settings.captureSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioSampleQueue)
                logger.info("已添加系统音频输出")
            }
            
            // 添加麦克风输出
            if settings.captureMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: microphoneSampleQueue)
                logger.info("已添加麦克风输出")
            }
            
            // 启动捕获
            logger.info("启动流捕获...")
            try await stream.startCapture()
            logger.info("流捕获启动成功")
            
            isCapturing = true
            
        } catch {
            logger.error("启动捕获失败: \(error.localizedDescription)")
            self.stream = nil
            throw CaptureError.streamStartFailed(error)
        }
    }
    
    func stopCapture() async throws {
        guard let stream = stream, isCapturing else {
            logger.info("没有活动的捕获需要停止")
            return
        }
        
        do {
            try await stream.stopCapture()
            logger.info("流捕获已停止")
        } catch {
            logger.error("停止捕获失败: \(error.localizedDescription)")
            throw error
        }
        
        self.stream = nil
        isCapturing = false
        isPresenterOverlayActive = false
    }
    
    func updateFilter(_ filter: SCContentFilter) async throws {
        contentFilter = filter
        
        if let stream = stream, isCapturing {
            try await stream.updateContentFilter(filter)
            logger.info("内容过滤器已更新")
        }
    }
    
    func clearSelection() {
        contentFilter = nil
    }
    
    func deactivatePicker() {
        picker.isActive = false
        logger.info("选择器已停用")
    }
    
    // MARK: - Configuration
    
    private func createStreamConfiguration(from settings: SettingsStore, contentSize: CGSize, sourceRect: CGRect? = nil) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        
        // 设置输出尺寸
        config.width = Int(contentSize.width)
        config.height = Int(contentSize.height)
        
        // 设置区域选择
        if let sourceRect = sourceRect {
            config.sourceRect = sourceRect
            logger.info("源矩形: \(sourceRect)")
        }
        
        // 帧率
        if settings.frameRate == .native {
            config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        } else {
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate.rawValue))
        }
        
        // 光标可见性
        config.showsCursor = settings.showCursor
        
        // 系统音频
        config.capturesAudio = settings.captureSystemAudio
        config.sampleRate = 48000
        config.channelCount = 2
        
        // 麦克风
        config.captureMicrophone = settings.captureMicrophone
        if let microphoneID = settings.selectedMicrophoneID {
            config.microphoneCaptureDeviceID = microphoneID
        }
        
        // Presenter Overlay
        if settings.presenterOverlayEnabled {
            config.presenterOverlayPrivacyAlertSetting = .always
        }
        
        // HDR/像素格式
        if settings.captureHDR && settings.videoCodec.supportsHDR {
            config.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            config.captureDynamicRange = .hdrLocalDisplay
        } else {
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.captureDynamicRange = .SDR
        }
        
        return config
    }
}

// MARK: - SCContentSharingPickerObserver

extension CaptureEngine: SCContentSharingPickerObserver {
    
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            self.contentFilter = filter
            self.delegate?.captureEngine(self, didUpdateFilter: filter)
            logger.info("内容过滤器已从选择器更新")
            picker.isActive = false
        }
    }
    
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            self.contentFilter = nil
            self.delegate?.captureEngineDidCancelPicker(self)
            logger.info("选择器已取消")
            picker.isActive = false
        }
    }
    
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            logger.error("选择器启动失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - SCStreamDelegate

extension CaptureEngine: SCStreamDelegate {
    
    func stream(_ stream: SCStream, didStopWithError error: Error?) {
        logger.error("流停止，错误: \(error?.localizedDescription ?? "无")")
        
        Task { @MainActor in
            isCapturing = false
            self.stream = nil
            delegate?.captureEngine(self, didStopWithError: error)
        }
    }
}

// MARK: - SCStreamOutput

extension CaptureEngine: SCStreamOutput {
    
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 使用非隔离代理
        guard let delegate = unsafeSampleBufferDelegate else { return }
        
        switch type {
        case .screen:
            delegate.captureEngine(self, didOutputVideoSampleBuffer: sampleBuffer)
        case .audio:
            delegate.captureEngine(self, didOutputAudioSampleBuffer: sampleBuffer)
        case .microphone:
            delegate.captureEngine(self, didOutputMicrophoneSampleBuffer: sampleBuffer)
        @unknown default:
            break
        }
    }
}
