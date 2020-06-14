import XCTest
@testable import SwiftClipper

final class DifferenceTests: XCTestCase {

    func testSimpleDifference() {
        let expectedDifference = [
            CGPoint(x: 20, y: 10),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 10, y: 20),
            CGPoint(x: 0, y: 20),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 20, y: 0),
        ]

        let diff = simplePath.difference(simplePath2)
        XCTAssertEqual(diff.count, 1)
        XCTAssertEqual(diff[0], expectedDifference)
    }

    func testLetterADifference() {
        let expectedDifferences = [
            [
                CGPoint(x: 5, y: 0), 
                CGPoint(x: 0, y: 0), 
                CGPoint(x: 7, y: -10),
                CGPoint(x: 13, y: -10),
            ],
            [
                CGPoint(x: 30, y: 0),
                CGPoint(x: 25, y: 0),
                CGPoint(x: 22, y: -10),
                CGPoint(x: 25, y: -10), 
                CGPoint(x: 25, y: -12),
                CGPoint(x: 22, y: -12),
                CGPoint(x: 20, y: -20),
                CGPoint(x: 14, y: -12),
                CGPoint(x: 8, y: -12),
                CGPoint(x: 20, y: -30),
            ],
        ]
        let differences = letterAPath.difference(letterAPath2)

        XCTAssertEqual(differences.count, 2)
        XCTAssertEqual(differences[0], expectedDifferences[0])
        XCTAssertEqual(differences[1], expectedDifferences[1])
    }
}