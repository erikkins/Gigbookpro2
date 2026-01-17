import SwiftUI
import UIKit

// MARK: - SwiftUI Punch Hole View

struct PunchHoleView: View {
    var body: some View {
        GeometryReader { geometry in
            // Scale hole size based on view width (smaller when sidebar open)
            let scale = min(geometry.size.width / 800, 1.0) // 800pt is roughly full width
            let holeSize: CGFloat = 20 * scale
            let leftOffset: CGFloat = 20 * scale
            
            HStack {
                Spacer()
                    .frame(width: leftOffset)
                
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.15)
                    
                    PunchHoleCircle(size: holeSize)
                    
                    Spacer()
                    
                    PunchHoleCircle(size: holeSize)
                    
                    Spacer()
                    
                    PunchHoleCircle(size: holeSize)
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.15)
                }
                .frame(width: holeSize)
                
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}

struct PunchHoleCircle: View {
    let size: CGFloat
    
    var body: some View {
        PunchHoleUIView()
            .frame(width: size, height: size)
    }
}

// MARK: - UIKit Punch Hole (for accurate gradient rendering)

struct PunchHoleUIView: UIViewRepresentable {
    func makeUIView(context: Context) -> PunchHole {
        let hole = PunchHole(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        hole.setGradientColor(red: 0.7, green: 0.7, blue: 0.7)
        return hole
    }
    
    func updateUIView(_ uiView: PunchHole, context: Context) {}
}

// MARK: - UIKit PunchHole Class (ported from Obj-C)

class PunchHole: UIView {
    private var gradient: CGGradient?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    func setGradientColor(red: CGFloat, green: CGFloat, blue: CGFloat) {
        let rgb = CGColorSpaceCreateDeviceRGB()
        let colors: [CGFloat] = [
            red, green, blue, 1.0,    // Start color (gray)
            1.0, 1.0, 1.0, 1.0         // End color (white)
        ]
        gradient = CGGradient(colorSpace: rgb, colorComponents: colors, locations: nil, count: 2)
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let gradient = gradient else { return }
        
        let width = bounds.size.width
        let height = bounds.size.height
        
        // Scale points (0-1 range)
        let startPoint = CGPoint(x: 0.5, y: 0)
        let endPoint = CGPoint(x: 0.5, y: 1)
        
        // Create transform to scale to actual size
        let transform = CGAffineTransform(scaleX: width, y: height)
        context.concatenate(transform)
        
        context.saveGState()
        
        // Create circular clipping path
        context.beginPath()
        context.addArc(
            center: CGPoint(x: 0.5, y: 0.5),
            radius: 0.4,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        context.closePath()
        context.clip()
        
        // Draw gradient inside circle
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        
        context.restoreGState()
    }
}
