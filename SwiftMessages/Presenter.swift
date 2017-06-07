//
//  MessagePresenter.swift
//  SwiftMessages
//
//  Created by Timothy Moose on 7/30/16.
//  Copyright © 2016 SwiftKick Mobile LLC. All rights reserved.
//

import UIKit

class Weak<T: AnyObject> {
    weak var value: T?
    init(value: T?) {
        self.value = value
    }
}

protocol PresenterDelegate: class {
    func hide(presenter: Presenter)
    func panStarted(presenter: Presenter)
    func panEnded(presenter: Presenter)
}

class Presenter: NSObject, AnimatorDelegate {

    enum PresentationContext {
        case viewController(_: Weak<UIViewController>)
        case view(_: Weak<UIView>)

        func viewControllerValue() -> UIViewController? {
            switch self {
            case .viewController(let weak):
                return weak.value
            case .view:
                return nil
            }
        }

        func viewValue() -> UIView? {
            switch self {
            case .viewController(let weak):
                return weak.value?.view
            case .view(let weak):
                return weak.value
            }
        }
    }

    let config: SwiftMessages.Config
    let view: UIView
    weak var delegate: PresenterDelegate?
    let maskingView = MaskingView()
    var presentationContext = PresentationContext.viewController(Weak<UIViewController>(value: nil))
    let panRecognizer: UIPanGestureRecognizer

    var animator: Animator? = nil
    init(config: SwiftMessages.Config, view: UIView, delegate: PresenterDelegate) {
        self.config = config
        self.view = view
        self.delegate = delegate
        panRecognizer = UIPanGestureRecognizer()
        super.init()
        panRecognizer.addTarget(self, action: #selector(Presenter.pan(pan:)))
        maskingView.clipsToBounds = true
    }

    var id: String? {
        let identifiable = view as? Identifiable
        return identifiable?.id
    }

    var pauseDuration: TimeInterval? {
        let duration: TimeInterval?
        switch self.config.duration {
        case .automatic:
            duration = 2
        case .seconds(let seconds):
            duration = seconds
        case .forever, .indefinite:
            duration = nil
        }
        return duration
    }

    var showDate: Date?

    fileprivate var interactivelyHidden = false;

    var delayShow: TimeInterval? {
        if case .indefinite(let opts) = config.duration { return opts.delay }
        return nil
    }

    /// Returns the required delay for hiding based on time shown
    var delayHide: TimeInterval? {
        if interactivelyHidden { return 0 }
        if case .indefinite(let opts) = config.duration, let showDate = showDate {
            let timeIntervalShown = -showDate.timeIntervalSinceNow
            return max(0, opts.minimum - timeIntervalShown)
        }
        return nil
    }

    func show(completion: @escaping (_ completed: Bool) -> Void) throws {
        try presentationContext = getPresentationContext()
        install()
        self.config.eventListeners.forEach { $0(.willShow) }
        showAnimation() { completed in
            completion(completed)
            if completed {
                if self.config.dimMode.modal {
                    self.showAccessibilityFocus()
                } else {
                    self.showAccessibilityAnnouncement()
                }
                self.config.eventListeners.forEach { $0(.didShow) }
            }
        }
    }

    private func showAccessibilityAnnouncement() {
        guard let accessibleMessage = view as? AccessibleMessage,
            let message = accessibleMessage.accessibilityMessage else { return }
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message)
    }

