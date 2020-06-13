
import XCTest
@testable import SwiftClipper

final class UnionTests: XCTestCase {

    func testUnion() {
        let expectedUnion: Path = [
            CGPoint(x: 15, y: 5),
            CGPoint(x: 20, y: 10),
            CGPoint(x: -10, y: 10),
            CGPoint(x: 0, y: 5),
            CGPoint(x: -5, y: 5),
            CGPoint(x: -5, y: -15),
            CGPoint(x: 20, y: -15), 
            CGPoint(x: 20, y: 5)
        ]
        let unions = path.union(path2)
        XCTAssertEqual(unions.count, 1)
        XCTAssertEqual(unions.first!, expectedUnion)
    }

    func testSimpleUnion() {
        let expectedUnion = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 20),
            CGPoint(x: 10, y: 20),
            CGPoint(x: 10, y: 30),
            CGPoint(x: 30, y: 30),
            CGPoint(x: 30, y: 10),
            CGPoint(x: 20, y: 10),
            CGPoint(x: 20, y: 0),
        ]
        let union = simplePath.union(simplePath2)
        XCTAssertEqual(union.count, 1)
        XCTAssertEqual(union.first!, expectedUnion)
    }

    func testLetterAUnion() {
        let expectedUnions = [
            [
                CGPoint(x: 30, y: 0),
                CGPoint(x: 25, y: 0),
                CGPoint(x: 22, y: -10),
                CGPoint(x: 13, y: -10),
                CGPoint(x: 5, y: 0),
                CGPoint(x: 0, y: 0),
                CGPoint(x: 7, y: -10),
                CGPoint(x: 0, y: -10),
                CGPoint(x: 0, y: -12),
                CGPoint(x: 8, y: -12),
                CGPoint(x: 20, y: -30),
            ],
            [
                CGPoint(x: 14, y: -12),
                CGPoint(x: 22, y: -12),
                CGPoint(x: 20, y: -20),
            ]
        ]
        let unions = letterAPath.union(letterAPath2)

        XCTAssertEqual(unions.count, 2)
        XCTAssertEqual(unions[0], expectedUnions[0])
        XCTAssertEqual(unions[1], expectedUnions[1])
    }
}