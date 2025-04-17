// PodRams
// Created by Tom Björnebark on 2025-02-25.


import SwiftUI
import CoreAudio

/// Data model representing an audio output device.
struct AudioOutputDevice: Identifiable {
    /// Unique identifier for the device.
    let id: AudioDeviceID
    /// Readable name of the device.
    let name: String
}

// MARK: - Helpers
extension AudioOutputSelectionView {
    /// Returns the current default output device ID.
    func getDefaultOutputDeviceID() -> AudioDeviceID? {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var defaultID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &defaultID)
        return (status == noErr && defaultID != 0) ? defaultID : nil
    }

    /// Returns a SF Symbol name representing the transport type of the device.
    func iconNameForDevice(_ id: AudioDeviceID) -> String {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        let iconMap: [UInt32: String] = [
            kAudioDeviceTransportTypeBluetooth: "headphones",
            kAudioDeviceTransportTypeBuiltIn: "speaker.fill",
            kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        ]
        return (status == noErr ? iconMap[transport] : nil) ?? "speaker"
    }
}

/// A SwiftUI view that displays available audio output devices and lets the user select one.
struct AudioOutputSelectionView: View {
    /// Environment property to dismiss the current view.
    @Environment(\.dismiss) var dismiss
    /// Local state holding the list of discovered audio output devices.
    @State private var devices: [AudioOutputDevice] = []
    @State private var selectedDeviceID: AudioDeviceID? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if devices.isEmpty {
                Text("No available output devices")
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Selected device first
                        if let selID = selectedDeviceID,
                           let selDevice = devices.first(where: { $0.id == selID }) {
                            Button(action: {
                                selectedDeviceID = selDevice.id
                                AudioOutputManager.shared.setOutputDevice(deviceID: selDevice.id)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: iconNameForDevice(selDevice.id))
                                        .frame(width: 24, height: 24)
                                    Text(selDevice.name)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .accessibilityIdentifier("AudioOutput_SelectedDeviceRow")
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Other devices header and list
                        if devices.count > 1 {
                            Text("Switch to:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 12)
                                .accessibilityIdentifier("AudioOutput_SwitchToHeader")

                            ForEach(Array(devices.filter { $0.id != selectedDeviceID }.enumerated()), id: \.element.id) { index, device in
                                Button(action: {
                                    selectedDeviceID = device.id
                                    AudioOutputManager.shared.setOutputDevice(deviceID: device.id)
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: iconNameForDevice(device.id))
                                            .frame(width: 24, height: 24)
                                        Text(device.name)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                                .accessibilityIdentifier("AudioOutput_DeviceRow_\(index)")
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("AudioOutputSelectionView")
        // On view appearance, populate the list of devices.
        .onAppear {
            devices = getOutputDevices()
            // Load current default output
            selectedDeviceID = getDefaultOutputDeviceID()
        }
        .frame(minWidth: 300, minHeight: 400)
    }
    
    /// Helper function to safely retrieve a CFString property for a given audio device.
    /// - Parameters:
    ///   - deviceID: The unique identifier of the audio device.
    ///   - address: The property address to query.
    ///   - size: The size of the property data.
    /// - Returns: The CFString value if retrieval succeeds; otherwise, nil.
    private func getDeviceName(for deviceID: AudioDeviceID,
                               address: inout AudioObjectPropertyAddress,
                               size: inout UInt32) -> CFString? {
        var name: CFString? = nil
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        return status == noErr ? name : nil
    }
    
    /// Retrieves a list of audio output devices from the system.
    ///
    /// The function queries the Core Audio system for available devices,
    /// filters for devices that have an output stream, and returns them along with their names.
    /// If no devices are found, it attempts to include the default output device.
    ///
    /// - Returns: An array of `AudioOutputDevice` representing available output devices.
    func getOutputDevices() -> [AudioOutputDevice] {
        var outputDevices: [AudioOutputDevice] = []
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        
        // Query the system for all audio devices.
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
        
        // Calculate the number of devices based on the data size.
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status2 = AudioObjectGetPropertyData(systemObjectID, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        if status2 != noErr {
            print("Error getting audio devices: \(status2)")
            return []
        }
        
        // Prepare the property address to query for output streams.
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0)
        
        // List all audio devices by name; system will handle valid output targets
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
        
        // If no output devices were found, try to add the default output device.
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
                    let name = deviceName as String
                    outputDevices.append(AudioOutputDevice(id: defaultDeviceID, name: name))
                }
            }
        }
        // Deduplicate devices by name, preferring the current default output device.
        var finalDevices: [AudioOutputDevice] = []
        var seenNames = Set<String>()
        // Ensure the default device appears first
        if let defaultID = getDefaultOutputDeviceID(), let defaultDevice = outputDevices.first(where: { $0.id == defaultID }) {
            finalDevices.append(defaultDevice)
            seenNames.insert(defaultDevice.name)
        }
        // Append remaining devices, skipping duplicates by name
        for device in outputDevices {
            if !seenNames.contains(device.name) {
                finalDevices.append(device)
                seenNames.insert(device.name)
            }
        }
        return finalDevices
    }
}