    private func showAccessibilityFocus() {
        guard let accessibleMessage = view as? AccessibleMessage,
            let focus = accessibleMessage.accessibilityElement ?? accessibleMessage.additonalAccessibilityElements?.first else { return }
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, focus)
    }

    func getPresentationContext() throws -> PresentationContext {
        func newWindowViewController(_ windowLevel: UIWindowLevel) -> UIViewController {
            let viewController = WindowViewController(windowLevel: windowLevel, config: config)
            return viewController
        }

        switch config.presentationContext {
        case .automatic:
            if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
                let viewController = rootViewController.sm_selectPresentationContextTopDown(config)
                return .viewController(Weak(value: viewController))
            } else {
                throw SwiftMessagesError.noRootViewController
            }
        case .window(let level):
            let viewController = newWindowViewController(level)
            return .viewController(Weak(value: viewController))
        case .viewController(let viewController):
            let viewController = viewController.sm_selectPresentationContextBottomUp(config)
            return .viewController(Weak(value: viewController))
        case .view(let view):
            return .view(Weak(value: view))
        }
    }

    /*
     MARK: - Installation
     */

    func install() {
        guard let containerView = presentationContext.viewValue() else { return }
        if let windowViewController = presentationContext.viewControllerValue() as? WindowViewController {
            windowViewController.install(becomeKey: becomeKeyWindow)
        }
        do {
            maskingView.translatesAutoresizingMaskIntoConstraints = false
            if let nav = presentationContext.viewControllerValue() as? UINavigationController {
                containerView.insertSubview(maskingView, belowSubview: nav.navigationBar)
            } else if let tab = presentationContext.viewControllerValue() as? UITabBarController {
                containerView.insertSubview(maskingView, belowSubview: tab.tabBar)
            } else {
                containerView.addSubview(maskingView)
            }
            let leading = NSLayoutConstraint(item: maskingView, attribute: .leading, relatedBy: .equal, toItem: containerView, attribute: .leading, multiplier: 1.00, constant: 0.0)
            let trailing = NSLayoutConstraint(item: maskingView, attribute: .trailing, relatedBy: .equal, toItem: containerView, attribute: .trailing, multiplier: 1.00, constant: 0.0)
            let top = topLayoutConstraint(view: maskingView, presentationContext: presentationContext)
            let bottom = bottomLayoutConstraint(view: maskingView, presentationContext: presentationContext)
            containerView.addConstraints([top, leading, bottom, trailing])
        }
        do {
            switch config.presentationStyle {
            case .top:
                animator = AnimatorTopBottom(view: view, toContainer: maskingView, inContext: presentationContext.viewControllerValue(), isTop: true)
            case .bottom:
                animator = AnimatorTopBottom(view: view, toContainer: maskingView, inContext: presentationContext.viewControllerValue(), isTop: false)
            case .custom(let animator):
                self.animator = animator((view: view, container: maskingView, context: presentationContext.viewControllerValue()))
            }

            animator?.delegate = self
            panRecognizer.delegate = animator
        }
        containerView.layoutIfNeeded()
        if config.interactiveHide {
            view.addGestureRecognizer(panRecognizer)
        }
        installInteractive()
        installAccessibility()
    }

    private func installInteractive() {
        guard config.dimMode.modal else { return }
        if config.dimMode.interactive {
            maskingView.tappedHander = { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.interactivelyHidden = true
                strongSelf.delegate?.hide(presenter: strongSelf)
            }
        } else {
            // There's no action to take, but the presence of
            // a tap handler prevents interaction with underlying views.
            maskingView.tappedHander = { }
        }
    }

    func installAccessibility() {
        var elements: [NSObject] = []
        if let accessibleMessage = view as? AccessibleMessage {
            if let message = accessibleMessage.accessibilityMessage {
                let element = accessibleMessage.accessibilityElement ?? view
                element.isAccessibilityElement = true
                if element.accessibilityLabel == nil {
                    element.accessibilityLabel = message
                }
                elements.append(element)
            }
            if let additional = accessibleMessage.additonalAccessibilityElements {
                elements += additional
            }
        }
        if config.dimMode.interactive {
            let dismissView = UIView(frame: maskingView.bounds)
            dismissView.translatesAutoresizingMaskIntoConstraints = true
            dismissView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            maskingView.addSubview(dismissView)
            maskingView.sendSubview(toBack: dismissView)
            dismissView.isUserInteractionEnabled = false
            dismissView.isAccessibilityElement = true
            dismissView.accessibilityLabel = config.dimModeAccessibilityLabel
            dismissView.accessibilityTraits = UIAccessibilityTraitButton
            elements.append(dismissView)
        }
        if config.dimMode.modal {
            maskingView.accessibilityViewIsModal = true
        }
        maskingView.accessibleElements = elements
    }

    private var becomeKeyWindow: Bool {
        if config.becomeKeyWindow == .some(true) { return true }
        switch config.dimMode {
        case .gray, .color, .blur:
            // Should become key window in modal presentation style
            // for proper VoiceOver handling.
            return true
        case .none:
            return false
        }
    }

    private func viewInterferesWithStatusBar(_ view: UIView) -> Bool {
        guard let window = view.window else { return false }
        let statusBarFrame = UIApplication.shared.statusBarFrame
        let statusBarWindowFrame = window.convert(statusBarFrame, from: nil)
        let statusBarViewFrame = view.convert(statusBarWindowFrame, from: nil)
        return statusBarViewFrame.intersects(view.bounds)
    }
    
    func topLayoutConstraint(view: UIView, presentationContext: PresentationContext) -> NSLayoutConstraint {
    if case .top = config.presentationStyle, let nav = presentationContext.viewControllerValue() as? UINavigationController, nav.sm_isVisible(view: nav.navigationBar) {
            return NSLayoutConstraint(item: view, attribute: .top, relatedBy: .equal, toItem: nav.navigationBar, attribute: .bottom, multiplier: 1.00, constant: 0.0)
        }
        return NSLayoutConstraint(item: view, attribute: .top, relatedBy: .equal, toItem: presentationContext.viewValue(), attribute: .top, multiplier: 1.00, constant: 0.0)
    }

    func bottomLayoutConstraint(view: UIView, presentationContext: PresentationContext) -> NSLayoutConstraint {
        if case .bottom = config.presentationStyle, let tab = presentationContext.viewControllerValue() as? UITabBarController, tab.sm_isVisible(view: tab.tabBar) {
            return NSLayoutConstraint(item: view, attribute: .bottom, relatedBy: .equal, toItem: tab.tabBar, attribute: .top, multiplier: 1.00, constant: 0.0)
        }
        return NSLayoutConstraint(item: view, attribute: .bottom, relatedBy: .equal, toItem: presentationContext.viewValue(), attribute: .bottom, multiplier: 1.00, constant: 0.0)
    }

    /*
     MARK: - Showing and hiding
     */

    func showAnimation(completion: @escaping (_ completed: Bool) -> Void) {

        showViewAnimation(completion: completion)

        func dim(_ color: UIColor) {
            self.maskingView.backgroundColor = UIColor.clear
            UIView.animate(withDuration: 0.2, animations: {
                self.maskingView.backgroundColor = color
            })
        }

        func blur(style: UIBlurEffectStyle, alpha: CGFloat) {
            let blurView = UIVisualEffectView(effect: nil)
            blurView.alpha = alpha
            maskingView.backgroundView = blurView
            UIView.animate(withDuration: 0.3) {
                blurView.effect = UIBlurEffect(style: style)
            }
        }

        switch config.dimMode {
        case .none:
            break
        case .gray:
            dim(UIColor(white: 0, alpha: 0.3))
        case .color(let color, _):
            dim(color)
        case .blur(let style, let alpha, _):
            blur(style: style, alpha: alpha)
        }
    }


    func showViewAnimation(completion: @escaping (_ completed: Bool) -> Void) {
        guard let animator = animator else {
            completion(false)
            return
        }

        animator.showViewAnimation(completion: { completed in
            completion(completed)
        })
    }

    var isHiding = false

    func hide(completion: @escaping (_ completed: Bool) -> Void) {
        guard let animator = animator else {
            completion(false)
            return
        }
        isHiding = true
        self.config.eventListeners.forEach { $0(.willHide) }
        animator.hide(completion: { completed in
            if let viewController = self.presentationContext.viewControllerValue() as? WindowViewController {
                viewController.uninstall()
            }
            self.maskingView.removeFromSuperview()
            completion(completed)
            self.config.eventListeners.forEach { $0(.didHide) }
        })

        func undim() {
            UIView.animate(withDuration: 0.2, delay: 0, options: .beginFromCurrentState, animations: {
                self.maskingView.backgroundColor = UIColor.clear
            }, completion: nil)
        }

        func unblur() {
            guard let view = maskingView.backgroundView as? UIVisualEffectView else { return }
            UIView.animate(withDuration: 0.2, delay: 0, options: .beginFromCurrentState, animations: { 
                view.effect = nil
            }, completion: nil)
        }

        switch config.dimMode {
        case .none:
            break
        case .gray:
            undim()
        case .color:
            undim()
        case .blur:
            unblur()
        }
    }

    @objc func pan(pan: UIPanGestureRecognizer) {
        animator?.pan(pan)
    }

    // MARK - AnimatorDelegate

    func hide(presenter: Animator) {
        interactivelyHidden = true
        delegate?.hide(presenter: self)
    }

    func panStarted(presenter: Animator) {
        delegate?.panStarted(presenter: self)
    }

    func panEnded(presenter: Animator) {
        delegate?.panEnded(presenter: self)
    }
}

