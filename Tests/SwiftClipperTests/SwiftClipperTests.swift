import XCTest
@testable import SwiftClipper

final class SwiftClipperTests: XCTestCase {
    func testExample() {
        let path = [CGPoint(x: -10, y: 10), CGPoint(x: 20, y: 10), CGPoint(x: 10, y: 0), CGPoint(x: 25, y: -8)]
        let path2 = [CGPoint(x: -5, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 20, y: -15), CGPoint(x: -5, y: -15)]

        let intersections  = path.intersection(path2)
        print(intersections)

        let unions = path.union(path2)
        print(unions)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
