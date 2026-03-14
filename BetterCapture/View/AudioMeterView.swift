//
//  AudioMeterView.swift
//  BetterCapture
//
//  Created for scap project - Audio visualization UI
//

import SwiftUI

/// Vertical level meter bar
struct LevelMeterBar: View {
    let level: Float
    let peakLevel: Float
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: geometry.size.width, height: height)

                // Level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(gradientForLevel(level))
                    .frame(width: geometry.size.width, height: levelHeight(for: level, in: geometry.size.height))

                // Peak marker
                if peakLevel > -60 {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width, height: 2)
                        .offset(y: -levelHeight(for: peakLevel, in: geometry.size.height) + 1)
                }
            }
        }
        .frame(height: height)
    }

    private func levelHeight(for dbLevel: Float, in totalHeight: CGFloat) -> CGFloat {
        // Map -60dB to 0dB into 0 to totalHeight
        let normalized = max(0, min(1, (dbLevel + 60) / 60))
        // Use logarithmic scale for more realistic meter response
        let logNormalized = pow(normalized, 0.5)
        return CGFloat(logNormalized) * totalHeight
    }

    private func gradientForLevel(_ level: Float) -> LinearGradient {
        let normalized = max(0, min(1, (level + 60) / 60))

        if normalized > 0.8 {
            return LinearGradient(
                gradient: Gradient(colors: [.green, .yellow, .red]),
                startPoint: .bottom,
                endPoint: .top
            )
        } else if normalized > 0.5 {
            return LinearGradient(
                gradient: Gradient(colors: [.green, .yellow]),
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [color.opacity(0.5), color]),
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }
}

/// Audio level meter showing both system audio and microphone
struct AudioLevelMeterView: View {
    @MainActor @Bindable var mixer: AudioMixer

    @State private var systemLevel: Float = -60
    @State private var systemPeak: Float = -60
    @State private var micLevel: Float = -60
    @State private var micPeak: Float = -60

    private let meterWidth: CGFloat = 20
    private let meterHeight: CGFloat = 120

    var body: some View {
        HStack(spacing: 12) {
            // System Audio Meter
            VStack(spacing: 4) {
                LevelMeterBar(
                    level: systemLevel,
                    peakLevel: systemPeak,
                    color: .blue,
                    height: meterHeight
                )
                .frame(width: meterWidth)

                Text("系统音频")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Microphone Meter
            VStack(spacing: 4) {
                LevelMeterBar(
                    level: micLevel,
                    peakLevel: micPeak,
                    color: .green,
                    height: meterHeight
                )
                .frame(width: meterWidth)

                Text("麦克风")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            startLevelUpdates()
        }
    }

    private func startLevelUpdates() {
        // Update level meter display from the mixer
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let levels = mixer.levelMeter.currentLevels
            withAnimation(.easeOut(duration: 0.05)) {
                systemLevel = levels.systemAudioLevel
                systemPeak = levels.systemAudioPeak
                micLevel = levels.microphoneLevel
                micPeak = levels.microphonePeak
            }
        }
    }
}

/// Volume slider with mute button
struct VolumeSlider: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { isMuted.toggle() }) {
                Image(systemName: isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundStyle(volume == 0 ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Slider(value: $volume, in: 0...1, step: 0.01) {
                Text("\(Int(volume * 100))%")
            } minimumValueLabel: {
                Text("0%")
            } maximumValueLabel: {
                Text("100%")
            }
            .disabled(isMuted)
        }
    }
}

/// Complete audio control panel
struct AudioControlPanel: View {
    @MainActor @Bindable var mixer: AudioMixer
    @MainActor @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 16) {
            // Level Meters
            AudioLevelMeterView(mixer: mixer)
                .padding(.vertical, 8)

            Divider()

            // Volume Controls
            VStack(spacing: 12) {
                VolumeSlider(
                    volume: $mixer.systemAudioVolume,
                    isMuted: $mixer.isSystemAudioMuted,
                    label: "系统音频",
                    icon: "speaker.wave.2.fill"
                )

                VolumeSlider(
                    volume: $mixer.microphoneVolume,
                    isMuted: $mixer.isMicrophoneMuted,
                    label: "麦克风",
                    icon: "mic.fill"
                )
            }

            Divider()

            // Audio Effects
            GroupBox("音频效果") {
                VStack(spacing: 10) {
                    HStack {
                        Toggle("降噪", isOn: .init(
                            get: { settings.noiseReductionAmount > 0 },
                            set: { newValue in
                                settings.noiseReductionAmount = newValue ? 0.5 : 0
                            }
                        ))
                        Slider(value: $settings.noiseReductionAmount, in: 0...1)
                            .frame(width: 80)
                    }

                    Toggle("自动增益", isOn: $settings.autoGainControlEnabled)

                    Toggle("压缩器", isOn: $settings.compressionEnabled)

                    Toggle("多音轨输出", isOn: $settings.enableMultiTrackOutput)
                        .help("将系统音频和麦克风保存为独立音轨")
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

#Preview {
    AudioControlPanel(
        mixer: AudioMixer(),
        settings: SettingsStore()
    )
    .frame(width: 300)
}