public protocol Animator: UIGestureRecognizerDelegate {
    weak var delegate: AnimatorDelegate? { get set }

    init(view: UIView, toContainer container: UIView, inContext context: UIViewController?)
    func showViewAnimation(completion: @escaping (_ completed: Bool) -> Void)
    func hide(completion: @escaping (_ completed: Bool) -> Void)
    func pan(_ pan: UIPanGestureRecognizer)
}

public protocol AnimatorDelegate: class {
    func hide(presenter: Animator)
    func panStarted(presenter: Animator)
    func panEnded(presenter: Animator)
}

public class AnimatorTopBottom: NSObject, Animator {

    private let translationConstraint: NSLayoutConstraint
    private let view: UIView
    private let context: UIViewController?
    private let isTop: Bool
    public weak var delegate: AnimatorDelegate? = nil

    public required convenience init(view: UIView, toContainer container: UIView, inContext context: UIViewController?) {
        self.init(view: view, toContainer: container, inContext: context, isTop: true)
    }

    public required init(view: UIView, toContainer container: UIView, inContext context: UIViewController?, isTop: Bool) {
        self.isTop = isTop
        self.view = view
        self.context = context
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        let leading = NSLayoutConstraint(item: view, attribute: .leading, relatedBy: .equal, toItem: container, attribute: .leading, multiplier: 1.00, constant: 0.0)
        let trailing = NSLayoutConstraint(item: view, attribute: .trailing, relatedBy: .equal, toItem: container, attribute: .trailing, multiplier: 1.00, constant: 0.0)
        let attribute: NSLayoutAttribute = isTop ? .top : .bottom
        translationConstraint = NSLayoutConstraint(item: isTop ? view : container, attribute: attribute, relatedBy: .equal, toItem: isTop ? container : view, attribute: attribute, multiplier: 1.00, constant: 0.0)

        container.addConstraints([leading, trailing, translationConstraint])
        if let adjustable = view as? MarginAdjustable {
            var top: CGFloat = 0.0
            var bottom: CGFloat = 0.0
            if isTop {
                top += adjustable.bounceAnimationOffset
                if !UIApplication.shared.isStatusBarHidden {
                    if let vc = context as? WindowViewController {
                        if vc.windowLevel == UIWindowLevelNormal {
                            top += adjustable.statusBarOffset
                        }
                    } else if let vc = context as? UINavigationController {
                        if !vc.sm_isVisible(view: vc.navigationBar) {
                            top += adjustable.statusBarOffset
                        }
                    } else {
                        top += adjustable.statusBarOffset
                    }
                }
            } else {
                bottom += adjustable.bounceAnimationOffset
            }
            view.layoutMargins = UIEdgeInsets(top: top, left: 0.0, bottom: bottom, right: 0.0)
        }
        let size = view.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
        translationConstraint.constant -= size.height
    }

