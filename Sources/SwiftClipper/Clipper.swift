//
//  Clipper.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/2.
//

import Foundation
import CoreGraphics

public class Clipper: ClipperBase {
    
    private var clipType = ClipType.union
    private var maxima: Maxima?
    private var sortedEdges: TEdge?
    private var intersectList = [IntersectNode]()
    private var executeLocked = false
    private var clipFillType = PolyFillType.evenOdd
    private var subjFillType = PolyFillType.evenOdd
    private var joins = [Join]()
    private var ghostJoins = [Join]()
    private var usingPolyTree = false
    private var reverseSolution = false
    private var strictlySimple = false

    public struct SolutionOptions: OptionSet {
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let `default`    = SolutionOptions(rawValue: 1 << 0)
        public static let reverse  = SolutionOptions(rawValue: 1 << 1)
        public static let strictlySimple   = SolutionOptions(rawValue: 1 << 2)
        public static let preserveCollinear   = SolutionOptions(rawValue: 1 << 3)
    }
    
    public init(options:SolutionOptions = .default) {
        super.init()
        reverseSolution = options.contains(.reverse)
        strictlySimple = options.contains(.strictlySimple)
        preserveCollinear = options.contains(.preserveCollinear)
    }
    
    @discardableResult
    public func execute(clipType: ClipType, solution:inout Paths, fillType: PolyFillType = .evenOdd) throws ->  Bool {
        return try execute(clipType: clipType, solution: &solution, subjFillType: fillType, clipFillType: fillType)
    }
    
    @discardableResult
    public func execute(clipType: ClipType, polytree:inout PolyTree, fillType: PolyFillType = .evenOdd) throws ->  Bool {
        return try execute(clipType: clipType, polytree: polytree, subjFillType: fillType, clipFillType: fillType)
    }
    
    @discardableResult
    public func execute(clipType: ClipType, solution:inout Paths, subjFillType: PolyFillType, clipFillType: PolyFillType ) throws ->  Bool {

        if executeLocked {
            return false
        }
        if hasOpenPaths {
            throw ClipperError(message:"Error: PolyTree struct is needed for open path clipping.")
        }
        
        executeLocked = true
        self.subjFillType = subjFillType
        self.clipFillType = clipFillType
        self.clipType = clipType
        self.usingPolyTree = false
        var succeeded = false
        do {
            succeeded = try executeInternal()
            //build the return polygons ...
            if succeeded {
                buildResult(&solution)
            }
        } catch {
            
        }
        
        clearOutRecs()
        executeLocked = false
        return succeeded
    }
    
    @discardableResult
    public func execute(clipType: ClipType, polytree: PolyTree, subjFillType: PolyFillType, clipFillType: PolyFillType) throws ->  Bool {

        if executeLocked {
            return false
        }
        executeLocked = true
        self.subjFillType = subjFillType
        self.clipFillType = clipFillType
        self.clipType = clipType
        self.usingPolyTree = true
        var succeeded = false
        
        succeeded = try executeInternal()
        //build the return polygons ...
        if succeeded {
            buildResult2(polytree)
        }
        
        clearOutRecs()
        executeLocked = false
        return succeeded
    }
    
    private func getDx(_ pt1: CGPoint,_ pt2: CGPoint) -> CGFloat {
        if pt1.y == pt2.y {return Horizontal}
        return pt2.x - pt1.x / pt2.y - pt1.y
    }
    
    private func firstIsBottomPt(_ btmPt1: OutPt, _ btmPt2: OutPt) -> Bool {
        guard var p = btmPt1.prev else {
            return false
        }
        
        while p.pt == btmPt1.pt && p !== btmPt1 {
            p = p.prev
        }
        
        let dx1p = abs(getDx(btmPt1.pt, p.pt))
        p = btmPt1.next
        
        while p.pt == btmPt1.pt && p !== btmPt1 {
            p = p.next
        }
        let dx1n = abs(getDx(btmPt1.pt, p.pt))
        
        p = btmPt2.prev
        while p.pt == btmPt2.pt && p !== btmPt2 {
            p = p.prev
        }
        
        let dx2p = abs(getDx(btmPt2.pt, p.pt))
        p = btmPt2.next
        
        while p.pt == btmPt2.pt && p !== btmPt2 {
            p = p.next
        }
        let dx2n = abs(getDx(btmPt2.pt, p.pt))
        
        if max(dx1p, dx1n) == max(dx2p, dx2n) && min(dx1p, dx1n) == min(dx2p, dx2n) {
            return btmPt1.area > 0 //if otherwise identical use orientation
        }
        
        return (dx1p >= dx2p && dx1p >= dx2n) || (dx1n >= dx2p && dx1n >= dx2n)
    }
    
    private func getBottomPt(_ pp: OutPt) -> OutPt? {
        guard var p = pp.next else {
            return nil
        }
        var pp = pp
        var dups:OutPt?
        while p !== pp {
            if p.pt.y > pp.pt.y {
                pp = p
                dups = nil
            } else if p.pt.y == pp.pt.y && p.pt.x <= pp.pt.x {
                if p.pt.x < pp.pt.x {
                    dups = nil
                    pp = p
                } else {
                    if p.next !== pp && p.prev !== pp {
                        dups = p
                    }
                }
            }
            p = p.next
        }
        if dups != nil {
            //there appears to be at least 2 vertices at bottomPt so ...
            while dups !== p {
                if !firstIsBottomPt(p, dups!) {
                    pp = dups!
                }
                dups = dups!.next
                while dups!.pt != pp.pt {
                    dups = dups?.next
                }
            }
        }
        return pp
    }
    
    private func getLowerMostRec(_ outRec1: OutRec, _ outRec2: OutRec) -> OutRec {
        //work out which polygon fragment has the correct hole state ...
        if outRec1.bottomPt == nil {
            outRec1.bottomPt = getBottomPt(outRec1.pts)
        }
        if outRec2.bottomPt == nil {
            outRec2.bottomPt = getBottomPt(outRec2.pts)
        }
        let bPt1 = outRec1.bottomPt!
        let bPt2 = outRec2.bottomPt!
        if bPt1.pt.y > bPt2.pt.y {
            return outRec1
        } else if bPt1.pt.y < bPt2.pt.y {
            return outRec2
        } else if bPt1.pt.x < bPt2.pt.x {
            return outRec1
        } else if bPt1.pt.x > bPt2.pt.x {
            return outRec2
        } else if bPt1.next == bPt1 {
            return outRec2
        } else if bPt2.next == bPt2 {
            return outRec1
        } else if firstIsBottomPt(bPt1, bPt2) {
            return outRec1
        } else {
            return outRec2
        }
    }
    
    private func horzSegmentsOverlap(_ seg1a: CGFloat, _ seg1b: CGFloat, _ seg2a: CGFloat, _ seg2b: CGFloat) -> Bool {
        var seg1a = seg1a
        var seg1b = seg1b
        var seg2a = seg2a
        var seg2b = seg2b
        if seg1a > seg1b {
            swap(&seg1a, &seg1b)
        }
        if seg2a > seg2b {
            swap(&seg2a, &seg2b)
        }
        return (seg1a < seg2b) && (seg2a < seg1b)
    }
    
    private func insertMaxima(_ x: CGFloat) {
        //double-linked list: sorted ascending, ignoring dups.
        let newMax = Maxima()
        newMax.x = x
        if maxima == nil {
            maxima = newMax
            maxima?.next = nil
            maxima?.prev = nil
        } else if x < maxima!.x {
            newMax.next = maxima
            newMax.prev = nil
            maxima = newMax
        } else {
            var m = maxima!
            while m.next != nil && x >= m.next!.x {
                m = m.next!
            }
            if x == m.x {
                return //ie ignores duplicates (& CG to clean up newMax)
            }
            //insert newMax between m and m.next ...
            newMax.next = m.next
            newMax.prev = m
            if m.next != nil {
                m.next!.prev = newMax
            }
            m.next = newMax
        }
    }
    
    private func fixHoleLinkage(_ outRec: OutRec) {
        //skip if an outermost polygon or
        //already already points to the correct firstLeft ...
        if outRec.firstLeft == nil ||
            (outRec.isHole != outRec.firstLeft?.isHole &&
                outRec.firstLeft?.pts != nil) {
            return
        }
        
        var orfl = outRec.firstLeft
        while orfl != nil && (orfl?.isHole == outRec.isHole || orfl?.pts == nil) {
            orfl = orfl?.firstLeft
        }
        outRec.firstLeft = orfl
    }
    
    private func executeInternal() throws -> Bool {
        
        defer {
            joins.removeAll()
            ghostJoins.removeAll()
        }
        
        
        reset()
        sortedEdges = nil
        maxima = nil
        
        var botY = CGFloat.zero, topY = CGFloat.zero
        if !popScanbeam(&botY) {
            return false
        }
        insertLocalMinimaIntoAEL(botY)
        while popScanbeam(&topY) || localMinimaPending {
            try processHorizontals()
            ghostJoins.removeAll()
            let result = processIntersections(topY)
            if !result {
                return false
            }
            try processEdgesAtTopOfScanbeam(topY)
            botY = topY
            insertLocalMinimaIntoAEL(botY)
        }
        
        //fix orientations ...
        for outRec in polyOuts {
            if outRec.pts == nil || outRec.isOpen {
                continue
            }
            if (outRec.isHole ^ reverseSolution) == (outRec.area > 0) {
                outRec.pts.reverse()
            }
        }
        
        joinCommonEdges()
        
        for outRec in polyOuts {
            if outRec.pts == nil {
                continue
            } else if outRec.isOpen {
                fixUpOutPolyline(outRec)
            } else {
                fixUpOutPolygon(outRec)
            }
            
        }
        
        if strictlySimple {
            doSimplePolygons()
        }
        return true
        
    }
    
