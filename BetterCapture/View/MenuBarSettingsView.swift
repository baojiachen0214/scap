//
//  MenuBarSettingsView.swift
//  BetterCapture
//
//  Created by Joshua Sattler on 02.02.26.
//

import SwiftUI

// MARK: - Section Divider

/// A styled divider for menu bar sections
struct SectionDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

// MARK: - Section Header

/// A styled section header for menu bar (bold, not uppercase)
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

// MARK: - Menu Bar Divider (smaller)

/// A styled divider for menu bar
struct MenuBarDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

// MARK: - Toggle Row

/// A menu bar style toggle with a switch on the right side and hover effect
struct MenuBarToggle: View {
    let name: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDisabled ? .secondary : .primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(.blue)
                .scaleEffect(0.8)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && !isDisabled ? .gray.opacity(0.1) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Expandable Picker Row

/// A menu bar style picker that expands inline to show options with hover effect
struct MenuBarExpandablePicker<SelectionValue: Hashable & Equatable>: View {
    let name: String
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, label: String, isDisabled: Bool, disabledMessage: String?)]
    @State private var isExpanded = false
    @State private var isHovered = false

    /// Convenience initializer for simple options without disabled state
    init(
        name: String,
        selection: Binding<SelectionValue>,
        options: [(value: SelectionValue, label: String)]
    ) {
        self.name = name
        self._selection = selection
        self.options = options.map { ($0.value, $0.label, false, nil) }
    }

    /// Full initializer with disabled state support
    init(
        name: String,
        selection: Binding<SelectionValue>,
        optionsWithState: [(value: SelectionValue, label: String, isDisabled: Bool, disabledMessage: String?)]
    ) {
        self.name = name
        self._selection = selection
        self.options = optionsWithState
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(currentLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? .gray.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded options
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(options, id: \.value) { option in
                        PickerOptionRow(
                            label: option.label,
                            isSelected: selection == option.value,
                            isDisabled: option.isDisabled,
                            disabledMessage: option.disabledMessage
                        ) {
                            selection = option.value
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .background(.quaternary.opacity(0.3))
            }
        }
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }
}

// MARK: - Picker Option Row

/// A single option row in an expandable picker with hover effect
struct PickerOptionRow: View {
    let label: String
    let isSelected: Bool
    var isDisabled: Bool = false
    var disabledMessage: String? = nil
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(isDisabled ? .tertiary : .primary)
                    if isDisabled, let message = disabledMessage {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && !isDisabled ? .gray.opacity(0.1) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Device Row (for microphone selection)

/// A device selection row with icon in circle, native macOS style
struct DeviceRow: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon in circle
                ZStack {
                    Circle()
                        .fill(isSelected ? .blue.opacity(0.8) : .gray.opacity(0.3))
                        .frame(width: 24, height: 24)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                }

                // Name
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                // Checkmark when selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? .gray.opacity(0.1) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Microphone Expandable Picker

/// A microphone picker with device-style rows (icon in circle)
struct MicrophoneExpandablePicker: View {
    @Binding var selectedID: String?
    let devices: [AudioInputDevice]
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Microphone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(currentLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? .gray.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded device options
            if isExpanded {
                VStack(spacing: 0) {
                    // System Default option
                    DeviceRow(
                        name: "System Default",
                        icon: "mic",
                        isSelected: selectedID == nil
                    ) {
                        selectedID = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    }

                    // Available devices
                    ForEach(devices) { device in
                        DeviceRow(
                            name: device.name,
                            icon: device.isDefault ? "mic.fill" : "mic",
                            isSelected: selectedID == device.id
                        ) {
                            selectedID = device.id
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .background(.quaternary.opacity(0.3))
            }
        }
    }

    private var currentLabel: String {
        if let id = selectedID, let device = devices.first(where: { $0.id == id }) {
            return device.name
        }
        return "System Default"
    }
}

// MARK: - Expandable Section (for arbitrary content)

/// A menu bar style expandable section with hover effect
struct MenuBarExpandableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? .gray.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded content
            if isExpanded {
                VStack(spacing: 0) {
                    content
                }
                .padding(.leading, 12)
                .background(.quaternary.opacity(0.3))
            }
        }
    }
}

// MARK: - Video Settings Section

/// Video settings section with header and inline content
struct VideoSettingsSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Video")

