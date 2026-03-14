//
//  AudioLevelMeter.swift
//  BetterCapture
//
//  Created for scap project - Audio visualization
//

import Foundation
import AVFoundation
import OSLog

/// Audio level metrics for visualization
struct AudioLevelMetrics: Sendable {
    /// RMS (Root Mean Square) level in dB, typically -60 to 0
    var systemAudioLevel: Float = -60.0
    /// Peak level in dB
    var systemAudioPeak: Float = -60.0
    /// RMS level for microphone in dB
    var microphoneLevel: Float = -60.0
    /// Peak level for microphone in dB
    var microphonePeak: Float = -60.0

    /// Convert dB to a 0-1 scale for UI visualization
    var systemAudioLevelNormalized: Float {
        max(0, min(1, (systemAudioLevel + 60) / 60))
    }

    var microphoneLevelNormalized: Float {
        max(0, min(1, (microphoneLevel + 60) / 60))
    }
}

/// Protocol for receiving audio level updates
@MainActor
protocol AudioLevelMeterDelegate: AnyObject {
    func audioLevelMeter(_ meter: AudioLevelMeter, didUpdateLevels levels: AudioLevelMetrics)
}

/// Service for measuring audio levels from sample buffers
final class AudioLevelMeter: Sendable {

    // MARK: - Properties

    @MainActor weak var delegate: AudioLevelMeterDelegate?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "scap",
        category: "AudioLevelMeter"
    )

    /// Current audio levels
    @MainActor
    private(set) var currentLevels = AudioLevelMetrics()

    /// Whether level metering is enabled
    @MainActor
    var isMeteringEnabled: Bool = false

    /// Decay rate for level meters (how quickly they fall back)
    private let decayRate: Float = 0.3

    /// Attack rate for level meters (how quickly they respond)
    private let attackRate: Float = 0.8

    // MARK: - Public Methods

    /// Enables or disables audio level metering
    @MainActor
    func setMeteringEnabled(_ enabled: Bool) {
        isMeteringEnabled = enabled
        if !enabled {
            currentLevels = AudioLevelMetrics()
        }
    }

    /// Process a system audio sample buffer for level metering
    func processSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isMeteringEnabled else { return }

        let levels = calculateLevels(from: sampleBuffer)
        updateLevels(systemRMS: levels.rms, systemPeak: levels.peak)
    }

    /// Process a microphone sample buffer for level metering
    func processMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isMeteringEnabled else { return }

        let levels = calculateLevels(from: sampleBuffer)
        updateLevels(micRMS: levels.rms, micPeak: levels.peak)
    }

    /// Reset all levels to silence
    @MainActor
    func resetLevels() {
        currentLevels = AudioLevelMetrics()
    }

    // MARK: - Private Methods

    /// Calculate audio levels from a sample buffer
    private func calculateLevels(from sampleBuffer: CMSampleBuffer) -> (rms: Float, peak: Float) {
        guard let audioBufferList = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeMemoryLocation: nil
        ) else {
            return (-60.0, -60.0)
        }

        var rms: Float = 0.0
        var peak: Float = -160.0

        let bufferCount = Int(audioBufferList.pointee.mNumberBuffers)
        let buffers = UnsafeBufferPointer(start: audioBufferList.pointee.mBuffers, count: bufferCount)

        for buffer in buffers {
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size

            guard let samples = buffer.mData?.assumingMemoryBound(to: Int16.self) else {
                continue
            }

            var sum: Float = 0.0
            var localPeak: Float = -160.0

            for i in 0..<sampleCount {
                let sample = Float(samples[i]) / 32768.0
                sum += sample * sample
                let absSample = abs(sample)
                if absSample > localPeak {
                    localPeak = absSample
                }
            }

            if sampleCount > 0 {
                let channelRMS = sqrt(sum / Float(sampleCount))
                rms = max(rms, channelRMS)
                peak = max(peak, localPeak)
            }
        }

        // Convert to dB
        let rmsDb = rms > 0 ? 20 * log10(rms) : -60.0
        let peakDb = peak > 0 ? 20 * log10(peak) : -60.0

        return (max(-60, rmsDb), max(-60, peakDb))
    }

    /// Update levels with smoothing
    @MainActor
    private func updateLevels(systemRMS: Float? = nil, systemPeak: Float? = nil,
                              micRMS: Float? = nil, micPeak: Float? = nil) {
        var newLevels = currentLevels

        // Apply smoothing to system audio
        if let rms = systemRMS {
            newLevels.systemAudioLevel = smoothLevel(
                current: currentLevels.systemAudioLevel,
                target: rms,
                attack: attackRate,
                decay: decayRate
            )
        }

        if let peak = systemPeak {
            newLevels.systemAudioPeak = max(newLevels.systemAudioPeak, peak)
        }

        // Apply smoothing to microphone
        if let rms = micRMS {
            newLevels.microphoneLevel = smoothLevel(
                current: currentLevels.microphoneLevel,
                target: rms,
                attack: attackRate,
                decay: decayRate
            )
        }

        if let peak = micPeak {
            newLevels.microphonePeak = max(newLevels.microphonePeak, peak)
        }

        currentLevels = newLevels
        delegate?.audioLevelMeter(self, didUpdateLevels: newLevels)
    }

    /// Smooth level transitions with different attack/decay rates
    private func smoothLevel(current: Float, target: Float, attack: Float, decay: Float) -> Float {
        let rate = target > current ? attack : decay
        return current + (target - current) * rate
    }
}