    private func addJoin(_ op1: OutPt, _ op2: OutPt, _ offPt: CGPoint) {
        let j = Join(op1:op1, op2:op2)
        j.offPt = offPt
        joins.append(j)
    }
    
    private func addGhostJoin(_ op: OutPt, _ offPt: CGPoint) {
        let j = Join(op1: op,op2: OutPt())
        j.offPt = offPt
        ghostJoins.append(j)
    }
    
    private func insertLocalMinimaIntoAEL(_ botY: CGFloat) {
        var lm:LocalMinima?
        while popLocalMinima(botY, &lm) {
            let lb = lm?.leftBound
            let rb = lm?.rightBound
            
            var op1: OutPt?
            if lb == nil {
                insertEdgeIntoAEL(rb!, nil)
                setWindingCount(rb!)
                if isContributing(rb!) {
                    op1 = addOutPt(rb!, rb!.bot)
                }
            } else if rb == nil {
                insertEdgeIntoAEL(lb!, nil)
                setWindingCount(lb!)
                if isContributing(lb!) {
                    op1 = addOutPt(lb!, lb!.bot)
                }
                insertScanbeam(lb!.top.y)
            } else {
                insertEdgeIntoAEL(lb!, nil)
                insertEdgeIntoAEL(rb!, lb)
                setWindingCount(lb!)
                rb?.windCnt = lb!.windCnt
                rb?.windCnt2 = lb!.windCnt2
                if isContributing(lb!) {
                    op1 = addLocalMinPoly(lb!, rb!, lb!.bot)
                }
                insertScanbeam(lb!.top.y)
            }
            
            if rb != nil {
                if rb!.isHorizontal {
                    addEdgeToSEL(rb!)
                    if rb?.nextInLML != nil {
                        insertScanbeam(rb!.nextInLML!.top.y)
                    }
                }
                else {
                    insertScanbeam(rb!.top.y)
                }
            }
            
            if lb == nil || rb == nil {
                continue
            }
            
            //if output polygons share an Edge with a horizontal rb, they'll need joining later ...
            if op1 != nil && rb!.isHorizontal &&
                ghostJoins.count > 0 && rb!.windDelta != 0 {
                for i in ghostJoins.indices {
                    //if the horizontal Rb and a 'ghost' horizontal overlap, then convert
                    //the 'ghost' join to a real join ready for later ...
                    let j = ghostJoins[i]
                    if horzSegmentsOverlap(j.outPt1.pt.x, j.offPt.x, rb!.bot.x, rb!.top.x) {
                        addJoin(j.outPt1, op1!, j.offPt)
                    }
                }
            }
            
            if (lb!.outIdx >= 0 && lb!.prevInAEL != nil &&
                lb!.prevInAEL!.curr.x == lb!.bot.x &&
                lb!.prevInAEL!.outIdx >= 0 &&
                lb!.prevInAEL!.curr.isSlopesEqual(lb!.prevInAEL!.top, lb!.curr, lb!.top) &&
                lb!.windDelta != 0 && lb!.prevInAEL!.windDelta != 0) {
                let op2 = addOutPt(lb!.prevInAEL!, lb!.bot)
                addJoin(op1!, op2, lb!.top)
            }
            
            if lb?.nextInAEL != rb {
                
                if (rb!.outIdx >= 0 && rb!.prevInAEL!.outIdx >= 0 &&
                    rb!.prevInAEL!.top.isSlopesEqual(rb!.prevInAEL!.curr, rb!.curr, rb!.top) &&
                    rb!.windDelta != 0 && rb!.prevInAEL!.windDelta != 0) {
                    let op2 = addOutPt(rb!.prevInAEL!, rb!.bot)
                    addJoin(op1!, op2, rb!.top)
                }
                
                var e = lb?.nextInAEL
                if e != nil {
                    while e != rb {
                        //nb: For calculating winding counts etc, intersectEdges() assumes
                        //that param1 will be to the right of param2 ABOVE the intersection ...
                        intersectEdges(rb!, e!, lb!.curr) //order important here
                        e = e!.nextInAEL
                    }
                }
                
            }
        }
    }
    
    private func insertEdgeIntoAEL(_ edge: TEdge, _ startEdge: TEdge?) {
        var startEdge = startEdge
        if activeEdges == nil {
            edge.prevInAEL = nil
            edge.nextInAEL = nil
            activeEdges = edge
        } else if startEdge == nil && e2InsertsBeforeE1(activeEdges!, edge) {
            edge.prevInAEL = nil
            edge.nextInAEL = activeEdges
            activeEdges?.prevInAEL = edge
            activeEdges = edge
        } else {
            if startEdge == nil {
                startEdge = activeEdges
            }
            while startEdge?.nextInAEL != nil && !e2InsertsBeforeE1(startEdge!.nextInAEL!, edge) {
                startEdge = startEdge?.nextInAEL
            }
            edge.nextInAEL = startEdge?.nextInAEL
            if startEdge?.nextInAEL != nil {
                startEdge?.nextInAEL?.prevInAEL = edge
            }
            edge.prevInAEL = startEdge
            startEdge?.nextInAEL = edge
        }
    }
    
    @inline(__always)
    private func e2InsertsBeforeE1(_ e1: TEdge, _ e2: TEdge) -> Bool {
        if e2.curr.x == e1.curr.x {
            if e2.top.y > e1.top.y {
                return e2.top.x < e1.topX(of: e2.top.y)
            } else {
                return e1.top.x > e2.topX(of: e1.top.y)
            }
        }
        return e2.curr.x < e1.curr.x
    }
    
    private func isEvenOddFillType(_ edge: TEdge) -> Bool {
        if edge.polyType == .subject {
            return subjFillType == .evenOdd
        }
        return clipFillType == .evenOdd
    }
    
    private func isEvenOddAltFillType(_ edge: TEdge) -> Bool {
        if edge.polyType == .subject {
            return clipFillType == .evenOdd
        }
        return subjFillType == .evenOdd
    }
    
    private func isContributing(_ edge: TEdge) -> Bool {
        var pft: PolyFillType
        var pft2: PolyFillType
        if edge.polyType == .subject {
            pft = subjFillType
            pft2 = clipFillType
        } else {
            pft = clipFillType
            pft2 = subjFillType
        }
        
        switch pft {
        case .evenOdd:
            //return false if a subj line has been flagged as inside a subj polygon
            if edge.windDelta == 0 && edge.windCnt != 1 {
                return false
            }
        case .nonZero:
            if abs(edge.windCnt) != 1 {
                return false
            }
        case .positive:
            if edge.windCnt != 1 {
                return false
            }
        default: //PolyFillType.negative
            if edge.windCnt != -1 {
                return false
            }
        }
        
        switch clipType {
        case .intersection:
            switch pft2 {
            case .evenOdd:fallthrough
            case .nonZero:
                return (edge.windCnt2 != 0)
            case .positive:
                return (edge.windCnt2 > 0)
            default:
                return (edge.windCnt2 < 0)
            }
        case .union:
            switch pft2
            {
            case .evenOdd:fallthrough
            case .nonZero:
                return (edge.windCnt2 == 0)
            case .positive:
                return (edge.windCnt2 <= 0)
            default:
                return (edge.windCnt2 >= 0)
            }
        case .difference:
            if edge.polyType == .subject {
                switch pft2
                {
                case .evenOdd:fallthrough
                case .nonZero:
                    return (edge.windCnt2 == 0)
                case .positive:
                    return (edge.windCnt2 <= 0)
                default:
                    return (edge.windCnt2 >= 0)
                }
            }
            else {
                switch pft2
                {
                case .evenOdd:fallthrough
                case .nonZero:
                    return (edge.windCnt2 != 0)
                case .positive:
                    return (edge.windCnt2 > 0)
                default:
                    return (edge.windCnt2 < 0)
                }
            }
            
        case .xor:
            if edge.windDelta == 0  {//XOr always contributing unless open
                switch pft2
                {
                case .evenOdd:fallthrough
                case .nonZero:
                    return (edge.windCnt2 == 0)
                case .positive:
                    return (edge.windCnt2 <= 0)
                default:
                    return (edge.windCnt2 >= 0)
                }
                
            }
            else {
                return true
            }
        default:
            return true
        }
    }
    
