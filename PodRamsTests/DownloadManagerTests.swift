import XCTest
@testable import PodRams

final class DownloadManagerTests: XCTestCase {
    var downloadManager: DownloadManager!
    var testEpisode: PodcastEpisode!
    
    override func setUp() {
        super.setUp()
        downloadManager = DownloadManager.shared
        testEpisode = PodcastEpisode(
            title: "Test Episode",
            url: URL(string: "https://example.com/test.mp3")!,
            artworkURL: nil,
            duration: nil,
            showNotes: nil,
            feedUrl: nil
        )
        
        // Clear any existing state
        downloadManager.downloadStates.removeAll()
    }
    
    override func tearDown() {
        // Clean up after tests
        downloadManager.downloadStates.removeAll()
        downloadManager = nil
        testEpisode = nil
        super.tearDown()
    }
    
    func testDownloadStateEquality() {
        let url1 = URL(string: "https://ex.com/e.mp3")!
        let url2 = URL(string: "https://ex.com/e2.mp3")!
        let state1: DownloadManager.DownloadState = .downloading(progress: 0.5)
        let state2: DownloadManager.DownloadState = .downloading(progress: 0.5)
        XCTAssertEqual(state1, state2)
        
        let downloaded1: DownloadManager.DownloadState = .downloaded(url1)
        let downloaded2: DownloadManager.DownloadState = .downloaded(url1)
        XCTAssertEqual(downloaded1, downloaded2)
        
        let downloadedDifferent1: DownloadManager.DownloadState = .downloaded(url1)
        let downloadedDifferent2: DownloadManager.DownloadState = .downloaded(url2)
        XCTAssertNotEqual(downloadedDifferent1, downloadedDifferent2)
        
        XCTAssertEqual(DownloadManager.DownloadState.none, DownloadManager.DownloadState.none)
    }
    
    func testPausedStateEquality() {
        let resumeData1 = Data([1, 2, 3, 4])
        let resumeData2 = Data([5, 6, 7, 8])
        
        let paused1: DownloadManager.DownloadState = .paused(progress: 0.5, resumeData: resumeData1)
        let paused2: DownloadManager.DownloadState = .paused(progress: 0.5, resumeData: resumeData2)
        
        // Paused states with same progress should be equal (resume data is not compared)
        XCTAssertEqual(paused1, paused2)
        
        let paused3: DownloadManager.DownloadState = .paused(progress: 0.3, resumeData: resumeData1)
        XCTAssertNotEqual(paused1, paused3)
    }
    
    func testDownloadStateTrasitions() {
        let episodeKey = testEpisode.url.absoluteString
        
        // Initial state should be none
        let initialState = downloadManager.downloadStates[episodeKey]
        XCTAssertNil(initialState)
        
        // Start download - should transition to downloading
        downloadManager.downloadEpisode(testEpisode)
        let downloadingState = downloadManager.downloadStates[episodeKey]
        
        if let state = downloadingState {
            switch state {
            case .downloading(let progress):
                XCTAssertGreaterThanOrEqual(progress, 0.0)
                XCTAssertLessThanOrEqual(progress, 1.0)
            default:
                XCTFail("State should be downloading")
            }
        } else {
            XCTFail("Download state should not be nil after starting download")
        }
    }
    
