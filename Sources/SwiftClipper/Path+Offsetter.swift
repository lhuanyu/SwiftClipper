//
//  Path+Offsetter.swift
//  
//
//  Created by LuoHuanyu on 2020/2/1.
//

import CoreGraphics


extension Path {
    
    func offset(_ delta: CGFloat) -> Paths {
        let o = Offsetter()
        var solution = Paths()
        _ = try? o.execute(&solution, delta: delta)
        return solution
    }
    
}