    private func setWindingCount(_ edge: TEdge) {
        var e = edge.prevInAEL
        //find the edge of the same polytype that immediately preceeds 'edge' in AEL
        while e != nil && (e!.polyType != edge.polyType || e!.windDelta == 0) {
            e = e?.prevInAEL
        }
        if e == nil {
            if edge.windDelta == 0 {
                let pft = (edge.polyType == .subject ? subjFillType : clipFillType)
                edge.windCnt = (pft == .negative ? -1 : 1)
            } else {
                edge.windCnt = edge.windDelta
            }
            edge.windCnt2 = 0
            e = activeEdges //ie get ready to calc windCnt2
        } else if edge.windDelta == 0 && clipType != .union {
            edge.windCnt = 1
            edge.windCnt2 = e!.windCnt2
            e = e!.nextInAEL //ie get ready to calc windCnt2
        } else if isEvenOddFillType(edge) {
            //EvenOdd filling ...
            if edge.windDelta == 0 {
                //are we inside a subj polygon ...
                var inside = true
                var e2 = e!.prevInAEL
                while e2 != nil {
                    if e2!.polyType == e!.polyType && e2!.windDelta != 0 {
                        inside = !inside
                    }
                    e2 = e2?.prevInAEL
                }
                edge.windCnt = (inside ? 0 : 1)
            } else {
                edge.windCnt = edge.windDelta
            }
            edge.windCnt2 = e!.windCnt2
            e = e!.nextInAEL //ie get ready to calc windCnt2
        } else {
            //nonZero, Positive or Negative filling ...
            if e!.windCnt * e!.windDelta < 0 {
                //prev edge is 'decreasing' WindCount (WC) toward zero
                //so we're outside the previous polygon ...
                if abs(e!.windCnt) > 1 {
                    //outside prev poly but still inside another.
                    //when reversing direction of prev poly use the same WC
                    if e!.windDelta * edge.windDelta < 0 {
                        edge.windCnt = e!.windCnt
                    } else { //otherwise continue to 'decrease' WC ...
                        edge.windCnt = e!.windCnt + edge.windDelta
                    }
                } else {
                    //now outside all polys of same polytype so set own WC ...
                    edge.windCnt = (edge.windDelta == 0 ? 1 : edge.windDelta)
                }
                
            } else {
                //prev edge is 'increasing' WindCount (WC) away from zero
                //so we're inside the previous polygon ...
                if edge.windDelta == 0 {
                    edge.windCnt = (e!.windCnt < 0 ? e!.windCnt - 1 : e!.windCnt + 1)
                } else if e!.windDelta * edge.windDelta < 0 {//if wind direction is reversing prev then use same WC
                    edge.windCnt = e!.windCnt
                } else {//otherwise add to WC ...
                    edge.windCnt = e!.windCnt + edge.windDelta
                }
            }
            edge.windCnt2 = e!.windCnt2
            e = e?.nextInAEL //ie get ready to calc windCnt2
        }
        
        //update windCnt2 ...
        if isEvenOddAltFillType(edge) {
            //EvenOdd filling ...
            while e != edge {
                if e!.windDelta != 0 {
                    edge.windCnt2 = (edge.windCnt2 == 0 ? 1 : 0)
                }
                e = e?.nextInAEL
            }
        } else {
            //nonZero, Positive or Negative filling ...
            while e != edge {
                edge.windCnt2 += e!.windDelta
                e = e!.nextInAEL
            }
        }
    }
    
    private func addEdgeToSEL(_ edge: TEdge) {
        //SEL pointers in PEdge are use to build transient lists of horizontal edges.
        //However, since we don't need to worry about processing order, all additions
        //are made to the front of the list ...PopEdgeFromSEL
        if sortedEdges == nil {
            sortedEdges = edge
            edge.prevInSEL = nil
            edge.nextInSEL = nil
        } else {
            edge.nextInSEL = sortedEdges
            edge.prevInSEL = nil
            sortedEdges?.prevInSEL = edge
            sortedEdges = edge
        }
    }
    
    private func popEdgeFromSEL(_ edge:inout TEdge?) -> Bool {
        if sortedEdges == nil {
            return false
            
        }
        edge = sortedEdges
        deleteFromSEL(sortedEdges!)
        return true
    }
    
    private func copyAELToSEL() {
        var e = activeEdges
        sortedEdges = e
        while e != nil {
            e?.prevInSEL = e?.prevInAEL
            e?.nextInSEL = e?.nextInAEL
            e = e?.nextInAEL
        }
    }
    
    private func swapPositionsInSEL(_ edge1: TEdge, _ edge2: TEdge) {
        if edge1.nextInSEL == nil && edge1.prevInSEL == nil {
            return
        }
        if edge2.nextInSEL == nil && edge2.prevInSEL == nil {
            return
        }
        
        if edge1.nextInSEL == edge2 {
            let next = edge2.nextInSEL
            if next != nil {
                next?.prevInSEL = edge1
            }
            let prev = edge1.prevInSEL
            if prev != nil {
                prev?.nextInSEL = edge2
            }
            edge2.prevInSEL = prev
            edge2.nextInSEL = edge1
            edge1.prevInSEL = edge2
            edge1.nextInSEL = next
        } else if edge2.nextInSEL == edge1 {
            let next = edge1.nextInSEL
            if next != nil {
                next?.prevInSEL = edge2
            }
            let prev = edge2.prevInSEL
            if prev != nil {
                prev?.nextInSEL = edge1
            }
            edge1.prevInSEL = prev
            edge1.nextInSEL = edge2
            edge2.prevInSEL = edge1
            edge2.nextInSEL = next
        } else {
            let next = edge1.nextInSEL
            let prev = edge1.prevInSEL
            edge1.nextInSEL = edge2.nextInSEL
            if edge1.nextInSEL != nil {
                edge1.nextInSEL?.prevInSEL = edge1
            }
            edge1.prevInSEL = edge2.prevInSEL
            if edge1.prevInSEL != nil {
                edge1.prevInSEL?.nextInSEL = edge1
            }
            edge2.nextInSEL = next
            if edge2.nextInSEL != nil {
                edge2.nextInSEL?.prevInSEL = edge2
            }
            edge2.prevInSEL = prev
            if edge2.prevInSEL != nil {
                edge2.prevInSEL?.nextInSEL = edge2
            }
        }
        
        if edge1.prevInSEL == nil {
            sortedEdges = edge1
        } else if edge2.prevInSEL == nil {
            sortedEdges = edge2
        }
    }
    
    private func addLocalMaxPoly(_ e1: TEdge, _ e2: TEdge, _ pt: CGPoint) {
        addOutPt(e1, pt)
        if e2.windDelta == 0 {
            addOutPt(e2, pt)
        }
        if e1.outIdx == e2.outIdx {
            e1.outIdx = Unassigned
            e2.outIdx = Unassigned
        } else if e1.outIdx < e2.outIdx {
            appendPolygon(e1, e2)
        } else {
            appendPolygon(e2, e1)
        }
    }
    
    @discardableResult
    private func addLocalMinPoly(_ e1: TEdge, _ e2: TEdge, _ pt: CGPoint) -> OutPt {
        var result: OutPt
        var e: TEdge
        var prevE: TEdge?
        if e2.isHorizontal || e1.dx > e2.dx {
            result = addOutPt(e1, pt)
            e2.outIdx = e1.outIdx
            e1.side = EdgeSide.left
            e2.side = EdgeSide.right
            e = e1
            if e.prevInAEL == e2 {
                prevE = e2.prevInAEL
            } else {
                prevE = e.prevInAEL
            }
        } else {
            result = addOutPt(e2, pt)
            e1.outIdx = e2.outIdx
            e1.side = EdgeSide.right
            e2.side = EdgeSide.left
            e = e2
            if e.prevInAEL == e1 {
                prevE = e1.prevInAEL
            } else {
                prevE = e.prevInAEL
            }
        }
        
        if prevE != nil && prevE!.outIdx >= 0 && prevE!.top.y < pt.y && e.top.y < pt.y {
            let xPrev = prevE!.topX(of: pt.y)
            let xE = e.topX(of: pt.y)
            if xPrev == xE && e.windDelta != 0 && prevE!.windDelta != 0 &&
                prevE!.top.isSlopesEqual(CGPoint(x: xPrev, y: pt.y), CGPoint(x: xE, y: pt.y), e.top)
            {
                let outPt = addOutPt(prevE!, pt)
                addJoin(result, outPt, e.top)
            }
        }
        return result
    }
    
    @discardableResult
    private func addOutPt(_ e: TEdge, _ pt: CGPoint) -> OutPt {
        if e.outIdx < 0 {
            let outRec = createOutRec()
            outRec.isOpen = (e.windDelta == 0)
            let newOp = OutPt()
            outRec.pts = newOp
            newOp.index = outRec.index
            newOp.pt = pt
            newOp.next = newOp
            newOp.prev = newOp
            if !outRec.isOpen {
                setHoleState(e, outRec)
            }
            e.outIdx = outRec.index //nb: do this after SetZ !
            return newOp
        } else {
            let outRec = polyOuts[e.outIdx]
            //OutRec.pts is the 'left-most' point & OutRec.pts.prev is the 'right-most'
            let op:OutPt = outRec.pts
            let toFront = (e.side == .left)
            if toFront && pt == op.pt {
                return op
            } else if !toFront && pt == op.prev.pt {
                return op.prev
            }
            
            let newOp = OutPt()
            newOp.index = outRec.index
            newOp.pt = pt
            newOp.next = op
            newOp.prev = op.prev
            newOp.prev.next = newOp
            op.prev = newOp
            if toFront {
                outRec.pts = newOp
            }
            return newOp
        }
    }
    
    private func getLastOutPt(_ e: TEdge) -> OutPt {
        let outRec = polyOuts[e.outIdx]
        if e.side == .left {
            return outRec.pts
        }
        return outRec.pts.prev
    }
    
    private func setHoleState(_ e: TEdge, _ outRec: OutRec) {
        var e2 = e.prevInAEL
        var eTmp: TEdge?
        while e2 != nil {
            if e2!.outIdx >= 0 && e2!.windDelta != 0 {
                if eTmp == nil {
                    eTmp = e2
                } else if eTmp!.outIdx == e2!.outIdx{
                    eTmp = nil //paired
                }
            }
            e2 = e2?.prevInAEL
        }
        
        if eTmp == nil {
            outRec.firstLeft = nil
            outRec.isHole = false
        } else {
            outRec.firstLeft = polyOuts[eTmp!.outIdx]
            outRec.isHole = !outRec.firstLeft!.isHole
        }
    }
    
    
    private func outRec1RightOfOutRec2(_ outRec1: OutRec?, _ outRec2: OutRec) -> Bool {
        var outRec1 = outRec1
        repeat {
            outRec1 = outRec1?.firstLeft
            if outRec1 == outRec2 {
                return true
            }
        } while outRec1 != nil
        return false
    }
    
