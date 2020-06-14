
import XCTest
@testable import SwiftClipper

final class XorTests: XCTestCase {
    func testSimpleXor() {
        let expectedXors = [
            [
                CGPoint(x: 30, y: 30),
                CGPoint(x: 10, y: 30),
                CGPoint(x: 10, y: 20),
                CGPoint(x: 20, y: 20),
                CGPoint(x: 20, y: 10),
                CGPoint(x: 30, y: 10),
            ],
            [
                CGPoint(x: 20, y: 10),
                CGPoint(x: 10, y: 10),
                CGPoint(x: 10, y: 20),
                CGPoint(x: 0, y: 20),
                CGPoint(x: 0, y: 0),
                CGPoint(x: 20, y: 0),
            ]
        ]

        let xors = simplePath.xor(simplePath2)
        XCTAssertEqual(xors.count, 2)
        XCTAssertEqual(xors[0], expectedXors[0])
        XCTAssertEqual(xors[1], expectedXors[1])
    }

    func testLetterAXor() {
        let expectedXors = [
            [
                CGPoint(x: 30, y: 0), 
                CGPoint(x: 25, y: 0), 
                CGPoint(x: 22, y: -10),
                CGPoint(x: 25, y: -10),
                CGPoint(x: 25, y: -12),
                CGPoint(x: 22, y: -12),
                CGPoint(x: 22, y: -10),
                CGPoint(x: 13, y: -10),
                CGPoint(x: 5, y: 0),
                CGPoint(x: 0, y: 0),
                CGPoint(x: 7, y: -10),
                CGPoint(x: 13, y: -10),
                CGPoint(x: 14, y: -12),
                CGPoint(x: 22, y: -12),
                CGPoint(x: 20, y: -20),
                CGPoint(x: 14, y: -12),
                CGPoint(x: 8, y: -12),
                CGPoint(x: 7, y: -10),
                CGPoint(x: 0, y: -10),
                CGPoint(x: 0, y: -12),
                CGPoint(x: 8, y: -12),
                CGPoint(x: 20, y: -30),
            ],
        ]
        let xors = letterAPath.xor(letterAPath2)

        XCTAssertEqual(xors.count, 1)
        XCTAssertEqual(xors[0], expectedXors[0])
    }
}
