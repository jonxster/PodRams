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

/// A SwiftUI view that displays available audio output devices and lets the user select one.
struct AudioOutputSelectionView: View {
    /// Environment property to dismiss the current view.
    @Environment(\.dismiss) var dismiss
    /// Local state holding the list of discovered audio output devices.
    @State private var devices: [AudioOutputDevice] = []
    
    var body: some View {
        VStack {
            // Header text for the selection view.
            Text("Select Audio Output")
                .font(.headline)
                .padding()
            
            // Display a message if no devices are available, otherwise list the devices.
            if devices.isEmpty {
                Text("No available output devices")
                    .padding()
            } else {
                List(devices) { device in
                    // Each device is rendered as a button. Tapping the button sets the device as default and dismisses the view.
                    Button(action: {
                        AudioOutputManager.shared.setOutputDevice(deviceID: device.id)
                        dismiss()
                    }) {
                        Text(device.name)
                    }
                }
            }
        }
        // On view appearance, populate the list of devices.
        .onAppear {
            devices = getOutputDevices()
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
        
        // Iterate over each device to determine if it supports output.
        for id in deviceIDs {
            if AudioObjectHasProperty(id, &outputAddress) {
                var streamSize: UInt32 = 0
                let status3 = AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &streamSize)
                if status3 == noErr, streamSize > 0 {
                    // Ensure the device has at least one valid output stream.
                    let streamCount = streamSize / UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    if streamCount > 0 {
                        var nameSize = UInt32(MemoryLayout<CFString?>.size)
                        var nameAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioObjectPropertyName,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain)
                        // Retrieve the device's name.
                        if let deviceName = getDeviceName(for: id, address: &nameAddress, size: &nameSize) {
                            let name = deviceName as String
                            outputDevices.append(AudioOutputDevice(id: id, name: name))
                        }
                    }
                }
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
        return outputDevices
    }
}
