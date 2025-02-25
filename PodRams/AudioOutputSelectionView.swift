//
//  AudioOutputSelectionView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import CoreAudio

struct AudioOutputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
}

struct AudioOutputSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @State private var devices: [AudioOutputDevice] = []
    
    var body: some View {
        VStack {
            Text("Select Audio Output")
                .font(.headline)
                .padding()
            if devices.isEmpty {
                Text("No available output devices")
                    .padding()
            } else {
                List(devices) { device in
                    Button(action: {
                        AudioOutputManager.shared.setOutputDevice(deviceID: device.id)
                        dismiss()
                    }) {
                        Text(device.name)
                    }
                }
            }
        }
        .onAppear {
            devices = getOutputDevices()
        }
        .frame(minWidth: 300, minHeight: 400)
    }
    
    // Helper function to safely retrieve a CFString property.
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
        
        // Prepare the output stream property address.
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0)
        
        for id in deviceIDs {
            if AudioObjectHasProperty(id, &outputAddress) {
                var streamSize: UInt32 = 0
                let status3 = AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &streamSize)
                if status3 == noErr, streamSize > 0 {
                    let streamCount = streamSize / UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    if streamCount > 0 {
                        var nameSize = UInt32(MemoryLayout<CFString?>.size)
                        var nameAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioObjectPropertyName,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain)
                        if let deviceName = getDeviceName(for: id, address: &nameAddress, size: &nameSize) {
                            let name = deviceName as String
                            outputDevices.append(AudioOutputDevice(id: id, name: name))
                        }
                    }
                }
            }
        }
        
        // (Optional) Include the default device if no devices were found.
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
