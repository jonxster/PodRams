//
//  FlowLayout.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//
import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var maxRows: Int = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var rowCount = 1
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if currentRowWidth + size.width > width {
                totalHeight += rowMaxHeight + spacing
                rowCount += 1
                if rowCount > maxRows { break }
                currentRowWidth = size.width + spacing
                rowMaxHeight = size.height
            } else {
                currentRowWidth += size.width + spacing
                rowMaxHeight = max(rowMaxHeight, size.height)
            }
        }
        totalHeight += rowMaxHeight
        return CGSize(width: width, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowMaxHeight: CGFloat = 0
        var rowCount = 1
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x + size.width > bounds.maxX {
                rowCount += 1
                if rowCount > maxRows { return }
                x = bounds.minX
                y += rowMaxHeight + spacing
                rowMaxHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
    }
}
