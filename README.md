# SwiftClipper

**This package is basically a Swift translation of the [Clipper Lib](http://www.angusj.com/delphi/clipper.php) authored by Angusj.**
For the consideration of complexity and performance, some features(like big integer support, line clipping) have been temporarily removed. Most codes are reorganized or rewritten in a Swift convention.

## Usage


Basic functions are written as extensions of CGPoint Array. 

```swift
import SwiftClipper

let path = [CGPoint(x: -10, y: 10), CGPoint(x: 20, y: 10), CGPoint(x: 10, y: 0), CGPoint(x: 25, y: -8)]
let path2 = [CGPoint(x: -5, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 20, y: -15), CGPoint(x: -5, y: -15)]

let intersections  = path.intersection(path2) 
//[[(15.0, 5.0), (10.0, 0.0), (0.0, 5.0)]]

let unions = path.union(path2)
//[[(15.0, 5.0), (20.0, 10.0), (-10.0, 10.0), (0.0, 5.0), (-5.0, 5.0), (-5.0, -15.0), (20.0, -15.0), (20.0, 5.0)]]
```

You can also use the Clipper class for customized operations.

```swift
import SwiftClipper

let path1 = [CGPoint(x: -10, y: 10), CGPoint(x: 20, y: 10), CGPoint(x: 10, y: 0), CGPoint(x: 25, y: -8)]
let path2 = [CGPoint(x: -5, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 20, y: -15), CGPoint(x: -5, y: -15)]

var paths = Paths()
let c = Clipper(options: .strictlySimple)
c.addPath(path1, .subject, isClosed)
c.addPath(path2, .clip, isClosed)
try c.execute(clipType: .difference, solution: &paths)
```
Additonal userful functions for geometry caculations are also included in these extensions. For details, check [Path+Geometry.swift](https://github.com/lhuanyu/SwiftClipper/blob/master/Sources/SwiftClipper/Path+Geometry.swift) and [Point.swift](https://github.com/lhuanyu/SwiftClipper/blob/master/Sources/SwiftClipper/Point.swift).

## Note

The original lib uses integer numeric for caculations due to the presicion issue. For some cases, using a minor floating number as coordinates can reach a unpredicable or unprecise result. **If you want to a more precise result, try to use a magnification scale for your numbers**.


