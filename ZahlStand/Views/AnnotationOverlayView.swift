import SwiftUI
import PDFKit

/// Renders annotation markers and connectors over a PDF view
struct AnnotationOverlayView: View {
    @ObservedObject var annotationService: AnnotationService
    let pdfViewController: PDFKeyCommandController
    let onAnnotationTap: (PDFAnnotation) -> Void

    @State private var visibleAnnotations: [AnnotationPosition] = []
    @State private var refreshTrigger: UUID = UUID()

    private let marginWidth: CGFloat = 120
    private let minVerticalSpacing: CGFloat = 50
    private let bubbleWidth: CGFloat = 100

    // Timer to periodically refresh positions during scroll
    private let refreshTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(visibleAnnotations, id: \.annotation.id) { position in
                    AnnotationMarkerView(
                        annotation: position.annotation,
                        anchorPosition: position.anchorPoint,
                        marginPosition: position.marginPoint,
                        isLeftSide: position.isLeftSide,
                        placeAbove: position.placeAbove,
                        onTap: { onAnnotationTap(position.annotation) }
                    )
                }
            }
            .onChange(of: annotationService.activeProfile?.annotations) { _ in
                updateAnnotationPositions(in: geometry)
            }
            .onChange(of: refreshTrigger) { _ in
                updateAnnotationPositions(in: geometry)
            }
            .onAppear {
                updateAnnotationPositions(in: geometry)
            }
            .onReceive(refreshTimer) { _ in
                updateAnnotationPositions(in: geometry)
            }
        }
        .allowsHitTesting(true)
    }

    private func updateAnnotationPositions(in geometry: GeometryProxy) {
        let pdfView = pdfViewController.pdfView
        guard let document = pdfView.document else {
            visibleAnnotations = []
            return
        }

        let allAnnotations = annotationService.allAnnotations
        if !allAnnotations.isEmpty && visibleAnnotations.isEmpty {
            print("🔍 Processing \(allAnnotations.count) annotations, geometry: \(geometry.size)")
        }
        var positions: [AnnotationPosition] = []

        for annotation in allAnnotations {
            guard annotation.pageIndex < document.pageCount else {
                print("⚠️ Annotation page \(annotation.pageIndex) >= pageCount \(document.pageCount)")
                continue
            }
            guard let screenPoint = pdfViewController.convertToScreenCoordinates(
                    pageIndex: annotation.pageIndex,
                    relativeX: annotation.relativeX,
                    relativeY: annotation.relativeY
                  ) else {
                print("⚠️ Failed to convert coordinates for annotation on page \(annotation.pageIndex)")
                continue
            }

            // Convert to overlay coordinate space
            let localPoint = CGPoint(
                x: screenPoint.x,
                y: screenPoint.y
            )

            // Skip if not visible
            if localPoint.y < -50 || localPoint.y > geometry.size.height + 50 {
                continue
            }

            // Determine if annotation is on left or right side of view
            let isOnLeftSide = localPoint.x < geometry.size.width / 2

            // Check if anchor would overlap with margin area - if so, place bubble above
            let leftMarginEdge = marginWidth + 30
            let rightMarginEdge = geometry.size.width - marginWidth - 30
            let placeAbove = (isOnLeftSide && localPoint.x < leftMarginEdge) ||
                             (!isOnLeftSide && localPoint.x > rightMarginEdge)

            positions.append(AnnotationPosition(
                annotation: annotation,
                anchorPoint: localPoint,
                marginPoint: .zero,  // Will be calculated below
                isLeftSide: isOnLeftSide,
                placeAbove: placeAbove
            ))
        }

        // Separate annotations by placement type
        let leftMarginPositions = positions.filter { $0.isLeftSide && !$0.placeAbove }.sorted { $0.anchorPoint.y < $1.anchorPoint.y }
        let rightMarginPositions = positions.filter { !$0.isLeftSide && !$0.placeAbove }.sorted { $0.anchorPoint.y < $1.anchorPoint.y }
        let abovePositions = positions.filter { $0.placeAbove }.sorted { $0.anchorPoint.y < $1.anchorPoint.y }

        // Calculate margin positions for left side
        let leftMarginX = marginWidth / 2 + 20
        var lastLeftY: CGFloat = -100
        for position in leftMarginPositions {
            if let idx = positions.firstIndex(where: { $0.annotation.id == position.annotation.id }) {
                let idealY = positions[idx].anchorPoint.y
                let y = max(idealY, lastLeftY + minVerticalSpacing)
                positions[idx].marginPoint = CGPoint(x: leftMarginX, y: y)
                lastLeftY = y
            }
        }

        // Calculate margin positions for right side
        let rightMarginX = geometry.size.width - marginWidth / 2 - 20
        var lastRightY: CGFloat = -100
        for position in rightMarginPositions {
            if let idx = positions.firstIndex(where: { $0.annotation.id == position.annotation.id }) {
                let idealY = positions[idx].anchorPoint.y
                let y = max(idealY, lastRightY + minVerticalSpacing)
                positions[idx].marginPoint = CGPoint(x: rightMarginX, y: y)
                lastRightY = y
            }
        }

        // Calculate positions for bubbles placed above anchor - avoid overlaps
        let bubbleHeight: CGFloat = 40  // Approximate height of bubble
        var usedAboveRegions: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] = []

        for position in abovePositions {
            if let idx = positions.firstIndex(where: { $0.annotation.id == position.annotation.id }) {
                let anchorX = positions[idx].anchorPoint.x
                var proposedY = positions[idx].anchorPoint.y - bubbleHeight - 15  // 15pt gap above anchor

                // Check for overlaps with existing bubbles and move up if needed
                var hasOverlap = true
                while hasOverlap {
                    hasOverlap = false
                    for region in usedAboveRegions {
                        // Check if this bubble would overlap
                        let horizontalOverlap = abs(anchorX - region.x) < (bubbleWidth + region.width) / 2
                        let verticalOverlap = abs(proposedY - region.y) < (bubbleHeight + region.height) / 2
                        if horizontalOverlap && verticalOverlap {
                            // Move this bubble above the overlapping one
                            proposedY = region.y - bubbleHeight - 10
                            hasOverlap = true
                            break
                        }
                    }
                }

                proposedY = max(20, proposedY)  // Don't go above top of screen
                positions[idx].marginPoint = CGPoint(x: anchorX, y: proposedY)
                usedAboveRegions.append((x: anchorX, y: proposedY, width: bubbleWidth, height: bubbleHeight))
            }
        }

        visibleAnnotations = positions
    }
}

