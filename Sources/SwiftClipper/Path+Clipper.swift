//
//  Path+Clipper.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/13.
//

import CoreGraphics

extension Path {
    
    public func union(_ path: Path, isClosed: Bool = true) -> Paths {
        var paths = Paths()
        let c = Clipper()
        c.addPath(self, .subject, isClosed)
        c.addPath(path, .clip, isClosed)
        _ = try? c.execute(clipType: .union, solution: &paths)
        return paths
    }
    
    public func intersection(_ path: Path, isClosed: Bool = true) -> Paths {
        var paths = Paths()
        let c = Clipper()
        c.addPath(self, .subject, isClosed)
        c.addPath(path, .clip, isClosed)
        _ = try? c.execute(clipType: .intersection, solution: &paths)
        return paths
    }
    
    public func difference(_ path: Path, isClosed: Bool = true) -> Paths {
        var paths = Paths()
        let c = Clipper()
        c.addPath(self, .subject, isClosed)
        c.addPath(path, .clip, isClosed)
        _ = try? c.execute(clipType: .difference, solution: &paths)
        return paths
    }
    
    public func xor(_ path: Path, isClosed: Bool = true) -> Paths {
        var paths = Paths()
        let c = Clipper()
        c.addPath(self, .subject, isClosed)
        c.addPath(path, .clip, isClosed)
        _ = try? c.execute(clipType: .xor, solution: &paths)
        return paths
    }
    
    
    public func simplify(fillType: PolyFillType = .evenOdd) -> Paths {
        var result = Paths()
        let c = Clipper(options: .strictlySimple)
        c.addPath(self, .subject, true)
        _ = try? c.execute(clipType: ClipType.union, solution: &result, subjFillType: fillType, clipFillType: fillType)
        return result
    }
    
    @discardableResult
    private func excludeOp(_ op: OutPt) -> OutPt {
        let result = op.prev
        result?.next = op.next
        op.next.prev = result
        result?.index = 0
        return result!
    }
    
    public func cleanPolygon(distance: CGFloat = 1.415) -> Path {
        //distance = proximity in units/pixels below which vertices will be stripped.
        //Default ~= sqrt(2) so when adjacent vertices or semi-adjacent vertices have
        //both x & y coords within 1 unit, then the second vertex will be stripped.
        
        var cnt = self.count
        
        if cnt == 0  {
            return Path()
        }
        
        let outPts = [OutPt](repeating: OutPt(), count: cnt)
        
        for i in self.indices {
            outPts[i].pt = self[i]
            outPts[i].next = outPts[(i + 1) % cnt]
            outPts[i].next.prev = outPts[i]
            outPts[i].index = 0
        }
        
        let distSqrd = distance * distance
        var op = outPts[0]
        while op.index == 0 && op.next !== op.prev {
            if op.pt.areClose(pt: op.prev.pt, distSqrd: distSqrd) {
                op = excludeOp(op)
                cnt -= 1
            } else if op.prev.pt.areClose(pt: op.next.pt, distSqrd: distSqrd) {
                excludeOp(op.next)
                op = excludeOp(op)
                cnt -= 2
            } else if op.prev.pt.slopesNearCollinear(pt2: op.pt, pt3: op.next.pt, distSqrd: distSqrd) {
                op = excludeOp(op)
                cnt -= 1
            } else {
                op.index = 1
                op = op.next
            }
        }
        
        if cnt < 3 {
            cnt = 0
        }
        var result = Path()
        for _ in self.indices {
            result.append(op.pt)
            op = op.next
        }
        return result
    }
    
    
    func minkowski(path: Path, isSum: Bool, isClosed: Bool) -> Paths {
        let delta = isClosed ? 1 : 0
        let polyCnt = self.count
        let pathCnt = path.count
        var result = Paths()
        if isSum {
            for i in path.indices {
                var p = Path()
                for ip in self {
                    p.append(CGPoint(x: path[i].x + ip.x, y:path[i].y + ip.y))
                }
                result.append(p)
            }
        } else {
            for i in path.indices {
                var p = Path()
                for ip in self {
                    p.append(CGPoint(x: path[i].x - ip.x, y: path[i].y - ip.y))
                }
                
                result.append(p)
            }
            
        }
        
        var quads = Paths()
        quads.reserveCapacity((pathCnt + delta) * (polyCnt + 1))
        for i in 0..<(pathCnt - 1 + delta) {
            for j in self.indices {
                var quad = Path()
                quad.append(result[i % pathCnt][j % polyCnt])
                quad.append(result[(i + 1) % pathCnt][j % polyCnt])
                quad.append(result[(i + 1) % pathCnt][(j + 1) % polyCnt])
                quad.append(result[i % pathCnt][(j + 1) % polyCnt])
                if !quad.orientation {
                    quad.reverse()
                }
                quads.append(quad)
            }
        }
        
        return quads
    }
    
    public func minkowskiSum(path: Path, isClosed: Bool) -> Paths {
        var paths = self.minkowski(path: path, isSum: true, isClosed: isClosed)
        let c = Clipper()
        c.addPaths(paths, .subject, true)
        _ = try? c.execute(clipType: ClipType.union, solution: &paths, subjFillType: PolyFillType.nonZero, clipFillType: PolyFillType.nonZero)
        return paths
    }
    
    private func translate(delta: CGPoint) -> Path {
        return self.map {
            return CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
        }
    }
    
    public func minkowskiSum(paths: Paths, isClosed: Bool) -> Paths {
        var solution = Paths()
        let c = Clipper()
        for i in paths.indices {
            let tmp = self.minkowski(path: paths[i], isSum: true, isClosed: isClosed)
            c.addPaths(tmp, .subject, true)
            if isClosed {
                let path = paths[i].translate(delta: self[0])
                c.addPath(path, .clip, true)
            }
        }
        _ = try? c.execute(clipType: ClipType.union, solution: &solution,
                  subjFillType: PolyFillType.nonZero, clipFillType: PolyFillType.nonZero)
        return solution
    }
    
    public func minkowskiDiff(poly poly2: Path) -> Paths {
        var paths = self.minkowski(path: poly2, isSum: false, isClosed: true)
        let c = Clipper()
        c.addPaths(paths, .subject, true)
        _ = try? c.execute(clipType: .union, solution: &paths, subjFillType: .nonZero, clipFillType: .nonZero)
        return paths
    }
}



extension Paths {
    
    public func unions(_ isClosed: Bool = true) -> Paths {
        var paths = Paths()
        let c = Clipper()
        c.addPaths(self, .subject, isClosed)
        _ = try? c.execute(clipType: .union, solution: &paths)
        return paths
    }
    
    public func intersection(_ path: Path, isClosed: Bool = true) -> Paths {
        var paths = Paths()
        let c = Clipper()
        c.addPaths(self, .subject, isClosed)
        _ = try? c.execute(clipType: .intersection, solution: &paths)
        return paths
    }
    
    public func simplify(fillType: PolyFillType = .evenOdd) -> Paths {
        var result = Paths()
        let c = Clipper(options: .strictlySimple)
        c.addPaths(self, .subject, true)
        _ = try? c.execute(clipType: ClipType.union, solution: &result, subjFillType: fillType, clipFillType: fillType)
        return result
    }
    
    public func cleanPolygons(distance: CGFloat) -> Paths {
        var result = Paths()
        for i in self.indices {
            result.append(self[i].cleanPolygon(distance: distance))
        }
        return result
    }
    
}
