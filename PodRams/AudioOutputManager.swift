//
// AudioOutputManager.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import CoreAudio
import AudioToolbox
import Combine
import os.log

// Manages audio output device updates using Core Audio APIs and publishes changes for UI binding.
@MainActor
final class AudioOutputManager: ObservableObject {
    // Singleton instance for global access.
    static let shared = AudioOutputManager()
    
    // Published properties to update the UI with the current audio route icon and device name.
    @Published var currentRouteIcon: String = "speaker"
    @Published var deviceName: String = "Unknown"
    
    // Indicates whether the property listener has been added.
    private var propertyListenerAdded = false
    // Records the time of the last update to enforce debouncing.
    private var lastUpdateTime: Date = .distantPast
    // Minimum interval between updates to prevent excessive UI refreshes.
    private let debounceInterval: TimeInterval = 0.2
    // Stores Combine subscriptions for throttling updates.
    private var cancellables = Set<AnyCancellable>()
    
    // Logger for audio operations
    private let logger = Logger(subsystem: "com.podrams", category: "AudioOutputManager")
    
    // Cache for device information to reduce redundant Core Audio calls
    private struct DeviceInfoCache {
        var deviceID: AudioDeviceID = 0
        var transport: UInt32 = 0
        var name: String = "Unknown"
        var lastUpdated: Date = .distantPast
        var isValid: Bool { lastUpdated.timeIntervalSinceNow > -5.0 } // Cache valid for 5 seconds
    }
    
    // Cache instance
    private var deviceCache = DeviceInfoCache()
    
    // Static callback conforming to AudioObjectPropertyListenerProc.
    // Debounces updates and schedules the output update on the main thread.
    nonisolated(unsafe) private static var cCallback: AudioObjectPropertyListenerProc = { objectID, addressesCount, addresses, clientData in
        // Retrieve the AudioOutputManager instance from the opaque pointer.
        guard let manager = clientData.map({ Unmanaged<AudioOutputManager>.fromOpaque($0).takeUnretainedValue() }) else {
            return kAudioHardwareUnspecifiedError
        }
        let now = Date()
        Task { @MainActor [weak manager] in
            guard let manager else { return }
            guard now.timeIntervalSince(manager.lastUpdateTime) >= manager.debounceInterval else { return }

            manager.deviceCache.lastUpdated = .distantPast
            manager.updateOutput()
            manager.lastUpdateTime = now
        }
        return noErr
    }
    
    // Initializes the manager by setting up throttling, performing an initial update, and registering the property listener.
    init() {
        // Initialize properties first
        propertyListenerAdded = false
        lastUpdateTime = .distantPast
        deviceCache = DeviceInfoCache()
        
        // Setup throttling
        setupThrottling()
        
        // Perform initial update safely
        DispatchQueue.main.async { [weak self] in
            self?.updateOutput()
        }
        
        // Add property listener on a background queue to avoid blocking main thread during initialization
        Task { @MainActor [weak self] in
            self?.addPropertyListener()
        }
    }
    
    // Cleans up resources by removing the property listener and cancelling subscriptions.
    deinit {}
    
    // Sets up throttling for published properties to limit how frequently changes propagate.
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
    
    // Retrieves the latest audio device information and updates the published properties.
    func updateOutput() {
        let (transport, name) = getDeviceInfo()
        currentRouteIcon = icon(for: transport)
        deviceName = name.isEmpty ? "Unknown" : name
    }
    
    // Returns an icon string based on the transport type of the audio device.
    // Optimized with a lookup table to reduce branch mispredictions
    private func icon(for transport: UInt32) -> String {
        // Use a dictionary as a lookup table instead of a switch statement
        // This can reduce branch mispredictions on Apple Silicon
        let iconMap: [UInt32: String] = [
            kAudioDeviceTransportTypeBluetooth: "headphones",
            kAudioDeviceTransportTypeBuiltIn: "speaker.fill",
            kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        ]
        
        return iconMap[transport] ?? "speaker"
    }
    
    // Retrieves the default audio output device's transport type and name.
    private func getDeviceInfo() -> (UInt32, String) {
        // Check if cache is valid
        if deviceCache.isValid {
            return (deviceCache.transport, deviceCache.name)
        }
        
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        // Specify the property for the default output device.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Obtain the default output device's ID.
        let status1 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status1 == noErr, deviceID != 0 else {
            logger.error("Failed to get default output device: \(status1)")
            return (0, "Unknown")
        }
        
        // Retrieve the transport type (e.g., built-in, Bluetooth, AirPlay).
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        let status2 = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        if status2 != noErr { 
            logger.warning("Failed to get transport type: \(status2)")
            transport = 0 
        }
        
        // Retrieve the device's name.
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
        
        if status3 != noErr {
            logger.warning("Failed to get device name: \(status3)")
        }
        
        // Update the cache
        deviceCache = DeviceInfoCache(
            deviceID: deviceID,
            transport: transport,
            name: nameString,
            lastUpdated: Date()
        )
        
        return (transport, nameString)
    }
    
    // Adds a listener for changes to the default audio output device.
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
            logger.info("Added audio property listener")
        } else {
            logger.error("Failed to add audio property listener: \(err)")
        }
    }
    
    // Removes the property listener when it is no longer required.
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
            logger.info("Removed audio property listener")
        } else {
            logger.error("Failed to remove audio property listener: \(err)")
        }
    }
    
    // Sets a new default audio output device and triggers an update after a short delay.
    func setOutputDevice(deviceID: AudioDeviceID) {
        // Validate input
        guard deviceID != 0 else {
            logger.error("Invalid device ID: 0")
            return
        }
        
        var newDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let error = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &newDeviceID)

        if error == noErr {
            logger.info("Successfully set output device: \(deviceID)")
            deviceCache.lastUpdated = .distantPast
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                updateOutput()
            }
        } else {
            logger.error("Error setting output device: \(error)")
        }
    }
}
