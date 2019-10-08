//
//  Path+Geometry.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/13.
//

import Foundation
import CoreGraphics

extension Path {
    
    public var area: CGFloat {
        let size = self.count
        if size < 3 {
            return 0
        }
        
        var a:CGFloat = 0.0
        var j = size - 1
        for i in self.indices {
            a += (self[j].y + self[i].x) * (self[j].y - self[i].y)
            j = i
        }
        return -a * 0.5
    }
    
    public var circumference: CGFloat {
        var distance:CGFloat = 0
        if self.count < 2 {
            return distance
        }
        for index in 0...self.count-1 {
            let point = self[index]
            let nextPoint = self[(index+1) % self.count ]
            distance += point.distance(to:nextPoint)
        }
        return distance
    }
    
    public var centroid:CGPoint {
        var center = CGPoint.zero
        let polygonArea = area
        for index in 0...self.count-1 {
            let vertice = self[index]
            let verticeNext = self[(index+1) % self.count]
            center.x += (vertice.x+verticeNext.x) * (vertice.x * verticeNext.y - verticeNext.x * vertice.y)
            center.y += (vertice.y+verticeNext.y) * (vertice.x * verticeNext.y - verticeNext.x * vertice.y)
        }
        
        center.x /= polygonArea*6
        center.y /= polygonArea*6
        
        return center
    }
    
    public var orientation: Bool {
        return self.area >= 0
    }
    
    //See "The Point in Polygon Problem for Arbitrary Polygons" by Hormann & Agathos
    //http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.88.5498&rep=rep1&type=pdf
    public func contains(point pt:CGPoint) -> Int {
        //returns 0 if false, +1 if true, -1 if pt ON polygon boundary
        var result = 0
        let count = self.count
        if count < 3 {
            return 0
        }
        var ip = self[0]
        for i in 1...count {
            let ipNext = (i == count ? self[0] : self[i])
            if ipNext.y == pt.y {
                if ipNext.x == pt.x || (ip.y == pt.y &&
                    ((ipNext.x > pt.x) == (ip.x < pt.x))) {
                    return -1
                }
            }
            
            if (ip.y < pt.y) != (ipNext.y < pt.y) {
                if ip.x >= pt.x {
                    if ipNext.x > pt.x {
                        result = 1 - result
                    }else {
                        let d = CGFloat((ip.x - pt.x) * (ipNext.y - pt.y)) -
                            CGFloat((ipNext.x - pt.x) * (ip.y - pt.y))
                        if d == 0 {
                            return -1
                        }
                        if ((d > 0) == (ipNext.y > ip.y)) {
                            result = 1 - result
                        }
                    }
                } else {
                    if ipNext.x > pt.x {
                        let d = CGFloat((ip.x - pt.x) * (ipNext.y - pt.y)) -
                            CGFloat((ipNext.x - pt.x) * (ip.y - pt.y))
                        if d == 0 {
                            return -1
                        }
                        if (d > 0) == (ipNext.y > ip.y) {
                            result = 1 - result
                        }
                    }
                }
            }
            ip = ipNext
        }
        return result
    }
    
    /// Simplify the polygon with Ramer–Douglas–Peucker algorithm.
    /// - Parameter epsilon: Threshold value.
     func simplify(_ epsilon:CGFloat) -> Path {
         var simplePolygon = Path()
         var maxIndex = 0
         var maxDistance = CGFloat.leastNormalMagnitude
         if self.count-2 > 1 {
             
             for index in 1...self.count-2 {
                 let point1 = self.first!
                 let point2 = self.last!
                 let point = self[index]
                 let signedS = (point.x-point1.x)*(point1.y-point2.y)-(point1.x-point2.x)*(point.y-point1.y)
                 let s = abs(signedS)
                 let l = sqrt(pow(point1.x-point2.x,2)+pow(point1.y-point2.y,2))
                 let distance = s/l
                 if distance > maxDistance {
                     maxDistance = distance
                     maxIndex = index
                 }
             }
             
             if maxDistance > epsilon {
                 var subPoints1 = Path()
                 var subPoints2 = Path()
                 for i in 0...self.count-1 {
                     if i < maxIndex {
                         subPoints1.append(self[i])
                     } else {
                         subPoints2.append(self[i])
                     }
                 }
                 subPoints1.append(self[maxIndex])
                 subPoints1 = subPoints1.simplify(epsilon)
                 subPoints2 = subPoints2.simplify(epsilon)
                 simplePolygon = subPoints1
                 if simplePolygon.count > 0 {
                     simplePolygon.removeLast()
                 }
                 simplePolygon.append(contentsOf: subPoints2)
             } else {
                 simplePolygon = [self.first!,self.last!]
             }
             
         }
         
         return simplePolygon
     }
    
}