    private func appendPolygon(_ e1:TEdge, _ e2: TEdge) {
        let outRec1: OutRec! = polyOuts[e1.outIdx]
        let outRec2: OutRec! = polyOuts[e2.outIdx]
        
        var holeStateRec: OutRec
        if outRec1RightOfOutRec2(outRec1, outRec2) {
            holeStateRec = outRec2!
        } else if outRec1RightOfOutRec2(outRec2, outRec1) {
            holeStateRec = outRec1!
        } else {
            holeStateRec = getLowerMostRec(outRec1, outRec2)
        }
        
        //get the start and ends of both output polygons and
        //join E2 poly onto E1 poly and delete pointers to E2 ...
        let p1_lft: OutPt = outRec1.pts
        let p1_rt: OutPt = p1_lft.prev
        let p2_lft: OutPt = outRec2.pts
        let p2_rt: OutPt = p2_lft.prev
        
        //join e2 poly onto e1 poly and delete pointers to e2 ...
        if e1.side == .left {
            if e2.side == .left {
                //z y x a b c
                p2_lft.reverse()
                p2_lft.next = p1_lft
                p1_lft.prev = p2_lft
                p1_rt.next = p2_rt
                p2_rt.prev = p1_rt
                outRec1.pts = p2_rt
            } else {
                //x y z a b c
                p2_rt.next = p1_lft
                p1_lft.prev = p2_rt
                p2_lft.prev = p1_rt
                p1_rt.next = p2_lft
                outRec1.pts = p2_lft
            }
        } else {
            if e2.side == .right {
                //a b c z y x
                p2_lft.reverse()
                p1_rt.next = p2_rt
                p2_rt.prev = p1_rt
                p2_lft.next = p1_lft
                p1_lft.prev = p2_lft
            } else {
                //a b c x y z
                p1_rt.next = p2_lft
                p2_lft.prev = p1_rt
                p1_lft.prev = p2_rt
                p2_rt.next = p1_lft
            }
        }
        
        outRec1.bottomPt = nil
        if holeStateRec == outRec2 {
            if outRec2.firstLeft != outRec1 {
                outRec1.firstLeft = outRec2.firstLeft
            }
            outRec1.isHole = outRec2.isHole
        }
        outRec2.pts = nil
        outRec2.bottomPt = nil
        
        outRec2.firstLeft = outRec1
        
        let OKIdx = e1.outIdx
        let ObsoleteIdx = e2.outIdx
        
        e1.outIdx = Unassigned //nb: safe because we only get here via addLocalMaxPoly
        e2.outIdx = Unassigned
        
        var e: TEdge! = activeEdges
        while e != nil {
            if e.outIdx == ObsoleteIdx {
                e.outIdx = OKIdx
                e.side = e1.side
                break
            }
            e = e.nextInAEL
        }
        outRec2.index = outRec1.index
    }    
    
    private func swapSides(_ edge1: TEdge, _ edge2: TEdge) {
        let side = edge1.side
        edge1.side = edge2.side
        edge2.side = side
    }
    
    private func swapPolyIndexes(_ edge1: TEdge, _ edge2:TEdge) {
        let outIdx = edge1.outIdx
        edge1.outIdx = edge2.outIdx
        edge2.outIdx = outIdx
    }
    
    private func intersectEdges(_ e1: TEdge, _ e2: TEdge, _ pt: CGPoint) {
        //e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
        //e2 in AEL except when e1 is being inserted at the intersection point ...
        
        let e1Contributing = (e1.outIdx >= 0)
        let e2Contributing = (e2.outIdx >= 0)
        
        //update winding counts...
        //assumes that e1 will be to the right of e2 ABOVE the intersection
        if e1.polyType == e2.polyType {
            if isEvenOddFillType(e1) {
                let oldE1WindCnt = e1.windCnt
                e1.windCnt = e2.windCnt
                e2.windCnt = oldE1WindCnt
            } else {
                if e1.windCnt + e2.windDelta == 0 {
                    e1.windCnt = -e1.windCnt
                } else {
                    e1.windCnt += e2.windDelta
                }
                if e2.windCnt - e1.windDelta == 0 {
                    e2.windCnt = -e2.windCnt
                } else {
                    e2.windCnt -= e1.windDelta
                }
            }
        } else {
            if !isEvenOddFillType(e2) {
                e1.windCnt2 += e2.windDelta
            } else {
                e1.windCnt2 = (e1.windCnt2 == 0) ? 1 : 0
            }
            if !isEvenOddFillType(e1) {
                e2.windCnt2 -= e1.windDelta
            } else {
                e2.windCnt2 = (e2.windCnt2 == 0) ? 1 : 0
            }
        }
        
        var e1FillType:PolyFillType, e2FillType: PolyFillType, e1FillType2: PolyFillType, e2FillType2:PolyFillType
        if e1.polyType == .subject {
            e1FillType = subjFillType
            e1FillType2 = clipFillType
        } else {
            e1FillType = clipFillType
            e1FillType2 = subjFillType
        }
        if e2.polyType == .subject {
            e2FillType = subjFillType
            e2FillType2 = clipFillType
        } else {
            e2FillType = clipFillType
            e2FillType2 = subjFillType
        }
        
        var e1Wc: Int, e2Wc: Int
        switch e1FillType
        {
        case .positive: e1Wc = e1.windCnt
        case .negative: e1Wc = -e1.windCnt
        default: e1Wc = abs(e1.windCnt)
        }
        switch e2FillType
        {
        case .positive: e2Wc = e2.windCnt
        case .negative: e2Wc = -e2.windCnt
        default: e2Wc = abs(e2.windCnt)
        }
        
        if e1Contributing && e2Contributing {
            if ((e1Wc != 0 && e1Wc != 1) || (e2Wc != 0 && e2Wc != 1) ||
                (e1.polyType != e2.polyType && clipType != ClipType.xor)) {
                addLocalMaxPoly(e1, e2, pt)
            } else {
                addOutPt(e1, pt)
                addOutPt(e2, pt)
                swapSides(e1, e2)
                swapPolyIndexes(e1, e2)
            }
        } else if e1Contributing {
            if e2Wc == 0 || e2Wc == 1 {
                addOutPt(e1, pt)
                swapSides(e1, e2)
                swapPolyIndexes(e1, e2)
            }
            
        } else if e2Contributing {
            if e1Wc == 0 || e1Wc == 1 {
                addOutPt(e2, pt)
                swapSides(e1, e2)
                swapPolyIndexes(e1, e2)
            }
        } else if (e1Wc == 0 || e1Wc == 1) && (e2Wc == 0 || e2Wc == 1) {
            //neither edge is currently contributing ...
            var e1Wc2: Int, e2Wc2: Int
            switch e1FillType2 {
            case .positive: e1Wc2 = e1.windCnt2
            case .negative: e1Wc2 = -e1.windCnt2
            default: e1Wc2 = abs(e1.windCnt2)
            }
            switch e2FillType2 {
            case .positive: e2Wc2 = e2.windCnt2
            case .negative: e2Wc2 = -e2.windCnt2
            default: e2Wc2 = abs(e2.windCnt2)
            }
            
            if e1.polyType != e2.polyType {
                addLocalMinPoly(e1, e2, pt)
            } else if e1Wc == 1 && e2Wc == 1 {
                switch clipType {
                case .intersection:
                    if e1Wc2 > 0 && e2Wc2 > 0 {
                        addLocalMinPoly(e1, e2, pt)
                    }
                case .union:
                    if e1Wc2 <= 0 && e2Wc2 <= 0 {
                        addLocalMinPoly(e1, e2, pt)
                    }
                case .difference:
                    if (((e1.polyType == .clip) && (e1Wc2 > 0) && (e2Wc2 > 0)) ||
                        ((e1.polyType == .subject) && (e1Wc2 <= 0) && (e2Wc2 <= 0))) {
                        addLocalMinPoly(e1, e2, pt)
                    }
                case .xor:
                    addLocalMinPoly(e1, e2, pt)
                }
            } else {
                swapSides(e1, e2)
            }
        }
    }
    
    private func deleteFromSEL(_ e: TEdge) {
        let selPrev = e.prevInSEL
        let selNext = e.nextInSEL
        if selPrev == nil && selNext == nil && e != sortedEdges {
            return //already deleted
        }
        if selPrev != nil {
            selPrev?.nextInSEL = selNext
        } else {
            sortedEdges = selNext
        }
        if selNext != nil {
            selNext?.prevInSEL = selPrev
        }
        e.nextInSEL = nil
        e.prevInSEL = nil
    }
    
    private func processHorizontals() throws {
        var horzEdge: TEdge? //sortedEdges
        while popEdgeFromSEL(&horzEdge) {
            try processHorizontal(&horzEdge!)
        }
    }
    
    private func getHorzDirection(_ HorzEdge: TEdge, _ dir:inout Direction , _ left:inout CGFloat, _ right:inout CGFloat) {
        if HorzEdge.bot.x < HorzEdge.top.x {
            left = HorzEdge.bot.x
            right = HorzEdge.top.x
            dir = .leftToRight
        } else {
            left = HorzEdge.top.x
            right = HorzEdge.bot.x
            dir = .rightToLeft
        }
    }
    
