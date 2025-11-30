//
// CachedAsyncImage.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import AppKit
import CryptoKit

private final class CachedImageState: @unchecked Sendable {
    let lock = NSLock()
    var loadingTasks: [String: URLSessionDataTask] = [:]
    let primaryCache = NSCache<NSURL, NSImage>()
    let optimizedCache: NSCache<NSURL, NSImage>
    var failedLoadTimestamps: [String: Date] = [:]
    var cachedDirectoryURL: URL?

    init() {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 40 * 1024 * 1024 // allow a wider in-memory working set for bursts
        cache.countLimit = 180
        optimizedCache = cache
    }
}

/// A SwiftUI view that asynchronously loads an image from a URL and caches it locally.
/// If the image is already cached, it is loaded from disk; otherwise, it is downloaded and stored.
public struct CachedAsyncImage: View {
    /// URL of the image to be loaded.
    let url: URL?
    /// Desired width of the displayed image.
    let width: CGFloat
    /// Desired height of the displayed image.
    let height: CGFloat

    /// Shared cache/state container to keep global mutable state isolated behind a lock.
    nonisolated private static let cacheState = CachedImageState()
    nonisolated private static let failureCooldownPeriod: TimeInterval = 300 // 5 minutes
    nonisolated private static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 12
        config.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 96 * 1024 * 1024,
            diskPath: "PodRamsImageCache"
        )

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 12
        delegateQueue.qualityOfService = .userInitiated

        return URLSession(configuration: config, delegate: nil, delegateQueue: delegateQueue)
    }()
    
    /// The loaded image (if available) represented as an NSImage.
    @State private var loadedImage: NSImage?
    /// Tracks whether an image load operation is currently in progress.
    @State private var isLoading = false
    @State private var loadError = false
    @Environment(\.colorScheme) private var colorScheme
    // To prevent onAppear from triggering multiple loads of the same image
    @State private var hasStartedLoading = false

    /// Initializes a CachedAsyncImage view.
    /// - Parameters:
    ///   - url: The URL from which to load the image.
    ///   - width: The width for the image view.
    ///   - height: The height for the image view.
    public init(url: URL?, width: CGFloat, height: CGFloat) {
        self.url = url
        self.width = width
        self.height = height
    }

    public var body: some View {
        ZStack {
            // If the image is already loaded, display it.
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
            } else if loadError {
                // Show error placeholder
                Image(systemName: "photo")
                    .font(.system(size: min(width, height) / 3))
                    .foregroundColor(.gray)
                    .frame(width: width, height: height)
            } else {
                // Otherwise, display a placeholder rectangle.
                Rectangle()
                    // Adjust the placeholder's color opacity based on the loading state.
                    .foregroundColor(colorScheme == .dark ? 
                        Color.gray.opacity(isLoading ? 0.3 : 0.2) : 
                        Color.gray.opacity(isLoading ? 0.3 : 0.1))
                    .frame(width: width, height: height)
                    // If currently loading, overlay a loading indicator.
                    .overlay(isLoading ?
                        LoadingIndicator()
                            .frame(width: width/4, height: height/4)
                        : nil)
            }
        }
        // Load image when the view appears, but only if we haven't already started loading
        .onAppear {
            if !hasStartedLoading {
                hasStartedLoading = true
                loadImage()
            }
        }
        // Cancel the loading if the view is removed
        .onDisappear(perform: cancelLoading)
        // Use UUID to prevent redrawing when URL string changes
        .id("AsyncImage-\(width)-\(height)-\(url?.absoluteString.hashValue ?? 0)")
    }
    
    /// Cancels any loading operation in progress
    private func cancelLoading() {
        guard let url = url else { return }
        
        // Use a more robust locking mechanism
        Self.cacheState.lock.lock()
        defer { Self.cacheState.lock.unlock() }
        
        if let task = Self.cacheState.loadingTasks[url.absoluteString] {
            task.cancel()
            Self.cacheState.loadingTasks.removeValue(forKey: url.absoluteString)
        }
        
        // Reset loading state
        isLoading = false
    }

    /// Loads the image either from the cache or by downloading it.
    /// Prevents multiple concurrent load operations using the `isLoading` flag.
    private func loadImage() {
        // Ensure a valid URL is provided and that no load is already in progress.
        guard let url = url, !isLoading else { 
            return 
        }
        
        // Don't attempt to reload images that have recently failed
        let urlKey = url.absoluteString
        
        // Skip loading if dimensions are very small (likely not visible)
        if width < 5 || height < 5 {
            return
        }

        // Reset error state and immediately indicate loading ON MAIN THREAD
        // Any further checks/work happen in the background.
        loadError = false
        isLoading = true
        
        // Perform disk or network loading on a background queue to avoid blocking the UI.
        DispatchQueue.global(qos: .userInitiated).async {
            // --- Start: Moved checks inside background queue --- 
            
            // Check in-memory cache first
            if let memImage = Self.cacheState.optimizedCache.object(forKey: url as NSURL) {
                DispatchQueue.main.async {
                    loadedImage = memImage
                    isLoading = false
                }
                return // Found in memory cache, exit background task
            }

            let fileURL = Self.cachedFileURL(for: url)

            Self.cacheState.lock.lock()
            if let failureDate = Self.cacheState.failedLoadTimestamps[urlKey],
               Date().timeIntervalSince(failureDate) < Self.failureCooldownPeriod {
                Self.cacheState.lock.unlock()
                DispatchQueue.main.async {
                    isLoading = false
                    loadError = true
                }
                return
            }
            if Self.cacheState.loadingTasks[urlKey] != nil {
                Self.cacheState.lock.unlock()
                return
            }
            Self.cacheState.lock.unlock()
            
            // Attempt to load from disk cache.
            if FileManager.default.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let image = processImageData(data) {
                
                Self.cacheState.lock.lock()
                Self.cacheState.failedLoadTimestamps.removeValue(forKey: urlKey)
                Self.cacheState.optimizedCache.setObject(image, forKey: url as NSURL)
                Self.cacheState.lock.unlock()
                
                DispatchQueue.main.async {
                    loadedImage = image
                    isLoading = false
                }
                return
            } else {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    // File exists but couldn't load as image - delete corrupted cache
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            // --- Network Loading --- 
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15",
                             forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .returnCacheDataElseLoad

            Self.cacheState.lock.lock()
            if let failureDate = Self.cacheState.failedLoadTimestamps[urlKey],
               Date().timeIntervalSince(failureDate) < Self.failureCooldownPeriod {
                Self.cacheState.lock.unlock()
                DispatchQueue.main.async {
                    isLoading = false
                    loadError = true
                }
                return
            }
            if Self.cacheState.loadingTasks[urlKey] != nil {
                Self.cacheState.lock.unlock()
                return
            }

            let task = Self.imageSession.dataTask(with: request) { data, _, error in
                Self.cacheState.lock.lock()
                Self.cacheState.loadingTasks.removeValue(forKey: urlKey)
                let wasCancelled = (error as NSError?)?.code == NSURLErrorCancelled
                if error != nil && !wasCancelled {
                    Self.cacheState.failedLoadTimestamps[urlKey] = Date()
                }
                Self.cacheState.lock.unlock()

                if error != nil {
                    if wasCancelled { return }
                    DispatchQueue.main.async {
                        isLoading = false
                        loadError = true
                    }
                    return
                }

                guard let data = data, !data.isEmpty else {
                    Self.cacheState.lock.lock()
                    Self.cacheState.failedLoadTimestamps[urlKey] = Date()
                    Self.cacheState.lock.unlock()
                    DispatchQueue.main.async {
                        isLoading = false
                        loadError = true
                    }
                    return
                }

                if let image = processImageData(data) {
                    Self.storeImage(data: data, for: url)
                    Self.cacheState.lock.lock()
                    Self.cacheState.failedLoadTimestamps.removeValue(forKey: urlKey)
                    Self.cacheState.optimizedCache.setObject(image, forKey: url as NSURL)
                    Self.cacheState.lock.unlock()
                    DispatchQueue.main.async {
                        loadedImage = image
                        isLoading = false
                    }
                    return
                }

                if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                   let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                    let fallbackImage = NSImage(cgImage: cgImage, size: .zero)
                    Self.storeImage(data: data, for: url)
                    Self.cacheState.lock.lock()
                    Self.cacheState.failedLoadTimestamps.removeValue(forKey: urlKey)
                    Self.cacheState.optimizedCache.setObject(fallbackImage, forKey: url as NSURL)
                    Self.cacheState.lock.unlock()
                    DispatchQueue.main.async {
                        loadedImage = fallbackImage
                        isLoading = false
                    }
                    return
                }

                Self.cacheState.lock.lock()
                Self.cacheState.failedLoadTimestamps[urlKey] = Date()
                Self.cacheState.lock.unlock()
                DispatchQueue.main.async {
                    isLoading = false
                    loadError = true
                }
            }

            Self.cacheState.loadingTasks[urlKey] = task
            Self.cacheState.lock.unlock()

            task.resume()
        }
    }
    
    /// Processes image data to create an optimized NSImage
    nonisolated private func processImageData(_ data: Data) -> NSImage? {
        // Try creating thumbnail directly if image might be large (heuristics based on data size)
        let maxDimension: CGFloat = 600
        var potentiallyLarge = data.count > 350 * 1024 // Anything above ~350KB gets downsized
        
        if !potentiallyLarge {
            // For smaller data, try NSImage first as it's often faster
            if let image = NSImage(data: data) {
                if image.size.width < 1 || image.size.height < 1 { return nil } // Invalid dimensions
                // Check if it needs scaling anyway
                if image.size.width > maxDimension || image.size.height > maxDimension {
                    potentiallyLarge = true // Mark for thumbnail generation
                } else {
                    return image // Return directly if small enough
                }
            }
        }
        
        // If potentially large or NSImage(data:) failed, use CGImageSource for optimized loading/scaling
        let options = [kCGImageSourceShouldCache: false] as CFDictionary // Don't cache intermediate decode
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            // If CGImageSource fails, try NSBitmapImageRep as a last resort
            if let bitmap = NSBitmapImageRep(data: data) {
                let finalImage = NSImage(size: bitmap.size)
                finalImage.addRepresentation(bitmap)
                // Validate final image size
                return (finalImage.size.width >= 1 && finalImage.size.height >= 1) ? finalImage : nil
            }
            return nil // All attempts failed
        }
        
        // Check image properties (optional, but can help)
        // let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        // let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        // let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        // if width < 1 || height < 1 { return nil }
        
        // Create thumbnail if potentially large, otherwise create full image
        let thumbnailOptions = [ 
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true, // Use full image if thumbnail generation fails
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let cgImage = potentiallyLarge ? 
                CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) :
                CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { // Fallback to full image if thumbnail fails
            return nil
        }
        
        let image = NSImage(cgImage: cgImage, size: .zero) // size .zero uses CGImage's size
        
        // Final validation
        return (image.size.width >= 1 && image.size.height >= 1) ? image : nil
    }

    /// Generates a unique cache file name by computing a SHA256 hash of the URL's absolute string.
    /// - Parameter url: The URL to hash.
    /// - Returns: A fixed-length file name derived from the URL hash, including the file extension if available.
    nonisolated private static func cacheFileName(for url: URL) -> String {
        // Convert the URL's absolute string to data.
        let inputData = Data(url.absoluteString.utf8)
        // Compute the SHA256 hash.
        let hashed = SHA256.hash(data: inputData)
        // Convert the hash bytes to a hexadecimal string.
        let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        // Append the original file extension if it exists.
        let ext = url.pathExtension
        return ext.isEmpty ? hashString : "\(hashString).\(ext)"
    }
    
    /// Returns the cache directory URL, creating and caching it on first access.
    nonisolated private static func cacheDirectoryURL() -> URL? {
        if let cached = withLock({ cacheState.cachedDirectoryURL }) {
            return cached
        }

        let fileManager = FileManager.default
        do {
            let base = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PodRamsImageCache", isDirectory: true)
            
            if !fileManager.fileExists(atPath: base.path) {
                try fileManager.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
            }

            withLock {
                cacheState.cachedDirectoryURL = base
            }
            return base
        } catch {
            return nil
        }
    }

    /// Constructs the full file URL in the temporary directory where the cached image is stored.
    /// - Parameter url: The original image URL.
    /// - Returns: A file URL pointing to the cached image.
    nonisolated private static func cachedFileURL(for url: URL) -> URL {
        if let cacheDir = cacheDirectoryURL() {
            return cacheDir.appendingPathComponent(cacheFileName(for: url))
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(cacheFileName(for: url))
    }

    /// Stores the downloaded image data in the cache.
    /// - Parameters:
    ///   - data: The image data to be stored.
    ///   - url: The original URL of the image, used to generate the cache file name.
    nonisolated private static func storeImage(data: Data, for url: URL) {
        let fileURL = cachedFileURL(for: url)
        do {
            // Make sure the directory exists (in case it was deleted between cache directory creation and image download)
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Write the data to disk atomically to ensure data integrity.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Just log the error, don't print
        }
    }

    // MARK: - Cache Helpers

    nonisolated static func updateOptimizedCache(totalCostLimit: Int? = nil, countLimit: Int? = nil) {
        let state = cacheState
        state.lock.lock()
        defer { state.lock.unlock() }
        if let totalCostLimit { state.optimizedCache.totalCostLimit = totalCostLimit }
        if let countLimit { state.optimizedCache.countLimit = countLimit }
    }

    nonisolated static func optimizedCacheCountLimit() -> Int {
        let state = cacheState
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.optimizedCache.countLimit
    }
    
    // Clear the loaded URL tracking cache to allow retry of previously failed URLs
    public nonisolated static func clearURLCache() {
        let state = cacheState
        state.lock.lock()
        defer { state.lock.unlock() }
        state.failedLoadTimestamps.removeAll()
    }
    
    // Clear entire image cache
    public nonisolated static func clearCache() {
        // Cancel in-flight loads to release locks quickly
        withLock {
            cacheState.loadingTasks.values.forEach { $0.cancel() }
            cacheState.loadingTasks.removeAll()
            cacheState.primaryCache.removeAllObjects()
            cacheState.optimizedCache.removeAllObjects()
            cacheState.failedLoadTimestamps.removeAll()
            cacheState.cachedDirectoryURL = nil
        }
        
        // Clear disk cache off the main queue to avoid blocking UI/thread asserts.
        DispatchQueue.global(qos: .utility).async {
            guard let cacheDir = CachedAsyncImage.cacheDirectoryURL() else { return }
            do {
                if FileManager.default.fileExists(atPath: cacheDir.path) {
                    try FileManager.default.removeItem(at: cacheDir)
                }
            } catch {
                // Ignore errors when clearing cache
            }
        }
    }
    /// Helper to perform a thread-safe read/write on cache state.
    private nonisolated static func withLock<T>(_ work: () -> T) -> T {
        let state = cacheState
        state.lock.lock()
        defer { state.lock.unlock() }
        return work()
    }
}
