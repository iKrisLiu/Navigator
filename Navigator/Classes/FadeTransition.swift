//
//  FadeTransition.swift
//  Navigator
//
//  Created by Kris Liu on 2019/5/8.
//  Copyright © 2019 Crescent. All rights reserved.
//

import UIKit

class FadeTransition: Transition {
    
    override func animatePresentingTransition(from fromView: UIView?, to toView: UIView?) {
        let containerView = transitionContext.containerView
        
        if isShow {
            if let toView = toView {
                containerView.addSubview(toView)
                toView.alpha = 0.0
            }
            
            UIView.animate(withDuration: animationDuration, animations: {
                toView?.alpha = 1.0
            }, completion: { _ in
                self.transitionContext.completeTransition(!self.transitionContext.transitionWasCancelled)
            })
        } else {
            if let toView = toView, let fromView = fromView {
                containerView.insertSubview(toView, belowSubview: fromView)
            }
            
            guard let fromView = fromView else {
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                return
            }
            
            UIView.animate(withDuration: animationDuration, animations: {
                fromView.alpha = 0.0
            }, completion: { _ in
                self.transitionContext.completeTransition(!self.transitionContext.transitionWasCancelled)
            })
        }
    }
}

extension FadeTransition {
    
    override func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return PopoverPresentationController(presentedViewController: presented, presenting: presenting, sourceRect: sourceRect, dismissWhenTapOutside: false)
    }
}
