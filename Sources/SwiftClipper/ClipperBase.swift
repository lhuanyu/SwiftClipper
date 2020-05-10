//
//  ClipperBase.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/2.
//

import Foundation
import CoreGraphics

public class ClipperBase {
    
    public struct ClipperError: Error {
        let message: String
    }
    
    class IntersectNode {
        var edge1: TEdge
        var edge2: TEdge
        var pt: CGPoint = .zero
        
        init(edge1: TEdge, edge2:TEdge) {
            self.edge1 = edge1
            self.edge2 = edge2
        }
    }

    class LocalMinima {
        var y: CGFloat = 0
        var leftBound: TEdge!
        var rightBound: TEdge!
        var next: LocalMinima!
    }

    class Scanbeam {
        var y: CGFloat = 0
        var next: Scanbeam?
    }

    class Maxima {
        var x: CGFloat = 0
        var next: Maxima?
        var prev: Maxima?
    }
    
    class Join {
        var outPt1: OutPt
        var outPt2: OutPt
        var offPt: CGPoint = .zero
        
        init(op1: OutPt, op2: OutPt) {
            self.outPt1 = op1
            self.outPt2 = op2
        }
    }
    
    var minimaList: LocalMinima?
    var currentLM: LocalMinima?
    var edges =  [[TEdge]]()
    var scanbeam: Scanbeam?
    var polyOuts = [OutRec]()
    var activeEdges: TEdge?
    var useFullRange = false
    var hasOpenPaths = false
    var preserveCollinear = false
    
    public func clear() {
        disposeLocalMinimaList()
        for i in edges.indices {
            edges[i].removeAll()
        }
        edges.removeAll()
        useFullRange = false
        hasOpenPaths = false
    }
    
    deinit {
//        print("Clipper deinit.")
    }
    
    
    private func disposeLocalMinimaList() {
        while minimaList != nil {
            let tmpLm = minimaList?.next
            minimaList = nil
            minimaList = tmpLm
        }
        currentLM = nil
    }
    
    func processBound(_ e:TEdge, _ leftBoundIsForward: Bool) -> TEdge {
        var e = e
        var eStart = e
        var result = e
        var horz: TEdge
        
        if result.outIdx == Skip {
            //check if there are edges beyond the skip edge in the bound and if so
            //create another LocMin and calling ProcessBound once more ...
            e = result
            if leftBoundIsForward {
                while e.top.y == e.next.bot.y {
                    e = e.next
                }
                while e !== result && e.dx == Horizontal {
                    e = e.prev
                }
            } else {
                while e.top.y == e.prev.bot.y {
                    e = e.prev
                }
                while e !== result && e.dx == Horizontal {
                    e = e.next
                }
            }
            
            if e == result {
                if leftBoundIsForward {
                    result = e.next
                } else {
                    result = e.prev
                }
            } else {
                //there are more edges in the bound beyond result starting with e
                if leftBoundIsForward {
                    e = result.next
                }else {
                    e = result.prev
                }
                let locMin = LocalMinima()
                locMin.next = nil
                locMin.y = e.bot.y
                locMin.leftBound = nil
                locMin.rightBound = e
                e.windDelta = 0
                result = processBound(e, leftBoundIsForward)
                insertLocalMinima(locMin)
            }
            return result
        }
        
        if e.dx == Horizontal {
            //We need to be careful with open paths because this may not be a
            //true local minima (ie e may be following a skip edge).
            //Also, consecutive horz. edges may start heading left before going right.
            if leftBoundIsForward {
                eStart = e.prev
            } else {
                eStart = e.next
            }
            if eStart.dx == Horizontal { //ie an adjoining Horizontal skip edge
                if eStart.bot.x != e.bot.x && eStart.top.x != e.bot.x {
                    e.reverseHorizontal()
                }
            } else if eStart.bot.x != e.bot.x {
                e.reverseHorizontal()
            }
        }
        
        eStart = e
        if leftBoundIsForward {
            while result.top.y == result.next.bot.y && result.next.outIdx != Skip {
                result = result.next
            }
            if result.dx == Horizontal && result.next.outIdx != Skip {
                //nb: at the top of a bound, Horizontals are added to the bound
                //only when the preceding edge attaches to the Horizontal's left vertex
                //unless a Skip edge is encountered when that becomes the top divide
                horz = result
                while horz.prev.dx == Horizontal {
                    horz = horz.prev
                }
                if horz.prev.top.x > result.next.top.x {
                    result = horz.prev
                }
            }
            while e !== result {
                e.nextInLML = e.next
                if e.dx == Horizontal && e !== eStart && e.bot.x != e.prev.top.x {
                    e.reverseHorizontal()
                }
                e = e.next
            }
            if e.dx == Horizontal && e !== eStart && e.bot.x != e.prev.top.x {
                e.reverseHorizontal()
            }
            result = result.next //move to the edge just beyond current bound
        } else {
            while result.top.y == result.prev.bot.y && result.prev.outIdx != Skip {
                result = result.prev
            }
            if result.dx == Horizontal && result.prev.outIdx != Skip {
                horz = result
                while horz.next.dx == Horizontal {
                    horz = horz.next
                }
                if horz.next.top.x == result.prev.top.x ||
                    horz.next.top.x > result.prev.top.x {
                    result = horz.next
                }
            }
            
            while e !== result {
                e.nextInLML = e.prev
                if e.dx == Horizontal && e !== eStart && e.bot.x != e.next.top.x {
                    e.reverseHorizontal()
                }
                e = e.prev
            }
            if e.dx == Horizontal && e !== eStart && e.bot.x != e.next.top.x {
                e.reverseHorizontal()
            }
            result = result.prev //move to the edge just beyond current bound
        }
        return result
    }
    
