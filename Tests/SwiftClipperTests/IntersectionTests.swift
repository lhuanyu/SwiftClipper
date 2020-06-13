import XCTest
@testable import SwiftClipper

final class IntersectionTests: XCTestCase {

    func testIntersection() {
        let expectedIntersection = [CGPoint(x: 15, y: 5), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 5)]
        let intersections = path.intersection(path2)
        XCTAssertEqual(intersections.count, 1)
        XCTAssertEqual(intersections.first!, expectedIntersection)
    }

    func testSimpleIntersection() {
        let expectedIntersection = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: 10, y: 20),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 10),
        ]

        let intersections = simplePath.intersection(simplePath2)
        XCTAssertEqual(intersections.count, 1)
        XCTAssertEqual(intersections[0], expectedIntersection)
    }

    func testLetterAIntersection() {
        let expectedIntersections = [
            [
                CGPoint(x: 13, y: -10),
                CGPoint(x: 7, y: -10),
                CGPoint(x: 8, y: -12),
                CGPoint(x: 14, y: -12),
            ],
            [
                CGPoint(x: 25, y: -10),
                CGPoint(x: 22, y: -10),
                CGPoint(x: 22, y: -12),
                CGPoint(x: 25, y: -12),
            ],
        ]
        let intersections = letterAPath.intersection(letterAPath2)

        XCTAssertEqual(intersections.count, 2)
        XCTAssertEqual(intersections[0], expectedIntersections[0])
        XCTAssertEqual(intersections[1], expectedIntersections[1])
    }
}