            // Content Filter Section
            MenuBarExpandableSection(title: "Content Filter") {
                MenuBarToggle(name: "Show Cursor", isOn: $settings.showCursor)
                MenuBarToggle(name: "Show Wallpaper", isOn: $settings.showWallpaper)
                MenuBarToggle(name: "Show Menu Bar", isOn: $settings.showMenuBar)
                MenuBarToggle(name: "Show Dock", isOn: $settings.showDock)
                MenuBarToggle(name: "Show Window Shadows", isOn: $settings.showWindowShadows)
                MenuBarToggle(name: "Show BetterCapture", isOn: $settings.showBetterCapture)
            }

            // Frame Rate Picker
            MenuBarExpandablePicker(
                name: "Frame Rate",
                selection: $settings.frameRate,
                options: FrameRate.allCases.map { ($0, $0.displayName) }
            )

            // Video Codec Picker (shows all codecs, disables incompatible ones)
            MenuBarExpandablePicker(
                name: "Codec",
                selection: $settings.videoCodec,
                optionsWithState: VideoCodec.allCases.map { codec in
                    let isSupported = settings.containerFormat.supportedVideoCodecs.contains(codec)
                    return (
                        value: codec,
                        label: codec.rawValue,
                        isDisabled: !isSupported,
                        disabledMessage: isSupported ? nil : "Not supported for \(settings.containerFormat.rawValue.uppercased())"
                    )
                }
            )

            // Container Format Picker
            MenuBarExpandablePicker(
                name: "Container",
                selection: $settings.containerFormat,
                options: ContainerFormat.allCases.map { ($0, $0.rawValue.uppercased()) }
            )

            // Alpha Channel Toggle (disabled if codec doesn't support or container doesn't support)
            MenuBarToggle(
                name: "Capture Alpha Channel",
                isOn: $settings.captureAlphaChannel,
                isDisabled: !settings.videoCodec.canToggleAlpha || !settings.containerFormat.supportsAlphaChannel
            )

            // HDR Recording Toggle (disabled for codecs that don't support HDR)
            MenuBarToggle(
                name: "HDR Recording",
                isOn: $settings.captureHDR,
                isDisabled: !settings.videoCodec.supportsHDR
            )
        }
    }
}

// MARK: - Audio Settings Section

/// Audio settings section with header and inline content
struct AudioSettingsSection: View {
    @Bindable var settings: SettingsStore
    let audioDeviceService: AudioDeviceService

    var body: some View {
        VStack(spacing: 0) {
            // Separator before Audio section
            SectionDivider()

            SectionHeader(title: "Audio")

            // System Audio Toggle
            MenuBarToggle(name: "Capture System Audio", isOn: $settings.captureSystemAudio)

            // Microphone Toggle
            MenuBarToggle(name: "Capture Microphone", isOn: $settings.captureMicrophone)

            // Microphone Source Picker (only shown when microphone is enabled)
            if settings.captureMicrophone {
                MicrophoneExpandablePicker(
                    selectedID: $settings.selectedMicrophoneID,
                    devices: audioDeviceService.availableDevices
                )
            }

            // Audio Codec Picker (shows all codecs, disables incompatible ones)
            MenuBarExpandablePicker(
                name: "Audio Codec",
                selection: $settings.audioCodec,
                optionsWithState: AudioCodec.allCases.map { codec in
                    let isSupported = settings.containerFormat.supportedAudioCodecs.contains(codec)
                    return (
                        value: codec,
                        label: codec.rawValue,
                        isDisabled: !isSupported,
                        disabledMessage: isSupported ? nil : "Not supported for \(settings.containerFormat.rawValue.uppercased())"
                    )
                }
            )
        }
    }
}

// MARK: - Camera Expandable Picker

/// A camera picker with device-style rows, matching the microphone picker pattern
struct CameraExpandablePicker: View {
    @Binding var selectedID: String?
    let devices: [CameraDevice]
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Camera")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(currentLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? .gray.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded device options
            if isExpanded {
                VStack(spacing: 0) {
                    // System Default option
                    DeviceRow(
                        name: "System Default",
                        icon: "camera",
                        isSelected: selectedID == nil
                    ) {
                        selectedID = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    }

                    // Available devices
                    ForEach(devices) { device in
                        DeviceRow(
                            name: device.name,
                            icon: "camera",
                            isSelected: selectedID == device.id
                        ) {
                            selectedID = device.id
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .background(.quaternary.opacity(0.3))
            }
        }
    }

    private var currentLabel: String {
        if let id = selectedID, let device = devices.first(where: { $0.id == id }) {
            return device.name
        }
        return "System Default"
    }
}

// MARK: - Presenter Overlay Settings Section

/// Presenter Overlay toggle and camera picker
struct PresenterOverlaySettingsSection: View {
    @Bindable var settings: SettingsStore
    let cameraDeviceService: CameraDeviceService

