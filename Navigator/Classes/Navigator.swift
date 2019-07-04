//
//  Navigator.swift
//  Navigator
//
//  Created by Kris Liu on 5/11/18.
//  Copyright © 2018 Syzygy. All rights reserved.
//

import UIKit
import os.log

@objc public class Navigator: NSObject {
    
    /// Use root navigator to open the initial view controller when App launch
    /// Also can use it to open any view controller for quick launch and debug, only need provide VC required data.
    @objc public static let root = Navigator()
    
    /// The default navigation controller which is used for containing content view controller when navigator mode is `present`.
    @objc public static var defaultNavigationControllerClass = UINavigationController.self
    
    /// - Note: Only if open App via deep linking, use the current navigator. It will append new page to current vc stack.
    @objc public static var current: Navigator {
        var navigator = _current
        if let tabVC = _current.topViewController?.tabBarController {
            if let splitVC = tabVC.selectedViewController as? UISplitViewController {
                navigator = splitVC.viewControllers.last?.navigator ?? _current
            } else {
                navigator = tabVC.selectedViewController?.navigator ?? _current
            }
        } else if let splitVC = _current.topViewController?.splitViewController {
            navigator = splitVC.viewControllers.last?.navigator ?? _current
        }
        
        return navigator
    }
    internal static var _current = root
    
    /// - Note: Must set the window variable first, then call navigator's show method.
    @objc public weak var window: UIWindow?
    @objc internal weak var rootViewController: UIViewController? {
        willSet {
            window?.rootViewController = newValue
            window?.makeKeyAndVisible()
        }
    }
    
    @objc public init(rootViewController: UIViewController? = nil) {
        super.init()
        
        if let vc = rootViewController {
            pushStack(vc)
            self.rootViewController = vc
        }
    }
    
    // Private Properties
    var stack: NSMapTable<NSNumber, UIViewController> = NSMapTable.weakToWeakObjects()
    
    var showAnimated: Bool = true
    var dismissAnimated: Bool = true
    var showCompletion: CompletionBlock?
    var dismissCompletion: CompletionBlock?
    
    weak var showModel: DataModel?
    var dismissData: Any?
    
    var level: Int = 0  // Dismiss which level view controller, level 0 means that dismiss current view controller, level 1 is previous VC. (Default is 0)
    
    // Calculate stack level (0 from bottom) according to dismiss level (0 from top)
    func stackLevel(_ level: Int) -> Int {
        return level >= 0 ? stackCount - level - 1 : abs(level - 1) - 1
    }
}

// MARK: - Show or Dismiss
public extension Navigator {
    
    typealias CompletionBlock = (() -> Void)
    
    /// Show a view controller with required data in dictionary.
    /// Build a linked node with data to handle universal link or deep link (A => B => C => D)
    /// - Note:
    ///   If the view controller is swift class, must add module name as prefix for class name.
    ///
    /// - Parameters:
    ///   - data: The data is required for view controller, can be any type. At least VC class name is required.
    ///   - animated: Whether show view controller with animation, default is true.
    ///   - completion: The optional callback to be executed after animation is completed.
    @objc func show(_ data: DataModel, animated: Bool = true, completion: CompletionBlock? = nil) {
        Navigator._current = self
        
        showModel = data
        showAnimated = animated
        showCompletion = completion
        
        if data.next != nil && data.mode == .reset {
            showDeepLinkViewControllers(data)
            data.next = nil     // Make sure linked all vc data models free
        } else {
            showViewControllers()
        }
    }
    
    /// Dismiss any view controller with optional data in dictionary.
    /// (A => B => C => D) -> dismiss(level: 1) -> (A => B)
    ///
    /// - Parameters:
    ///   - data: The data is passed to previous view controller, default is nil.
    ///   - level: Which view controller will be dismissed, default 0 is current VC, 1 is previous one VC.
    ///            If level is equal to -1, it will dimisss to root view controller of current navigator.
    ///   - animated: Whether dismiss view controller with animation, default is true.
    ///   - completion: The optional callback to be executed after animation is completed.
    @objc func dismiss(_ data: Any? = nil, level: Int = 0, animated: Bool = true, completion: CompletionBlock? = nil) {
        self.level = level
        
        dismissData = data
        dismissAnimated = animated
        dismissCompletion = completion
        
        dismissViewControllers()
    }
    
    /// Dismiss view controllers until the specified VC is at the top of the navigation stack.
    /// If there are many view controllers that are same name in the stack, it will dismiss all VCs until remains the first one.
    ///
    /// - Parameters:
    ///   - vcName: The VC that you want to be at the top of the stack. This VC must currently be on the navigation stack.
    ///   - data: The data is passed to previous view controller, default is nil.
    ///   - animated: Whether dismiss view controller with animation, default is true.
    ///   - completion: The optional callback to be executed after animation is completed.
    @objc func dismissTo(vcName: String, data: Any? = nil, animated: Bool = true, completion: CompletionBlock? = nil) {
        guard let level = stackIndex(of: vcName), level < stackCount - 1 else { return }
        
        dismiss(data, level: stackLevel(level + 1), animated: animated, completion: completion)
    }
    
