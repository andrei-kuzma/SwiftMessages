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
    init() { }
}

protocol PresenterDelegate: class {
    func hide(presenter presenter: Presenter)
    func panStarted(presenter presenter: Presenter)
    func panEnded(presenter presenter: Presenter)
}

class Presenter: NSObject, AnimatorDelegate {

    let config: SwiftMessages.Config
    let view: UIView
    weak var delegate: PresenterDelegate?
    let maskingView = PassthroughView()
    let presentationContext = Weak<UIViewController>()
    let panRecognizer: UIPanGestureRecognizer

    var animator: Animator? = nil
    init(config: SwiftMessages.Config, view: UIView, delegate: PresenterDelegate) {
        self.config = config
        self.view = view
        self.delegate = delegate
        panRecognizer = UIPanGestureRecognizer()
        super.init()
        panRecognizer.addTarget(self, action: #selector(Presenter.pan(_:)))
        maskingView.clipsToBounds = true
    }

    var id: String? {
        let identifiable = view as? Identifiable
        return identifiable?.id
    }

    var pauseDuration: NSTimeInterval? {
        let duration: NSTimeInterval?
        switch self.config.duration {
        case .Automatic:
            duration = 2.0
        case .Seconds(let seconds):
            duration = seconds
        case .Forever:
            duration = nil
        }
        return duration
    }

    func show(completion completion: (completed: Bool) -> Void) throws {
        try presentationContext.value = getPresentationContext()
        install()
        showAnimation(completion: completion)
    }

    func getPresentationContext() throws -> UIViewController {

        func newWindowViewController(windowLevel: UIWindowLevel) -> UIViewController {
            let viewController = WindowViewController(windowLevel: windowLevel)
            if windowLevel == UIWindowLevelNormal {
                viewController.statusBarStyle = config.preferredStatusBarStyle
            }
            return viewController
        }

        switch config.presentationContext {
        case .Automatic:
            if let rootViewController = UIApplication.sharedApplication().keyWindow?.rootViewController {
                return rootViewController.sm_selectPresentationContextTopDown(config.presentationStyle)
            } else {
                throw Error.NoRootViewController
            }
        case .Window(let level):
            return newWindowViewController(level)
        case .ViewController(let viewController):
            return viewController.sm_selectPresentationContextBottomUp(config.presentationStyle)
        }
    }

    /*
     MARK: - Installation
     */

    func install() {
        guard let presentationContext = presentationContext.value else { return }
        if let windowViewController = presentationContext as? WindowViewController {
            windowViewController.install()
        }
        let containerView = presentationContext.view
        do {
            maskingView.translatesAutoresizingMaskIntoConstraints = false
            if let nav = presentationContext as? UINavigationController {
                containerView.insertSubview(maskingView, belowSubview: nav.navigationBar)
            } else if let tab = presentationContext as? UITabBarController {
                containerView.insertSubview(maskingView, belowSubview: tab.tabBar)
            } else {
                containerView.addSubview(maskingView)
            }
            let leading = NSLayoutConstraint(item: maskingView, attribute: .Leading, relatedBy: .Equal, toItem: containerView, attribute: .Leading, multiplier: 1.00, constant: 0.0)
            let trailing = NSLayoutConstraint(item: maskingView, attribute: .Trailing, relatedBy: .Equal, toItem: containerView, attribute: .Trailing, multiplier: 1.00, constant: 0.0)
            let top = topLayoutConstraint(view: maskingView, presentationContext: presentationContext)
            let bottom = bottomLayoutConstraint(view: maskingView, presentationContext: presentationContext)
            containerView.addConstraints([top, leading, bottom, trailing])
        }
        do {

            switch config.presentationStyle {
            case .Top:
                animator = AnimatorTopBottom(view: view, toContainer: maskingView, inContext: presentationContext, isTop: true)
            case .Bottom:
                animator = AnimatorTopBottom(view: view, toContainer: maskingView, inContext: presentationContext, isTop: false)
            case .Custom(let animator):
                self.animator = animator()
            }

            animator?.delegate = self
            panRecognizer.delegate = animator
        }
        containerView.layoutIfNeeded()
        if config.interactiveHide {
            view.addGestureRecognizer(panRecognizer)
        }
        do {

            func setupInteractive(interactive: Bool) {
                if interactive {
                    maskingView.tappedHander = { [weak self] in
                        guard let strongSelf = self else { return }
                        self?.delegate?.hide(presenter: strongSelf)
                    }
                } else {
                    // There's no action to take, but the presence of
                    // a tap handler prevents interaction with underlying views.
                    maskingView.tappedHander = { }
                }
            }

            switch config.dimMode {
            case .None:
                break
            case .Gray(let interactive):
                setupInteractive(interactive)
            case .Color(_, let interactive):
                setupInteractive(interactive)
            }
        }
    }

    func topLayoutConstraint(view view: UIView, presentationContext: UIViewController) -> NSLayoutConstraint {
        if case .Top = config.presentationStyle, let nav = presentationContext as? UINavigationController where nav.sm_isVisible(view: nav.navigationBar) {
            return NSLayoutConstraint(item: view, attribute: .Top, relatedBy: .Equal, toItem: nav.navigationBar, attribute: .Bottom, multiplier: 1.00, constant: 0.0)
        }
        return NSLayoutConstraint(item: view, attribute: .Top, relatedBy: .Equal, toItem: presentationContext.view, attribute: .Top, multiplier: 1.00, constant: 0.0)
    }

    func bottomLayoutConstraint(view view: UIView, presentationContext: UIViewController) -> NSLayoutConstraint {
        if case .Bottom = config.presentationStyle, let tab = presentationContext as? UITabBarController where tab.sm_isVisible(view: tab.tabBar) {
            return NSLayoutConstraint(item: view, attribute: .Bottom, relatedBy: .Equal, toItem: tab.tabBar, attribute: .Top, multiplier: 1.00, constant: 0.0)
        }
        return NSLayoutConstraint(item: view, attribute: .Bottom, relatedBy: .Equal, toItem: presentationContext.view, attribute: .Bottom, multiplier: 1.00, constant: 0.0)
    }

    /*
     MARK: - Showing and hiding
     */

    func showAnimation(completion completion: (completed: Bool) -> Void) {

        showViewAnimation(completion: completion)

        func dim(color: UIColor) {
            self.maskingView.backgroundColor = UIColor.clearColor()
            UIView.animateWithDuration(0.2, animations: {
                self.maskingView.backgroundColor = color
            })
        }

        switch config.dimMode {
        case .None:
            break
        case .Gray:
            dim(UIColor(white: 0, alpha: 0.3))
        case .Color(let color, _):
            dim(color)
        }
    }

    func showViewAnimation(completion completion: (completed: Bool) -> Void) {
        guard let animator = animator else {
            completion(completed: false)
            return
        }

        animator.showViewAnimation(completion: { [weak self] completed in
            completion(completed: completed)
        })
    }

    func hide(completion completion: (completed: Bool) -> Void) {
        guard let animator = animator else {
            completion(completed: false)
            return
        }
        animator.hide(completion: { completed in
            if let viewController = self.presentationContext.value as? WindowViewController {
                viewController.uninstall()
            }
            self.maskingView.removeFromSuperview()
            completion(completed: completed)
        })

        func undim() {
            UIView.animateWithDuration(0.2, animations: {
                self.maskingView.backgroundColor = UIColor.clearColor()
            })
        }

        switch config.dimMode {
        case .None:
            break
        case .Gray:
            undim()
        case .Color:
            undim()
        }
    }

    @objc func pan(pan: UIPanGestureRecognizer) {
        animator?.pan(pan)
    }

    // MARK - AnimatorDelegate

    func hide(presenter presenter: Animator) {
        delegate?.hide(presenter: self)
    }

    func panStarted(presenter presenter: Animator) {
        delegate?.panStarted(presenter: self)
    }

    func panEnded(presenter presenter: Animator) {
        delegate?.panEnded(presenter: self)
    }

}

public protocol Animator: UIGestureRecognizerDelegate {
    weak var delegate: AnimatorDelegate? { get set }

