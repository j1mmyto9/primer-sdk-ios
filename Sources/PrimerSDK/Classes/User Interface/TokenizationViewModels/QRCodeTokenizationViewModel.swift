//
//  QRCodeTokenizationViewModel.swift
//  PrimerSDK
//
//  Copyright © 2022 Primer API ltd. All rights reserved.
//

#if canImport(UIKit)

import SafariServices
import UIKit

class QRCodeTokenizationViewModel: WebRedirectPaymentMethodTokenizationViewModel {
    
    private var tokenizationService: TokenizationServiceProtocol?
    private var statusUrl: URL!
    internal var qrCode: String?
    private var resumeToken: String!
    
    deinit {
        tokenizationService = nil
        qrCode = nil
        log(logLevel: .debug, message: "🧨 deinit: \(self) \(Unmanaged.passUnretained(self).toOpaque())")
    }
    
    override func validate() throws {
        guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken, decodedJWTToken.isValid else {
            let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
            ErrorHandler.handle(error: err)
            throw err
        }
    }
    
    override func performPreTokenizationSteps() -> Promise<Void> {
        let event = Analytics.Event(
            eventType: .ui,
            properties: UIEventProperties(
                action: .click,
                context: Analytics.Event.Property.Context(
                    issuerId: nil,
                    paymentMethodType: self.config.type,
                    url: nil),
                extra: nil,
                objectType: .button,
                objectId: .select,
                objectClass: "\(Self.self)",
                place: .bankSelectionList))
        Analytics.Service.record(event: event)
        
        return Promise { seal in
            firstly {
                self.validateReturningPromise()
            }
            .then { () -> Promise<Void> in
                return self.handlePrimerWillCreatePaymentEvent(PrimerPaymentMethodData(type: self.config.type))
            }
            .done {
                seal.fulfill()
            }
            .catch { err in
                seal.reject(err)
            }
        }
    }
    
    override func performTokenizationStep() -> Promise<Void> {
        return Promise { seal in
            PrimerDelegateProxy.primerHeadlessUniversalCheckoutTokenizationDidStart(for: self.config.type)
            
            firstly {
                self.checkouEventsNotifierModule.fireDidStartTokenizationEvent()
            }
            .then { () -> Promise<PrimerPaymentMethodTokenData> in
                return self.tokenize()
            }
            .then { paymentMethodTokenData -> Promise<Void> in
                self.paymentMethodTokenData = paymentMethodTokenData
                return self.checkouEventsNotifierModule.fireDidFinishTokenizationEvent()
            }
            .done {
                seal.fulfill()
            }
            .catch { err in
                seal.reject(err)
            }
        }
    }
    
    override func performPostTokenizationSteps() -> Promise<Void> {
        return Promise { seal in
            seal.fulfill()
        }
    }
    
    override func presentPaymentMethodUserInterface() -> Promise<Void> {
        return Promise { seal in
            DispatchQueue.main.async {
                let qrcvc = QRCodeViewController(viewModel: self)
                self.willPresentPaymentMethodUI?()
                PrimerUIManager.primerRootViewController?.show(viewController: qrcvc)
                self.didPresentPaymentMethodUI?()
                seal.fulfill(())
            }
        }
    }
    
