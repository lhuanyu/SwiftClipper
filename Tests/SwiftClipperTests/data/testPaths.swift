import CoreGraphics

// A rectangle intersecting a triangle-like polygon that has an extra point which causes a very thin offshoot
let path = [
    CGPoint(x: -10, y: 10),
    CGPoint(x: 20, y: 10),
    CGPoint(x: 10, y: 0),
    CGPoint(x: 25, y: -8)
]
let path2 = [
    CGPoint(x: -5, y: 5),
    CGPoint(x: 20, y: 5),
    CGPoint(x: 20, y: -15),
    CGPoint(x: -5, y: -15)
]

// Two intersecting squares
let simplePath = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 20), CGPoint(x: 0, y: 20)]
let simplePath2 = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 30, y: 30), CGPoint(x: 10, y: 30)]


// Together, these shapes make a shape similar to a capital "A", but with a crossbar that starts to the left of the arch, 
// and ends in the middle of the arch's right side.
let letterAPath = [
    CGPoint(x: 0, y: 0),
    CGPoint(x: 20, y: -30),
    CGPoint(x: 30, y: 0),
    CGPoint(x: 25, y: 0),
    CGPoint(x: 20, y: -20),
    CGPoint(x: 5, y: 0),
]
let letterAPath2 = [
    CGPoint(x: 0, y: -10),
    CGPoint(x: 25, y: -10),
    CGPoint(x: 25, y: -12),
    CGPoint(x: 0, y: -12),
]
