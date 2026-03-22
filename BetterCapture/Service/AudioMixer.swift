//
//  AudioMixer.swift
//  BetterCapture
//
//  音频混音 - 支持系统音频和麦克风混音、音量控制
//

import Foundation
import AVFoundation
import Accelerate
import OSLog

/// 音频混音器 - 支持系统音频和麦克风混音、音量控制
@MainActor
@Observable
final class AudioMixer {
    
    // MARK: - Properties
    
    /// 系统音频音量 (0.0 到 1.0)
    var systemAudioVolume: Float = 1.0 {
        didSet {
            systemAudioVolume = max(0, min(1, systemAudioVolume))
        }
    }
    
    /// 麦克风音量 (0.0 到 1.0)
    var microphoneVolume: Float = 1.0 {
        didSet {
            microphoneVolume = max(0, min(1, microphoneVolume))
        }
    }
    
    /// 系统音频是否静音
    var isSystemAudioMuted: Bool = false {
        didSet {
            if isSystemAudioMuted {
                systemAudioVolume = 0
            } else if systemAudioVolume == 0 {
                systemAudioVolume = 1.0
            }
        }
    }
    
    /// 麦克风是否静音
    var isMicrophoneMuted: Bool = false {
        didSet {
            if isMicrophoneMuted {
                microphoneVolume = 0
            } else if microphoneVolume == 0 {
                microphoneVolume = 1.0
            }
        }
    }
    
    /// 音频电平表
    let levelMeter = AudioLevelMeter()
    