    ///Notes: Horizontal edges (HEs) at scanline intersections (ie at the Top or
    /// Bottom of a scanbeam) are processed as if layered. The order in which HEs
    /// are processed doesn't matter. HEs intersect with other HE Bot.Xs only [#]
    ///(or they could intersect with Top.Xs only, ie EITHER Bot.Xs OR Top.Xs),
    /// and with other non-horizontal edges [*]. Once these intersections are
    /// processed, intermediate HEs then 'promote' the Edge above (NextInLML) into
    /// the AEL. These 'promoted' edges may in turn intersect [%] with other HEs.
    private func processHorizontal(_ horzEdge:inout TEdge) throws {
        var dir:Direction = .leftToRight
        var horzLeft = CGFloat.zero, horzRight = CGFloat.zero
        let isOpen = horzEdge.windDelta == 0
        
        getHorzDirection(horzEdge, &dir, &horzLeft, &horzRight)
        
        var eLastHorz = horzEdge
        var eMaxPair: TEdge?
        while eLastHorz.nextInLML != nil && eLastHorz.nextInLML!.isHorizontal {
            eLastHorz = eLastHorz.nextInLML!
        }
        if eLastHorz.nextInLML == nil {
            eMaxPair = getMaximaPair(eLastHorz)
        }
        
        var currMax = maxima
        if currMax != nil {
            //get the first maxima in range (x) ...
            if dir == .leftToRight {
                while currMax != nil && currMax!.x <= horzEdge.bot.x {
                    currMax = currMax?.next
                }
                if currMax != nil && currMax!.x >= eLastHorz.top.x {
                    currMax = nil
                }
            } else {
                while currMax?.next != nil && currMax!.next!.x < horzEdge.bot.x {
                    currMax = currMax?.next
                }
                if currMax!.x <= eLastHorz.top.x {
                    currMax = nil
                }
            }
        }
        
        var op1: OutPt?
        while true //loop through consec. horizontal edges
        {
            let IsLastHorz = (horzEdge == eLastHorz)
            var e = getNextInAEL(horzEdge, dir)
            while e != nil {
                
                //this code block inserts extra coords into horizontal edges (in output
                //polygons) whereever maxima touch these horizontal edges. This helps
                //'simplifying' polygons (ie if the Simplify property is set).
                if currMax != nil {
                    if dir == .leftToRight {
                        while currMax != nil && currMax!.x < e!.curr.x {
                            if horzEdge.outIdx >= 0 && !isOpen {
                                addOutPt(horzEdge, CGPoint(x: currMax!.x, y: horzEdge.bot.y))
                            }
                            currMax = currMax?.next
                        }
                    } else {
                        while currMax != nil && currMax!.x > e!.curr.x {
                            if horzEdge.outIdx >= 0 && !isOpen {
                                addOutPt(horzEdge, CGPoint(x :currMax!.x, y: horzEdge.bot.y))
                            }
                            currMax = currMax?.prev
                        }
                    }
                }
                
                if (dir == .leftToRight && e!.curr.x > horzRight) ||
                    (dir == .rightToLeft && e!.curr.x < horzLeft) {
                    break
                }
                
                //Also break if we've got to the end of an intermediate horizontal edge ...
                //nb: Smaller dx's are to the right of larger dx's ABOVE the horizontal.
                if (e!.curr.x == horzEdge.top.x && horzEdge.nextInLML != nil &&
                    e!.dx < horzEdge.nextInLML!.dx)  {
                    break
                }
                
                if horzEdge.outIdx >= 0 && !isOpen { //note: may be done multiple times
                    
                    op1 = addOutPt(horzEdge, e!.curr)
                    var eNextHorz = sortedEdges
                    while eNextHorz != nil {
                        if eNextHorz!.outIdx >= 0 &&
                            horzSegmentsOverlap(horzEdge.bot.x,
                                                horzEdge.top.x, eNextHorz!.bot.x, eNextHorz!.top.x) {
                            let op2 = getLastOutPt(eNextHorz!)
                            addJoin(op2, op1!, eNextHorz!.top)
                        }
                        eNextHorz = eNextHorz!.nextInSEL
                    }
                    addGhostJoin(op1!, horzEdge.bot)
                }
                
                //OK, so far we're still in range of the horizontal Edge  but make sure
                //we're at the last of consec. horizontals when matching with eMaxPair
                if e == eMaxPair && IsLastHorz {
                    if horzEdge.outIdx >= 0 {
                        addLocalMaxPoly(horzEdge, eMaxPair!, horzEdge.top)
                    }
                    deleteFromAEL(horzEdge)
                    deleteFromAEL(eMaxPair!)
                    return
                }
                
                if dir == .leftToRight {
                    let pt = CGPoint(x: e!.curr.x, y: horzEdge.curr.y)
                    intersectEdges(horzEdge, e!, pt)
                } else {
                    let pt = CGPoint(x: e!.curr.x, y: horzEdge.curr.y)
                    intersectEdges(e!, horzEdge, pt)
                }
                let eNext = getNextInAEL(e!, dir)
                swapPositionsInAEL(horzEdge, e!)
                e = eNext
            } //end while(e != nil)
            
            //Break out of loop if HorzEdge.nextInLML is not also horizontal ...
            if horzEdge.nextInLML == nil || !horzEdge.nextInLML!.isHorizontal {
                break
            }
            
            try updateEdgeIntoAEL(&horzEdge)
            if horzEdge.outIdx >= 0 {
                addOutPt(horzEdge, horzEdge.bot)
            }
            getHorzDirection(horzEdge, &dir, &horzLeft, &horzRight)
            
        } //end for ()
        
        if horzEdge.outIdx >= 0 && op1 == nil {
            op1 = getLastOutPt(horzEdge)
            var eNextHorz = sortedEdges
            while eNextHorz != nil {
                if (eNextHorz!.outIdx >= 0 &&
                    horzSegmentsOverlap(horzEdge.bot.x,
                                        horzEdge.top.x, eNextHorz!.bot.x, eNextHorz!.top.x))
                {
                    let op2 = getLastOutPt(eNextHorz!)
                    addJoin(op2, op1!, eNextHorz!.top)
                }
                eNextHorz = eNextHorz?.nextInSEL
            }
            addGhostJoin(op1!, horzEdge.top)
        }
        
        if horzEdge.nextInLML != nil {
            if horzEdge.outIdx >= 0 {
                op1 = addOutPt( horzEdge, horzEdge.top)
                
                try updateEdgeIntoAEL(&horzEdge)
                if horzEdge.windDelta == 0 {
                    return
                }
                
                //nb: HorzEdge is no longer horizontal here
                let ePrev = horzEdge.prevInAEL
                let eNext = horzEdge.nextInAEL
                if (ePrev != nil && ePrev!.curr.x == horzEdge.bot.x &&
                    ePrev!.curr.y == horzEdge.bot.y && ePrev!.windDelta != 0 &&
                    (ePrev!.outIdx >= 0 && ePrev!.curr.y > ePrev!.top.y &&
                        horzEdge.isSlopesEqual(with: ePrev!)))
                {
                    let op2 = addOutPt(ePrev!, horzEdge.bot)
                    addJoin(op1!, op2, horzEdge.top)
                }
                else if (eNext != nil && eNext!.curr.x == horzEdge.bot.x &&
                    eNext!.curr.y == horzEdge.bot.y && eNext!.windDelta != 0 &&
                    eNext!.outIdx >= 0 && eNext!.curr.y > eNext!.top.y &&
                    horzEdge.isSlopesEqual(with: eNext!))
                {
                    let op2 = addOutPt(eNext!, horzEdge.bot)
                    addJoin(op1!, op2, horzEdge.top)
                }
            } else {
                try updateEdgeIntoAEL(&horzEdge)
            }
        } else {
            if horzEdge.outIdx >= 0 {
                addOutPt(horzEdge, horzEdge.top)
            }
            deleteFromAEL(horzEdge)
        }
    }
    
    private func getNextInAEL(_ e: TEdge, _ direction: Direction) -> TEdge? {
        return direction == .leftToRight ? e.nextInAEL: e.prevInAEL
    }
    
    private func isMinima(_ e: TEdge?) -> Bool {
        return e != nil && (e!.prev.nextInLML != e) && (e?.next.nextInLML != e)
    }
    
    private func isMaxima(_ e: TEdge?, _ y: CGFloat) -> Bool {
        return (e != nil && e!.top.y == y && e?.nextInLML == nil)
    }
    
    private func isIntermediate(_ e: TEdge, _ y: CGFloat) -> Bool {
        return (e.top.y == y && e.nextInLML != nil)
    }
    
    private func getMaximaPair(_ e: TEdge) -> TEdge? {
        if e.next.top == e.top && e.next.nextInLML == nil {
            return e.next
        } else if e.prev.top == e.top && e.prev.nextInLML == nil {
            return e.prev
        }
        return nil
    }
    
    private func getMaximaPairEx(_ e: TEdge) -> TEdge? {
        //as above but returns nil if MaxPair isn't in AEL (unless it's horizontal)
        let result = getMaximaPair(e)
        if result == nil || result?.outIdx == Skip ||
            (result!.nextInAEL == result!.prevInAEL && !result!.isHorizontal) {
            return nil
        }
        return result
    }
    
    private func processIntersections(_ topY: CGFloat) -> Bool {
        if activeEdges == nil {
            return true
        }
        buildIntersectList(topY)
        if intersectList.count == 0 {
            return true
        }
        if intersectList.count == 1 || fixUpIntersectionOrder() {
            processIntersectList()
        } else {
            return false
        }
        
        sortedEdges = nil
        return true
    }
    
    private func buildIntersectList(_ topY: CGFloat) {
        if activeEdges == nil {
            return
        }
        
        //prepare for sorting ...
        var e = activeEdges
        sortedEdges = e

        while e != nil {
            e?.prevInSEL = e?.prevInAEL
            e?.nextInSEL = e?.nextInAEL
            e?.curr.x = e!.topX(of: topY)
            e = e?.nextInAEL
        }
        
        //bubblesort ...
        var isModified = true
        repeat {
            isModified = false
            e = sortedEdges
            while e?.nextInSEL != nil {
                let eNext: TEdge = e!.nextInSEL!
                var pt: CGPoint
                if e!.curr.x > eNext.curr.x {
                    pt = e!.intersect(with: eNext)
                    if pt.y < topY {
                        pt = CGPoint(x: e!.topX(of: topY), y: topY)
                    }
                    let newNode = IntersectNode(edge1: e!, edge2:eNext)
                    newNode.pt = pt
                    intersectList.append(newNode)
                    
                    swapPositionsInSEL(e!, eNext)
                    isModified = true
                } else {
                    e = eNext
                }
            }
            if e?.prevInSEL != nil {
                e?.prevInSEL?.nextInSEL = nil
            } else {
                break
            }
        } while isModified
        sortedEdges = nil
    }
    
