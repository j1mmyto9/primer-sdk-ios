//
//  RootViewController.swift
//  PrimerSDK
//
//  Created by Carl Eriksson on 11/01/2021.
//

#if canImport(UIKit)

import UIKit

internal class RootViewController: UIViewController {

    weak var transitionDelegate: TransitionDelegate?

    lazy var backdropView: UIView = UIView()

    let mainView = UIView()
    
    var routes: [UIViewController] = []
    var heights: [CGFloat] = []

    weak var topConstraint: NSLayoutConstraint?
    weak var bottomConstraint: NSLayoutConstraint?
    weak var heightConstraint: NSLayoutConstraint?

    var hasSetPointOrigin = false
    var currentHeight: CGFloat = 0

    init() {
        super.init(nibName: nil, bundle: nil)
        
        let settings: PrimerSettingsProtocol = DependencyContainer.resolve()
        if !settings.isFullScreenOnly {
            self.modalPresentationStyle = .custom
            self.transitioningDelegate = self
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        log(logLevel: .debug, message: "🧨 destroyed: \(self.self)")
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        let settings: PrimerSettingsProtocol = DependencyContainer.resolve()
        let theme: PrimerThemeProtocol = DependencyContainer.resolve()
        
        switch Primer.shared.flow.internalSessionFlow {
        case .vaultKlarna,
             .vaultPayPal,
             .checkoutWithKlarna:
            mainView.backgroundColor = settings.isInitialLoadingHidden ? .clear : theme.colorTheme.main1
        default:
            mainView.backgroundColor = theme.colorTheme.main1
        }

        view.addSubview(backdropView)
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainView)
        backdropView.pin(to: view)

        if #available(iOS 13.0, *) {
            mainView.clipsToBounds = true
            mainView.layer.maskedCorners = [.layerMinXMinYCorner,.layerMaxXMinYCorner]
            mainView.layer.cornerRadius = theme.cornerRadiusTheme.sheetView
        }

        mainView.translatesAutoresizingMaskIntoConstraints = false
        mainView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        bottomConstraint = mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        bottomConstraint?.isActive = true
        
        if settings.isFullScreenOnly {
            topConstraint = mainView.topAnchor.constraint(equalTo: view.topAnchor)
            topConstraint?.isActive = true
        } else {
            heightConstraint = mainView.heightAnchor.constraint(equalToConstant: 400)
            heightConstraint?.isActive = true
            self.modalPresentationStyle = .custom
            self.transitioningDelegate = transitionDelegate
            let panGesture = UIPanGestureRecognizer(
                target: self,
                action: #selector(panGestureRecognizerAction)
            )
            mainView.addGestureRecognizer(panGesture)
        }

        bindFirstFlowView()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        backdropView.addGestureRecognizer(tapGesture)
        addKeyboardObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if isBeingDismissed {
            let settings: PrimerSettingsProtocol = DependencyContainer.resolve()
            // FIXME: Quick fix for now. It still should be handled by our logic instead of
            // the view controller's life-cycle.
            settings.onCheckoutDismiss()
        }
    }

    private func bindFirstFlowView() {
        let state: AppStateProtocol = DependencyContainer.resolve()
        let router: RouterDelegate = DependencyContainer.resolve()
        let theme: PrimerThemeProtocol = DependencyContainer.resolve()
        
        switch Primer.shared.flow.internalSessionFlow {
        case .checkout:
            router.show(.vaultCheckout)
        case .vaultCard, .checkoutWithCard:
            router.show(.form(type: .cardForm(theme: theme)))
        case .vaultPayPal,
             .checkoutWithPayPal:
            router.show(.oAuth(host: .paypal))
        case .vaultDirectDebit:
            router.show(
                .form(
                    type: .iban(mandate: state.directDebitMandate, popOnComplete: true),
                    closeOnSubmit: false)
            )
        case .checkoutWithKlarna:
            router.show(.oAuth(host: .klarna))
        case .vaultKlarna:
            router.show(.oAuth(host: .klarna))
        case .vault:
            router.show(.vaultCheckout)
        case .checkoutWithApplePay:
            break
        }
    }
    
    private func addKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow2),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide2),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc
    func keyboardWillShow2(notification: NSNotification) {
        if let keyboardSize = (
            notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        )?.cgRectValue {
            let newConstant = -keyboardSize.height
            let duration = bottomConstraint!.constant.distance(to: newConstant) < 100 ? 0.0 : 0.5
            bottomConstraint!.constant = newConstant
            if currentHeight + keyboardSize.height > UIScreen.main.bounds.height - 40 {
                currentHeight = UIScreen.main.bounds.height - (40 + keyboardSize.height)
                heightConstraint?.constant = UIScreen.main.bounds.height - (40 + keyboardSize.height)
            }
            UIView.animate(withDuration: duration) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc
    func keyboardWillHide2(notification: NSNotification) {
        if let keyboardSize = (
            notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        )?.cgRectValue {
            bottomConstraint?.constant += keyboardSize.height
            UIView.animate(withDuration: 0.5) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func panGestureRecognizerAction(sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: view)

        heightConstraint?.constant = currentHeight - translation.y

        if currentHeight - translation.y < 220 {
            UIView.animate(withDuration: 0.3) { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.currentHeight = 280
                strongSelf.heightConstraint?.constant = 280
                strongSelf.view.layoutIfNeeded()
            }
            return
        }

        if sender.state == .ended {
            if currentHeight - translation.y > UIScreen.main.bounds.height - 80 {
                UIView.animate(withDuration: 0.3) { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.currentHeight = UIScreen.main.bounds.height - 80
                    strongSelf.heightConstraint.setFullScreen()
                    strongSelf.view.layoutIfNeeded()
                }
            } else {
                currentHeight = heightConstraint?.constant ?? 400
            }
        }
    }
}

internal extension Optional where Wrapped == NSLayoutConstraint {
    mutating func setFullScreen() {
        self?.constant = UIScreen.main.bounds.height - 40
    }
}

extension RootViewController: UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        PresentationController(presentedViewController: presented, presenting: presenting)
    }
}

#endif
