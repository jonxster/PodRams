//
//  CachedAsyncImage.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// CachedAsyncImage.swift

import SwiftUI
import AppKit
import CryptoKit

public struct CachedAsyncImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    @State private var loadedImage: NSImage?
    @State private var isLoading = false

    public init(url: URL?, width: CGFloat, height: CGFloat) {
        self.url = url
        self.width = width
        self.height = height
    }

    public var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
            } else {
                Rectangle()
                    .foregroundColor(.gray.opacity(isLoading ? 0.3 : 0.1))
                    .frame(width: width, height: height)
                    .overlay(isLoading ? ProgressView() : nil)
                    .onAppear { loadImage() }
            }
        }
    }

    private func loadImage() {
        guard let url = url, !isLoading else { return }
        isLoading = true

        // Check for a cached file first.
        if let cached = loadCachedImage(for: url) {
            loadedImage = cached
            isLoading = false
            return
        }

        // Download the image if not cached.
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async { self.isLoading = false }
            guard let data = data, let image = NSImage(data: data) else { return }
            storeImage(data: data, for: url)
            DispatchQueue.main.async { self.loadedImage = image }
        }.resume()
    }

    // Generate a fixed-length file name by hashing the URL's absolute string.
    private func cacheFileName(for url: URL) -> String {
        let inputData = Data(url.absoluteString.utf8)
        let hashed = SHA256.hash(data: inputData)
        let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension
        return ext.isEmpty ? hashString : "\(hashString).\(ext)"
    }

    // Return the temporary file URL for the cached image.
    private func cachedFileURL(for url: URL) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = cacheFileName(for: url)
        return tempDir.appendingPathComponent(fileName)
    }

    private func loadCachedImage(for url: URL) -> NSImage? {
        let fileURL = cachedFileURL(for: url)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    private func storeImage(data: Data, for url: URL) {
        let fileURL = cachedFileURL(for: url)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Error storing cached image: \(error)")
        }
    }
}