    private func edgesAdjacent(_ inode: IntersectNode) -> Bool {
        return (inode.edge1.nextInSEL == inode.edge2) ||
            (inode.edge1.prevInSEL == inode.edge2)
    }
    
    private func IntersectNodeSort(_ node1: IntersectNode, _ node2: IntersectNode) -> CGFloat {
        //the following typecast is safe because the differences in pt.y will
        //be limited to the height of the scanbeam.
        return node2.pt.y - node1.pt.y
    }
    
    private func fixUpIntersectionOrder() -> Bool {
        //pre-condition: intersections are sorted bottom-most first.
        //Now it's crucial that intersections are made only between adjacent edges,
        //so to ensure this the order of intersections may need adjusting ...
        intersectList.sort { (node1, node2) -> Bool in
            let i = node2.pt.y - node1.pt.y;
            if i > 0 {
                return true
            } else if i < 0 {
                return false
            } else {
                return false
            }
        }
        
        copyAELToSEL()
        let cnt = intersectList.count
        for i in 0..<cnt {
            if !edgesAdjacent(intersectList[i]) {
                var j = i + 1
                while j < cnt && !edgesAdjacent(intersectList[j]) {
                    j += 1
                }
                if j == cnt {
                    return false
                }
                
                let tmp = intersectList[i]
                intersectList[i] = intersectList[j]
                intersectList[j] = tmp
                
            }
            swapPositionsInSEL(intersectList[i].edge1, intersectList[i].edge2)
        }
        return true
    }
    
    private func processIntersectList() {
        for iNode in intersectList {
            intersectEdges(iNode.edge1, iNode.edge2, iNode.pt)
            swapPositionsInAEL(iNode.edge1, iNode.edge2)
        }
        intersectList.removeAll()
    }
    
    private func processEdgesAtTopOfScanbeam(_ topY: CGFloat) throws {
        var e = activeEdges
        while e != nil {
            //1. process maxima, treating them as if they're 'bent' horizontal edges,
            //   but exclude maxima with horizontal edges. nb: e can't be a horizontal.
            var isMaximaEdge = isMaxima(e, topY)
            
            if isMaximaEdge {
                let eMaxPair = getMaximaPairEx(e!)
                isMaximaEdge = (eMaxPair == nil || !eMaxPair!.isHorizontal)
            }
            
            if isMaximaEdge {
                if strictlySimple {
                    insertMaxima(e!.top.x)
                }
                let ePrev = e!.prevInAEL
                try doMaxima(e!)
                if ePrev == nil {
                    e = activeEdges
                } else {
                    e = ePrev?.nextInAEL
                }
            } else {
                //2. promote horizontal edges, otherwise update curr.x and curr.y ...
                if isIntermediate(e!, topY) && e!.nextInLML!.isHorizontal {
                    try updateEdgeIntoAEL(&e!)
                    if e!.outIdx >= 0 {
                        addOutPt(e!, e!.bot)
                    }
                    addEdgeToSEL(e!)
                } else {
                    e?.curr.x = e!.topX(of: topY )
                    e?.curr.y = topY
                }
                //When strictlySimple and 'e' is being touched by another edge, then
                //make sure both edges have a vertex here ...
                if strictlySimple {
                    let ePrev = e!.prevInAEL
                    if ((e!.outIdx >= 0) && (e!.windDelta != 0) && ePrev != nil &&
                        (ePrev!.outIdx >= 0) && (ePrev!.curr.x == e!.curr.x) &&
                        (ePrev!.windDelta != 0))
                    {
                        let ip = e!.curr
                        let op = addOutPt(ePrev!, ip)
                        let op2 = addOutPt(e!, ip)
                        addJoin(op, op2, ip) //strictlySimple (type-3) join
                    }
                }
                
                e = e?.nextInAEL
            }
        }
        
        //3. Process horizontals at the.top of the scanbeam ...
        try processHorizontals()
        maxima = nil
        
        //4. Promote intermediate vertices ...
        e = activeEdges
        while e != nil {
            if isIntermediate(e!, topY) {
                var op: OutPt?
                if e!.outIdx >= 0 {
                    op = addOutPt(e!, e!.top)
                }
                try updateEdgeIntoAEL(&e!)
                
                //if output polygons share an edge, they'll need joining later ...
                let ePrev = e?.prevInAEL
                let eNext = e?.nextInAEL
                if (ePrev != nil && ePrev!.curr.x == e!.bot.x &&
                    ePrev!.curr.y == e!.bot.y && op != nil &&
                    ePrev!.outIdx >= 0 && ePrev!.curr.y > ePrev!.top.y &&
                    ePrev!.curr.isSlopesEqual(e!.curr, e!.top, ePrev!.top) &&
                    (e!.windDelta != 0) && (ePrev!.windDelta != 0))
                {
                    let op2 = addOutPt(ePrev!, e!.bot)
                    addJoin(op!, op2, e!.top)
                } else if (eNext != nil && eNext!.curr.x == e!.bot.x &&
                    eNext!.curr.y == e!.bot.y && op != nil &&
                    eNext!.outIdx >= 0 && eNext!.curr.y > eNext!.top.y &&
                    eNext!.curr.isSlopesEqual(e!.curr, e!.top, eNext!.top) &&
                    (e!.windDelta != 0) && (eNext!.windDelta != 0))
                {
                    let op2 = addOutPt(eNext!, e!.bot)
                    addJoin(op!, op2, e!.top)
                }
            }
            e = e?.nextInAEL
        }
    }
    
    private func doMaxima(_ e: TEdge) throws {
        guard let eMaxPair = getMaximaPairEx(e) else {
            if e.outIdx >= 0 {
                addOutPt(e, e.top)
            }
            deleteFromAEL(e)
            return
        }
        
        var eNext = e.nextInAEL
        while eNext != nil && eNext != eMaxPair {
            intersectEdges(e, eNext!, e.top)
            swapPositionsInAEL(e, eNext!)
            eNext = e.nextInAEL
        }
        
        if(e.outIdx == Unassigned && eMaxPair.outIdx == Unassigned) {
            deleteFromAEL(e)
            deleteFromAEL(eMaxPair)
        } else if( e.outIdx >= 0 && eMaxPair.outIdx >= 0 ) {
            if e.outIdx >= 0 {
                addLocalMaxPoly(e, eMaxPair, e.top)
            }
            deleteFromAEL(e)
            deleteFromAEL(eMaxPair)
        } else {
            throw ClipperError(message: "doMaxima error")
        }
    }
    
    private func pointCount(_ pts: OutPt?) -> Int {
        if pts == nil {
            return 0
        }
        var result = 0
        var p = pts
        repeat {
            result += 1
            p = p?.next
        } while p != pts
        return result
    }
    
    private func buildResult(_ polyg:inout Paths) {
        for i in polyOuts.indices {
            let outRec = polyOuts[i]
            if outRec.pts == nil {
                continue
            }
            var p:OutPt = outRec.pts.prev
            let cnt = pointCount(p)
            if cnt < 2 {
                continue
            }
            var pg = Path()
            for _ in 0..<cnt {
                pg.append(p.pt)
                p = p.prev
            }
            polyg.append(pg)
        }
    }
    
    private func buildResult2(_ polytree: PolyTree) {
        polytree.clear()
        //add each output polygon/contour to polytree ...
        for i in polyOuts.indices {
            let outRec = polyOuts[i]
            let cnt = pointCount(outRec.pts)
            if (outRec.isOpen && cnt < 2) ||
                (!outRec.isOpen && cnt < 3) {
                continue
            }
            fixHoleLinkage(outRec)
            let pn = PolyNode()
            polytree.allPolys.append(pn)
            outRec.polyNode = pn
            var op = outRec.pts.prev
            for _ in 0..<cnt {
                pn.polygon.append(op!.pt)
                op = op?.prev
            }
        }
        
        //fixup PolyNode links etc ...
        for i in polyOuts.indices {
            let outRec = polyOuts[i]
            if outRec.polyNode == nil {
                continue
            } else if outRec.isOpen {
                outRec.polyNode?.isOpen = true
                polytree.addChild(outRec.polyNode!)
            } else if outRec.firstLeft != nil && outRec.firstLeft?.polyNode != nil {
                outRec.firstLeft?.polyNode?.addChild(outRec.polyNode!)
            } else {
                polytree.addChild(outRec.polyNode!)
            }
        }
    }
    
    private func fixUpOutPolyline(_ outrec: OutRec) {
        var pp: OutPt! = outrec.pts
        var lastPP: OutPt! = pp.prev
        while pp != lastPP {
            pp = pp.next
            if pp.pt == pp.prev.pt {
                if pp == lastPP {
                    lastPP = pp.prev
                }
                let tmpPP = pp.prev
                tmpPP?.next = pp.next
                pp.next.prev = tmpPP
                pp = tmpPP
            }
        }
        if pp == pp.prev {
            outrec.pts = nil
        }
    }
    
