import SwiftUI
import AppKit
import CoreAudio

struct AudioOutputSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var devices: [AudioOutputDevice] = []
    @State private var selectedDeviceID: AudioDeviceID?

    private var mode: AppTheme.Mode { colorScheme == .dark ? .dark : .light }
    private var primaryText: Color { AppTheme.color(.primaryText, in: mode) }
    private var secondaryText: Color { AppTheme.color(.secondaryText, in: mode) }

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            Text("Audio Outputs")
                .font(.title3.weight(.semibold))
                .foregroundColor(primaryText)

            if devices.isEmpty {
                Text("No available output devices")
                    .foregroundColor(secondaryText)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(devices, id: \.id) { device in
                            deviceRow(device)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 420)
        .background(AppTheme.color(.background, in: mode))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            devices = getOutputDevices()
            selectedDeviceID = getDefaultOutputDeviceID()
        }
        .accessibilityIdentifier("AudioOutputSelectionView")
    }

    private func deviceRow(_ device: AudioOutputDevice) -> some View {
        let isSelected = device.id == selectedDeviceID

        return Button {
            selectedDeviceID = device.id
            AudioOutputManager.shared.setOutputDevice(deviceID: device.id)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: iconNameForDevice(device.id))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? AppTheme.accent : primaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .foregroundColor(primaryText)
                        .font(.body)
                    if isSelected {
                        Text("Current output")
                            .font(.caption)
                            .foregroundColor(AppTheme.accent)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(rowBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isSelected ? "AudioOutput_SelectedDeviceRow" : "AudioOutput_DeviceRow_\(device.id)")
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? AppTheme.color(.hoverSurface, in: mode) : AppTheme.color(.surface, in: mode))
            .shadow(color: AppTheme.color(.secondaryText, in: mode).opacity(isSelected ? 0.18 : 0.08), radius: 5, x: 0, y: 3)
    }
}

// MARK: - Device Helpers (existing implementation retained below)

extension AudioOutputSelectionView {
    private func getDeviceName(for deviceID: AudioDeviceID,
                               address: inout AudioObjectPropertyAddress,
                               size: inout UInt32) -> CFString? {
        var name: CFString? = nil
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        return status == noErr ? name : nil
    }

    func getOutputDevices() -> [AudioOutputDevice] {
        // existing implementation ...
        var outputDevices: [AudioOutputDevice] = []
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(systemObjectID, &propertyAddress, 0, nil, &dataSize)
        if status != noErr {
            print("Error getting data size for audio devices: \(status)")
            return []
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status2 = AudioObjectGetPropertyData(systemObjectID, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        if status2 != noErr {
            print("Error getting audio devices: \(status2)")
            return []
        }
        for id in deviceIDs {
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            if let deviceName = getDeviceName(for: id, address: &nameAddress, size: &nameSize) {
                outputDevices.append(AudioOutputDevice(id: id, name: deviceName as String))
            }
        }
        if outputDevices.isEmpty {
            var defaultDeviceID = AudioDeviceID(0)
            var sizeDefault = UInt32(MemoryLayout<AudioDeviceID>.size)
            var defaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let statusDefault = AudioObjectGetPropertyData(systemObjectID, &defaultAddress, 0, nil, &sizeDefault, &defaultDeviceID)
            if statusDefault == noErr, defaultDeviceID != 0 {
                var nameSize = UInt32(MemoryLayout<CFString?>.size)
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                if let deviceName = getDeviceName(for: defaultDeviceID, address: &nameAddress, size: &nameSize) {
                    outputDevices.append(AudioOutputDevice(id: defaultDeviceID, name: deviceName as String))
                }
            }
        }
        return outputDevices
    }

    func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var defaultDeviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDeviceID)
        return status == noErr ? defaultDeviceID : nil
    }

    func iconNameForDevice(_ deviceID: AudioDeviceID) -> String {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)

        if status == noErr {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth: return "headphones"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeBuiltIn: return "speaker.wave.3.fill"
            default: break
            }
        }

        if let defaultID = getDefaultOutputDeviceID(), defaultID == deviceID {
            return "speaker.wave.3.fill"
        }

        return "hifispeaker.fill"
    }
}

// Placeholder model retained from original implementation
struct AudioOutputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
}
