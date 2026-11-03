// Native presentations follow the game root's orientation policy, including
// either portrait direction on companion-enabled phones and tablets.
import SwiftUI
import UIKit

final class GameHostingController<Content: View>: UIViewController {
    private let hosting: UIHostingController<Content>
    weak var orientationOwner: UIViewController?
    private var canvasObserver: NSObjectProtocol?

    init(rootView: Content) {
        hosting = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(rootView:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        canvasObserver = NotificationCenter.default.addObserver(forName: Notification.Name("DmCanvasOrientationChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.updateCanvasOrientation()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCanvasOrientation()
    }

    private func updateCanvasOrientation() {
        // UIKit retains its presentation container. Rotate its owned content,
        // with explicit bounds, rather than changing a transformed root frame.
        // Embedded companions inherit the game canvas exactly once.
        let angle = parent == nil ? orientationOwner.map { dm_canvas_rotation($0) } ?? 0 : 0
        let quarter = Int((angle / (.pi / 2)).rounded())
        let size = quarter & 1 == 0 ? view.bounds.size : CGSize(width: view.bounds.height, height: view.bounds.width)
        hosting.view.bounds = CGRect(origin: .zero, size: size)
        hosting.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        hosting.view.transform = CGAffineTransform(rotationAngle: angle)
    }

    deinit {
        if let canvasObserver { NotificationCenter.default.removeObserver(canvasObserver) }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let parent { orientationOwner = parent }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationOwner?.supportedInterfaceOrientations ?? .all
    }

    override var shouldAutorotate: Bool { true }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if let orientation = orientationOwner?.view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
           supportedInterfaceOrientations.contains(UIInterfaceOrientationMask(rawValue: UInt(1) << orientation.rawValue)) {
            return orientation
        }
        return super.preferredInterfaceOrientationForPresentation
    }
}
