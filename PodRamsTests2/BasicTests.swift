//
//  BasicTests.swift
//  PodRamsTests2
//
//  Created by Tom Björnebark on 2025-02-25.
//

import XCTest
@testable import PodRams

class BasicTests: XCTestCase {
    func testAudioPlayer() {
        let player = AudioPlayer()
        XCTAssertEqual(player.volume, 0.5)
    }
} 