    private func fixUpOutPolygon(_ outRec: OutRec) {
        //fixUpOutPolygon() - removes duplicate points and simplifies consecutive
        //parallel edges by removing the middle vertex.
        var lastOK: OutPt?
        outRec.bottomPt = nil
        var pp: OutPt = outRec.pts
        let preserveCol = preserveCollinear || strictlySimple
        while true {
            if pp.prev == pp || pp.prev == pp.next {
                outRec.pts = nil
                return
            }
            //test for duplicate points and collinear edges ...
            if ((pp.pt == pp.next.pt) || (pp.pt == pp.prev.pt) ||
                (pp.pt.isSlopesEqual(pp.prev.pt, pp.next.pt) &&
                    (!preserveCol || !pp.pt.isBetween(pp.prev.pt, pp.next.pt)))) {
                lastOK = nil
                pp.prev.next = pp.next
                pp.next.prev = pp.prev
                pp = pp.prev
            }
            else if pp == lastOK {
                break
            } else {
                if lastOK == nil {
                    lastOK = pp
                }
                pp = pp.next
            }
        }
        outRec.pts = pp
    }
    
    private func dupOutPt(_ outPt: OutPt, _ insertAfter: Bool) -> OutPt {
        let result = OutPt()
        result.pt = outPt.pt
        result.index = outPt.index
        if insertAfter {
            result.next = outPt.next
            result.prev = outPt
            outPt.next.prev = result
            outPt.next = result
        } else {
            result.prev = outPt.prev
            result.next = outPt
            outPt.prev.next = result
            outPt.prev = result
        }
        return result
    }
    
    private func getOverlap(_ a1: CGFloat, _ a2: CGFloat, _ b1: CGFloat, _ b2: CGFloat, _ left:inout CGFloat, _ right:inout CGFloat) -> Bool {
        if a1 < a2 {
            if b1 < b2 {left = max(a1,b1); right = min(a2,b2)}
            else {left = max(a1,b2); right = min(a2,b1)}
        } else {
            if b1 < b2 {left = max(a2,b1); right = min(a1,b2)}
            else { left = max(a2, b2); right = min(a1, b1) }
        }
        return left < right
    }
    
    private func JoinHorz(_ op1:inout OutPt, _ op1b:inout OutPt, _ op2:inout OutPt, _ op2b:inout OutPt,
                  _ pt: CGPoint, _ discardLeft: Bool) -> Bool {
        let dir1 = (op1.pt.x > op1b.pt.x ?
            Direction.rightToLeft : .leftToRight)
        let dir2 = (op2.pt.x > op2b.pt.x ?
            Direction.rightToLeft : .leftToRight)
        if dir1 == dir2 {
            return false
        }
        
        //When discardLeft, we want Op1b to be on the left of op1, otherwise we
        //want Op1b to be on the right. (And likewise with op2 and Op2b.)
        //So, to facilitate this while inserting Op1b and Op2b ...
        //when discardLeft, make sure we're AT or RIGHT of pt before adding Op1b,
        //otherwise make sure we're AT or LEFT of pt. (Likewise with Op2b.)
        if dir1 == .leftToRight {
            while op1.next.pt.x <= pt.x && op1.next.pt.x >= op1.pt.x && op1.next.pt.y == pt.y {
                op1 = op1.next
            }
            if discardLeft && op1.pt.x != pt.x {
                op1 = op1.next
            }
            op1b = dupOutPt(op1, !discardLeft)
            if op1b.pt != pt {
                op1 = op1b
                op1.pt = pt
                op1b = dupOutPt(op1, !discardLeft)
            }
        } else {
            while op1.next.pt.x >= pt.x && op1.next.pt.x <= op1.pt.x && op1.next.pt.y == pt.y {
                op1 = op1.next
            }
            if !discardLeft && (op1.pt.x != pt.x) {
                op1 = op1.next
            }
            op1b = dupOutPt(op1, discardLeft)
            if op1b.pt != pt {
                op1 = op1b
                op1.pt = pt
                op1b = dupOutPt(op1, discardLeft)
            }
        }
        
        if dir2 == .leftToRight {
            while op2.next.pt.x <= pt.x && op2.next.pt.x >= op2.pt.x && op2.next.pt.y == pt.y {
                op2 = op2.next
            }
            if discardLeft && (op2.pt.x != pt.x) {
                op2 = op2.next
            }
            op2b = dupOutPt(op2, !discardLeft)
            if op2b.pt != pt {
                op2 = op2b
                op2.pt = pt
                op2b = dupOutPt(op2, !discardLeft)
            }
        } else {
            while op2.next.pt.x >= pt.x && op2.next.pt.x <= op2.pt.x && op2.next.pt.y == pt.y {
                op2 = op2.next
            }
            if !discardLeft && op2.pt.x != pt.x {
                op2 = op2.next
            }
            op2b = dupOutPt(op2, discardLeft)
            if op2b.pt != pt {
                op2 = op2b
                op2.pt = pt
                op2b = dupOutPt(op2, discardLeft)
            }
        }
        
        if (dir1 == .leftToRight) == discardLeft {
            op1.prev = op2
            op2.next = op1
            op1b.next = op2b
            op2b.prev = op1b
        } else {
            op1.next = op2
            op2.prev = op1
            op1b.prev = op2b
            op2b.next = op1b
        }
        return true
    }
    
    private func joinPoints(_ j: Join, _ outRec1: OutRec, _ outRec2: OutRec) -> Bool {
        var op1 = j.outPt1, op1b: OutPt
        var op2 = j.outPt2, op2b: OutPt
        
        //There are 3 kinds of joins for output polygons ...
        //1. Horizontal joins where Join.outPt1 & Join.outPt2 are vertices anywhere
        //along (horizontal) collinear edges (& Join.offPt is on the same horizontal).
        //2. Non-horizontal joins where Join.outPt1 & Join.outPt2 are at the same
        //location at the Bottom of the overlapping segment (& Join.offPt is above).
        //3. strictlySimple joins where edges touch but are not collinear and where
        //Join.outPt1, Join.outPt2 & Join.offPt all share the same point.
        let isHorizontal = (j.outPt1.pt.y == j.offPt.y)
        
        if isHorizontal && (j.offPt == j.outPt1.pt) && (j.offPt == j.outPt2.pt) {
            //Strictly Simple join ...
            if outRec1 != outRec2 {
                return false
            }
            op1b = j.outPt1.next
            while op1b != op1 && op1b.pt == j.offPt {
                op1b = op1b.next
            }
            let reverse1 = (op1b.pt.y > j.offPt.y)
            op2b = j.outPt2.next
            while op2b != op2 && op2b.pt == j.offPt {
                op2b = op2b.next
            }
            let reverse2 = (op2b.pt.y > j.offPt.y)
            if reverse1 == reverse2 {
                return false
            }
            if reverse1 {
                op1b = dupOutPt(op1, false)
                op2b = dupOutPt(op2, true)
                op1.prev = op2
                op2.next = op1
                op1b.next = op2b
                op2b.prev = op1b
                j.outPt1 = op1
                j.outPt2 = op1b
                return true
            } else {
                op1b = dupOutPt(op1, true)
                op2b = dupOutPt(op2, false)
                op1.next = op2
                op2.prev = op1
                op1b.prev = op2b
                op2b.next = op1b
                j.outPt1 = op1
                j.outPt2 = op1b
                return true
            }
        } else if isHorizontal {
            //treat horizontal joins differently to non-horizontal joins since with
            //them we're not yet sure where the overlapping is. outPt1.pt & outPt2.pt
            //may be anywhere along the horizontal edge.
            op1b = op1
            while op1.prev.pt.y == op1.pt.y && op1.prev != op1b && op1.prev != op2 {
                op1 = op1.prev
            }
            while op1b.next.pt.y == op1b.pt.y && op1b.next != op1 && op1b.next != op2 {
                op1b = op1b.next
            }
            if op1b.next == op1 || op1b.next == op2 {
                return false //a flat 'polygon'
            }
            
            op2b = op2
            while op2.prev.pt.y == op2.pt.y && op2.prev != op2b && op2.prev != op1b {
                op2 = op2.prev
            }
            while op2b.next.pt.y == op2b.pt.y && op2b.next != op2 && op2b.next != op1 {
                op2b = op2b.next
            }
            if op2b.next == op2 || op2b.next == op1 {
                return false //a flat 'polygon'
            }
            
            var left = CGFloat.zero
            var right = CGFloat.zero
            //op1 -. Op1b & op2 -. Op2b are the extremites of the horizontal edges
            if !getOverlap(op1.pt.x, op1b.pt.x, op2.pt.x, op2b.pt.x, &left, &right) {
                return false
            }
            
            //DiscardLeftSide: when overlapping edges are joined, a spike will created
            //which needs to be cleaned up. However, we don't want op1 or op2 caught up
            //on the discard side as either may still be needed for other joins ...
            var pt = CGPoint.zero
            var DiscardLeftSide =  false
            if op1.pt.x >= left && op1.pt.x <= right {
                pt = op1.pt
                DiscardLeftSide = (op1.pt.x > op1b.pt.x)
            } else if op2.pt.x >= left && op2.pt.x <= right {
                pt = op2.pt
                DiscardLeftSide = (op2.pt.x > op2b.pt.x)
            } else if op1b.pt.x >= left && op1b.pt.x <= right {
                pt = op1b.pt
                DiscardLeftSide = op1b.pt.x > op1.pt.x
            } else  {
                pt = op2b.pt
                DiscardLeftSide = (op2b.pt.x > op2.pt.x)
            }
            j.outPt1 = op1
            j.outPt2 = op2
            return JoinHorz(&op1, &op1b, &op2, &op2b, pt, DiscardLeftSide)
        } else {
            //nb: For non-horizontal joins ...
            //    1. Jr.outPt1.pt.y == Jr.outPt2.pt.y
            //    2. Jr.outPt1.pt > Jr.offPt.y
            
            //make sure the polygons are correctly oriented ...
            op1b = op1.next
            while op1b.pt == op1.pt && op1b != op1 {
                op1b = op1b.next
            }
            let Reverse1 = ((op1b.pt.y > op1.pt.y) || !op1b.pt.isSlopesEqual(op1.pt, j.offPt))
            if Reverse1 {
                op1b = op1.prev
                while op1b.pt == op1.pt && op1b != op1 {
                    op1b = op1b.prev
                }
                if op1b.pt.y > op1.pt.y || !op1b.pt.isSlopesEqual(op1.pt, j.offPt) {
                    return false
                }
            }
            op2b = op2.next
            while op2b.pt == op2.pt && op2b != op2 {
                op2b = op2b.next
            }
            let Reverse2 = ((op2b.pt.y > op2.pt.y) || !op2b.pt.isSlopesEqual(op2.pt, j.offPt))
            if Reverse2 {
                op2b = op2.prev
                while op2b.pt == op2.pt && op2b != op2 {
                    op2b = op2b.prev
                }
                if op2b.pt.y > op2.pt.y || !op2b.pt.isSlopesEqual(op2.pt, j.offPt) {
                    return false
                }
            }
            
            if op1b == op1 || op2b == op2 || op1b == op2b ||
                ((outRec1 == outRec2) && (Reverse1 == Reverse2)) {
                return false
            }
            
            if Reverse1 {
                op1b = dupOutPt(op1, false)
                op2b = dupOutPt(op2, true)
                op1.prev = op2
                op2.next = op1
                op1b.next = op2b
                op2b.prev = op1b
                j.outPt1 = op1
                j.outPt2 = op1b
                return true
            } else {
                op1b = dupOutPt(op1, true)
                op2b = dupOutPt(op2, false)
                op1.next = op2
                op2.prev = op1
                op1b.prev = op2b
                op2b.next = op1b
                j.outPt1 = op1
                j.outPt2 = op1b
                return true
            }
        }
    }
    
    
    