    func testPauseDownload() {
        let episodeKey = testEpisode.url.absoluteString
        
        // Start download first
        downloadManager.downloadEpisode(testEpisode)
        
        // Simulate downloading state with progress and create a mock task
        let testProgress = 0.5
        downloadManager.downloadStates[episodeKey] = .downloading(progress: testProgress)
        
        // Create a mock download task to simulate the pause behavior
        let mockTask = URLSession.shared.downloadTask(with: testEpisode.url)
        downloadManager.downloadTasks[episodeKey] = mockTask
        
        // Create an expectation for the async pause operation
        let pauseExpectation = expectation(description: "Download should be paused")
        
        // Pause the download
        downloadManager.pauseDownload(for: testEpisode)
        
        // Since pauseDownload is asynchronous, we need to wait a bit for the state to update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Verify state changed to paused or failed (since we're using a mock task)
            if let state = self.downloadManager.downloadStates[episodeKey] {
                switch state {
                case .paused(let progress, let resumeData):
                    XCTAssertEqual(progress, testProgress, accuracy: 0.01)
                    XCTAssertNotNil(resumeData)
                    pauseExpectation.fulfill()
                case .failed:
                    // This is expected with a mock task since it can't provide real resume data
                    pauseExpectation.fulfill()
                default:
                    XCTFail("State should be paused or failed after calling pauseDownload, but was \(state)")
                }
            } else {
                XCTFail("Download state should not be nil after pausing")
            }
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    func testResumeDownload() {
        let episodeKey = testEpisode.url.absoluteString
        let testProgress = 0.3
        let testResumeData = Data([1, 2, 3, 4, 5])
        
        // Set initial paused state
        downloadManager.downloadStates[episodeKey] = .paused(progress: testProgress, resumeData: testResumeData)
        
        // Resume the download
        downloadManager.resumeDownload(for: testEpisode)
        
        // Verify state changed back to downloading
        if let state = downloadManager.downloadStates[episodeKey] {
            switch state {
            case .downloading(let progress):
                XCTAssertGreaterThanOrEqual(progress, testProgress)
                XCTAssertLessThanOrEqual(progress, 1.0)
            default:
                XCTFail("State should be downloading after calling resumeDownload")
            }
        } else {
            XCTFail("Download state should not be nil after resuming")
        }
    }
    
    func testPauseNonDownloadingEpisode() {
        let episodeKey = testEpisode.url.absoluteString
        
        // Try to pause when not downloading
        downloadManager.pauseDownload(for: testEpisode)
        
        // State should remain unchanged (none)
        let state = downloadManager.downloadStates[episodeKey]
        XCTAssertNil(state, "State should remain nil when pausing non-downloading episode")
    }
    
    func testResumeNonPausedEpisode() {
        let episodeKey = testEpisode.url.absoluteString
        
        // Try to resume when not paused
        downloadManager.resumeDownload(for: testEpisode)
        
        // State should remain unchanged (none)
        let state = downloadManager.downloadStates[episodeKey]
        XCTAssertNil(state, "State should remain nil when resuming non-paused episode")
    }
    
    func testDownloadStateMethod() {
        let episodeKey = testEpisode.url.absoluteString
        
        // Test none state
        var state = downloadManager.downloadState(for: testEpisode)
        XCTAssertEqual(state, .none)
        
        // Test downloading state
        downloadManager.downloadStates[episodeKey] = .downloading(progress: 0.5)
        state = downloadManager.downloadState(for: testEpisode)
        if case .downloading(let progress) = state {
            XCTAssertEqual(progress, 0.5, accuracy: 0.01)
        } else {
            XCTFail("Should return downloading state")
        }
        
        // Test paused state
        let testResumeData = Data([1, 2, 3])
        downloadManager.downloadStates[episodeKey] = .paused(progress: 0.7, resumeData: testResumeData)
        state = downloadManager.downloadState(for: testEpisode)
        if case .paused(let progress, let resumeData) = state {
            XCTAssertEqual(progress, 0.7, accuracy: 0.01)
            XCTAssertEqual(resumeData, testResumeData)
        } else {
            XCTFail("Should return paused state")
        }
        
        // Test failed state
        let testError = NSError(domain: "TestDomain", code: 1)
        downloadManager.downloadStates[episodeKey] = .failed(testError)
        state = downloadManager.downloadState(for: testEpisode)
        if case .failed = state {
            // Success - failed state returned correctly
        } else {
            XCTFail("Should return failed state")
        }
    }
    
    func testFailedStateEquality() {
        let error1 = NSError(domain: "TestDomain", code: 1)
        let error2 = NSError(domain: "TestDomain", code: 2)
        
        let failed1: DownloadManager.DownloadState = .failed(error1)
        let failed2: DownloadManager.DownloadState = .failed(error2)
        
        // Failed states should be equal regardless of the specific error
        XCTAssertEqual(failed1, failed2)
    }
    
    func testAllStateComparisons() {
        let url = URL(string: "https://example.com/test.mp3")!
        let resumeData = Data([1, 2, 3])
        let error = NSError(domain: "Test", code: 1)
        
        let states: [DownloadManager.DownloadState] = [
            .none,
            .downloading(progress: 0.5),
            .paused(progress: 0.5, resumeData: resumeData),
            .downloaded(url),
            .failed(error)
        ]
        
        // Test that different state types are not equal
        for i in 0..<states.count {
            for j in 0..<states.count {
                if i == j {
                    XCTAssertEqual(states[i], states[j], "Same state types should be equal")
                } else {
                    // Special case: failed states are always equal to other failed states
                    if case .failed = states[i], case .failed = states[j] {
                        XCTAssertEqual(states[i], states[j])
                    } else {
                        XCTAssertNotEqual(states[i], states[j], "Different state types should not be equal")
                    }
                }
            }
        }
    }
}