    /// Dismiss view controllers until the specified VC is at the top of the navigation stack.
    /// If there are many view controllers that are same name in the stack, it will dismiss all VCs until remains the first one.
    ///
    /// - Parameters:
    ///   - vcClass: The VC that you want to be at the top of the stack. This VC must currently be on the navigation stack.
    ///   - data: The data is passed to previous view controller, default is nil.
    ///   - animated: Whether dismiss view controller with animation, default is true.
    ///   - completion: The optional callback to be executed after animation is completed.
    @objc func dismissTo(vcClass: UIViewController.Type, data: Any? = nil, animated: Bool = true, completion: CompletionBlock? = nil) {
        guard let level = stackIndex(of: NSStringFromClass(vcClass)), level < stackCount - 1 else { return }
        
        dismiss(data, level: stackLevel(level + 1), animated: animated, completion: completion)
    }
    
    /// Jump to any view controller only if the vc is already in the navigator stack.
    /// Can jump to another navigator's VC from one navigator. (e.g. jump to any tab in UITabBarController)
    ///
    /// - Parameter vcName: The view controller class name. If it is swift class, must add module name as prefix for class name.
    @objc class func goto(vcName: String) {
        guard let rootVC = root.rootViewController, !root.gotoViewControllerIfExisted(vcName) else { return }
        
        let viewControllers = childViewControllers(of: rootVC)
        
        for vc in viewControllers where vc.navigator != nil {
            if vc.navigator!.gotoViewControllerIfExisted(vcName) {
                break
            }
        }
    }
    
    @objc class func goto(vcClass: UIViewController.Type) {
        goto(vcName: NSStringFromClass(vcClass))
    }
}

// MARK: - Deep Link
public extension Navigator {
    
    /// Deep link to a view controller with required data in DataModel.
    /// Build a linked node with data to handle universal link or deep link (A => B => C => D)
    ///
    /// - Parameters:
    ///   - data: The data is required for view controller, can be any type. At least VC class name is required.
    ///   - animated: Whether show view controller with animation, default is true.
    ///   - completion: The optional callback to be executed after animation is completed.
    @objc func deepLink(_ data: DataModel, animated: Bool = true, completion: CompletionClosure? = nil) {
        guard topViewController?.ignoreDeepLinking == false else { return }
        
        if data.mode == .goto {
            Navigator.goto(vcName: data.vcName)
        } else {
            show(data)
        }
    }

    typealias DeepLinkHandler = ((URL) -> DataModel?)
    
    /// Use this method to open the specified resource. If the specified URL scheme is handled by another app, iOS launches that app and passes the URL to it.
    ///
    /// - Parameters:
    ///   - url: The resource identified by this URL may be local to the current app or it may be one that must be provided by a different app.
    ///          UIKit supports many common schemes, including the http, https, tel, facetime, and mailto schemes.
    ///   - handler: The handler is for parsing the url and return a data model for navigator show. If handler is nil, will open URL by UIApplication.
    @objc func open(url: URL, handler: DeepLinkHandler? = nil) {
        if let handler = handler {
            if let dataModel = handler(url) {
                self.deepLink(dataModel)
            }
        } else {
            UIApplication.shared.open(url)
        }
    }
    
    /// Returns a Boolean value indicating whether an app is available to handle a URL scheme.
    @objc class func canOpenURL(_ url: URL) -> Bool {
        return UIApplication.shared.canOpenURL(url)
    }
}

// MARK: - Send Data
public extension Navigator {
    
    /// Send data to previous any page before current page dismissed.
    /// The level parameter is same with dismiss method's level parameter.
    ///
    /// - Parameters:
    ///   - data: The data is passed to previous any view controller.
    ///   - level: Send data to which view controller, default 0 is current VC, 1 is previous one VC.
    ///            If level is equal to -1, it will send data to root view controller of current navigator.
    @objc func sendDataBeforeBack(_ data: Any?, level: Int = 0) {
        self.level = level
        
        guard let data = data, let poppedVC = popStack(from: stackLevel(level)) else { return }
        
        let toVC = topViewController ?? poppedVC
        p_sendDataBeforeBack(data, fromVC: poppedVC, toVC: toVC)
        
        pushStack(poppedVC)     // Need push back the VC because it hasn't been dismiss
    }
    
    /// Send data to previous one page after current page dismissed.
    /// If current page is already dismissed, only send data to previous one page, so can't assign level.
    /// In iOS, user can pop view controller by swipe to right on left screen edge. But can't catch the event.
    /// For this edge case, we can call this method in deinit() to solve data passing issue.
    ///
    /// - Parameter data: The data is passed to previous view controller.
    @objc func sendDataAfterBack(_ data: Any?) {
        guard let data = data else { return }
        guard let toVC = topViewController else { return }
        
        p_sendDataAfterBack(data, toVC: toVC)
    }
    
    @objc var topViewController: UIViewController? {
        return stackCount > 0 ? stack.object(forKey: (stackCount - 1) as NSNumber) : nil
    }
}

// MARK: - Navigator Mode
public extension Navigator {
    
    @objc(NavigatorMode)
    enum Mode: Int, CustomStringConvertible {
        /// Reset view controller stack when initialize a new VC or deep link
        case reset
        /// Change tab in tab controller
        case goto
        case push
        case present
        // The presentationStyle must be forced with `custom` when mode is overlay/popover
        case overlay
        case popover
        
        public var description: String {
            switch self {
            case .reset: return "reset"
            case .goto: return "goto"
            case .push: return "push"
            case .present: return "present"
            case .overlay: return "overlay"
            case .popover: return "popover"
            }
        }
    }
}
