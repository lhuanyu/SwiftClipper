//
//  TEdge.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/2.
//

import CoreGraphics
import Foundation

/// TEdge is a-linked list represents a polygon.
public class TEdge {
    var bot: CGPoint = .zero
    var curr: CGPoint = .zero  //current (updated for every new scanbeam)
    var top: CGPoint = .zero
    var dx: CGFloat = 0.0
    var polyType: PolyType = .clip
    var side: EdgeSide = .left //side only refers to current side of solution poly
    var windDelta: Int = 0 //1 or -1 depending on winding direction
    var windCnt: Int = 0
    var windCnt2: Int = 0 //winding count of the opposite polytype
    var outIdx: Int =  Unassigned
    
    weak var next: TEdge! /// edge is strongly referenced  by clipper, make it weak to resolve retain cycle.
    weak var prev: TEdge!
    weak var nextInLML: TEdge?
    weak var nextInAEL: TEdge?
    weak var prevInAEL: TEdge?
    weak var nextInSEL: TEdge?
    weak var prevInSEL: TEdge?
    
    deinit {
//        print("TEdge deinit.")
    }
}

extension TEdge: Equatable {
    public static func == (lhs: TEdge, rhs: TEdge) -> Bool {
        return lhs === rhs
    }
}

extension TEdge {
    static func initEdge(edge: TEdge, next: TEdge, prev: TEdge, pt: CGPoint) {
        edge.next = next
        edge.prev = prev
        edge.curr = pt
    }
    
    static func initEdge(edge: TEdge, polyType: PolyType) {
        if edge.curr.y >= edge.next.curr.y {
            edge.bot = edge.curr
            edge.top = edge.next.curr
        } else {
            edge.top  = edge.curr
            edge.bot = edge.next.curr
        }
        setDx(edge)
        edge.polyType = polyType
    }
    
    @inline(__always)
    static func setDx(_ e: TEdge) {
        let dy  = e.top.y - e.bot.y
        if dy == 0 {
            e.dx = Horizontal
        }
        else {
            e.dx = (e.top.x - e.bot.x) / dy
        }
    }
    
    static func removeEdge(_ e: TEdge) -> TEdge {
        //removes e from double_linked_list (but without removing from memory)
        e.prev.next = e.next
        e.next.prev = e.prev
        let result: TEdge = e.next
        e.prev = nil//flag as removed (see ClipperBase.Clear)
        return result
    }
    
    static func findNextLocMin(_ e: TEdge) -> TEdge {
        var e = e
        while true  {
            while e.bot != e.prev.bot || e.curr == e.top {
                e = e.next
            }
            if !e.isHorizontal && !e.prev.isHorizontal {
                break
            }
            while e.prev.isHorizontal {
                e = e.prev
            }
            let e2: TEdge = e
            while e.isHorizontal {
                e = e.next
            }
            if e.top.y == e.prev.bot.y {
                continue//ie just an intermediate horz.
            }
            if e2.prev.bot.x < e.bot.x {
                e = e2
            }
            break
        }
        return e
    }
}


extension TEdge {
    
    func isSlopesEqual(with edge: TEdge) -> Bool {
        return (self.top.y - self.bot.y) * (edge.top.x - edge.bot.x) == (self.top.x - self.bot.x) * (edge.top.y - edge.bot.y)
    }
    
    var isHorizontal: Bool {
        return self.dx == Horizontal
    }
    
    @inline(__always)
    func swapSide(with edge: TEdge) {
        let side =  self.side
        self.side = edge.side
        edge.side = side
    }
    
    @inline(__always)
    func swapPolyIndexes(with edge: TEdge) {
      let outIdx =  self.outIdx
      self.outIdx = edge.outIdx
      edge.outIdx = outIdx
    }

    @inline(__always)
    func topX(of currenty: CGFloat) -> CGFloat {
        if currenty == self.top.y {
            return self.top.x
        }
        return self.bot.x + round(self.dx * (currenty - self.bot.y))
    }
    
    @inline(__always)
    func reverseHorizontal() {
        //swap horizontal edges' Top and Bottom x's so they follow the natural
        //progression of the bounds - ie so their xbots will align with the
        //adjoining lower edge. [Helpful in the processHorizontal() method.]
        swap(&self.top.x, &self.bot.x);
    }
    
    func intersect(with edge: TEdge) -> CGPoint {
    
        var b1:CGFloat = 0.0
        var b2:CGFloat = 0.0
        var ip = CGPoint.zero
        if self.dx == edge.dx {
            ip.y = self.curr.y
            ip.x = topX(of: ip.y)
            return ip
        }
        
        if self.dx == 0 {
            ip.x = self.bot.x
            if edge.isHorizontal {
                ip.y = edge.bot.y
            } else {
                b2 = edge.bot.y - (edge.bot.x / edge.dx)
                ip.y = round(ip.x / edge.dx + b2)
            }
        } else if edge.dx == 0 {
            ip.x = edge.bot.x
            if self.isHorizontal {
                ip.y = self.bot.y
            } else {
                b1 = self.bot.y - (self.bot.x / self.dx)
                ip.y = round(ip.x / self.dx + b1)
            }
        } else {
            b1 = self.bot.x - self.bot.y * self.dx
            b2 = edge.bot.x - edge.bot.y * edge.dx
            let q = (b2-b1) / (self.dx - edge.dx)
            ip.y = round(q)
            if abs(self.dx) < abs(edge.dx) {
                ip.x = round(self.dx * q + b1)
            } else {
                ip.x = round(edge.dx * q + b2)
            }
        }
        
        if ip.y < self.top.y || ip.y < edge.top.y {
            if self.top.y > edge.top.y {
                ip.y = self.top.y
            } else {
                ip.y = edge.top.y
            }
            if abs(self.dx) < abs(edge.dx) {
                ip.x = self.topX(of: ip.y)
            } else {
                ip.x = edge.topX(of: ip.y)
            }
        }
        //finally, don't allow 'ip' to be BELOW curr.y (ie bottom of scanbeam) ...
        if ip.y > self.curr.y {
            ip.y = self.curr.y
            //use the more vertical edge to derive x ...
            if abs(self.dx) > abs(edge.dx) {
                ip.x = edge.topX(of: ip.y)
            }
            else {
                ip.x = topX(of: ip.y)
            }
        }
        return ip
    }
    
    
    
}