    @discardableResult
    public func addPath(_ pg: Path, _ polyType: PolyType, _ closed: Bool) -> Bool {
        
        var highI = pg.count - 1
        if closed {
            while highI > 0 && pg[highI] == pg[0] {
                highI -= 1
            }
        }
        while highI > 0 && pg[highI] == pg[highI - 1] {
            highI -= 1
        }
        if closed && highI < 2 || (!closed && highI < 1) {
            return false
        }
        
        //create a new edge array ...
        var edges = [TEdge]()
        for _ in 0...highI {
            let edege = TEdge()
            edges.append(edege)
        }
        
        var isFlat = true
        
        //1. Basic (first) edge initialization ...
        edges[1].curr = pg[1]
        TEdge.initEdge(edge: edges[0], next: edges[1], prev: edges[highI], pt: pg[0])
        TEdge.initEdge(edge: edges[highI], next: edges[0], prev: edges[highI - 1], pt: pg[highI])
        for i in (1...highI-1).reversed() {
            TEdge.initEdge(edge: edges[i], next: edges[i + 1], prev: edges[i - 1], pt: pg[i])
        }
        
        var eStart = edges.first!
        
        //2. Remove duplicate vertices, and (when closed) collinear edges ...
        var e = eStart
        var eLoopStop = eStart
        while true {
            //nb: allows matching start and end points when not closed ...
            if e.curr == e.next.curr && (closed || e.next != eStart) {
                if e == e.next {
                    break
                }
                if e == eStart {
                    eStart = e.next
                }
                e = TEdge.removeEdge(e)
                eLoopStop = e
                continue
            }
            if e.prev == e.next {
                break //only two vertices
            } else if closed && e.curr.isSlopesEqual(e.prev.curr, e.next.curr) && (!preserveCollinear || !e.curr.isBetween(e.prev.curr, e.next.curr)) {
                //Collinear edges are allowed for open paths but in closed paths
                //the default is to merge adjacent collinear edges into a single edge.
                //However, if the preserveCollinear property is enabled, only overlapping
                //collinear edges (ie spikes) will be removed from closed paths.
                if e == eStart {
                    eStart = e.next
                }
                e = TEdge.removeEdge(e)
                e = e.prev
                eLoopStop = e
                continue
            }
            e = e.next
            if (e == eLoopStop) || (!closed && e.next == eStart) {
                break
            }
        }
        
        if (!closed && e == e.next) || (closed && e.prev == e.next) {
            return false
        }
        
        if !closed {
            hasOpenPaths = true
            eStart.prev.outIdx = Skip
        }
        
        //3. Do second stage of edge initialization ...
        e = eStart
        repeat {
            TEdge.initEdge(edge: e, polyType: polyType)
            e = e.next
            if isFlat && e.curr.y != eStart.curr.y {
                isFlat = false
            }
        } while e != eStart
        
        //4. Finally, add edge bounds to LocalMinima list ...
        
        //Totally flat paths must be handled differently when adding them
        //to LocalMinima list to avoid endless loops etc ...
        if isFlat {
            if closed {
                return false
            }
            e.prev.outIdx = Skip
            let locMin = LocalMinima()
            locMin.next = nil
            locMin.y = e.bot.y
            locMin.leftBound = nil
            locMin.rightBound = e
            locMin.rightBound.side = .right
            locMin.rightBound.windDelta = 0
            while true {
                if e.bot.x != e.prev.top.x {
                    e.reverseHorizontal()
                }
                if e.next.outIdx == Skip {
                    break
                }
                e.nextInLML = e.next
                e = e.next
            }
            insertLocalMinima(locMin)
            self.edges.append(edges)
            return true
        }
        
        self.edges.append(edges)
        var leftBoundIsForward = false
        var EMin: TEdge? = nil
        
        //workaround to avoid an endless loop in the while loop below when
        //open paths have matching start and end points ...
        if e.prev.bot == e.prev.top {
            e = e.next
        }
        
        while true {
            e = TEdge.findNextLocMin(e)
            if e == EMin {
                break
            } else if EMin == nil {
                EMin = e
            }
            
            //e and e.prev now share a local minima (left aligned if Horizontal).
            //Compare their slopes to find which starts which bound ...
            let locMin = LocalMinima()
            locMin.next = nil
            locMin.y = e.bot.y
            if e.dx < e.prev.dx {
                locMin.leftBound = e.prev
                locMin.rightBound = e
                leftBoundIsForward = false //Q.nextInLML = Q.prev
            } else {
                locMin.leftBound = e
                locMin.rightBound = e.prev
                leftBoundIsForward = true //Q.nextInLML = Q.next
            }
            locMin.leftBound.side = .left
            locMin.rightBound.side = .right
            
            if !closed {
                locMin.leftBound.windDelta = 0
            } else if locMin.leftBound.next == locMin.rightBound {
                locMin.leftBound.windDelta = -1
            } else {
                locMin.leftBound.windDelta = 1
            }
            locMin.rightBound.windDelta = -locMin.leftBound.windDelta
            
            e = processBound(locMin.leftBound, leftBoundIsForward)
            if e.outIdx == Skip {
                e = processBound(e, leftBoundIsForward)
            }
            
            var E2 = processBound(locMin.rightBound, !leftBoundIsForward)
            if E2.outIdx == Skip {
                E2 = processBound(E2, !leftBoundIsForward)
            }
            
            if locMin.leftBound.outIdx == Skip {
                locMin.leftBound = nil
            } else if locMin.rightBound.outIdx == Skip {
                locMin.rightBound = nil
            }
            insertLocalMinima(locMin)
            if !leftBoundIsForward {
                e = E2
            }
        }
        return true
        
    }
    