/// Holds calculated positions for an annotation
struct AnnotationPosition {
    let annotation: PDFAnnotation
    let anchorPoint: CGPoint
    var marginPoint: CGPoint
    var isLeftSide: Bool = false
    var placeAbove: Bool = false
}

/// Renders a single annotation marker with connector and bubble
struct AnnotationMarkerView: View {
    let annotation: PDFAnnotation
    let anchorPosition: CGPoint
    let marginPosition: CGPoint
    let isLeftSide: Bool
    let placeAbove: Bool
    let onTap: () -> Void

    private let anchorSize: CGFloat = 10
    private let bubbleWidth: CGFloat = 100

    // Calculate the point where the line should end (edge of bubble nearest to anchor)
    private var lineEndPoint: CGPoint {
        if placeAbove {
            // Bubble is above anchor, line connects to bottom center of bubble
            return CGPoint(x: marginPosition.x, y: marginPosition.y + 15)
        } else if isLeftSide {
            // Bubble is on left, line connects to right edge of bubble
            return CGPoint(x: marginPosition.x + bubbleWidth / 2, y: marginPosition.y)
        } else {
            // Bubble is on right, line connects to left edge of bubble
            return CGPoint(x: marginPosition.x - bubbleWidth / 2, y: marginPosition.y)
        }
    }

    var body: some View {
        ZStack {
            // Connector line - stops at bubble's left edge
            ConnectorLine(
                from: anchorPosition,
                to: lineEndPoint,
                color: annotation.color.uiColor
            )

            // Anchor circle on PDF
            Circle()
                .fill(annotation.color.uiColor)
                .frame(width: anchorSize, height: anchorSize)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .position(anchorPosition)

            // Annotation bubble in margin
            AnnotationBubbleView(
                text: annotation.text,
                color: annotation.color.uiColor,
                fontSize: annotation.fontSize,
                isBold: annotation.isBold
            )
            .frame(width: bubbleWidth)
            .position(marginPosition)
            .onTapGesture {
                onTap()
            }
        }
    }
}

/// Draws a connector line between anchor and margin bubble
struct ConnectorLine: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
    }
}

/// The annotation text bubble displayed in the margin
struct AnnotationBubbleView: View {
    let text: String
    let color: Color
    let fontSize: AnnotationFontSize
    let isBold: Bool

    private var textFont: Font {
        isBold ? fontSize.font.bold() : fontSize.font
    }

    var body: some View {
        Text(text)
            .font(textFont)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(color, lineWidth: 1)
                    )
            )
            .foregroundColor(.primary)
    }
}