    init(view: UIView, toContainer container: UIView, inContext context: UIViewController)
    func showViewAnimation(completion completion: (completed: Bool) -> Void)
    func hide(completion completion: (completed: Bool) -> Void)
    func pan(pan: UIPanGestureRecognizer)
}

public protocol AnimatorDelegate: class {
    func hide(presenter presenter: Animator)
    func panStarted(presenter presenter: Animator)
    func panEnded(presenter presenter: Animator)

}

public class AnimatorTopBottom: NSObject, Animator {

    private let translationConstraint: NSLayoutConstraint
    private let view: UIView
    private let context: UIViewController
    private let isTop: Bool
    public weak var delegate: AnimatorDelegate? = nil

    public required convenience init(view: UIView, toContainer container: UIView, inContext context: UIViewController) {
        self.init(view: view, toContainer: container, inContext: context, isTop: true)
    }

    public required init(view: UIView, toContainer container: UIView, inContext context: UIViewController, isTop: Bool) {
        self.isTop = isTop
        self.view = view
        self.context = context
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        let leading = NSLayoutConstraint(item: view, attribute: .Leading, relatedBy: .Equal, toItem: container, attribute: .Leading, multiplier: 1.00, constant: 0.0)
        let trailing = NSLayoutConstraint(item: view, attribute: .Trailing, relatedBy: .Equal, toItem: container, attribute: .Trailing, multiplier: 1.00, constant: 0.0)
        let attribute: NSLayoutAttribute = isTop ?.Top: .Bottom
        translationConstraint = NSLayoutConstraint(item: isTop ? view : container, attribute: attribute, relatedBy: .Equal, toItem: isTop ? container : view, attribute: attribute, multiplier: 1.00, constant: 0.0)

        container.addConstraints([leading, trailing, translationConstraint])
        if let adjustable = view as? MarginAdjustable {
            var top: CGFloat = 0.0
            var bottom: CGFloat = 0.0
            if isTop {
                top += adjustable.bounceAnimationOffset
                if !UIApplication.sharedApplication().statusBarHidden {
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
        let size = view.systemLayoutSizeFittingSize(UILayoutFittingCompressedSize)
        translationConstraint.constant -= size.height
    }

    private var bounceOffset: CGFloat {
        var bounceOffset: CGFloat = 5.0
        if let adjustable = view as? MarginAdjustable {
            bounceOffset = adjustable.bounceAnimationOffset
        }
        return bounceOffset
    }

    private var panBackgroundView: UIView {
        if let view = view as? BackgroundViewable {
            return view.backgroundView
        } else {
            return view
        }
    }

    public func showViewAnimation(completion completion: (completed: Bool) -> Void) {
        // Cap the initial velocity at zero because the bounceOffset may not be great
        // enough to allow for greater bounce induced by a quick panning motion.
        let animationDistance = translationConstraint.constant + bounceOffset
        let initialSpringVelocity = animationDistance == 0.0 ? 0.0 : min(0.0, closeSpeed / animationDistance)
        UIView.animateWithDuration(
            0.4,
            delay: 0.0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: initialSpringVelocity,
            options: [.BeginFromCurrentState, .CurveLinear, .AllowUserInteraction],
            animations: {
                self.translationConstraint.constant = -self.bounceOffset
                self.view.superview?.layoutIfNeeded()
            },
            completion: { completed in

                print(self.view.convertRect(self.view.frame, toView: self.view.window))
                completion(completed: completed)
            }
        )
    }

    public func hide(completion completion: (completed: Bool) -> Void) {

        UIView.animateWithDuration(
            0.2,
            delay: 0,
            options: [.BeginFromCurrentState, .CurveEaseIn],
            animations: {
                let size = self.view.systemLayoutSizeFittingSize(UILayoutFittingCompressedSize)
                self.translationConstraint.constant -= size.height
                self.view.superview?.layoutIfNeeded()
            },
            completion: { completed in

                completion(completed: completed)
            }
        )
    }

    /*
     MARK: - Swipe to close
     */

    private var closing = false
    private var closeSpeed: CGFloat = 0.0
    private var closePercent: CGFloat = 0.0
    private var panTranslationY: CGFloat = 0.0

    public func pan(pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .Changed:
            let backgroundView = panBackgroundView
            let backgroundHeight = backgroundView.bounds.height - bounceOffset
            if backgroundHeight <= 0 { return }
            let point = pan.locationOfTouch(0, inView: backgroundView)
            var velocity = pan.velocityInView(backgroundView)
            var translation = pan.translationInView(backgroundView)
            if isTop {
                velocity.y *= -1.0
                translation.y *= -1.0
            }
            if !closing {
                if CGRectContainsPoint(backgroundView.bounds, point) && velocity.y > 0.0 && velocity.x / velocity.y < 5.0 {
                    closing = true
                    pan.setTranslation(CGPointZero, inView: backgroundView)
                    delegate?.panStarted(presenter: self)
                }
            }
            if !closing { return }
            let translationAmount = -bounceOffset - max(0.0, translation.y)
            translationConstraint.constant = translationAmount
            closeSpeed = velocity.y
            closePercent = translation.y / backgroundHeight
            panTranslationY = translation.y
        case .Ended, .Cancelled:
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

    private func shouldBeginPan(pan: UIGestureRecognizer) -> Bool {
        let backgroundView = panBackgroundView
        let point = pan.locationOfTouch(0, inView: backgroundView)
        return CGRectContainsPoint(backgroundView.bounds, point)
    }

    /*
     MARK: - UIGestureRecognizerDelegate
     */

    public func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.delegate === self {
            return shouldBeginPan(gestureRecognizer)
        }
        return true
    }
}
