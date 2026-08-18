import SwiftUI

@Animatable
struct CalendarAgendaBackgroundShape: Shape {
    var selectedColumn: CGFloat

    func path(in rect: CGRect) -> Path {
        let columnCount: CGFloat = 7
        let column = min(max(selectedColumn, 0), columnCount - 1)
        let columnWidth = rect.width / columnCount
        let tabMinX = columnWidth * column
        let tabMaxX = tabMinX + columnWidth
        let panelTop = min(AppTheme.calendarDayHeight, rect.maxY)
        let panelBottom = max(
            panelTop,
            rect.maxY - AppTheme.calendarAgendaBottomSpacing
        )
        let tabCornerRadius = min(
            AppTheme.calendarAgendaTabCornerRadius,
            columnWidth / 2,
            panelTop / 2
        )
        let jointCornerRadius = min(
            AppTheme.calendarAgendaJointCornerRadius,
            columnWidth / 2,
            panelTop / 2
        )
        let panelCornerRadius = min(
            AppTheme.calendarAgendaCornerRadius,
            rect.width / 2,
            (panelBottom - panelTop) / 2
        )

        guard panelBottom > panelTop else {
            var collapsedPath = Path()
            collapsedPath.addRoundedRect(
                in: CGRect(
                    x: tabMinX,
                    y: 0,
                    width: columnWidth,
                    height: panelTop
                ),
                cornerSize: CGSize(
                    width: tabCornerRadius,
                    height: tabCornerRadius
                ),
                style: .continuous
            )
            return collapsedPath
        }

        let leftGap = max(tabMinX, 0)
        let rightGap = max(rect.maxX - tabMaxX, 0)
        let leftRadiusScale = radiusScale(
            for: leftGap,
            panelCornerRadius: panelCornerRadius,
            jointCornerRadius: jointCornerRadius
        )
        let rightRadiusScale = radiusScale(
            for: rightGap,
            panelCornerRadius: panelCornerRadius,
            jointCornerRadius: jointCornerRadius
        )
        let leftPanelCornerRadius = panelCornerRadius * leftRadiusScale
        let leftJointCornerRadius = jointCornerRadius * leftRadiusScale
        let rightPanelCornerRadius = panelCornerRadius * rightRadiusScale
        let rightJointCornerRadius = jointCornerRadius * rightRadiusScale

        var path = Path()

        // Scale both radii as the tab approaches an outer edge so the concave
        // joint turns continuously into the card edge instead of snapping.
        path.move(to: CGPoint(x: 0, y: panelTop + leftPanelCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: leftPanelCornerRadius, y: panelTop),
            control: CGPoint(x: 0, y: panelTop)
        )
        path.addLine(to: CGPoint(x: tabMinX - leftJointCornerRadius, y: panelTop))
        path.addQuadCurve(
            to: CGPoint(x: tabMinX, y: panelTop - leftJointCornerRadius),
            control: CGPoint(x: tabMinX, y: panelTop)
        )
        path.addLine(to: CGPoint(x: tabMinX, y: tabCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: tabMinX + tabCornerRadius, y: 0),
            control: CGPoint(x: tabMinX, y: 0)
        )

        path.addLine(to: CGPoint(x: tabMaxX - tabCornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: tabMaxX, y: tabCornerRadius),
            control: CGPoint(x: tabMaxX, y: 0)
        )

        path.addLine(to: CGPoint(x: tabMaxX, y: panelTop - rightJointCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: tabMaxX + rightJointCornerRadius, y: panelTop),
            control: CGPoint(x: tabMaxX, y: panelTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX - rightPanelCornerRadius, y: panelTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: panelTop + rightPanelCornerRadius),
            control: CGPoint(x: rect.maxX, y: panelTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: panelBottom - panelCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - panelCornerRadius, y: panelBottom),
            control: CGPoint(x: rect.maxX, y: panelBottom)
        )
        path.addLine(to: CGPoint(x: panelCornerRadius, y: panelBottom))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: panelBottom - panelCornerRadius),
            control: CGPoint(x: 0, y: panelBottom)
        )
        path.closeSubpath()

        return path
    }

    private func radiusScale(
        for gap: CGFloat,
        panelCornerRadius: CGFloat,
        jointCornerRadius: CGFloat
    ) -> CGFloat {
        let combinedRadius = panelCornerRadius + jointCornerRadius
        guard combinedRadius > 0 else { return 0 }
        return min(1, gap / combinedRadius)
    }
}
