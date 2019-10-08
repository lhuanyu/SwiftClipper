//
//  PolyNode.swift
//  
//
//  Created by Luo,Huanyu on 2019/10/1.
//

import Foundation

public class PolyNode {
    
    var parent:PolyNode?
    var polygon = Path()
    var index = 0
    var joinType = JoinType.square
    var endType = EndType.closedPolygon
    var children = [PolyNode]()
    
    var isHole: Bool  {
        var result = true
        var node = parent
        while node != nil {
            result = !result
            node = node?.parent
        }
        return result
    }
    
    var isOpen:Bool = false
    
    public var childCount: Int {
        return children.count
    }

    public var contour: Path {
        return polygon
    }
    
    public func addChild(_ child: PolyNode) {
        let count = children.count
        children.append(child)
        child.parent = self
        child.index = count
    }
    
    public func next() -> PolyNode? {
        if children.count > 0 {
            return children[0]
        }
        return nextSiblingUp()
    }
    
    func nextSiblingUp() -> PolyNode? {
        guard let parent = parent else {
            return nil
        }
        
        if index == parent.children.count - 1 {
            return parent.nextSiblingUp()
        } else {
            return parent.children[index + 1]
        }
    }
    
}

extension PolyNode: Equatable {
    
    public static func == (lhs: PolyNode, rhs: PolyNode) -> Bool {
        return lhs.polygon == rhs.polygon && lhs.parent == rhs.parent
    }
    
}

extension PolyNode {
    
    public enum NodeType { case any, open, closed }
    
    public func addPolyNodeToPaths(polynode: PolyNode,  nt: NodeType, paths:inout Paths) {
        var match = true
        switch nt {
        case .open:
            return
        case .closed:
            match = !polynode.isOpen
        default:
            break
        }
        
        if polynode.polygon.count > 0 && match {
            paths.append(polynode.polygon)
        }
        for pn in polynode.children {
            addPolyNodeToPaths(polynode: pn, nt: nt, paths: &paths)
        }
    }
}


/// PolyTree
public class PolyTree: PolyNode {
    var allPolys = [PolyNode]()
    
    public func clear(keepingCapacity: Bool = false) {
        allPolys.removeAll(keepingCapacity: keepingCapacity)
        children.removeAll(keepingCapacity: keepingCapacity)
    }
    
    public var first: PolyNode? {
        return allPolys.first
    }
    
    public var total: Int {
        var result = allPolys.count
        //with negative offsets, ignore the hidden outer polygon ...
        if result > 0 && children[0] != allPolys[0] {
            result -= 1
        }
        return result
    }

}


extension PolyTree {
    
    public var openPaths: Paths {
        var result = Paths()
        for i in self.children.indices {
            if (self.children[i].isOpen) {
                result.append(self.children[i].polygon)
            }
        }
        return result
    }
    
    public var closedPaths: Paths {
        var result = Paths()
        addPolyNodeToPaths(polynode: self, nt: .closed, paths: &result)
        return result
    }
    
    public var paths: Paths {
        var result = Paths()
        addPolyNodeToPaths(polynode: self, nt: .any, paths: &result)
        return result
    }
    
}
