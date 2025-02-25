//
//  AudioOutputManager.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// AudioOutputManager.swift

import Foundation
import CoreAudio
import AudioToolbox
import Combine

final class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published var currentRouteIcon: String = "speaker"
    @Published var deviceName: String = "Unknown"

    private var propertyListenerAdded = false
    private var lastUpdateTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.2
    private var cancellables = Set<AnyCancellable>()

    private static var cCallback: AudioObjectPropertyListenerProc = { objectID, addressesCount, addresses, clientData in
        guard let manager = clientData.map({ Unmanaged<AudioOutputManager>.fromOpaque($0).takeUnretainedValue() }) else {
            return kAudioHardwareUnspecifiedError
        }
        DispatchQueue.main.async {
            let now = Date()
            guard now.timeIntervalSince(manager.lastUpdateTime) >= manager.debounceInterval else { return }
            manager.updateOutput()
            manager.lastUpdateTime = now
        }
        return noErr
    }

    init() {
        setupThrottling()
        updateOutput()
        addPropertyListener()
    }

    deinit {
        removePropertyListener()
        cancellables.removeAll()
    }

    private func setupThrottling() {
        $currentRouteIcon
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] icon in self?.currentRouteIcon = icon }
            .store(in: &cancellables)
        
        $deviceName
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] name in self?.deviceName = name }
            .store(in: &cancellables)
    }

    func updateOutput() {
        let (transport, name) = getDeviceInfo()
        currentRouteIcon = icon(for: transport)
        deviceName = name.isEmpty ? "Unknown" : name
    }

    private func icon(for transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth:
            return "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            return "speaker.fill"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default:
            return "speaker"
        }
    }

    private func getDeviceInfo() -> (UInt32, String) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status1 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status1 == noErr, deviceID != 0 else {
            return (0, "Unknown")
        }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        let status2 = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        if status2 != noErr { transport = 0 }

        size = UInt32(MemoryLayout<CFString?>.size)
        address.mSelector = kAudioObjectPropertyName
        let namePtr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        namePtr.initialize(to: nil)
        defer {
            namePtr.deinitialize(count: 1)
            namePtr.deallocate()
        }
        let status3 = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, namePtr)
        let nameString = (status3 == noErr && namePtr.pointee != nil) ? String(namePtr.pointee!) : "Unknown"

        return (transport, nameString)
    }

    private func addPropertyListener() {
        guard !propertyListenerAdded else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let err = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, Self.cCallback, selfPtr)
        if err == noErr {
            propertyListenerAdded = true
        } else {
            print("Failed to add audio property listener: \(err)")
        }
    }

    private func removePropertyListener() {
        guard propertyListenerAdded else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let err = AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, Self.cCallback, selfPtr)
        if err == noErr {
            propertyListenerAdded = false
        } else {
            print("Failed to remove audio property listener: \(err)")
        }
    }
    
    func setOutputDevice(deviceID: AudioDeviceID) {
        var newDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let error = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &newDeviceID)
        if error == noErr {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateOutput()
            }
        } else {
            print("Error setting output device: \(error)")
        }
    }
}