    /// 音频处理器 (降噪、AGC等)
    let audioProcessor: AudioProcessor
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetterCapture",
        category: "AudioMixer"
    )
    
    // MARK: - Initialization
    
    init(settingsStore: SettingsStore? = nil) {
        self.audioProcessor = AudioProcessor(settingsStore: settingsStore)
        levelMeter.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// 混音系统音频
    func mixSystemAudio(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        // 电平检测
        levelMeter.processSystemAudio(sampleBuffer)
        
        // 应用音量
        if systemAudioVolume != 1.0 {
            return applyVolumeToSampleBuffer(sampleBuffer, volume: systemAudioVolume)
        }
        
        return sampleBuffer
    }
    
    /// 混音麦克风音频
    func mixMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        // 电平检测
        levelMeter.processMicrophoneAudio(sampleBuffer)
        
        // 应用音量
        if microphoneVolume != 1.0 {
            return applyVolumeToSampleBuffer(sampleBuffer, volume: microphoneVolume)
        }
        
        return sampleBuffer
    }
    
    /// 混音两个音频源 (系统音频 + 麦克风)
    /// 返回混合后的音频样本缓冲区
    func mixAudioSources(
        systemAudio: CMSampleBuffer,
        microphone: CMSampleBuffer
    ) -> CMSampleBuffer? {
        // 分别处理两个音频源
        let processedSystem = mixSystemAudio(systemAudio)
        let processedMic = mixMicrophoneAudio(microphone)
        
        // 混音
        return mixTwoAudioBuffers(buffer1: processedSystem, buffer2: processedMic)
    }
    
    /// 重置混音器状态
    func reset() {
        systemAudioVolume = 1.0
        microphoneVolume = 1.0
        isSystemAudioMuted = false
        isMicrophoneMuted = false
        levelMeter.resetLevels()
    }
    
    // MARK: - Private Methods
    
    /// 应用音量到样本缓冲区
    private func applyVolumeToSampleBuffer(_ sampleBuffer: CMSampleBuffer, volume: Float) -> CMSampleBuffer {
        guard let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        CMBlockBufferGetDataPointer(
            audioBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard let data = dataPointer else { return sampleBuffer }
        
        // 将数据转换为 Float 数组进行处理
        let sampleCount = length / MemoryLayout<Int16>.size
        var int16Buffer = UnsafeMutableBufferPointer<Int16>(
            start: UnsafeMutablePointer<Int16>(OpaquePointer(data)),
            count: sampleCount
        )
        
        // 转换为 Float 进行处理
        var floatBuffer = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            floatBuffer[i] = Float(int16Buffer[i]) / 32768.0 * volume
        }
        
        // 限制范围防止削波
        for i in 0..<sampleCount {
            floatBuffer[i] = max(-1.0, min(1.0, floatBuffer[i]))
        }
        
        // 转换回 Int16
        for i in 0..<sampleCount {
            int16Buffer[i] = Int16(floatBuffer[i] * 32767)
        }
        
        return sampleBuffer
    }
    
    /// 混音两个音频缓冲区
    private func mixTwoAudioBuffers(buffer1: CMSampleBuffer, buffer2: CMSampleBuffer) -> CMSampleBuffer? {
        // 获取音频格式信息
        guard let format1 = CMSampleBufferGetFormatDescription(buffer1),
              let format2 = CMSampleBufferGetFormatDescription(buffer2) else {
            return buffer1 // 返回第一个作为后备
        }
        
        // 检查格式是否匹配
        let asbd1 = CMAudioFormatDescriptionGetStreamBasicDescription(format1)
        let asbd2 = CMAudioFormatDescriptionGetStreamBasicDescription(format2)
        
        guard let asbd1 = asbd1?.pointee, let asbd2 = asbd2?.pointee else {
            return buffer1
        }
        
        // 如果格式不匹配，只返回第一个
        if asbd1.mSampleRate != asbd2.mSampleRate ||
           asbd1.mChannelsPerFrame != asbd2.mChannelsPerFrame {
            logger.warning("音频格式不匹配，无法混音")
            return buffer1
        }
        
        guard let data1 = CMSampleBufferGetDataBuffer(buffer1),
              let data2 = CMSampleBufferGetDataBuffer(buffer2) else {
            return buffer1
        }
        
        var length1: Int = 0
        var length2: Int = 0
        var ptr1: UnsafeMutablePointer<Int8>?
        var ptr2: UnsafeMutablePointer<Int8>?
        
        CMBlockBufferGetDataPointer(data1, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &length1, dataPointerOut: &ptr1)
        CMBlockBufferGetDataPointer(data2, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &length2, dataPointerOut: &ptr2)
        
        guard let p1 = ptr1, let p2 = ptr2 else { return buffer1 }
        
        // 使用较短的缓冲区长度
        let minLength = min(length1, length2)
        let sampleCount = minLength / MemoryLayout<Int16>.size
        
        // 创建新的混音缓冲区
        var mixedSamples = [Int16](repeating: 0, count: sampleCount)
        
        let int16Ptr1 = UnsafeBufferPointer<Int16>(
            start: UnsafePointer<Int16>(OpaquePointer(p1)),
            count: sampleCount
        )
        let int16Ptr2 = UnsafeBufferPointer<Int16>(
            start: UnsafePointer<Int16>(OpaquePointer(p2)),
            count: sampleCount
        )
        
        // 混音：简单相加然后限制
        for i in 0..<sampleCount {
            let sum = Int32(int16Ptr1[i]) + Int32(int16Ptr2[i])
            // 限制在 Int16 范围内
            mixedSamples[i] = Int16(max(Int32(Int16.min), min(Int32(Int16.max), sum)))
        }
        
        // 创建新的样本缓冲区
        return createSampleBuffer(from: mixedSamples, format: format1, timing: buffer1)
    }
    
    /// 从样本数据创建 CMSampleBuffer
    private func createSampleBuffer(
        from samples: [Int16],
        format: CMFormatDescription,
        timing: CMSampleBuffer
    ) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        var audioBuffer: CMBlockBuffer?
        
        let dataSize = samples.count * MemoryLayout<Int16>.size
        
        // 创建块缓冲区
        let result = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &audioBuffer
        )
        
        guard result == kCMBlockBufferNoErr, let buffer = audioBuffer else {
            return nil
        }
        
        // 复制数据
        samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!,
                                          blockBuffer: buffer,
                                          offsetIntoDestination: 0,
                                          dataLength: dataSize)
        }
        
        // 创建样本缓冲区
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: samples.count / 2,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}

// MARK: - AudioLevelMeterDelegate

extension AudioMixer: AudioLevelMeterDelegate {
    func audioLevelMeter(_ meter: AudioLevelMeter, didUpdateLevels levels: AudioLevelMetrics) {
        // 电平更新 - UI 会通过 levelMeter 获取
    }
}
