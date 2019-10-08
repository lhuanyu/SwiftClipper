//
//  Defines.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/13.
//

import Foundation
import CoreGraphics

public typealias Path = [CGPoint]
public typealias Paths = [[CGPoint]]

public enum ClipType {
    case intersection, union, difference, xor
}

public enum PolyType {
    case subject, clip
}

public enum PolyFillType {
    case evenOdd, nonZero, positive, negative
}

public enum JoinType {
    case square, round, miter
}
public enum EndType {
    case closedPolygon, closedLine, openButt, openSquare, openRound
}

enum EdgeSide {
    case left, right
}

enum Direction {
    case rightToLeft, leftToRight
}

enum PointSideType: Int {
    case outside = 0
    case inside = 1
    case onBoundary = -1
}

let Horizontal = -CGFloat.greatestFiniteMagnitude;
let Unassigned = -1;  //edge not currently 'owning' a solution
let Skip = -2;        //edge that would otherwise close a path
