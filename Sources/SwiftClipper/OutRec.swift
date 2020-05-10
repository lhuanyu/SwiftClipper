//
//  OutRec.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/13.
//

import CoreGraphics

/// OutRec contains a path in the clipping solution. Edges in the AEL will carry a pointer to an OutRec when they are part of the clipping solution.
class OutRec {
    var index = Unassigned
    var isHole = false
    var isOpen = false
    var firstLeft: OutRec?
    var pts: OutPt!
    var bottomPt: OutPt?
    var polyNode: PolyNode?
    
    func clear() {
        var pt = pts?.next
        while pt != pts {
            let next = pt?.next
            pt?.next = nil
            pt?.prev = nil
            pt = next
        }
    }
}

extension OutRec: Equatable {
    static func == (lhs: OutRec, rhs: OutRec) -> Bool {
        return lhs === rhs
    }
}

extension OutRec {
    var area: CGFloat {
        return self.pts?.area ?? 0.0
    }
}

class OutPt {
    var index = 0
    var pt = CGPoint.zero
    var next: OutPt!
    var prev: OutPt!
}

extension OutPt: Equatable {
    static func == (lhs: OutPt, rhs: OutPt) -> Bool {
        return lhs === rhs
    }
}

extension OutPt {
    var area: CGFloat {
        var current = self
        var a: CGFloat = 0.0
        repeat {
            a += (prev.pt.y + current.pt.x) * (prev.pt.y - current.pt.y)
            current = current.next
        } while current !== self
        return a * 0.5
    }
    
    func isVertex(_ point: CGPoint) -> Bool {
        var current = self
        repeat {
            if current.pt == point {
                return true
            }
            current = current.next
        } while (current !== self)
        return false
    }
    
    func contains(point pt:CGPoint) -> Int {
        //returns 0 if false, +1 if true, -1 if pt ON polygon boundary
        var result = 0
        var op = self
        repeat {
            if op.next.pt.y == pt.y {
                if op.next.pt.x == pt.x || (op.pt.y == pt.y &&
                    ((op.next.pt.x > pt.x) == (op.pt.x < pt.x))) {
                    return -1
                }
            }
            
            if (op.pt.y < pt.y) != (op.next.pt.y < pt.y) {
                if op.pt.x >= pt.x {
                    if op.next.pt.x > pt.x {
                        result = 1 - result
                    } else {
                        let d = CGFloat((op.pt.x - pt.x) * (op.next.pt.y - pt.y)) -
                            CGFloat((op.next.pt.x - pt.x) * (op.pt.y - pt.y))
                        if d == 0 {
                            return -1
                        }
                        if (d > 0) == (op.next.pt.y > op.pt.y) {
                            result = 1 - result
                        }
                    }
                } else {
                    if op.next.pt.x > pt.x {
                        let d = CGFloat((op.pt.x - pt.x) * (op.next.pt.y - pt.y)) -
                            CGFloat((op.next.pt.x - pt.x) * (op.pt.y - pt.y))
                        if d == 0 {
                            return -1
                        }
                        if (d > 0) == (op.next.pt.y > op.pt.y) {
                            result = 1 - result
                        }
                    }
                }
            }
            op = op.next
        } while self === op
        
        return result
    }
    
    func contains(polygon op:OutPt) -> Bool {
        var current = op
        repeat {
            //nb: PointInPolygon returns 0 if false, +1 if true, -1 if pt on polygon
            let res = self.contains(point: current.pt)
            if res >= 0 {
                return res > 0
            }
            current = current.next
        } while op !== current
        return true
    }
    
    func reverse() {
        var pp1:OutPt?
        var pp2:OutPt?
        pp1 = self
        repeat {
            pp2 = pp1?.next
            pp1?.next = pp1?.prev
            pp1?.prev = pp2
            pp1 = pp2
        } while pp1 !== self
    }
    
}



