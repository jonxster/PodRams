import XCTest
@testable import PodRams

final class DownloadManagerTests: XCTestCase {
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
}