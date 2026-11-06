import SwiftUI
import UIKit

enum ControlMode: String, CaseIterable, Identifiable {
    case pad = "触控板"
    case touch = "直触"
    case view = "浏览"
    var id: String { rawValue }
}

struct RemoteScreenView: UIViewRepresentable {
    @ObservedObject var client: RemoteClient
    @Binding var mode: ControlMode
    @Binding var zoom: CGFloat
    let command: Int

    func makeUIView(context: Context) -> RemoteCanvas {
        let view = RemoteCanvas()
        view.client = client
        view.mode = mode
        view.onZoom = { value in DispatchQueue.main.async { zoom = value } }
        return view
    }

    func updateUIView(_ view: RemoteCanvas, context: Context) {
        view.client = client
        view.image = client.frame
        view.mode = mode
        view.pointer = CGPoint(x: client.pointerX, y: client.pointerY)
        if abs(view.zoom - zoom) > 0.005 { view.setZoom(zoom) }
        if context.coordinator.lastCommand != command {
            context.coordinator.lastCommand = command
            if command > 0 && command % 2 == 1 { view.fit() }
            if command > 0 && command % 2 == 0 { view.actualSize() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastCommand = 0 }
}

final class RemoteCanvas: UIView, UIGestureRecognizerDelegate {
    weak var client: RemoteClient?
    var image: UIImage? { didSet { setNeedsDisplay() } }
    var mode: ControlMode = .pad { didSet { setNeedsDisplay() } }
    var zoom: CGFloat = 1
    var offset = CGPoint.zero
    var pointer = CGPoint(x: 32768, y: 32768)
    var onZoom: ((CGFloat) -> Void)?
    private var draggingDirect = false
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.025, green: 0.045, blue: 0.075, alpha: 1)
        isMultipleTouchEnabled = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1
        let twoPan = UIPanGestureRecognizer(target: self, action: #selector(twoFingerPan(_:)))
        twoPan.minimumNumberOfTouches = 2; twoPan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let rightTap = UITapGestureRecognizer(target: self, action: #selector(rightTap(_:)))
        rightTap.numberOfTouchesRequired = 2
        [pan, twoPan, pinch, tap, rightTap].forEach { $0.delegate = self; addGestureRecognizer($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != bounds.size { lastSize = bounds.size; clampOffset(); setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let image else {
            let text = "等待远程画面…" as NSString
            text.draw(at: CGPoint(x: 20, y: 20), withAttributes: [.foregroundColor: UIColor.lightGray, .font: UIFont.systemFont(ofSize: 16)])
            return
        }
        context.interpolationQuality = zoom > 1.4 ? .none : .high
        let target = imageRect()
        image.draw(in: target)
        guard mode != .view else { return }
        let point = CGPoint(x: target.minX + target.width * pointer.x / 65535,
                            y: target.minY + target.height * pointer.y / 65535)
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        let cursor = UIBezierPath()
        cursor.move(to: .zero); cursor.addLine(to: CGPoint(x: 0, y: 25)); cursor.addLine(to: CGPoint(x: 6, y: 18))
        cursor.addLine(to: CGPoint(x: 11, y: 28)); cursor.addLine(to: CGPoint(x: 16, y: 25)); cursor.addLine(to: CGPoint(x: 11, y: 16))
        cursor.addLine(to: CGPoint(x: 21, y: 16)); cursor.close()
        UIColor.black.setStroke(); UIColor.white.setFill(); cursor.lineWidth = 2; cursor.fill(); cursor.stroke()
        context.restoreGState()
    }

    func setZoom(_ value: CGFloat) {
        zoom = min(8, max(0.25, value)); clampOffset(); onZoom?(zoom); setNeedsDisplay()
    }

    func fit() { offset = .zero; setZoom(1) }

    func actualSize() {
        guard let image else { return }
        let fit = fitScale(image)
        offset = .zero
        setZoom(1 / max(0.001, fit))
    }

    private func fitScale(_ image: UIImage) -> CGFloat {
        min(bounds.width / max(1, image.size.width), bounds.height / max(1, image.size.height))
    }

    private func imageRect() -> CGRect {
        guard let image else { return .zero }
        let scale = fitScale(image) * zoom
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + offset.x,
                      y: (bounds.height - size.height) / 2 + offset.y,
                      width: size.width, height: size.height)
    }

    private func clampOffset() {
        let rect = imageRect()
        let maxX = max(0, (rect.width - bounds.width) / 2)
        let maxY = max(0, (rect.height - bounds.height) / 2)
        offset.x = min(maxX, max(-maxX, offset.x)); offset.y = min(maxY, max(-maxY, offset.y))
    }

    private func setPointer(_ location: CGPoint) {
        let rect = imageRect()
        guard rect.width > 0, rect.height > 0 else { return }
        pointer.x = min(65535, max(0, (location.x - rect.minX) / rect.width * 65535))
        pointer.y = min(65535, max(0, (location.y - rect.minY) / rect.height * 65535))
        setNeedsDisplay()
    }

    private func sendMove() { client?.mouse(x: Int(pointer.x), y: Int(pointer.y), action: 0) }

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        if mode == .view {
            offset.x += translation.x; offset.y += translation.y; clampOffset(); setNeedsDisplay()
        } else if mode == .pad {
            pointer.x = min(65535, max(0, pointer.x + translation.x / max(1, bounds.width) * 65535))
            pointer.y = min(65535, max(0, pointer.y + translation.y / max(1, bounds.height) * 65535))
            sendMove(); setNeedsDisplay()
        } else {
            setPointer(recognizer.location(in: self)); sendMove()
            if recognizer.state == .began { client?.mouse(x: Int(pointer.x), y: Int(pointer.y), action: 1); draggingDirect = true }
        }
        recognizer.setTranslation(.zero, in: self)
        if recognizer.state == .ended || recognizer.state == .cancelled {
            if draggingDirect { client?.mouse(x: Int(pointer.x), y: Int(pointer.y), action: 2); draggingDirect = false }
        }
    }

    @objc private func twoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        offset.x += translation.x; offset.y += translation.y; clampOffset(); setNeedsDisplay()
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) {
        setZoom(zoom * recognizer.scale); recognizer.scale = 1
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        if mode == .view { return }
        if mode == .touch { setPointer(recognizer.location(in: self)); sendMove() }
        client?.click(x: Int(pointer.x), y: Int(pointer.y))
    }

    @objc private func rightTap(_ recognizer: UITapGestureRecognizer) {
        if mode == .view { return }
        if mode == .touch { setPointer(recognizer.location(in: self)); sendMove() }
        client?.click(x: Int(pointer.x), y: Int(pointer.y), right: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer)
    }
}

