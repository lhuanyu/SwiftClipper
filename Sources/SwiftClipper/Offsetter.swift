//
//  Offsetter.swift
//  
//
//  Created by LuoHuanyu on 2020/1/21.
//

import CoreGraphics

public class Offsetter {
    
    private var destPolys = Paths()
    private var srcPoly = Path()
    private var destPoly = Path()
    private var normals = Path()
    private var delta = CGFloat.zero
    private var sinA = CGFloat.zero
    private var sin = CGFloat.zero
    private var cos = CGFloat.zero
    private var miterLim = CGFloat.zero
    private var stepsPerRad = CGFloat.zero
    
    private var lowest = CGPoint.zero
    private var polyNodes = PolyNode()
    
    public var arcTolerance = CGFloat.zero
    public var miterLimit = CGFloat.zero
    
    private let TwoPi = CGFloat.pi * 2
    private let ArcTolerance: CGFloat = 0.25
    
    public init(miterLimit: CGFloat = 2.0, arcTolerance: CGFloat = 0.25) {
        self.miterLimit = miterLimit
        self.arcTolerance = arcTolerance
        lowest.x = -1
    }
    
    public func clear() {
        polyNodes.children.removeAll()
        lowest.x = -1
    }
    
    public func addPath(_ path: Path, joinType: JoinType, endType: EndType) {
        var highI = path.count - 1
        if (highI < 0) {
            return
        }
        let newNode = PolyNode()
        newNode.joinType = joinType
        newNode.endType = endType
        
        //strip duplicate points from path and also get index to the lowest point ...
        if endType == .closedLine || endType == .closedPolygon {
            while highI > 0 && path[0] == path[highI] {
                highI -= 1
            }
        }

        newNode.polygon.append(path[0])
        var j = 0
        var k = 0
        var i = 1
        while i <= highI {
            if newNode.polygon[j] != path[i] {
                j += 1
                newNode.polygon.append(path[i])
                if path[i].y > newNode.polygon[k].y ||
                    (path[i].y == newNode.polygon[k].y &&
                        path[i].x < newNode.polygon[k].x) {
                    k = j
                }
            }
            i += 1
        }

        if endType == .closedPolygon && j < 2 {
            return
        }
        
        polyNodes.addChild(newNode)
        
        //if this path's lowest pt is lower than all the others then update lowest
        if endType != .closedPolygon {
            return
        }
        if lowest.x < 0 {
            lowest = [(polyNodes.childCount - 1).cgFloat, k.cgFloat]
        } else {
            let ip = polyNodes.children[Int(lowest.x)].polygon[Int(lowest.y)]
            if newNode.polygon[k].y > ip.y ||
                (newNode.polygon[k].y == ip.y &&
                    newNode.polygon[k].x < ip.x) {
                lowest = [(polyNodes.childCount - 1).cgFloat, k.cgFloat]
            }
        }
    }
    
    
    public func addPaths(_ paths: Paths, joinType: JoinType, endType: EndType) {
        paths.forEach {
            addPath($0, joinType: joinType, endType: endType)
        }
    }
    
    
    private func fixOrientations () {
        //fixup orientations of all closed paths if the orientation of the
        //closed path with the lowermost vertex is wrong ...
        if lowest.x >= 0 && !polyNodes.children[lowest.x.int].polygon.orientation {
            for node in polyNodes.children {
                if node.endType == .closedPolygon ||
                    (node.endType == .closedLine && node.polygon.orientation) {
                    node.polygon.reverse()
                }
            }
        } else {
            for node in polyNodes.children {
                if node.endType == .closedLine && node.polygon.orientation {
                    node.polygon.reverse()
                }
            }
        }
    }
    
    
    func getUnitNormal(_ pt1: CGPoint, _ pt2: CGPoint) -> CGPoint {
        var dx = pt2.x - pt1.x
        var dy = pt2.y - pt1.y
        if dx == 0 && dy == 0 {
            return .zero
        }
        
        let f = 1.0 / sqrt(dx * dx + dy * dy)
        dx *= f
        dy *= f
        
        return [dy, -dx]
    }
    
    
    private func doOffset(_ delta: CGFloat) {
        destPolys = Paths()
        self.delta = delta
        
        //if Zero offset, just copy any CLOSED polygons to p and return ...
        if delta == 0 {
            for node in polyNodes.children {
                if node.endType == .closedPolygon {
                    destPolys.append(node.polygon)
                }
            }
            return
        }
        
        //see offset_triginometry3.svg in the documentation folder ...
        if miterLimit > 2 {
            miterLim = 2 / miterLimit * miterLimit
        } else {
            miterLim = 0.5
        }
        
        var y = CGFloat.zero
        if arcTolerance <= 0.0 {
            y = ArcTolerance
        }
        else if arcTolerance > abs(delta) * ArcTolerance {
            y = abs(delta) * ArcTolerance
        } else {
            y = arcTolerance
        }
        //see offset_triginometry2.svg in the documentation folder ...
        let steps = CGFloat.pi / acos(1 - y / abs(delta))
        
        sin = CoreGraphics.sin(TwoPi / steps)
        cos = CoreGraphics.cos(TwoPi / steps)
        stepsPerRad = steps / TwoPi
        if delta < 0.0 {
            sin = -sin
        }
        
        for node in polyNodes.children {
            srcPoly = node.polygon
            
            let len = srcPoly.count
            
            if len == 0 || (delta <= 0 && (len < 3 ||
                node.endType != .closedPolygon)) {
                continue
            }
            
            destPoly = Path()
            
            if len == 1 {
                if node.joinType == .round {
                    var x: CGFloat = 1.0
                    var y: CGFloat = 0.0
                    for _ in 1...steps.int {
                        destPoly.append([round(srcPoly[0].x + x * delta), round(srcPoly[0].y + y * delta)])
                        let x2 = x
                        x = x * cos - sin * y
                        y = x2 * sin + y * cos
                    }
                } else {
                    var x: CGFloat = -1.0
                    var y: CGFloat = -1.0
                    for _ in 0...3 {
                        destPoly.append([round(srcPoly[0].x + x * delta), round(srcPoly[0].y + y * delta)])
                        if x < 0 {
                            x = 1
                        } else if y < 0 {
                            y = 1
                        } else {
                            x = -1
                        }
                    }
                }
                destPolys.append(destPoly)
                continue
            }
            
            //build normals ...
            normals.removeAll()

            for j in 0..<len - 1 {
                normals.append(getUnitNormal(srcPoly[j], srcPoly[j + 1]))
            }
            if node.endType == .closedLine ||
                node.endType == .closedPolygon {
                normals.append(getUnitNormal(srcPoly[len - 1], srcPoly[0]))
            } else {
                normals.append(normals[len - 2])
            }
            
            if node.endType == .closedPolygon {
                var k = len - 1
                for j in 0..<len {
                    offsetPoint(j, &k, node.joinType)
                }
                destPolys.append(destPoly)
            } else if node.endType == .closedLine {
                var k = len - 1
                for j in 0..<len {
                    offsetPoint(j, &k, node.joinType)
                }
                destPolys.append(destPoly)
                destPoly = Path()
                //re-build normals ...
                let n = normals[len - 1]
                var j = len - 1
                while j >= 1 {
                    normals[j] = [-normals[j - 1].x, -normals[j - 1].y]
                    j -= 1
                }
                normals[0] = [-n.x, -n.y]
                k = 0
                j = len - 1
                while j >= 0 {
                    offsetPoint(j, &k, node.joinType)
                    j -= 1
                }
                destPolys.append(destPoly)
            } else {
                var k = 0
                for j in 1..<len - 1 {
                    offsetPoint(j, &k, node.joinType)
                }
                
                var pt1: CGPoint
                if node.endType == .openButt {
                    let j = len - 1
                    pt1 =  [round(srcPoly[j].x + normals[j].x * delta), round(srcPoly[j].y + normals[j].y * delta)]
                    destPoly.append(pt1)
                    pt1 =  [round(srcPoly[j].x - normals[j].x * delta), round(srcPoly[j].y - normals[j].y * delta)]
                    destPoly.append(pt1)
                } else {
                    let j = len - 1
                    k = len - 2
                    sinA = 0
                    normals[j] = [-normals[j].x, -normals[j].y]
                    if node.endType == .openSquare {
                        doSquare(j, k)
                    } else {
                        doRound(j, k)
                    }
                }
                
                //re-build normals ...
                var j = len - 1
                while j >= 1 {
                    normals[j] = [-normals[j - 1].x, -normals[j - 1].y]
                    j -= 1
                }
                
                normals[0] = [-normals[1].x, -normals[1].y]
                
                k = len - 1
                j = k-1
                while j >= 1 {
                    offsetPoint(j, &k, node.joinType)
                    j -= 1
                }
                
                if node.endType == .openButt {
                    pt1 = [round(srcPoly[0].x - normals[0].x * delta),round(srcPoly[0].y - normals[0].y * delta)]
                    destPoly.append(pt1)
                    pt1 = [round(srcPoly[0].x + normals[0].x * delta),round(srcPoly[0].y + normals[0].y * delta)]
                    destPoly.append(pt1)
                } else {
                    k = 1
                    sinA = 0
                    if node.endType == .openSquare {
                        doSquare (0, 1)
                    } else {
                        doRound (0, 1)
                    }
                }
                destPolys.append(destPoly)
            }
        }
    }
    
    
    public func execute(_ solution: inout Paths,  delta: CGFloat) throws {

        fixOrientations ()
        doOffset(delta)
        //now clean up 'corners' ...

        if delta > 0 {
            let clpr = Clipper()
            clpr.addPaths(destPolys, .subject, true)
            try clpr.execute(clipType: .union,
                         solution: &solution,
                         subjFillType: .positive,
                         clipFillType: .positive)
        } else {
            let clpr = Clipper(options: .reverse)
            clpr.addPaths(destPolys, .subject, true)
            let r = destPolys.bounds
            var outer = Path()
            
            outer.append([r.left - 10, r.bottom + 10])
            outer.append([r.right + 10, r.bottom + 10])
            outer.append([r.right + 10, r.top - 10])
            outer.append([r.left - 10, r.top - 10])
            
            clpr.addPath(outer, .subject, true)
            try clpr.execute(clipType: .union,
                             solution: &solution,
                             subjFillType: .negative,
                             clipFillType: .negative)
            if solution.count > 0 {
                solution.remove(at: 0)
            }
        }
    }
    
    
    public func execute(_ solution: PolyTree,  delta: CGFloat) throws {
        fixOrientations ()
        doOffset(delta)
        
        //now clean up 'corners' ...
        if delta > 0 {
            let clpr = Clipper()
            clpr.addPaths(destPolys, PolyType.subject, true)
            try clpr.execute(clipType: .union,
                         polytree: solution,
                         subjFillType: .positive,
                         clipFillType: .positive)
        } else {
            let clpr = Clipper(options: .reverse)
            clpr.addPaths(destPolys, PolyType.subject, true)
            let r = destPolys.bounds
            var outer = Path()
            
            outer.append([r.left - 10, r.bottom + 10])
            outer.append([r.right + 10, r.bottom + 10])
            outer.append([r.right + 10, r.top - 10])
            outer.append([r.left - 10, r.top - 10])
            
            clpr.addPath(outer, PolyType.subject, true)
            try clpr.execute(clipType: .union,
                         polytree: solution,
                         subjFillType: .negative,
                         clipFillType: .negative)
            
            //remove the outer PolyNode rectangle ...
            if solution.childCount == 1 && solution.children[0].childCount > 0 {
                let outerNode = solution.children[0]
                solution.children[0] = outerNode.children[0]
                solution.children[0].parent = solution
                for i in 1..<outerNode.childCount {
                    solution.addChild(outerNode.children[i])
                }
            } else {
                solution.clear()
            }
        }
    }
    
    
    private func offsetPoint(_ j: Int, _ k: inout Int, _ joinType: JoinType) {
        //cross product ...
        sinA = (normals[k].x * normals[j].y - normals[j].x * normals[k].y)
        
        if (abs(sinA * delta) < 1.0) {
            //dot product ...
            let cosA = (normals[k].x * normals[j].x + normals[j].y * normals[k].y)
            if cosA > 0 { // angle ==> 0 degrees
                destPoly.append([round(srcPoly[j].x + normals[k].x * delta),round(srcPoly[j].y + normals[k].y * delta)])
                return
            }
            //else angle ==> 180 degrees
        } else if (sinA > 1.0) {
            sinA = 1.0
        } else if (sinA < -1.0) {
            sinA = -1.0
        }
        
        if (sinA * delta < 0) {
            destPoly.append([round(srcPoly[j].x + normals[k].x * delta),round(srcPoly[j].y + normals[k].y * delta)])
            destPoly.append(srcPoly[j])
            destPoly.append([round(srcPoly[j].x + normals[j].x * delta),round(srcPoly[j].y + normals[j].y * delta)])
        } else {
            switch joinType {
            case .miter:
                let r = 1 + (normals[j].x * normals[k].x +
                    normals[j].y * normals[k].y)
                if r >= miterLim {
                    doMiter (j, k, r)
                } else {
                    doSquare (j, k)
                }
            case .square:doSquare (j, k)
            case .round: doRound (j, k)
            }
        }
        k = j
    }
    