    @discardableResult
    public func addPaths(_ ppg: Paths, _ polyType: PolyType, _ closed: Bool) -> Bool {
        var result = false
        for i in ppg.indices {
            if addPath(ppg[i], polyType, closed) {
                result = true
            }
        }
        return result
    }
    
    func insertLocalMinima(_ newLm: LocalMinima) {
        if minimaList == nil {
            minimaList = newLm
        } else if newLm.y >= minimaList!.y {
            newLm.next = minimaList
            minimaList = newLm
        } else {
            var tmpLm:LocalMinima = minimaList!
            while tmpLm.next != nil  && newLm.y < tmpLm.next!.y {
                tmpLm = tmpLm.next!
            }
            newLm.next = tmpLm.next
            tmpLm.next = newLm
        }
    }
    
    func popLocalMinima(_ y: CGFloat, _ current:inout LocalMinima?) -> Bool {
        current = currentLM
        if currentLM != nil && currentLM!.y == y {
            currentLM = currentLM!.next
            return true
        }
        return false
    }
    
    func reset() {
        currentLM = minimaList
        if currentLM == nil {
            return //ie nothing to process
        }
        
        //reset all edges ...
        scanbeam = nil
        var lm = minimaList
        while lm != nil {
            insertScanbeam(lm!.y)
            var e = lm!.leftBound
            if e != nil {
                e?.curr = e!.bot
                e?.outIdx = Unassigned
            }
            e = lm?.rightBound
            if e != nil {
                e?.curr = e!.bot
                e?.outIdx = Unassigned
            }
            lm = lm?.next
        }
        activeEdges = nil
    }
    
    func insertScanbeam(_ y: CGFloat) {
        //single-linked list: sorted descending, ignoring dups.
        if scanbeam == nil {
            scanbeam = Scanbeam()
            scanbeam?.next = nil
            scanbeam?.y = y
        } else if y > scanbeam!.y {
            let newSb = Scanbeam()
            newSb.y = y
            newSb.next = scanbeam
            scanbeam = newSb
        } else {
            var sb2 = scanbeam
            while sb2?.next != nil && (y <= sb2!.next!.y) {
                sb2 = sb2?.next
            }
            if y == sb2!.y {
                return //ie ignores duplicates
            }
            let newSb = Scanbeam()
            newSb.y = y
            newSb.next = sb2?.next
            sb2?.next = newSb
        }
    }
    