    fileprivate var bounceOffset: CGFloat {
        var bounceOffset: CGFloat = 5.0
        if let adjustable = view as? MarginAdjustable {
            bounceOffset = adjustable.bounceAnimationOffset
        }
        return bounceOffset
    }

    public func showViewAnimation(completion: @escaping (_ completed: Bool) -> Void) {
        // Cap the initial velocity at zero because the bounceOffset may not be great
        // enough to allow for greater bounce induced by a quick panning motion.
        let animationDistance = translationConstraint.constant + bounceOffset
        let initialSpringVelocity = animationDistance == 0.0 ? 0.0 : min(0.0, closeSpeed / animationDistance)
        UIView.animate(
                       withDuration: 0.4,
                       delay: 0.0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: initialSpringVelocity,
                       options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction],
                       animations: {
            self.translationConstraint.constant = -self.bounceOffset
            self.view.superview?.layoutIfNeeded()
        },
                       completion: { completed in
            completion(completed)
        }
        )
    }

    public func hide(completion: @escaping (_ completed: Bool) -> Void) {

        UIView.animate(
                       withDuration: 0.2,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseIn],
                       animations: {
            let size = self.view.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
            self.translationConstraint.constant -= size.height
            self.view.superview?.layoutIfNeeded()
        },
                       completion: { completed in

            completion(completed)
        }
        )
    }

    /*
     MARK: - Swipe to close
     */

    fileprivate var closing = false
    fileprivate var closeSpeed: CGFloat = 0.0
    fileprivate var closePercent: CGFloat = 0.0
    fileprivate var panTranslationY: CGFloat = 0.0

    @objc public func pan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .changed:
            let backgroundView = panBackgroundView
            let backgroundHeight = backgroundView.bounds.height - bounceOffset

            guard backgroundHeight > 0 else { return }

            let point = pan.location(ofTouch: 0, in: backgroundView)
            var velocity = pan.velocity(in: backgroundView)
            var translation = pan.translation(in: backgroundView)
            if isTop {
                velocity.y *= -1.0
                translation.y *= -1.0
            }
            if !closing {
                if backgroundView.bounds.contains(point) && velocity.y > 0.0 && velocity.x / velocity.y < 5.0 {
                    closing = true
                    pan.setTranslation(CGPoint.zero, in: backgroundView)
                    delegate?.panStarted(presenter: self)
                }
            }
            if !closing { return }
            let translationAmount = -bounceOffset - max(0.0, translation.y)
            translationConstraint.constant = translationAmount
            closeSpeed = velocity.y
            closePercent = translation.y / backgroundHeight
            panTranslationY = translation.y
        case .ended, .cancelled:
            if closeSpeed > 750.0 || closePercent > 0.33 {
                delegate?.hide(presenter: self)
            } else {
                closing = false
                closeSpeed = 0.0
                closePercent = 0.0
                panTranslationY = 0.0
                showViewAnimation(completion: { (completed) in
                    self.delegate?.panEnded(presenter: self)
                })
            }
        default:
            break
        }
    }

    fileprivate var panBackgroundView: UIView {
        if let view = view as? BackgroundViewable {
            return view.backgroundView
        } else {
            return view
        }
    }

    fileprivate func shouldBeginPan(_ pan: UIGestureRecognizer) -> Bool {
        let backgroundView = panBackgroundView
        let point = pan.location(ofTouch: 0, in: backgroundView)
        return backgroundView.bounds.contains(point)
    }

    /*
     MARK: - UIGestureRecognizerDelegate
     */
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self {
            return shouldBeginPan(gestureRecognizer)
        }
        return true
    }
}

