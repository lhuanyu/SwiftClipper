//
//  Rect.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/1.
//

import Foundation
import CoreGraphics

public struct Rect: Equatable {
    var left: CGFloat
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat
    
    static var zero:Rect {
        return Rect(left: 0, top: 0, right: 0, bottom: 0)
    }
    
    public static func == (lhs: Rect, rhs: Rect) -> Bool {
        return lhs.left == rhs.left && lhs.right == rhs.right && lhs.top == rhs.top && lhs.bottom == rhs.bottom
    }
    
}

extension CGRect {
    var left: CGFloat {
        set {
            origin.x = newValue
        }
        get {
            return origin.x
        }
    }
    
    var right: CGFloat {
        set {
            size.width = newValue - left
        }
        get {
            return left + size.width
        }
    }
    
    var top: CGFloat {
        set {
            origin.y = newValue
        }
        get {
            return origin.y
        }
    }
    
    var bottom: CGFloat {
        set {
            size.height = newValue - top
        }
        get {
            return origin.x
        }
    }
}

extension Paths {
    
    var bounds: Rect {
        var i = 0
        let cnt = self.count
        while i < cnt && self[i].count == 0 {
            i += 1
        }
        if i == cnt {
            return .zero
        }
        var result = Rect.zero
        result.left = self[i][0].x
        result.right = result.left
        result.top = self[i][0].y
        result.bottom = result.top
        while i < cnt {
            for j in self[i].indices {
                if self[i][j].x < result.left{
                    result.left = self[i][j].x
                } else if self[i][j].x > result.right {
                    result.right = self[i][j].x
                }
                if self[i][j].y < result.top{
                    result.top = self[i][j].y
                } else if self[i][j].y > result.bottom {
                    result.bottom = self[i][j].y
                }
            }
            i += 1
        }
        
        return result
    }
}