    func popScanbeam(_ y:inout CGFloat) -> Bool {
        if scanbeam == nil {
            y = 0
            return false
        }
        y = scanbeam!.y
        scanbeam = scanbeam!.next
        return true
    }
    
    
    var localMinimaPending: Bool{
        return currentLM != nil
    }
    
    func createOutRec() -> OutRec {
        let result = OutRec()
        polyOuts.append(result)
        result.index = polyOuts.count - 1
        return result
    }
    
    func clearOutRecs() {
        for poly in polyOuts {
            poly.clear()
        }
    }
    
    func updateEdgeIntoAEL(_ e:inout TEdge) throws {
        if e.nextInLML == nil {
            throw ClipperError(message: "updateEdgeIntoAEL: invalid call")
        }
        e.nextInLML?.outIdx = e.outIdx
        let aelPrev = e.prevInAEL
        let aelNext = e.nextInAEL
        if aelPrev != nil {
            aelPrev?.nextInAEL = e.nextInLML
        } else {
            activeEdges = e.nextInLML
        }
        if aelNext != nil {
            aelNext?.prevInAEL = e.nextInLML
        }
        e.nextInLML?.side = e.side
        e.nextInLML?.windDelta = e.windDelta
        e.nextInLML?.windCnt = e.windCnt
        e.nextInLML?.windCnt2 = e.windCnt2
        e = e.nextInLML!
        e.curr = e.bot
        e.prevInAEL = aelPrev
        e.nextInAEL = aelNext
        if !e.isHorizontal {
            insertScanbeam(e.top.y)
        }
    }
    
    func swapPositionsInAEL(_ edge1: TEdge, _ edge2: TEdge) {
        //check that one or other edge hasn't already been removed from AEL ...
        if edge1.nextInAEL == edge1.prevInAEL || edge2.nextInAEL == edge2.prevInAEL {
            return
        }
        
        if edge1.nextInAEL == edge2 {
            let next = edge2.nextInAEL
            if next != nil {
                next?.prevInAEL = edge1
            }
            let prev = edge1.prevInAEL
            if prev != nil {
                prev?.nextInAEL = edge2
            }
            edge2.prevInAEL = prev
            edge2.nextInAEL = edge1
            edge1.prevInAEL = edge2
            edge1.nextInAEL = next
        } else if edge2.nextInAEL == edge1 {
            let next = edge1.nextInAEL
            if next != nil {
                next?.prevInAEL = edge2
            }
            let prev = edge2.prevInAEL
            if prev != nil {
                prev?.nextInAEL = edge1
            }
            edge1.prevInAEL = prev
            edge1.nextInAEL = edge2
            edge2.prevInAEL = edge1
            edge2.nextInAEL = next
        } else {
            let next = edge1.nextInAEL
            let prev = edge1.prevInAEL
            edge1.nextInAEL = edge2.nextInAEL
            if edge1.nextInAEL != nil {
                edge1.nextInAEL?.prevInAEL = edge1
            }
            edge1.prevInAEL = edge2.prevInAEL
            if edge1.prevInAEL != nil {
                edge1.prevInAEL?.nextInAEL = edge1
            }
            edge2.nextInAEL = next
            if edge2.nextInAEL != nil {
                edge2.nextInAEL?.prevInAEL = edge2
            }
            edge2.prevInAEL = prev
            if edge2.prevInAEL != nil {
                edge2.prevInAEL?.nextInAEL = edge2
            }
        }
        
        if edge1.prevInAEL == nil {
            activeEdges = edge1
        } else if edge2.prevInAEL == nil {
            activeEdges = edge2
        }
    }
    
    
    func deleteFromAEL(_ e: TEdge) {
        let aelPrev = e.prevInAEL
        let aelNext = e.nextInAEL
        if aelPrev == nil && aelNext == nil && e != activeEdges {
            return //already deleted
        }
        if aelPrev != nil {
            aelPrev?.nextInAEL = aelNext
        } else {
            activeEdges = aelNext
        }
        if aelNext != nil {
            aelNext?.prevInAEL = aelPrev
        }
        e.nextInAEL = nil
        e.prevInAEL = nil
    }
    
    
}
