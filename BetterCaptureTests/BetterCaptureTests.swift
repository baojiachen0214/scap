//
//  BetterCaptureTests.swift
//  BetterCapture
//
//  完整的单元测试套件
//

import XCTest
import AVFoundation
import ScreenCaptureKit
@testable import BetterCapture

final class BetterCaptureTests: XCTestCase {
    
    // MARK: - SettingsStore Tests
    
    func testSettingsStoreDefaultValues() {
        let settings = SettingsStore()
        
        XCTAssertEqual(settings.videoCodec, .hevc)
        XCTAssertEqual(settings.containerFormat, .mov)
        XCTAssertEqual(settings.frameRate, .fps60)
        XCTAssertTrue(settings.showCursor)
        XCTAssertTrue(settings.captureSystemAudio)
    }
    
    func testSettingsStoreCodecCompatibility() {
        let settings = SettingsStore()
        
        // ProRes 4444 应该自动启用 alpha 通道
        settings.videoCodec = .proRes4444
        XCTAssertTrue(settings.captureAlphaChannel)
        
        // MP4 容器不支持 ProRes
        settings.containerFormat = .mp4
        XCTAssertFalse(settings.containerFormat.supportedVideoCodecs.contains(.proRes422))
    }
    
    func testSettingsStoreFilenameGeneration() {
        let settings = SettingsStore()
        let filename = settings.generateFilename()
        
        XCTAssertTrue(filename.hasPrefix("BetterCapture_"))
        XCTAssertTrue(filename.hasSuffix(".mov"))
    }
    
    // MARK: - AudioMixer Tests
    
    func testAudioMixerVolumeControl() {
        let mixer = AudioMixer()
        
        mixer.systemAudioVolume = 0.5
        XCTAssertEqual(mixer.systemAudioVolume, 0.5)
        
        mixer.microphoneVolume = 0.8
        XCTAssertEqual(mixer.microphoneVolume, 0.8)
        
        // 测试边界值
        mixer.systemAudioVolume = 1.5 // 应该被限制为 1.0
        XCTAssertEqual(mixer.systemAudioVolume, 1.0)
        
        mixer.microphoneVolume = -0.5 // 应该被限制为 0.0
        XCTAssertEqual(mixer.microphoneVolume, 0.0)
    }
    
    func testAudioMixerMute() {
        let mixer = AudioMixer()
        
        mixer.systemAudioVolume = 0.8
        mixer.isSystemAudioMuted = true
        XCTAssertEqual(mixer.systemAudioVolume, 0)
        
        mixer.isSystemAudioMuted = false
        XCTAssertEqual(mixer.systemAudioVolume, 1.0)
    }
    
    // MARK: - VideoCompressor Tests
    
    func testCompressionQualityBitrateRatio() {
        XCTAssertEqual(CompressionQuality.high.bitrateRatio, 0.8)
        XCTAssertEqual(CompressionQuality.medium.bitrateRatio, 0.5)
        XCTAssertEqual(CompressionQuality.low.bitrateRatio, 0.3)
        XCTAssertEqual(CompressionQuality.veryLow.bitrateRatio, 0.15)
    }
    
    func testCompressionQualityCRF() {
        XCTAssertEqual(CompressionQuality.high.crfValue, 18)
        XCTAssertEqual(CompressionQuality.medium.crfValue, 23)
        XCTAssertEqual(CompressionQuality.low.crfValue, 28)
        XCTAssertEqual(CompressionQuality.veryLow.crfValue, 35)
    }
    
    // MARK: - RecordingStats Tests
    
    func testRecordingStatsBitrateFormatting() {
        let stats = RecordingStats()
        
        // 需要通过反射或直接测试格式化方法
        // 这里测试公共接口
        stats.startRecording()
        stats.updateBytesWritten(6_250_000) // 约 6.25 MB
        
        XCTAssertGreaterThan(stats.currentBitrate, 0)
    }
    
    func testRecordingStatsFrameRate() {
        let stats = RecordingStats()
        stats.startRecording()
        
        // 模拟 30fps
        for _ in 0..<30 {
            stats.recordFrame()
            Thread.sleep(forTimeInterval: 0.033) // 约 30fps
        }
        
        XCTAssertGreaterThan(stats.actualFrameRate, 0)
    }
    
    // MARK: - VideoCodec Tests
    
    func testVideoCodecAlphaSupport() {
        XCTAssertTrue(VideoCodec.proRes4444.supportsAlphaChannel)
        XCTAssertTrue(VideoCodec.hevc.supportsAlphaChannel)
        XCTAssertFalse(VideoCodec.h264.supportsAlphaChannel)
        XCTAssertFalse(VideoCodec.proRes422.supportsAlphaChannel)
    }
    
    func testVideoCodecHDRSupport() {
        XCTAssertTrue(VideoCodec.proRes422.supportsHDR)
        XCTAssertTrue(VideoCodec.proRes4444.supportsHDR)
        XCTAssertFalse(VideoCodec.h264.supportsHDR)
        XCTAssertFalse(VideoCodec.hevc.supportsHDR)
    }
    
    // MARK: - ContainerFormat Tests
    
    func testContainerFormatExtensions() {
        XCTAssertEqual(ContainerFormat.mov.fileExtension, "mov")
        XCTAssertEqual(ContainerFormat.mp4.fileExtension, "mp4")
    }
    
    func testContainerFormatAlphaSupport() {
        XCTAssertTrue(ContainerFormat.mov.supportsAlphaChannel)
        XCTAssertFalse(ContainerFormat.mp4.supportsAlphaChannel)
    }
    
    // MARK: - FrameRate Tests
    
    func testFrameRateDisplayNames() {
        XCTAssertEqual(FrameRate.native.displayName, "Native")
        XCTAssertEqual(FrameRate.fps30.displayName, "30 fps")
        XCTAssertEqual(FrameRate.fps60.displayName, "60 fps")
    }
    
    // MARK: - Performance Tests
    
    func testAudioMixerPerformance() {
        let mixer = AudioMixer()
        
        measure {
            for _ in 0..<1000 {
                mixer.systemAudioVolume = Float.random(in: 0...1)
                _ = mixer.mixSystemAudio(CMSampleBuffer())
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testCaptureEngineInitialization() async {
        let engine = CaptureEngine()
        
        // 测试初始化后状态
        XCTAssertFalse(engine.isCapturing)
        XCTAssertNil(engine.contentFilter)
    }
    
    func testAssetWriterSetup() throws {
        let writer = AssetWriter()
        let settings = SettingsStore()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mp4")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // 测试设置是否成功
        XCTAssertNoThrow(try writer.setup(url: tempURL, settings: settings, videoSize: CGSize(width: 1920, height: 1080)))
    }
}
