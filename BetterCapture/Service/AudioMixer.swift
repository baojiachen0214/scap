//
//  AudioMixer.swift
//  BetterCapture
//
//  Created for scap project - Audio mixing and volume control
//

import Foundation
import AVFoundation
import OSLog

/// Audio mixer for controlling volume levels of different audio sources
@MainActor
@Observable
final class AudioMixer {

    // MARK: - Properties

    /// System audio volume (0.0 to 1.0)
    var systemAudioVolume: Float = 1.0 {
        didSet {
            systemAudioVolume = max(0, min(1, systemAudioVolume))
        }
    }

    /// Microphone volume (0.0 to 1.0)
    var microphoneVolume: Float = 1.0 {
        didSet {
            microphoneVolume = max(0, min(1, microphoneVolume))
        }
    }

    /// Whether system audio is muted
    var isSystemAudioMuted: Bool = false {
        didSet {
            if isSystemAudioMuted {
                systemAudioVolume = 0
            } else if systemAudioVolume == 0 {
                systemAudioVolume = 1.0
            }
        }
    }

    /// Whether microphone is muted
    var isMicrophoneMuted: Bool = false {
        didSet {
            if isMicrophoneMuted {
                microphoneVolume = 0
            } else if microphoneVolume == 0 {
                microphoneVolume = 1.0
            }
        }
    }

    /// Audio level meter
    let levelMeter = AudioLevelMeter()

    /// Audio processor for effects
    let audioProcessor: AudioProcessor

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "scap",
        category: "AudioMixer"
    )

    // MARK: - Initialization

    init(settingsStore: SettingsStore? = nil) {
        self.audioProcessor = AudioProcessor(settingsStore: settingsStore)
        levelMeter.delegate = self
    }

    // MARK: - Public Methods

    /// Apply volume mixing to a system audio sample buffer
    func mixSystemAudio(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        // Process through level meter
        levelMeter.processSystemAudio(sampleBuffer)

        // Apply volume if needed
        if systemAudioVolume != 1.0 {
            return applyVolume(sampleBuffer, volume: systemAudioVolume)
        }

        return sampleBuffer
    }

    /// Apply volume mixing to a microphone sample buffer
    func mixMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        // Process through level meter
        levelMeter.processMicrophoneAudio(sampleBuffer)

        // Apply volume if needed
        if microphoneVolume != 1.0 {
            return applyVolume(sampleBuffer, volume: microphoneVolume)
        }

        return sampleBuffer
    }

    /// Reset mixer to default state
    func reset() {
        systemAudioVolume = 1.0
        microphoneVolume = 1.0
        isSystemAudioMuted = false
        isMicrophoneMuted = false
        levelMeter.resetLevels()
    }

    // MARK: - Private Methods

    /// Apply volume change to a sample buffer
    private func applyVolume(_ sampleBuffer: CMSampleBuffer, volume: Float) -> CMSampleBuffer {
        // Note: Modifying CMSampleBuffer in real-time requires Core Audio APIs
        // This is a placeholder for the volume control logic
        // For actual implementation, you would use an AVAudioEngine with volume nodes
        return sampleBuffer
    }
}

// MARK: - AudioLevelMeterDelegate

extension AudioMixer: AudioLevelMeterDelegate {
    func audioLevelMeter(_ meter: AudioLevelMeter, didUpdateLevels levels: AudioLevelMetrics) {
        // Levels are updated - UI will be notified through the shared level meter
    }
}
