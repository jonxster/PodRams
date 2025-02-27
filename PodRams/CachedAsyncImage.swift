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

    /// The loaded image (if available) represented as an NSImage.
    @State private var loadedImage: NSImage?
    /// Tracks whether an image load operation is currently in progress.
    @State private var isLoading = false

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
            } else {
                // Otherwise, display a placeholder rectangle.
                Rectangle()
                    // Adjust the placeholder's color opacity based on the loading state.
                    .foregroundColor(.gray.opacity(isLoading ? 0.3 : 0.1))
                    .frame(width: width, height: height)
                    // If currently loading, overlay a loading indicator.
                    .overlay(isLoading ?
                        LoadingIndicator()
                            .frame(width: width/4, height: height/4)
                        : nil)
                    // Start loading the image when the view appears.
                    .onAppear { loadImage() }
            }
        }
    }

    /// Loads the image either from the cache or by downloading it.
    /// Prevents multiple concurrent load operations using the `isLoading` flag.
    private func loadImage() {
        // Ensure a valid URL is provided and that no load is already in progress.
        guard let url = url, !isLoading else { return }
        isLoading = true

        // Attempt to retrieve the image from the cache.
        if let cached = loadCachedImage(for: url) {
            loadedImage = cached
            isLoading = false
            return
        }

        // If not cached, download the image using URLSession.
        URLSession.shared.dataTask(with: url) { data, _, _ in
            // Ensure UI updates are executed on the main thread.
            DispatchQueue.main.async { self.isLoading = false }
            // Validate that data exists and can be converted into an NSImage.
            guard let data = data, let image = NSImage(data: data) else { return }
            // Cache the downloaded image data for future use.
            storeImage(data: data, for: url)
            // Update the loaded image on the main thread.
            DispatchQueue.main.async { self.loadedImage = image }
        }.resume()
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
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = cacheFileName(for: url)
        return tempDir.appendingPathComponent(fileName)
    }

    /// Attempts to load an image from the cache.
    /// - Parameter url: The URL of the image.
    /// - Returns: The cached NSImage if it exists; otherwise, nil.
    private func loadCachedImage(for url: URL) -> NSImage? {
        let fileURL = cachedFileURL(for: url)
        // Check if the cache file exists, then load and convert it into an NSImage.
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    /// Stores the downloaded image data in the cache.
    /// - Parameters:
    ///   - data: The image data to be stored.
    ///   - url: The original URL of the image, used to generate the cache file name.
    private func storeImage(data: Data, for url: URL) {
        let fileURL = cachedFileURL(for: url)
        do {
            // Write the data to disk atomically to ensure data integrity.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Error storing cached image: \(error)")
        }
    }
}
