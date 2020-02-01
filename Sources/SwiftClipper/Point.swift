//
//  Point.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/1.
//

import CoreGraphics

extension CGPoint: ExpressibleByArrayLiteral {
    
    public init(arrayLiteral elements: CGFloat...) {
        self.init()
        if elements.count > 1 {
            self.x = elements[0]
            self.y = elements[1]
        } else {
            self.x = 0
            self.y = 0
        }
    }
        
}

extension CGPoint {
    
    public func isSlopesEqual(_ pt1: CGPoint, _ pt3: CGPoint) -> Bool {
        return (pt1.y-self.y)*(self.x-pt3.x) == (pt1.x-self.x)*(self.y-pt3.y)
    }
    
    public func isSlopesEqual(_ pt2: CGPoint, _ pt3: CGPoint, _ pt4: CGPoint) -> Bool {
        return (self.y-pt2.y)*(pt3.x-pt4.x) == (self.x-pt2.x)*(pt3.y-pt4.y)
    }
    
    public func isBetween(_ pt1: Self, _ pt2: Self) -> Bool {
        if pt1 == pt2 || pt1 == self || pt2 == self {
            return false
        } else if pt1.x != pt2.x {
            return (self.x > pt1.x) == (self.x < pt2.x)
        }
        return (self.y > pt1.y) == (self.y < pt2.y)
    }
    
    public func distance(to point: CGPoint) -> CGFloat {
        let dx = self.x-point.x
        let dy = self.y-point.y
        return sqrt(dx*dx+dy*dy)
    }
    
    public func distanceFromLineSqrd(_ ln1: CGPoint, _ ln2: CGPoint) -> CGFloat {
        //The equation of a line in general form (Ax + By + C = 0)
        //given 2 points (x¹,y¹) & (x²,y²) is ...
        //(y¹ - y²)x + (x² - x¹)y + (y² - y¹)x¹ - (x² - x¹)y¹ = 0
        //A = (y¹ - y²) B = (x² - x¹) C = (y² - y¹)x¹ - (x² - x¹)y¹
        //perpendicular distance of point (x³,y³) = (Ax³ + By³ + C)/Sqrt(A² + B²)
        //see http://en.wikipedia.org/wiki/Perpendicular_distance
        let A = ln1.y - ln2.y
        let B = ln2.x - ln1.x
        var C = A * ln1.x  + B * ln1.y
        C = A * self.x + B * self.y - C
        return (C * C) / (A * A + B * B)
    }
    
    public func slopesNearCollinear(pt2: CGPoint, pt3: CGPoint, distSqrd: CGFloat) -> Bool {
        //this function is more accurate when the point that's GEOMETRICALLY
        //between the other 2 points is the one that's tested for distance.
        //nb: with 'spikes', either pt1(self) or pt3 is geometrically between the other pts
        if abs(self.x - pt2.x) > abs(self.y - pt2.y) {
            if (self.x > pt2.x) == (self.x < pt3.x) {
                return self.distanceFromLineSqrd(pt2, pt3) < distSqrd
            }
            else if (pt2.x > self.x) == (pt2.x < pt3.x) {
                return pt2.distanceFromLineSqrd(self, pt3) < distSqrd
            }
            else {
                return pt3.distanceFromLineSqrd(self, pt2) < distSqrd
            }
        } else {
            if (self.y > pt2.y) == (self.y < pt3.y) {
                return self.distanceFromLineSqrd(pt2, pt3) < distSqrd
            } else if (pt2.y > self.y) == (pt2.y < pt3.y) {
                return pt2.distanceFromLineSqrd(self, pt3) < distSqrd
            } else {
                return pt3.distanceFromLineSqrd(self, pt2) < distSqrd
            }
        }
    }
    
    public func areClose(pt pt2: CGPoint, distSqrd: CGFloat) -> Bool {
        let dx = self.x - pt2.x
        let dy = self.y - pt2.y
        return ((dx * dx) + (dy * dy) <= distSqrd)
    }
    
    static func - (left:CGPoint,right:CGPoint) -> CGPoint {
        return CGPoint(x: left.x-right.x,y: left.y-right.y)
    }

    static func -= (left:inout CGPoint,right:CGPoint) {
        left = CGPoint(x: left.x-right.x,y: left.y-right.y)
    }

    static func + (left:CGPoint,right:CGPoint) -> CGPoint {
        return CGPoint(x: left.x+right.x,y: left.y+right.y)
    }

    static func += (left:inout CGPoint,right:CGPoint) {
        left = CGPoint(x: left.x+right.x,y: left.y+right.y)
    }

    static func * (left:CGPoint,right:CGFloat) -> CGPoint {
        return CGPoint(x: left.x*right,y: left.y*right)
    }

    static func / (left:CGPoint,right:CGFloat) -> CGPoint {
        return CGPoint(x: left.x/right,y: left.y/right)
    }

    
}

extension Int {
    var cgFloat: CGFloat {
        return CGFloat(self)
    }
}

extension CGFloat {
    var int: Int {
        return Int(self)
    }
}