    private func fixupFirstLefts1(_ OldOutRec: OutRec, _ NewOutRec: OutRec) {
        for outRec in polyOuts {
            let firstLeft = parseFirstLeft(outRec.firstLeft)
            if outRec.pts != nil && firstLeft == OldOutRec {
                if NewOutRec.pts.contains(polygon: outRec.pts) {
                    outRec.firstLeft = NewOutRec
                }
            }
        }
    }
    
    private func fixupFirstLefts2(_ innerOutRec: OutRec, _ outerOutRec: OutRec) {
        //A polygon has split into two such that one is now the inner of the other.
        //It's possible that these polygons now wrap around other polygons, so check
        //every polygon that's also contained by OuterOutRec's firstLeft container
        //(including nil) to see if they've become inner to the inner polygon ...
        let orfl = outerOutRec.firstLeft
        for outRec in polyOuts {
            if outRec.pts == nil || outRec == outerOutRec || outRec == innerOutRec {
                continue
            }
            let firstLeft = parseFirstLeft(outRec.firstLeft)
            if firstLeft != orfl && firstLeft != innerOutRec && firstLeft != outerOutRec {
                continue
            }
            if innerOutRec.pts.contains(polygon: outRec.pts) {
                outRec.firstLeft = innerOutRec
            } else if outerOutRec.pts.contains(polygon: outRec.pts) {
                outRec.firstLeft = outerOutRec
            }  else if outRec.firstLeft == innerOutRec || outRec.firstLeft == outerOutRec {
                outRec.firstLeft = orfl
            }
        }
    }
    
    private func fixupFirstLefts3(_ OldOutRec: OutRec, _ NewOutRec: OutRec) {
        //same as fixupFirstLefts1 but doesn't call Poly2ContainsPoly1()
        for outRec in polyOuts {
            let firstLeft = parseFirstLeft(outRec.firstLeft)
            if outRec.pts != nil && firstLeft == OldOutRec {
                outRec.firstLeft = NewOutRec
            }
        }
    }
    
    private func parseFirstLeft(_ firstLeft:OutRec?) -> OutRec {
        var firstLeft = firstLeft
        while firstLeft != nil && firstLeft?.pts == nil {
            firstLeft = firstLeft?.firstLeft;
        }
        return firstLeft!
    }
    
    private func getOutRec(_ idx: Int) -> OutRec {
        var outrec = polyOuts[idx]
        while outrec != polyOuts[outrec.index] {
            outrec = polyOuts[outrec.index]
        }
        return outrec
    }
    
    
    private func joinCommonEdges() {
        for i in joins.indices {
            let join = joins[i]
            
            let outRec1: OutRec! = getOutRec(join.outPt1.index)
            var outRec2: OutRec! = getOutRec(join.outPt2.index)
            
            if outRec1.pts == nil || outRec2.pts == nil {
                continue
            }
            if outRec1.isOpen || outRec2.isOpen {
                continue
            }
            
            //get the polygon fragment with the correct hole state (firstLeft)
            //before calling joinPoints() ...
            var holeStateRec: OutRec
            if outRec1 == outRec2 {
                holeStateRec = outRec1
            } else if outRec1RightOfOutRec2(outRec1, outRec2)  {
                holeStateRec = outRec2
            } else if outRec1RightOfOutRec2(outRec2, outRec1) {
                holeStateRec = outRec1
            } else {
                holeStateRec = getLowerMostRec(outRec1, outRec2)
            }
            
            if !joinPoints(join, outRec1, outRec2){
                continue
            }
            
            if outRec1 == outRec2 {
                //instead of joining two polygons, we've just created a one by
                //splitting one polygon into two.
                outRec1.pts = join.outPt1
                outRec1.bottomPt = nil
                outRec2 = createOutRec()
                outRec2.pts = join.outPt2
                
                //update all OutRec2.pts index's ...
                updateOutPtIdxs(outRec2)
                
                if outRec1.pts.contains(polygon: outRec2.pts) {
                    //outRec1 contains outRec2 ...
                    outRec2.isHole = !outRec1.isHole
                    outRec2.firstLeft = outRec1
                    
                    if usingPolyTree {
                        fixupFirstLefts2(outRec2, outRec1)
                    }
                    
                    if (outRec2.isHole ^ reverseSolution) == (outRec2.area > 0) {
                        outRec2.pts.reverse()
                    }
                    
                } else if outRec2.pts.contains(polygon: outRec1.pts) {
                    //outRec2 contains outRec1 ...
                    outRec2.isHole = outRec1.isHole
                    outRec1.isHole = !outRec2.isHole
                    outRec2.firstLeft = outRec1.firstLeft
                    outRec1.firstLeft = outRec2
                    
                    if usingPolyTree {
                        fixupFirstLefts2(outRec1, outRec2)
                    }
                    
                    if (outRec1.isHole ^ reverseSolution) == (outRec1.area > 0) {
                        outRec1.pts.reverse()
                    }
                } else {
                    //the 2 polygons are completely separate ...
                    outRec2.isHole = outRec1.isHole
                    outRec2.firstLeft = outRec1.firstLeft
                    
                    //fixup firstLeft pointers that may need reassigning to OutRec2
                    if usingPolyTree {
                        fixupFirstLefts1(outRec1, outRec2)
                    }
                }
                
            } else {
                //joined 2 polygons together ...
                
                outRec2.pts = nil
                outRec2.bottomPt = nil
                outRec2.index = outRec1.index
                
                outRec1.isHole = holeStateRec.isHole
                if holeStateRec == outRec2 {
                    outRec1.firstLeft = outRec2.firstLeft
                }
                outRec2.firstLeft = outRec1
                
                //fixup firstLeft pointers that may need reassigning to OutRec1
                if usingPolyTree {
                    fixupFirstLefts3(outRec2, outRec1)
                }
            }
        }
    }
    
    private func updateOutPtIdxs(_ outrec: OutRec) {
        var op = outrec.pts
        repeat {
            op?.index = outrec.index
            op = op?.prev
        } while op != outrec.pts
    }
    
    private func doSimplePolygons() {
        var i = 0
        while i < polyOuts.count {
            let outrec = polyOuts[i]
            i += 1
            var op: OutPt! = outrec.pts
            if op == nil || outrec.isOpen {
                continue
            }
            repeat  {//for each pt in Polygon until duplicate found do ...
                
                var op2:OutPt = op!.next
                while op2 != outrec.pts {
                    if op.pt == op2.pt && op2.next != op && op2.prev != op {
                        //split the polygon into two ...
                        let op3: OutPt  = op.prev
                        let op4: OutPt = op2.prev
                        op.prev = op4
                        op4.next = op
                        op2.prev = op3
                        op3.next = op2
                        
                        outrec.pts = op
                        let outrec2 = createOutRec()
                        outrec2.pts = op2
                        updateOutPtIdxs(outrec2)
                        if outrec.pts.contains(polygon: outrec2.pts){
                            //OutRec2 is contained by OutRec1 ...
                            outrec2.isHole = !outrec.isHole
                            outrec2.firstLeft = outrec
                            if usingPolyTree {
                                fixupFirstLefts2(outrec2, outrec)
                            }
                        } else if outrec2.pts.contains(polygon: outrec.pts) {
                            //OutRec1 is contained by OutRec2 ...
                            outrec2.isHole = outrec.isHole
                            outrec.isHole = !outrec2.isHole
                            outrec2.firstLeft = outrec.firstLeft
                            outrec.firstLeft = outrec2
                            if usingPolyTree {
                                fixupFirstLefts2(outrec, outrec2)
                            }
                        } else {
                            //the 2 polygons are separate ...
                            outrec2.isHole = outrec.isHole
                            outrec2.firstLeft = outrec.firstLeft
                            if usingPolyTree {
                                fixupFirstLefts1(outrec, outrec2)
                            }
                        }
                        op2 = op //ie get ready for the next iteration
                    }
                    op2 = op2.next
                }
                op = op.next
            } while op != outrec.pts
        }
    }
    
    
}

extension Bool {
    fileprivate static func ^(lhs: Bool, rhs: Bool) -> Bool {
        return lhs != rhs
    }
}