    var body: some View {
        VStack(spacing: 0) {
            SectionDivider()

            SectionHeader(title: "Camera")

            MenuBarToggle(name: "Presenter Overlay", isOn: $settings.presenterOverlayEnabled)

            if settings.presenterOverlayEnabled {
                CameraExpandablePicker(
                    selectedID: $settings.selectedCameraID,
                    devices: cameraDeviceService.availableDevices
                )
            }
        }
    }
}

// MARK: - Audio Control Panel Entry

/// A compact audio control panel entry in the menu bar with level meters and volume sliders
struct AudioControlPanelEntry: View {
    @MainActor @Bindable var mixer: AudioMixer
    @MainActor @Bindable var settings: SettingsStore
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row - click to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    // Icon with indicator
                    ZStack {
                        Circle()
                            .fill(.gray.opacity(0.2))
                            .frame(width: 24, height: 24)

                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    Text("音频控制")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? .gray.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )

            // Expanded content
            if isExpanded {
                VStack(spacing: 8) {
                    // Mini level meters
                    HStack(spacing: 16) {
                        MiniLevelMeter(
                            level: mixer.levelMeter.currentLevels.systemAudioLevel,
                            color: .blue,
                            label: "系统音频"
                        )

                        MiniLevelMeter(
                            level: mixer.levelMeter.currentLevels.microphoneLevel,
                            color: .green,
                            label: "麦克风"
                        )
                    }
                    .padding(.horizontal, 12)

                    // Volume sliders
                    VStack(spacing: 6) {
                        MiniVolumeSlider(
                            volume: $mixer.systemAudioVolume,
                            isMuted: $mixer.isSystemAudioMuted,
                            label: "系统音频"
                        )

                        MiniVolumeSlider(
                            volume: $mixer.microphoneVolume,
                            isMuted: $mixer.isMicrophoneMuted,
                            label: "麦克风"
                        )
                    }
                    .padding(.horizontal, 12)

                    // Audio effects toggles
                    VStack(spacing: 4) {
                        HStack {
                            Toggle("降噪", isOn: .init(
                                get: { settings.noiseReductionAmount > 0 },
                                set: { newValue in
                                    settings.noiseReductionAmount = newValue ? 0.5 : 0
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .scaleEffect(0.9)

                            Toggle("自动增益", isOn: $settings.autoGainControlEnabled)
                                .toggleStyle(.checkbox)
                                .scaleEffect(0.9)

                            Toggle("压缩", isOn: $settings.compressionEnabled)
                                .toggleStyle(.checkbox)
                                .scaleEffect(0.9)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))
            }
        }
    }
}

// MARK: - Mini Level Meter

struct MiniLevelMeter: View {
    let level: Float
    let color: Color
    let label: String

    @State private var displayLevel: Float = -60

    var body: some View {
        VStack(spacing: 4) {
            // Level bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: CGFloat(max(0, min(1, (displayLevel + 60) / 60))) * geometry.size.width, height: 8)
                }
            }
            .frame(height: 8)
            .onChange(of: level) { _, newLevel in
                withAnimation(.easeOut(duration: 0.1)) {
                    displayLevel = newLevel
                }
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mini Volume Slider

struct MiniVolumeSlider: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { isMuted.toggle() }) {
                Image(systemName: isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(volume == 0 ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            Slider(value: $volume, in: 0...1, step: 0.01)
                .disabled(isMuted)

            Text("\(Int(volume * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        VideoSettingsSection(settings: SettingsStore())
        PresenterOverlaySettingsSection(settings: SettingsStore(), cameraDeviceService: CameraDeviceService())
        AudioControlPanelEntry(mixer: AudioMixer(), settings: SettingsStore())
        AudioSettingsSection(settings: SettingsStore(), audioDeviceService: AudioDeviceService())
    }
    .frame(width: 320)
    .padding(.vertical, 8)
}
