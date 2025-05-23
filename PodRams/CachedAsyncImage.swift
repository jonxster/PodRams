//
// CachedAsyncImage.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import AppKit
import CryptoKit

/// A SwiftUI view that asynchronously loads an image from a URL and caches it locally.
/// If the image is already cached, it is loaded from disk; otherwise, it is downloaded and stored.
public struct CachedAsyncImage: View {
    /// URL of the image to be loaded.
    let url: URL?
    /// Desired width of the displayed image.
    let width: CGFloat
    /// Desired height of the displayed image.
    let height: CGFloat

    /// In-memory cache for loaded images to avoid repeated disk I/O.
    private static let imageCache = NSCache<NSURL, NSImage>()
    // Cache for image loading tasks to prevent duplicate requests
    private static var loadingTasks = [String: URLSessionDataTask]()
    private static let loadingTaskLock = NSLock()
    
    // Use a more sophisticated cache with size limits
    private static let urlRequestCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.totalCostLimit = 100 // Limit to 100 URLs
        cache.countLimit = 100
        return cache
    }()
    
    // Optimize cache configuration
    static let optimizedImageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        cache.countLimit = 200 // Maximum 200 images
        return cache
    }()
    
    // Track the last URL we tried to load to prevent redundant loading
    private static var lastLoadedURLs = [String: Date]()
    private static let failureCooldownPeriod: TimeInterval = 300 // 5 minutes
    
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
        Self.loadingTaskLock.lock()
        defer { Self.loadingTaskLock.unlock() }
        
        if let task = Self.loadingTasks[url.absoluteString] {
            task.cancel()
            Self.loadingTasks.removeValue(forKey: url.absoluteString)
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
            if let memImage = Self.optimizedImageCache.object(forKey: url as NSURL) {
                DispatchQueue.main.async {
                    loadedImage = memImage
                    isLoading = false
                }
                return // Found in memory cache, exit background task
            }

            // Check if already loading - requires lock
            Self.loadingTaskLock.lock()
            if Self.loadingTasks[urlKey] != nil {
                // Task is already in progress, just let the existing one finish
                Self.loadingTaskLock.unlock()
                return 
            }
            
            // Check if we recently failed to load this URL with cooldown
            if let lastAttempt = Self.lastLoadedURLs[urlKey] {
                let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
                if timeSinceLastAttempt < Self.failureCooldownPeriod {
                    Self.loadingTaskLock.unlock()
                     DispatchQueue.main.async {
                        isLoading = false 
                        loadError = true
                    }
                    return
                }
            }
            
            // Mark that we've attempted to load this URL
            Self.lastLoadedURLs[urlKey] = Date()
            
            // Capture fileURL before unlocking
            let fileURL = self.cachedFileURL(for: url)
            
            // --- End: Moved checks inside background queue --- 
            
            // Create a placeholder task using a valid initializer before unlocking
            let dummyRequest = URLRequest(url: URL(string: "placeholder://task")!) // Dummy request
            let placeholderTask = URLSession.shared.dataTask(with: dummyRequest) // Non-deprecated init
            Self.loadingTasks[urlKey] = placeholderTask 
            Self.loadingTaskLock.unlock() // Unlock *before* potentially slow disk I/O
            
            // Attempt to load from disk cache.
            if FileManager.default.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let image = processImageData(data) {
                
                Self.loadingTaskLock.lock()
                Self.optimizedImageCache.setObject(image, forKey: url as NSURL)
                // Remove placeholder task if we loaded from disk
                if Self.loadingTasks[urlKey] === placeholderTask { 
                    Self.loadingTasks.removeValue(forKey: urlKey)
                }
                Self.loadingTaskLock.unlock()
                
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
            
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 60.0
            config.waitsForConnectivity = true
            config.requestCachePolicy = .returnCacheDataElseLoad
            
            let session = URLSession(configuration: config)
            
            // Create the actual data task
            let task = session.dataTask(with: request) { data, response, error in
                // Task completion handler (already on background thread)
                
                // Always remove task from tracking inside lock
                Self.loadingTaskLock.lock()
                Self.loadingTasks.removeValue(forKey: urlKey)
                Self.loadingTaskLock.unlock()
                
                if let _ = error {
                    DispatchQueue.main.async { 
                        isLoading = false 
                        loadError = true
                    }
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    DispatchQueue.main.async { 
                        isLoading = false 
                        loadError = true
                    }
                    return
                }
                
                guard let image = processImageData(data) else {
                     // If processing fails, try the CGImageSource fallback
                    if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                       let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                        let fallbackImage = NSImage(cgImage: cgImage, size: .zero)
                        
                        // Store fallback image in memory cache
                        Self.loadingTaskLock.lock()
                        Self.imageCache.setObject(fallbackImage, forKey: url as NSURL)
                        Self.loadingTaskLock.unlock()
                        
                        // Store image data to disk
                        storeImage(data: data, for: url)
                        
                        DispatchQueue.main.async {
                            loadedImage = fallbackImage
                            isLoading = false
                        }
                        return // Successfully loaded via fallback
                    }
                    
                    // Both processing attempts failed
                    DispatchQueue.main.async { 
                        isLoading = false
                        loadError = true
                    }
                    return
                }
                
                // Successfully processed image data
                storeImage(data: data, for: url) // Store to disk cache
                
                Self.loadingTaskLock.lock()
                Self.optimizedImageCache.setObject(image, forKey: url as NSURL) // Store to memory cache
                Self.loadingTaskLock.unlock()
                
                DispatchQueue.main.async {
                    loadedImage = image
                    isLoading = false
                }
            }
            
            // Store the *actual* task, replacing the placeholder, and start it
            Self.loadingTaskLock.lock()
            Self.loadingTasks[urlKey] = task
            Self.loadingTaskLock.unlock()
            
            task.resume()
        }
    }
    
    /// Processes image data to create an optimized NSImage
    private func processImageData(_ data: Data) -> NSImage? {
        // Try creating thumbnail directly if image might be large (heuristics based on data size)
        let maxDimension: CGFloat = 1200
        var potentiallyLarge = data.count > 500 * 1024 // Assume > 500KB might be large
        
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
    private func cacheFileName(for url: URL) -> String {
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

    /// Constructs the full file URL in the temporary directory where the cached image is stored.
    /// - Parameter url: The original image URL.
    /// - Returns: A file URL pointing to the cached image.
    private func cachedFileURL(for url: URL) -> URL {
        // Use the application support directory instead of temporary directory
        // for better persistence and proper sandbox permissions
        let fileManager = FileManager.default
        
        // Get the app's cache directory
        let cacheDir: URL
        
        do {
            // Get the app support directory specific to this app
            cacheDir = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PodRamsImageCache", isDirectory: true)
            
            // Create the ImageCache directory if it doesn't exist
            if !fileManager.fileExists(atPath: cacheDir.path) {
                try fileManager.createDirectory(
                    at: cacheDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        } catch {
            // Fall back to temporary directory if we can't access app support
            return fileManager.temporaryDirectory.appendingPathComponent(cacheFileName(for: url))
        }
        
        let fileName = cacheFileName(for: url)
        return cacheDir.appendingPathComponent(fileName)
    }

    /// Stores the downloaded image data in the cache.
    /// - Parameters:
    ///   - data: The image data to be stored.
    ///   - url: The original URL of the image, used to generate the cache file name.
    private func storeImage(data: Data, for url: URL) {
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
    
    // Clear the loaded URL tracking cache to allow retry of previously failed URLs
    public static func clearURLCache() {
        loadingTaskLock.lock()
        defer { loadingTaskLock.unlock() }
        lastLoadedURLs.removeAll()
    }
    
    // Clear entire image cache
    public static func clearCache() {
        loadingTaskLock.lock()
        defer { loadingTaskLock.unlock() }
        imageCache.removeAllObjects()
        lastLoadedURLs.removeAll()
        
        // Try to clear disk cache too
        do {
            let fileManager = FileManager.default
            let cacheDir = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ).appendingPathComponent("PodRamsImageCache", isDirectory: true)
            
            if fileManager.fileExists(atPath: cacheDir.path) {
                try fileManager.removeItem(at: cacheDir)
            }
        } catch { // Ignore error, variable not needed - CHANGED
            // Ignore errors when clearing cache
        }
    }
}
