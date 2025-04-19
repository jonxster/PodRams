//
//  HTMLStrippedString.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-21.
//

import Foundation
import AppKit

extension String {
    // Cache for already processed HTML
    private static var htmlCache = NSCache<NSString, NSString>()
    private static let cacheLock = NSLock()
    private static let processingTimeout: TimeInterval = 5.0  // 5 second timeout
    
    /// Converts an HTML string to plain text (stripped of <p>, <br>, etc.) 
    /// Uses NSAttributedString for macOS (AppKit) and caches results
    var htmlStripped: String {
        // For empty strings or nil, return as is
        if self.isEmpty { return self }
        
        // Check cache first (thread-safe)
        String.cacheLock.lock()
        if let cached = String.htmlCache.object(forKey: self as NSString) {
            String.cacheLock.unlock()
            return cached as String
        }
        String.cacheLock.unlock()
        
        // If the string is extremely large, truncate it
        let processableString: String
        let maxLength = 50000  // Reasonable maximum length
        if self.count > maxLength {
            processableString = String(self.prefix(maxLength)) + "... [truncated]"
        } else {
            processableString = self
        }
        
        // If HTML processing is too complex, fallback to simpler processing
        if processableString.contains("<table") || 
           processableString.contains("<script") || 
           processableString.contains("<style") {
            return simplifiedHTMLStripped(processableString)
        }
        
        // If on main thread, process in background
        if Thread.isMainThread {
            // Return a simplified fallback version immediately to avoid blocking UI
            let simplified = simplifiedHTMLStripped(processableString)
            
            // Process full version in background and cache for next time
            DispatchQueue.global(qos: .utility).async {
                _ = processHTML(processableString)
            }
            
            return simplified
        } else {
            // Already on background thread, process directly with timeout protection
            return processHTML(processableString)
        }
    }
    
    /// Simplified HTML stripping for immediate display
    private func simplifiedHTMLStripped(_ html: String) -> String {
        // Quick and dirty HTML tag removal for immediate UI response
        var result = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        
        // Consolidate multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Process HTML on a background thread with timeout protection
    private func processHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else {
            return html
        }
        
        var result = html
        var completed = false
        
        // Use a semaphore to implement timeout
        let semaphore = DispatchSemaphore(value: 0)
        
        // Process in a separate thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use default options but with a timeout
                let attributed = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
                
                result = attributed.string
                
                // Cache the result for future requests (thread-safe)
                String.cacheLock.lock()
                String.htmlCache.setObject(result as NSString, forKey: html as NSString)
                String.cacheLock.unlock()
                
                completed = true
                semaphore.signal()
            } catch {
                // On error, use simplified version
                result = simplifiedHTMLStripped(html)
                completed = true
                semaphore.signal()
            }
        }
        
        // Wait with timeout
        _ = semaphore.wait(timeout: .now() + String.processingTimeout)
        
        // If not completed in time, use simplified version
        if !completed {
            result = simplifiedHTMLStripped(html)
            
            // Log warning
            print("Warning: HTML processing timed out, using simplified version")
        }
        
        return result
    }
}
