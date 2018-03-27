//
//  LineChartRenderer.swift
//  Charts
//
//  Copyright 2015 Daniel Cohen Gindi & Philipp Jahoda
//  A port of MPAndroidChart for iOS
//  Licensed under Apache License 2.0
//
//  https://github.com/danielgindi/Charts
//

import Foundation
import CoreGraphics

#if !os(OSX)
    import UIKit
#endif


open class LineChartRenderer: LineRadarRenderer
{
    @objc open weak var dataProvider: LineChartDataProvider?
    
    @objc public init(dataProvider: LineChartDataProvider, animator: Animator, viewPortHandler: ViewPortHandler)
    {
        super.init(animator: animator, viewPortHandler: viewPortHandler)
        
        self.dataProvider = dataProvider
    }
    
    open override func drawData(context: CGContext)
    {
        guard let lineData = dataProvider?.lineData else { return }
        
        for i in 0 ..< lineData.dataSetCount
        {
            guard let set = lineData.getDataSetByIndex(i) else { continue }
            
            if set.isVisible
            {
                if !(set is LineChartDataSetProtocol)
                {
                    fatalError("Datasets for LineChartRenderer must conform to LineChartDataSetProtocol")
                }
                
                drawDataSet(context: context, dataSet: set as! LineChartDataSetProtocol)
            }
        }
    }
    
    @objc open func drawDataSet(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        if dataSet.entryCount < 1
        {
            return
        }
        
        context.saveGState()
        
        context.setLineWidth(dataSet.lineWidth)
        if dataSet.lineDashLengths != nil
        {
            context.setLineDash(phase: dataSet.lineDashPhase, lengths: dataSet.lineDashLengths!)
        }
        else
        {
            context.setLineDash(phase: 0.0, lengths: [])
        }
        
        // if drawing cubic lines is enabled
        switch dataSet.mode
        {
        case .linear: fallthrough
        case .stepped:
            drawLinear(context: context, dataSet: dataSet)
            
        case .cubicBezier:
            drawCubicBezier(context: context, dataSet: dataSet)
            
        case .horizontalBezier:
            drawHorizontalBezier(context: context, dataSet: dataSet)
        }
        
        context.restoreGState()
    }
    
    @objc open func drawCubicBezier(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        guard let dataProvider = dataProvider else { return }
        
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        
        let phaseY = animator.phaseY
        
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
        
        // get the color that is specified for this position from the DataSet
        let drawingColor = dataSet.colors.first!
        
        let intensity = dataSet.cubicIntensity
        
        // the path for the cubic-spline
        let cubicPath = CGMutablePath()
        
        let valueToPixelMatrix = trans.valueToPixelMatrix
        
        if _xBounds.range >= 1
        {
            var prevDx: CGFloat = 0.0
            var prevDy: CGFloat = 0.0
            var curDx: CGFloat = 0.0
            var curDy: CGFloat = 0.0
            
            // Take an extra point from the left, and an extra from the right.
            // That's because we need 4 points for a cubic bezier (cubic=4), otherwise we get lines moving and doing weird stuff on the edges of the chart.
            // So in the starting `prev` and `cur`, go -2, -1
            // And in the `lastIndex`, add +1
            
            let firstIndex = _xBounds.min + 1
            let lastIndex = _xBounds.min + _xBounds.range
            
            var prevPrev: ChartDataEntry! = nil
            var prev: ChartDataEntry! = dataSet.entryForIndex(max(firstIndex - 2, 0))
            var cur: ChartDataEntry! = dataSet.entryForIndex(max(firstIndex - 1, 0))
            var next: ChartDataEntry! = cur
            var nextIndex: Int = -1
            
            if cur == nil { return }
            
            // let the spline start
            cubicPath.move(to: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y * phaseY)), transform: valueToPixelMatrix)
            
