//
//  AudioProcessor.swift
//  BetterCapture
//
//  Created for scap project - Audio effects processing
//

import Foundation
import AVFoundation
import Accelerate
import OSLog

/// Audio processor for applying effects to sample buffers
final class AudioProcessor: Sendable {

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "scap",
        category: "AudioProcessor"
    )

    /// Reference to settings store
    @MainActor
    weak var settingsStore: SettingsStore?

    /// Processing state for AGC
    private var currentGain: Float = 1.0
    private var runningRMS: Float = 0.0

    /// Ring buffer for noise estimation
    private var noiseProfile: [Float] = Array(repeating: 0, count: 1024)
    private var noiseProfileIndex = 0
    private var noiseProfileCount = 0

    // MARK: - Initialization

    init(settingsStore: SettingsStore? = nil) {
        self.settingsStore = settingsStore
    }

    // MARK: - Public Methods

    /// Process audio sample buffer with enabled effects
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        return sampleBuffer
    }

    /// Process raw audio data with settings from SettingsStore
    @MainActor
    func processAudioData(_ buffer: inout [Float], sampleRate: Double, channels: Int) {
        guard let settings = settingsStore else { return }
        guard !buffer.isEmpty else { return }

        if settings.noiseReductionAmount > 0 {
            applyNoiseReduction(&buffer, amount: settings.noiseReductionAmount)
        }

        if settings.autoGainControlEnabled {
            applyAutoGainControl(&buffer, sampleRate: sampleRate, targetRMS: -20.0)
        }

        if settings.compressionEnabled {
            applyCompression(&buffer, threshold: -30.0, ratio: 4.0)
        }
    }

    // MARK: - Audio Effects

    @MainActor
    private func applyNoiseReduction(_ buffer: inout [Float], amount: Float) {
        guard amount > 0 else { return }

        // Update noise profile
        for i in 0..<min(buffer.count, noiseProfile.count) {
            let sample = abs(buffer[i])
            noiseProfile[noiseProfileIndex] = sample
            noiseProfileIndex = (noiseProfileIndex + 1) % noiseProfile.count
            if noiseProfileCount < noiseProfile.count {
                noiseProfileCount += 1
            }
        }

        // Calculate noise floor estimate
        let noiseFloor = noiseProfile.prefix(noiseProfileCount).reduce(0) { $0 + $1 }
            / Float(max(1, noiseProfileCount))

        // Apply noise gating
        let threshold = noiseFloor * (1 + amount * 2)

        for i in 0..<buffer.count {
            let absSample = abs(buffer[i])
            if absSample < threshold {
                let attenuation = absSample / (threshold + 0.0001)
                buffer[i] *= pow(attenuation, amount)
            }
        }
    }

    @MainActor
    private func applyAutoGainControl(_ buffer: inout [Float], sampleRate: Double, targetRMS: Float) {
        // Calculate RMS of current buffer
        var sum: Float = 0
        for sample in buffer {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.count))

        // Update running RMS with smoothing
        runningRMS = runningRMS * 0.9 + rms * 0.1

        // Calculate required gain to reach target level
        let targetLinear = pow(10, targetRMS / 20)
        let requiredGain = runningRMS > 0 ? targetLinear / runningRMS : 1.0

        // Smooth gain changes to avoid pumping
        let maxGainChange: Float = 1.1
        var newGain = currentGain

        if requiredGain > currentGain {
            newGain = min(requiredGain, currentGain * maxGainChange)
        } else {
            newGain = max(requiredGain, currentGain / maxGainChange)
        }

        // Limit gain to prevent clipping
        newGain = min(newGain, 10.0)
        newGain = max(newGain, 0.1)

        currentGain = newGain

        for i in 0..<buffer.count {
            buffer[i] *= currentGain
        }
    }

    @MainActor
    private func applyCompression(_ buffer: inout [Float], threshold: Float, ratio: Float) {
        let thresholdLinear = pow(10, threshold / 20)

        for i in 0..<buffer.count {
            let sample = buffer[i]
            let absSample = abs(sample)

            if absSample > thresholdLinear {
                let excess = absSample - thresholdLinear
                let compressedExcess = excess / ratio
                let compressedSample = thresholdLinear + compressedExcess
                buffer[i] = sample > 0 ? compressedSample : -compressedSample
            }
        }
    }
}
