//
//  RecorderViewModel.swift
//  BetterCapture
//
//  修复版 - 稳定的录制控制
//

import Foundation
import ScreenCaptureKit
import AppKit
import OSLog

/// 录制视图模型
@MainActor
@Observable
final class RecorderViewModel: CaptureEngineDelegate, CaptureEngineSampleBufferDelegate {
    
    // MARK: - Recording State
    
    enum RecordingState {
        case idle
        case recording
        case stopping
    }
    
    // MARK: - Published Properties
    
    private(set) var state: RecordingState = .idle
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var lastError: Error?
    private(set) var selectedContentFilter: SCContentFilter?
    
    private(set) var selectedSourceRect: CGRect?
    private(set) var selectedScreenRect: CGRect?
    
    var isRecording: Bool {
        state == .recording
    }
    
    var canStartRecording: Bool {
        selectedContentFilter != nil && state == .idle
    }
    
    var hasContentSelected: Bool {
        selectedContentFilter != nil
    }
    
    var formattedDuration: String {
        let hours = Int(recordingDuration) / 3600
        let minutes = (Int(recordingDuration) % 3600) / 60
        let seconds = Int(recordingDuration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private(set) var isPresenterOverlayActive = false
    
    // MARK: - Dependencies
    
    let settings: SettingsStore
    let audioDeviceService: AudioDeviceService
    let cameraDeviceService: CameraDeviceService
    let previewService: PreviewService
    let notificationService: NotificationService
    let permissionService: PermissionService
    
    private let captureEngine: CaptureEngine
    private let assetWriter: AssetWriter
    private let cameraSession = CameraSession()
    let audioMixer: AudioMixer
    
    private let areaSelectionOverlay = AreaSelectionOverlay()
    private let selectionBorderFrame = SelectionBorderFrame()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture", category: "RecorderViewModel")
    
    // MARK: - Private Properties
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var videoSize: CGSize = .zero
    
    // MARK: - Initialization
    
    init() {
        self.settings = SettingsStore()
        self.audioDeviceService = AudioDeviceService()
        self.cameraDeviceService = CameraDeviceService()
        self.previewService = PreviewService()
        self.notificationService = NotificationService(settings: SettingsStore())
        self.permissionService = PermissionService()
        self.captureEngine = CaptureEngine()
        self.assetWriter = AssetWriter()
        self.audioMixer = AudioMixer(settingsStore: settings)
        
        // 设置代理关系
        captureEngine.delegate = self
        captureEngine.sampleBufferDelegate = self
        previewService.delegate = self
        
        // 设置 AssetWriter 代理
        assetWriter.setupAsSampleBufferDelegate(for: captureEngine)
    }
    
    // MARK: - Permission Methods
    
    func requestPermissionsOnLaunch() async {
        await permissionService.requestPermissions(includeMicrophone: settings.captureMicrophone)
    }
    
    func refreshPermissions() {
        permissionService.updatePermissionStates()
    }
    
    // MARK: - Content Selection
    
    func presentPicker() {
        captureEngine.presentPicker()
    }
    
    func presentAreaSelection() async {
        selectionBorderFrame.dismiss()
        
        guard let result = await areaSelectionOverlay.present() else {
            logger.info("区域选择已取消")
            return
        }
        
        selectionBorderFrame.show(screenRect: result.screenRect)
        
        do {
            let content = try await SCShareableContent.current
            
            let screenNumber = result.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            
            guard let display = content.displays.first(where: { $0.displayID == screenNumber }) else {
                logger.error("找不到对应的显示器")
                return
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // 转换坐标
            let displayHeight = CGFloat(display.height)
            let screenOrigin = result.screen.frame.origin
            
            let localX = result.screenRect.origin.x - screenOrigin.x
            let localY = result.screenRect.origin.y - screenOrigin.y
            let flippedY = displayHeight - localY - result.screenRect.height
            
            let scale = result.screen.backingScaleFactor
            let pixelWidth = result.screenRect.width * scale
            let pixelHeight = result.screenRect.height * scale
            let evenPixelWidth = ceil(pixelWidth / 2) * 2
            let evenPixelHeight = ceil(pixelHeight / 2) * 2
            
            let sourceRect = CGRect(
                x: localX,
                y: flippedY,
                width: evenPixelWidth / scale,
                height: evenPixelHeight / scale
            )
            
            captureEngine.clearSelection()
            
            selectedSourceRect = sourceRect
            selectedScreenRect = result.screenRect
            selectedContentFilter = filter
            try await captureEngine.updateFilter(filter)
            
            logger.info("区域已选择: \(sourceRect)")
            
            await previewService.setContentFilter(filter, sourceRect: sourceRect)
            
        } catch {
            selectionBorderFrame.dismiss()
            logger.error("获取共享内容失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording() async {
        guard canStartRecording else {
            logger.warning("无法开始录制: 未选择内容或已在录制中")
            return
        }
        
        do {
            state = .recording
            lastError = nil
            
            logger.info("开始录制序列...")
            
            // 停止预览
            await previewService.stopPreview()
            
            // 确定视频尺寸
            if let filter = selectedContentFilter {
                videoSize = await getContentSize(from: filter)
            }
            logger.info("视频尺寸: \(videoSize.width)x\(videoSize.height)")
            
            // 访问输出目录
            _ = settings.startAccessingOutputDirectory()
            
            // 设置 AssetWriter
            let outputURL = settings.generateOutputURL()
            try assetWriter.setup(url: outputURL, settings: settings, videoSize: videoSize)
            try assetWriter.startWriting()
            
            // 启动摄像头
            if settings.presenterOverlayEnabled {
                await cameraSession.start(deviceID: settings.selectedCameraID)
            }
            
            // 启动捕获
            logger.info("启动捕获引擎...")
            try await captureEngine.startCapture(with: settings, videoSize: videoSize, sourceRect: selectedSourceRect)
            
            startTimer()
            
            logger.info("录制已开始")
            
        } catch {
            state = .idle
            lastError = error
            cameraSession.stop()
            selectionBorderFrame.dismiss()
            settings.stopAccessingOutputDirectory()
            logger.error("开始录制失败: \(error.localizedDescription)")
            
            // 显示错误通知
            notificationService.sendRecordingFailedNotification(error: error)
        }
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        
        state = .stopping
        stopTimer()
        selectionBorderFrame.dismiss()
        
        do {
            // 停止捕获
            try await captureEngine.stopCapture()
            cameraSession.stop()
            isPresenterOverlayActive = false
            
            // 完成写入
            let outputURL = try await assetWriter.finishWriting()
            
            state = .idle
            recordingDuration = 0
            
            logger.info("录制已停止并保存到: \(outputURL.lastPathComponent)")
            
            // 发送通知
            notificationService.sendRecordingSavedNotification(fileURL: outputURL)
            
            settings.stopAccessingOutputDirectory()
            
        } catch {
            state = .idle
            lastError = error
            assetWriter.cancel()
            settings.stopAccessingOutputDirectory()
            notificationService.sendRecordingFailedNotification(error: error)
            logger.error("停止录制失败: \(error.localizedDescription)")
        }
    }
    
    func clearSelection() {
        captureEngine.clearSelection()
    }
    
    func resetAreaSelection() async {
        selectedSourceRect = nil
        selectedScreenRect = nil
        selectedContentFilter = nil
        selectionBorderFrame.dismiss()
        await previewService.stopPreview()
        previewService.clearPreview()
    }
    
    // MARK: - Preview
    
    func startPreview() async {
        guard !isRecording else { return }
        await previewService.startPreview()
    }
    
    func stopPreview() async {
        await previewService.stopPreview()
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        recordingStartTime = Date()
        recordingDuration = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
    
    // MARK: - Helpers
    
    private func getContentSize(from filter: SCContentFilter) async -> CGSize {
        do {
            let content = try await SCShareableContent.current
            
            if let display = content.displays.first {
                return CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
            }
            
            if let window = content.windows.first {
                return window.frame.size
            }
        } catch {
            logger.error("获取内容尺寸失败: \(error.localizedDescription)")
        }
        
        return CGSize(width: 1920, height: 1080)
    }
    
    // MARK: - CaptureEngineDelegate
    
    func captureEngine(_ engine: CaptureEngine, didUpdateFilter filter: SCContentFilter) {
        selectedContentFilter = filter
        Task {
            await previewService.setContentFilter(filter)
        }
    }
    
    func captureEngine(_ engine: CaptureEngine, didStopWithError error: Error?) {
        if let error = error {
            logger.error("捕获引擎停止，错误: \(error.localizedDescription)")
            Task { @MainActor in
                if isRecording {
                    await stopRecording()
                }
            }
        }
    }
    
    func captureEngineDidCancelPicker(_ engine: CaptureEngine) {
        selectedContentFilter = nil
    }
    
    func captureEngine(_ engine: CaptureEngine, presenterOverlayDidChange isActive: Bool) {
        isPresenterOverlayActive = isActive
    }
    
    // MARK: - CaptureEngineSampleBufferDelegate
    
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        // 通过 AssetWriter 处理
    }
    
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        // 通过 AssetWriter 处理
    }
    
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputMicrophoneSampleBuffer sampleBuffer: CMSampleBuffer) {
        // 通过 AssetWriter 处理
    }
}

// MARK: - PreviewServiceDelegate

extension RecorderViewModel: PreviewServiceDelegate {
    func previewServiceDidStopByUser(_ service: PreviewService) {
        Task { @MainActor in
            selectedContentFilter = nil
            selectedSourceRect = nil
            selectedScreenRect = nil
        }
    }
}

// MARK: - AssetWriter Extension

extension AssetWriter {
    func setupAsSampleBufferDelegate(for captureEngine: CaptureEngine) {
        captureEngine.sampleBufferDelegate = self
    }
}