    private func doSquare (_ j: Int, _ k: Int) {
        let dx = tan(atan2(sinA, normals[k].x * normals[j].x + normals[k].y * normals[j].y) / 4)
        destPoly.append([round(srcPoly[j].x + delta * (normals[k].x - normals[k].y * dx)),
            round(srcPoly[j].y + delta * (normals[k].y + normals[k].x * dx))])
        destPoly.append([round(srcPoly[j].x + delta * (normals[j].x + normals[j].y * dx)),
                         round(srcPoly[j].y + delta * (normals[j].y - normals[j].x * dx))])
    }


    private func doMiter (_ j: Int, _ k: Int, _ r: CGFloat) {
        let q = delta / r
        destPoly.append([round(srcPoly[j].x + (normals[k].x + normals[j].x) * q),round(srcPoly[j].y + (normals[k].y + normals[j].y) * q)])
    }

    private func doRound (_ j: Int, _ k: Int) {
        let a = atan2(sinA, normals[k].x * normals[j].x + normals[k].y * normals[j].y)
        let steps = max(round(stepsPerRad * abs(a)).int,1)
        
        var x = normals[k].x
        var y = normals[k].y
        var x2 = CGFloat.zero
        for _ in 0..<steps {
            destPoly.append([round(srcPoly[j].x + x * delta),round(srcPoly[j].y + y * delta)])
            x2 = x
            x = x * cos - sin * y
            y = x2 * sin + y * cos
        }
        destPoly.append([round(srcPoly[j].x + normals[j].x * delta),round(srcPoly[j].y + normals[j].y * delta)])
    }
    
}

                
                

                
                