            for j in stride(from: firstIndex, through: lastIndex, by: 1)
            {
                prevPrev = prev
                prev = cur
                cur = nextIndex == j ? next : dataSet.entryForIndex(j)
                
                nextIndex = j + 1 < dataSet.entryCount ? j + 1 : j
                next = dataSet.entryForIndex(nextIndex)
                
                if next == nil { break }
                
                prevDx = CGFloat(cur.x - prevPrev.x) * intensity
                prevDy = CGFloat(cur.y - prevPrev.y) * intensity
                curDx = CGFloat(next.x - prev.x) * intensity
                curDy = CGFloat(next.y - prev.y) * intensity
                
                cubicPath.addCurve(
                    to: CGPoint(
                        x: CGFloat(cur.x),
                        y: CGFloat(cur.y) * CGFloat(phaseY)),
                    control1: CGPoint(
                        x: CGFloat(prev.x) + prevDx,
                        y: (CGFloat(prev.y) + prevDy) * CGFloat(phaseY)),
                    control2: CGPoint(
                        x: CGFloat(cur.x) - curDx,
                        y: (CGFloat(cur.y) - curDy) * CGFloat(phaseY)),
                    transform: valueToPixelMatrix)
            }
        }
        
        context.saveGState()
        defer { context.restoreGState() }
        
        if dataSet.isDrawFilledEnabled
        {
            // Copy this path because we make changes to it
            let fillPath = cubicPath.mutableCopy()
            
            drawCubicFill(context: context, dataSet: dataSet, spline: fillPath!, matrix: valueToPixelMatrix, bounds: _xBounds)
        }
        
        if dataSet.isDrawLineWithGradientEnabled
        {
            drawGradientLine(context: context, dataSet: dataSet, spline: cubicPath, matrix: valueToPixelMatrix)
        }
        else
        {
            context.beginPath()
            context.addPath(cubicPath)
            context.setStrokeColor(drawingColor.cgColor)
            context.strokePath()
        }
    }
    
    @objc open func drawHorizontalBezier(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        guard let dataProvider = dataProvider else { return }
        
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        
        let phaseY = animator.phaseY
        
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
        
        // get the color that is specified for this position from the DataSet
        let drawingColor = dataSet.colors.first!
        
        // the path for the cubic-spline
        let cubicPath = CGMutablePath()
        
        let valueToPixelMatrix = trans.valueToPixelMatrix
        
        if _xBounds.range >= 1
        {
            var prev: ChartDataEntry! = dataSet.entryForIndex(_xBounds.min)
            var cur: ChartDataEntry! = prev
            
            if cur == nil { return }
            
            // let the spline start
            cubicPath.move(to: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y * phaseY)), transform: valueToPixelMatrix)
            
            for j in stride(from: (_xBounds.min + 1), through: _xBounds.range + _xBounds.min, by: 1)
            {
                prev = cur
                cur = dataSet.entryForIndex(j)
                
                let cpx = CGFloat(prev.x + (cur.x - prev.x) / 2.0)
                
                cubicPath.addCurve(
                    to: CGPoint(
                        x: CGFloat(cur.x),
                        y: CGFloat(cur.y * phaseY)),
                    control1: CGPoint(
                        x: cpx,
                        y: CGFloat(prev.y * phaseY)),
                    control2: CGPoint(
                        x: cpx,
                        y: CGFloat(cur.y * phaseY)),
                    transform: valueToPixelMatrix)
            }
        }
        
        context.saveGState()
        
        if dataSet.isDrawFilledEnabled
        {
            // Copy this path because we make changes to it
            let fillPath = cubicPath.mutableCopy()
            
            drawCubicFill(context: context, dataSet: dataSet, spline: fillPath!, matrix: valueToPixelMatrix, bounds: _xBounds)
        }
        
        context.beginPath()
        context.addPath(cubicPath)
        context.setStrokeColor(drawingColor.cgColor)
        context.strokePath()
        
        context.restoreGState()
    }
    
    open func drawCubicFill(
        context: CGContext,
        dataSet: LineChartDataSetProtocol,
        spline: CGMutablePath,
        matrix: CGAffineTransform,
        bounds: XBounds)
    {
        guard
            let dataProvider = dataProvider
            else { return }
        
        if bounds.range <= 0
        {
            return
        }
        
        let fillMin = dataSet.fillFormatter?.getFillLinePosition(dataSet: dataSet, dataProvider: dataProvider) ?? 0.0
        
        var pt1 = CGPoint(x: CGFloat(dataSet.entryForIndex(bounds.min + bounds.range)?.x ?? 0.0), y: fillMin)
        var pt2 = CGPoint(x: CGFloat(dataSet.entryForIndex(bounds.min)?.x ?? 0.0), y: fillMin)
        pt1 = pt1.applying(matrix)
        pt2 = pt2.applying(matrix)
        
        spline.addLine(to: pt1)
        spline.addLine(to: pt2)
        spline.closeSubpath()
        
        if dataSet.fill != nil
        {
            drawFilledPath(context: context, path: spline, fill: dataSet.fill!, fillAlpha: dataSet.fillAlpha)
        }
        else
        {
            drawFilledPath(context: context, path: spline, fillColor: dataSet.fillColor, fillAlpha: dataSet.fillAlpha)
        }
    }
    
    private var _lineSegments = [CGPoint](repeating: CGPoint(), count: 2)
    
    @objc open func drawLinear(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        guard let dataProvider = dataProvider else { return }
        
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        
        let valueToPixelMatrix = trans.valueToPixelMatrix
        
        let entryCount = dataSet.entryCount
        let isDrawSteppedEnabled = dataSet.mode == .stepped
        let pointsPerEntryPair = isDrawSteppedEnabled ? 4 : 2
        
        let phaseY = animator.phaseY
        
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
        
        // if drawing filled is enabled
        if dataSet.isDrawFilledEnabled && entryCount > 0
        {
            drawLinearFill(context: context, dataSet: dataSet, trans: trans, bounds: _xBounds)
        }
        
        context.saveGState()
        defer { context.restoreGState() }
        
        context.setLineCap(dataSet.lineCapType)
        
        let isGradient = dataSet.isDrawLineWithGradientEnabled
        
        
        // more than 1 color
        if dataSet.colors.count > 1
        {
            if _lineSegments.count != pointsPerEntryPair
            {
                // Allocate once in correct size
                _lineSegments = [CGPoint](repeating: CGPoint(), count: pointsPerEntryPair)
            }
            
            var prevE: ChartDataEntry!
            for j in stride(from: _xBounds.min, through: _xBounds.range + _xBounds.min, by: 1)
            {
                var e: ChartDataEntry! = dataSet.entryForIndex(j)
                var isDashed = false
                
                if e == nil { continue }
                
                if let data = e.data as? NSDictionary {
                    if data["lineStyle"] != nil && data["lineStyle"] as! String == "dashed" {
                        isDashed = true
                    }
                }
                
                
                _lineSegments[0].x = CGFloat(e.x)
                _lineSegments[0].y = CGFloat(e.y * phaseY)
                
                if j < _xBounds.max
                {
                    e = dataSet.entryForIndex(j + 1)
                    
                    if e == nil { break }
                    
                    if let data = e.data as? NSDictionary {
                        if data["lineStyle"] != nil && data["lineStyle"] as! String == "dashed" {
                            isDashed = true
                        }
                    }
                    
                    if isDrawSteppedEnabled && !isGradient
                    {
                        _lineSegments[1] = CGPoint(x: CGFloat(e.x), y: _lineSegments[0].y)
                        _lineSegments[2] = _lineSegments[1]
                        _lineSegments[3] = CGPoint(x: CGFloat(e.x), y: CGFloat(e.y * phaseY))
                    }
                    else
                    {
                        _lineSegments[1] = CGPoint(x: CGFloat(e.x), y: CGFloat(e.y * phaseY))
                    }
                }
                else
                {
                    _lineSegments[1] = _lineSegments[0]
                }
                
                for i in 0..<_lineSegments.count
                {
                    _lineSegments[i] = _lineSegments[i].applying(valueToPixelMatrix)
                }
                
                if (!viewPortHandler.isInBoundsRight(_lineSegments[0].x))
                {
                    break
                }
                
                // make sure the lines don't do shitty things outside bounds
                if !viewPortHandler.isInBoundsLeft(_lineSegments[1].x)
                    || (!viewPortHandler.isInBoundsTop(_lineSegments[0].y) && !viewPortHandler.isInBoundsBottom(_lineSegments[1].y))
                {
                    continue
                }
                
                var color1 = dataSet.color(atIndex: j)
                var color2 = color1
                
                let hasCircleColors = dataSet.circleColors.count == dataSet.entryCount
                
                if hasCircleColors {
                    color1 = dataSet.circleColors[j];
                    color2 = j+1 < dataSet.circleColors.count ? dataSet.circleColors[j+1] : color1
                }
                
                let equalColors = (color1 == color2 && !isDashed)
                
                if (!isGradient || equalColors) {
                    // get the color that is set for this line-segment
                    context.setStrokeColor(color1.cgColor)
                    context.strokeLineSegments(between: _lineSegments)
                } else {
                    
                    let startPoint = _lineSegments[0]
                    let endPoint = _lineSegments[1]
                    
                    context.saveGState()
                    
                    if (!isDashed) {
                        let slope:CGFloat = atan2((startPoint.y - endPoint.y), (startPoint.x - endPoint.x))
                        let cosineY:CGFloat = cos(slope)
                        let sineY:CGFloat = sin(slope)
                        let lineWidth:CGFloat = 1.0;
                        
                        context.move(to: CGPoint(x:startPoint.x-lineWidth*sineY, y: startPoint.y+lineWidth*cosineY))
                        context.addLine(to: CGPoint(x:endPoint.x-lineWidth*sineY, y: endPoint.y+lineWidth*cosineY))
                        context.addLine(to: CGPoint(x:endPoint.x+lineWidth*sineY, y: endPoint.y-lineWidth*cosineY))
                        context.addLine(to: CGPoint(x:startPoint.x+lineWidth*sineY, y: startPoint.y-lineWidth*cosineY))
                        context.addLine(to: CGPoint(x:startPoint.x-lineWidth*sineY, y: startPoint.y+lineWidth*cosineY))
                    } else {
                        context.setLineDash(phase: 0, lengths: [5, 2])
                        context.move(to: CGPoint(x:startPoint.x, y: startPoint.y))
                        context.addLine(to: CGPoint(x:endPoint.x, y: endPoint.y))
                        context.replacePathWithStrokedPath()
                    }
                    
                    context.clip()
                    
                    let baseSpace = CGColorSpaceCreateDeviceRGB()
                    
                    
                    
                    let colours = [color1.cgColor, color2.cgColor] as CFArray
                    let grad = CGGradient.init(colorsSpace: baseSpace, colors: colours, locations: [0,1])
                    
                    context.drawLinearGradient(grad!, start: _lineSegments[0], end: _lineSegments[1], options: CGGradientDrawingOptions(rawValue: 0))
                    
                    context.restoreGState()
                }
                prevE = e;
                
            }
        }
        else if !isGradient
        { // only one color per dataset
            
            var e1: ChartDataEntry!
            var e2: ChartDataEntry!
            
            e1 = dataSet.entryForIndex(_xBounds.min)
            
            if e1 != nil
            {
                
                var firstPoint = true
                
                context.saveGState()
                
                for x in stride(from: _xBounds.min, through: _xBounds.range + _xBounds.min, by: 1)
                {
                    var isDashed = false
                    
                    context.beginPath()
                    e1 = dataSet.entryForIndex(x == 0 ? 0 : (x - 1))
                    e2 = dataSet.entryForIndex(x)
                    
                    if e1 == nil || e2 == nil { continue }
                    
                    if let data = e1.data as? NSDictionary {
                        if data["lineStyle"] != nil && data["lineStyle"] as! String == "dashed" {
                            isDashed = true
                        }
                    }
                    
                    if let data = e2.data as? NSDictionary {
                        if data["lineStyle"] != nil && data["lineStyle"] as! String == "dashed" {
                            isDashed = true
                        }
                    }
                    
                    if (isDashed) {
                        context.setLineDash(phase: 0, lengths: [5, 2])
                    } else {
                        context.setLineDash(phase: 0, lengths: [])
                    }
                    
                    let pt = CGPoint(
                        x: CGFloat(e1.x),
                        y: CGFloat(e1.y * phaseY)
                        ).applying(valueToPixelMatrix)
                    
                    context.setStrokeColor(dataSet.color(atIndex: 0).cgColor)
                    context.move(to: pt)
                    
                    if isDrawSteppedEnabled
                    {
                        context.addLine(to: CGPoint(
                            x: CGFloat(e2.x),
                            y: CGFloat(e1.y * phaseY)
                            ).applying(valueToPixelMatrix))
                    }
                    
                    
                    context.addLine(to: CGPoint(
                        x: CGFloat(e2.x),
                        y: CGFloat(e2.y * phaseY)
                        ).applying(valueToPixelMatrix))
                    context.strokePath()
                }
                
                context.restoreGState()
            }
        }
        
        /*
         if (isGradient)
         {
         let path = generateGradientLinePath(dataSet: dataSet,
         fillMin: dataSet.fillFormatter?.getFillLinePosition(dataSet: dataSet, dataProvider: dataProvider) ?? 0.0,
         from: _xBounds.min,
         to: _xBounds.max,
         matrix: trans.valueToPixelMatrix)
         
         drawGradientLine(context: context, dataSet: dataSet, spline: path, matrix: valueToPixelMatrix)
         }*/
    }
    
    open func drawLinearFill(context: CGContext, dataSet: LineChartDataSetProtocol, trans: Transformer, bounds: XBounds)
    {
        guard let dataProvider = dataProvider else { return }
        
        let filled = generateFilledPath(
            dataSet: dataSet,
            fillMin: dataSet.fillFormatter?.getFillLinePosition(dataSet: dataSet, dataProvider: dataProvider) ?? 0.0,
            bounds: bounds,
            matrix: trans.valueToPixelMatrix)
        
        if dataSet.fill != nil
        {
            drawFilledPath(context: context, path: filled, fill: dataSet.fill!, fillAlpha: dataSet.fillAlpha)
        }
        else
        {
            drawFilledPath(context: context, path: filled, fillColor: dataSet.fillColor, fillAlpha: dataSet.fillAlpha)
        }
    }
    
    /// Generates the path that is used for filled drawing.
    private func generateFilledPath(dataSet: LineChartDataSetProtocol, fillMin: CGFloat, bounds: XBounds, matrix: CGAffineTransform) -> CGPath
    {
        let phaseY = animator.phaseY
        let isDrawSteppedEnabled = dataSet.mode == .stepped
        let matrix = matrix
        
        var e: ChartDataEntry!
        
        let filled = CGMutablePath()
        
        e = dataSet.entryForIndex(bounds.min)
        if e != nil
        {
            filled.move(to: CGPoint(x: CGFloat(e.x), y: fillMin), transform: matrix)
            filled.addLine(to: CGPoint(x: CGFloat(e.x), y: CGFloat(e.y * phaseY)), transform: matrix)
        }
        
        // create a new path
        for x in stride(from: (bounds.min + 1), through: bounds.range + bounds.min, by: 1)
        {
            guard let e = dataSet.entryForIndex(x) else { continue }
            
            if isDrawSteppedEnabled
            {
                guard let ePrev = dataSet.entryForIndex(x-1) else { continue }
                filled.addLine(to: CGPoint(x: CGFloat(e.x), y: CGFloat(ePrev.y * phaseY)), transform: matrix)
            }
            
            filled.addLine(to: CGPoint(x: CGFloat(e.x), y: CGFloat(e.y * phaseY)), transform: matrix)
        }
        
        // close up
        e = dataSet.entryForIndex(bounds.range + bounds.min)
        if e != nil
        {
            filled.addLine(to: CGPoint(x: CGFloat(e.x), y: fillMin), transform: matrix)
        }
        filled.closeSubpath()
        
        return filled
    }
    
    open override func drawValues(context: CGContext)
    {
        guard
            let dataProvider = dataProvider,
            let lineData = dataProvider.lineData
            else { return }
        
        if isDrawingValuesAllowed(dataProvider: dataProvider)
        {
            var dataSets = lineData.dataSets
            
            let phaseY = animator.phaseY
            
            var pt = CGPoint()
            
            for i in 0 ..< dataSets.count
            {
                guard let dataSet = dataSets[i] as? LineChartDataSetProtocol else { continue }
                
                if !shouldDrawValues(forDataSet: dataSet)
                {
                    continue
                }
                
                let valueFont = dataSet.valueFont
                
                guard let formatter = dataSet.valueFormatter else { continue }
                
                let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
                let valueToPixelMatrix = trans.valueToPixelMatrix
                
                let iconsOffset = dataSet.iconsOffset
                
                // make sure the values do not interfear with the circles
                var valOffset = Int(dataSet.circleRadius * 1.75)
                
                if !dataSet.isDrawCirclesEnabled
                {
                    valOffset = valOffset / 2
                }
                
                _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
                
                for j in stride(from: _xBounds.min, through: min(_xBounds.min + _xBounds.range, _xBounds.max), by: 1)
                {
                    guard let e = dataSet.entryForIndex(j) else { break }
                    
                    pt.x = CGFloat(e.x)
                    pt.y = CGFloat(e.y * phaseY)
                    pt = pt.applying(valueToPixelMatrix)
                    
                    if (!viewPortHandler.isInBoundsRight(pt.x))
                    {
                        break
                    }
                    
                    if (!viewPortHandler.isInBoundsLeft(pt.x) || !viewPortHandler.isInBoundsY(pt.y))
                    {
                        continue
                    }
                    
                    if dataSet.isDrawValuesEnabled {
                        ChartUtils.drawText(
                            context: context,
                            text: formatter.stringForValue(
                                e.y,
                                entry: e,
                                dataSetIndex: i,
                                viewPortHandler: viewPortHandler),
                            point: CGPoint(
                                x: pt.x,
                                y: pt.y - CGFloat(valOffset) - valueFont.lineHeight),
                            align: .center,
                            attributes: [NSAttributedStringKey.font: valueFont, NSAttributedStringKey.foregroundColor: dataSet.valueTextColorAt(j)])
                    }
                    
                    if let icon = e.icon, dataSet.isDrawIconsEnabled
                    {
                        ChartUtils.drawImage(context: context,
                                             image: icon,
                                             x: pt.x + iconsOffset.x,
                                             y: pt.y + iconsOffset.y,
                                             size: icon.size)
                    }
                }
            }
        }
    }
    
    open override func drawExtras(context: CGContext)
    {
        drawCircles(context: context)
    }
    
    private func drawCircles(context: CGContext)
    {
        guard
            let dataProvider = dataProvider,
            let lineData = dataProvider.lineData
            else { return }
        
        let phaseY = animator.phaseY
        
        let dataSets = lineData.dataSets
        
        var pt = CGPoint()
        var rect = CGRect()
        
        context.saveGState()
        
        for i in 0 ..< dataSets.count
        {
            guard let dataSet = lineData.getDataSetByIndex(i) as? LineChartDataSetProtocol else { continue }
            
            if !dataSet.isVisible || !dataSet.isDrawCirclesEnabled || dataSet.entryCount == 0
            {
                continue
            }
            
            let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
            let valueToPixelMatrix = trans.valueToPixelMatrix
            
            _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
            
            let circleRadius = dataSet.circleRadius
            let circleDiameter = circleRadius * 2.0
            let circleHoleRadius = dataSet.circleHoleRadius
            let circleHoleDiameter = circleHoleRadius * 2.0
            
            let drawCircleHole = dataSet.isDrawCircleHoleEnabled &&
                circleHoleRadius < circleRadius &&
                circleHoleRadius > 0.0
            let drawTransparentCircleHole = drawCircleHole &&
                (dataSet.circleHoleColor == nil ||
                    dataSet.circleHoleColor == NSUIColor.clear)
            
            for j in stride(from: _xBounds.min, through: _xBounds.range + _xBounds.min, by: 1)
            {
                guard let e = dataSet.entryForIndex(j) else { break }
                
                pt.x = CGFloat(e.x)
                pt.y = CGFloat(e.y * phaseY)
                pt = pt.applying(valueToPixelMatrix)
                
                if (!viewPortHandler.isInBoundsRight(pt.x))
                {
                    break
                }
                
                // make sure the circles don't do shitty things outside bounds
                if (!viewPortHandler.isInBoundsLeft(pt.x) || !viewPortHandler.isInBoundsY(pt.y))
                {
                    continue
                }
                
                context.setFillColor(dataSet.getCircleColor(atIndex: j)!.cgColor)
                
                rect.origin.x = pt.x - circleRadius
                rect.origin.y = pt.y - circleRadius
                rect.size.width = circleDiameter
                rect.size.height = circleDiameter
                
                if drawTransparentCircleHole
                {
                    // Begin path for circle with hole
                    context.beginPath()
                    context.addEllipse(in: rect)
                    
                    // Cut hole in path
                    rect.origin.x = pt.x - circleHoleRadius
                    rect.origin.y = pt.y - circleHoleRadius
                    rect.size.width = circleHoleDiameter
                    rect.size.height = circleHoleDiameter
                    context.addEllipse(in: rect)
                    
                    // Fill in-between
                    context.fillPath(using: .evenOdd)
                }
                else
                {
                    context.fillEllipse(in: rect)
                    
                    if drawCircleHole
                    {
                        context.setFillColor(dataSet.circleHoleColor!.cgColor)
                        
                        // The hole rect
                        rect.origin.x = pt.x - circleHoleRadius
                        rect.origin.y = pt.y - circleHoleRadius
                        rect.size.width = circleHoleDiameter
                        rect.size.height = circleHoleDiameter
                        
                        context.fillEllipse(in: rect)
                    }
                }
            }
        }
        
        context.restoreGState()
    }
    
    open override func drawHighlighted(context: CGContext, indices: [Highlight])
    {
        guard
            let dataProvider = dataProvider,
            let lineData = dataProvider.lineData
            else { return }
        
        let chartXMax = dataProvider.chartXMax
        
        context.saveGState()
        
        for high in indices
        {
            guard let set = lineData.getDataSetByIndex(high.dataSetIndex) as? LineChartDataSetProtocol
                , set.isHighlightEnabled
                else { continue }
            
            guard let e = set.entryForXValue(high.x, closestToY: high.y) else { continue }
            
            if !isInBoundsX(entry: e, dataSet: set)
            {
                continue
            }
            
            context.setStrokeColor(set.highlightColor.cgColor)
            context.setLineWidth(set.highlightLineWidth)
            if set.highlightLineDashLengths != nil
            {
                context.setLineDash(phase: set.highlightLineDashPhase, lengths: set.highlightLineDashLengths!)
            }
            else
            {
                context.setLineDash(phase: 0.0, lengths: [])
            }
            
            let x = high.x // get the x-position
            let y = high.y * Double(animator.phaseY)
            
            if x > chartXMax * animator.phaseX
            {
                continue
            }
            
            let trans = dataProvider.getTransformer(forAxis: set.axisDependency)
            
            let pt = trans.pixelForValues(x: x, y: y)
            
            high.setDraw(pt: pt)
            
            // draw the lines
            drawHighlightLines(context: context, point: pt, set: set)
        }
        
        context.restoreGState()
    }
    
    /// Generates the path that is used for gradient drawing.
    private func generateGradientLinePath(dataSet: LineChartDataSetProtocol, fillMin: CGFloat, from: Int, to: Int, matrix: CGAffineTransform) -> CGPath
    {
        let phaseX = CGFloat(animator.phaseX)
        let phaseY = CGFloat(animator.phaseY)
        
        var e: ChartDataEntry!
        
        let generatedPath = CGMutablePath()
        e = dataSet.entryForIndex(from)
        if e != nil
        {
            generatedPath.move(to: CGPoint(x: CGFloat(e.x), y: CGFloat(e.y) * phaseY), transform: matrix)
        }
        
        // create a new path
        let to = Int(ceil(CGFloat(to - from) * phaseX + CGFloat(from)))
        for i in (from + 1)..<to+1
        {
            guard let e = dataSet.entryForIndex(i) else { continue }
            generatedPath.addLine(to: CGPoint(x: CGFloat(e.x), y: CGFloat(e.y) * phaseY), transform: matrix)
        }
        return generatedPath
    }
    
    func drawGradientLine(context: CGContext, dataSet: LineChartDataSetProtocol, spline: CGPath, matrix: CGAffineTransform)
    {
        context.saveGState()
        defer { context.restoreGState() }
        
        let gradientPath = spline.copy(strokingWithWidth: dataSet.lineWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        context.addPath(gradientPath)
        context.drawPath(using: .fill)
        
        let boundingBox = gradientPath.boundingBox
        let gradientStart = CGPoint(x: 0, y: boundingBox.maxY)
        let gradientEnd = CGPoint(x: 0, y: boundingBox.minY)
        var gradientLocations = [CGFloat]()
        var gradientColors = [CGFloat]()
        var cRed: CGFloat = 0
        var cGreen: CGFloat = 0
        var cBlue: CGFloat = 0
        var cAlpha: CGFloat = 0
        
        //Set lower bound color
        gradientLocations.append(0)
        var cColor = dataSet.color(atIndex: 0)
        if cColor.getRed(&cRed, green: &cGreen, blue: &cBlue, alpha: &cAlpha)
        {
            gradientColors += [cRed, cGreen, cBlue, cAlpha]
        }
        
        //Set middle colors
        guard let gradientPositions = dataSet.gradientPositions else
        {
            fatalError("Must set `gradientPositions if `dataSet.isDrawLineWithGradientEnabled` is true")
        }
        
        for position in gradientPositions
        {
            let positionLocation = CGPoint(x: 0, y: position)
                .applying(matrix)
            let normPositionLocation = (positionLocation.y - gradientStart.y) / (gradientEnd.y - gradientStart.y)
            if (normPositionLocation < 0) {
                gradientLocations.append(0)
            } else if (normPositionLocation > 1) {
                gradientLocations.append(1)
            } else {
                gradientLocations.append(normPositionLocation)
            }
        }
        
        
        if dataSet.colors.count > 2
        {
            for i in 0..<dataSet.colors.count
            {
                cColor = dataSet.color(atIndex: i)
                if cColor.getRed(&cRed, green: &cGreen, blue: &cBlue, alpha: &cAlpha)
                {
                    gradientColors += [cRed, cGreen, cBlue, cAlpha]
                }
            }
        }
        
        
        //Set upper bound color
        gradientLocations.append(1)
        cColor = dataSet.color(atIndex: dataSet.colors.count - 1)
        if cColor.getRed(&cRed, green: &cGreen, blue: &cBlue, alpha: &cAlpha)
        {
            gradientColors += [cRed, cGreen, cBlue, cAlpha]
        }
        
        //Define gradient
        let baseSpace = CGColorSpaceCreateDeviceRGB()
        let gradient: CGGradient?
        if gradientPositions.count > 1
        {
            gradient = CGGradient(colorSpace: baseSpace, colorComponents: &gradientColors, locations: &gradientLocations, count: gradientColors.count / 4)
        } else
        {
            gradient = CGGradient(colorSpace: baseSpace, colorComponents: gradientColors, locations: nil, count: gradientColors.count / 4)
        }
        
        guard gradient != nil else { return }
        
        //Draw gradient path
        context.beginPath()
        context.addPath(gradientPath)
        context.clip()
        context.drawLinearGradient(gradient!, start: gradientStart, end: gradientEnd, options: [])
    }
}