    override func awaitUserInput() -> Promise<Void> {
        return Promise { seal in
            let pollingModule = PollingModule(url: statusUrl)
            self.didCancel = {
                let err = PrimerError.cancelled(
                    paymentMethodType: self.config.type,
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                pollingModule.cancel(withError: err)
                return
            }
            
            firstly {
                pollingModule.start()
            }
            .done { resumeToken in
                self.resumeToken = resumeToken
                seal.fulfill()
            }
            .catch { err in
                seal.reject(err)
            }
        }
    }
    
    func cancel() {
        didCancel?()
    }
    
    override func tokenize() -> Promise<PrimerPaymentMethodTokenData> {
        return Promise { seal in
            guard let configId = config.id else {
                let err = PrimerError.invalidValue(key: "configuration.id", value: config.id, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                seal.reject(err)
                return
            }
            
            let sessionInfo = WebRedirectSessionInfo(locale: PrimerSettings.current.localeData.localeCode)
            
            let paymentInstrument = OffSessionPaymentInstrument(
                paymentMethodConfigId: configId,
                paymentMethodType: config.type,
                sessionInfo: sessionInfo)
            
            
            let requestBody = Request.Body.Tokenization(paymentInstrument: paymentInstrument)
            
            let tokenizationService: TokenizationServiceProtocol = TokenizationService()
            firstly {
                tokenizationService.tokenize(requestBody: requestBody)
            }
            .done{ paymentMethod in
                seal.fulfill(paymentMethod)
            }
            .catch { err in
                seal.reject(err)
            }
        }
    }
    
    override func handleDecodedClientTokenIfNeeded(_ decodedJWTToken: DecodedJWTToken) -> Promise<String?> {
        return Promise { seal in
            if let statusUrlStr = decodedJWTToken.statusUrl,
               let statusUrl = URL(string: statusUrlStr),
               decodedJWTToken.intent != nil {
                
                self.statusUrl = statusUrl
                self.qrCode = decodedJWTToken.qrCode
                
                firstly {
                    self.evaluateFireDidReceiveAdditionalInfoEvent()
                }
                .then { () -> Promise<Void> in
                    self.evaluatePresentUserInterface()
                }
                .then { () -> Promise<Void> in
                    return self.awaitUserInput()
                }
                .done { () in
                    seal.fulfill(self.resumeToken)
                }
                .catch { err in
                    seal.reject(err)
                }
            } else {
                let error = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                seal.reject(error)
            }
        }
    }
}

extension QRCodeTokenizationViewModel {
    
    private func evaluatePresentUserInterface() -> Promise<Void> {
        return Promise { seal in
            
            let isHeadlessCheckoutDelegateImplemented = PrimerHeadlessUniversalCheckout.current.delegate != nil
            
            /// There is no need to check whether the Headless is implemented as the unsupported payment methods will be listed into
            /// PrimerHeadlessUniversalCheckout's private constant `unsupportedPaymentMethodTypes`
            /// Xfers is among them so it won't be loaded
            
            guard isHeadlessCheckoutDelegateImplemented == false else {
                seal.fulfill()
                return
            }
            
            firstly {
                self.presentPaymentMethodUserInterface()
            }
            .done {
                seal.fulfill()
            }
            .catch { error in
                seal.reject(error)
            }
            
            return
        }
    }
    
    private func evaluateFireDidReceiveAdditionalInfoEvent() -> Promise<Void> {
        return Promise { seal in
            
            /// There is no need to check whether the Headless is implemented as the unsupported payment methods will be listed into
            /// PrimerHeadlessUniversalCheckout's private constant `unsupportedPaymentMethodTypes`
            /// Xfers is among them so it won't be loaded
            ///
            ///
            /// This Promise only fires event in case of Headless support ad its been designed ad-hoc for this purpose
            
            let isHeadlessCheckoutDelegateImplemented = PrimerHeadlessUniversalCheckout.current.delegate != nil
            
            guard isHeadlessCheckoutDelegateImplemented else {
                // We are not in Headless, so no need to go through this logic
                seal.fulfill()
                return
            }
            
            let isHeadlessDidReceiveAdditionalInfoImplemented = PrimerHeadlessUniversalCheckout.current.delegate?.primerHeadlessUniversalCheckoutDidReceiveAdditionalInfo != nil

            guard isHeadlessDidReceiveAdditionalInfoImplemented else {
                let err = PrimerError.generic(message: "Delegate function 'primerHeadlessUniversalCheckoutDidReceiveAdditionalInfo(_ additionalInfo: PrimerCheckoutAdditionalInfo?)' hasn't been implemented. No events will be sent to your delegate instance.", userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                seal.reject(err)
                return
            }
            
            /// We don't want to put a lot of conditions for already unhandled payment methods
            /// So we'll fulFill the promise directly, leaving the rest of the logic as clean as possible to proceed with almost
            /// only happy path
            
            guard self.config.type != PrimerPaymentMethodType.xfersPayNow.rawValue else {
                seal.fulfill()
                return
            }

            
            var additionalInfo: PrimerCheckoutAdditionalInfo?
            
            switch self.config.type {
            case PrimerPaymentMethodType.rapydPromptPay.rawValue,
                PrimerPaymentMethodType.omisePromptPay.rawValue:
                
                guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                    let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                guard let expiresAt = decodedJWTToken.expDate else {
                    let err = PrimerError.invalidValue(key: "decodedClientToken.expiresAt", value: decodedJWTToken.expiresAt, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                guard let qrCodeString = decodedJWTToken.qrCode else {
                    let err = PrimerError.invalidValue(key: "decodedClientToken.qrCode", value: decodedJWTToken.qrCode, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                let formatter = DateFormatter().withExpirationDisplayDateFormat()
                let expiresAtDateString = formatter.string(from: expiresAt)
                
                if qrCodeString.isHttpOrHttpsURL, URL(string: qrCodeString) != nil {

                    additionalInfo = PromptPayCheckoutAdditionalInfo(expiresAt: expiresAtDateString,
                                                                     qrCodeUrl: qrCodeString,
                                                                     qrCodeBase64: nil)
                } else {
                    additionalInfo = PromptPayCheckoutAdditionalInfo(expiresAt: expiresAtDateString,
                                                                     qrCodeUrl: nil,
                                                                     qrCodeBase64: qrCodeString)
                }
                
            default:
                log(logLevel: .info, title: "UNHANDLED PAYMENT METHOD RESULT", message: self.config.type, prefix: nil, suffix: nil, bundle: nil, file: nil, className: nil, function: #function, line: nil)
                break
            }
                        
            if let additionalInfo = additionalInfo {
                PrimerDelegateProxy.primerDidReceiveAdditionalInfo(additionalInfo)
                seal.fulfill()
            } else {
                let err = PrimerError.invalidValue(key: "additionalInfo", value: additionalInfo, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                seal.reject(err)
            }
        }
    }
}

#endif

