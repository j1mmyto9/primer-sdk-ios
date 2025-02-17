//
//  PrimerCheckoutComponentsUIManager.swift
//  PrimerSDK
//
//  Created by Evangelos on 9/2/22.
//

#if canImport(UIKit)

import Foundation
import SafariServices

public protocol PrimerHeadlessUniversalCheckoutInputData{}

extension PrimerHeadlessUniversalCheckout {
    struct IBANData: PrimerHeadlessUniversalCheckoutInputData {
        var iban: String
        var name: String
    }
    
    struct OTPData: PrimerHeadlessUniversalCheckoutInputData {
        var otp: String
    }
}

public protocol PrimerHeadlessUniversalCheckoutUIManager {
    init(paymentMethodType: String) throws
    func tokenize(withData data: PrimerHeadlessUniversalCheckoutInputData?)
}

public protocol PrimerCardFormDelegate: AnyObject  {
    func cardFormUIManager(_ cardFormUIManager: PrimerHeadlessUniversalCheckout.CardFormUIManager, isCardFormValid: Bool)
}

extension PrimerHeadlessUniversalCheckout {
    
    public class UIManager: PrimerHeadlessUniversalCheckoutUIManager {
        
        private(set) public var paymentMethodType: String
        private let appState: AppStateProtocol = AppState.current
        
        required public init(paymentMethodType: String) throws {
            guard let availablePaymentMethodTypes = PrimerHeadlessUniversalCheckout.current.listAvailablePaymentMethodsTypes() else {
                let err = PrimerError.misconfiguredPaymentMethods(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                throw err
            }
            
            if availablePaymentMethodTypes.filter({ $0 == paymentMethodType }).isEmpty {
                let err = PrimerError.unableToPresentPaymentMethod(paymentMethodType: paymentMethodType, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                throw err
            }
            
            self.paymentMethodType = paymentMethodType
        }
        
        public func tokenize(withData data: PrimerHeadlessUniversalCheckoutInputData? = nil) {
            
            // TODO: Implement data handling
            
            //            guard let data = data else { return }
            //
            //            if let ibanData = data as? IBANData {
            //
            //            } else if let otpData = data as? OTPData {
            //
            //            }
            //
        }
    }
    
    public final class CardFormUIManager: NSObject, PrimerInputElementDelegate {
        
        private(set) public var paymentMethodType: String
        private let appState: AppStateProtocol = AppState.current
        private(set) public var requiredInputElementTypes: [PrimerInputElementType] = []
        public var inputElements: [PrimerInputElement] = [] {
            didSet {
                var tmpInputElementsContainers: [Weak<PrimerInputElementDelegateContainer>] = []
                inputElements.forEach { el in
                    if let _ = el.inputElementDelegate {
                        tmpInputElementsContainers.append(Weak(value: PrimerInputElementDelegateContainer(element: el, delegate: el.inputElementDelegate)))
                    }
                }
                inputElements.forEach { el in
                    el.inputElementDelegate = self
                }
                originalInputElementsContainers = tmpInputElementsContainers
            }
        }
        private var originalInputElementsContainers: [Weak<PrimerInputElementDelegateContainer>]? = []
        public weak var cardFormUIManagerDelegate: PrimerCardFormDelegate?
        private(set) public var isCardFormValid: Bool = false {
            didSet {
                DispatchQueue.main.async {
                    self.cardFormUIManagerDelegate?.cardFormUIManager(self, isCardFormValid: self.isCardFormValid)
                }
            }
        }
        private(set) public var paymentMethod: PrimerPaymentMethodTokenData?
        private var resumePaymentId: String?
        private var paymentMethodTokenData: PrimerPaymentMethodTokenData?
        private var paymentCheckoutData: PrimerCheckoutData?
        private var webViewController: SFSafariViewController?
        private var webViewCompletion: ((_ authorizationToken: String?, _ error: PrimerError?) -> Void)?
        
        deinit {
            log(logLevel: .debug, message: "🧨 deinit: \(self) \(Unmanaged.passUnretained(self).toOpaque())")
        }
        
        public init(paymentMethodType: String) throws {
            
            guard let availablePaymentMethodTypes = PrimerHeadlessUniversalCheckout.current.listAvailablePaymentMethodsTypes() else {
                let err = PrimerError.misconfiguredPaymentMethods(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                throw err
            }
            
            if availablePaymentMethodTypes.filter({ $0 == paymentMethodType }).isEmpty {
                let err = PrimerError.unableToPresentPaymentMethod(paymentMethodType: paymentMethodType, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                throw err
            }

            self.paymentMethodType = paymentMethodType
            super.init()
            self.requiredInputElementTypes = PrimerHeadlessUniversalCheckout.current.listRequiredInputElementTypes(for: paymentMethodType) ?? []
        }
        
        @available(*, deprecated, message: "This initiliazer supports `.paymentCard` as a payment method type only. Use the default `init(paymentMethodType: String)` to support multiple payment method types that requires card element inputs.")
        public override init() {
            self.paymentMethodType = PrimerPaymentMethodType.paymentCard.rawValue
            super.init()
            self.requiredInputElementTypes = PrimerHeadlessUniversalCheckout.current.listRequiredInputElementTypes(for: paymentMethodType) ?? []
        }
        
        public func tokenize(withData data: PrimerHeadlessUniversalCheckoutInputData? = nil) {
            PrimerDelegateProxy.primerHeadlessUniversalCheckoutPreparationDidStart(for: self.paymentMethodType)
            
            firstly {
                PrimerHeadlessUniversalCheckout.current.validateSession()
            }
            .then { () -> Promise<Void> in
                self.validateInputData()
            }
            .then { () -> Promise<Void> in
                self.handlePrimerWillCreatePaymentEvent(PrimerPaymentMethodData(type: self.paymentMethodType))
            }
            .then { () -> Promise<Request.Body.Tokenization> in
                try self.buildRequestBody()
            }
            .then { requestBody -> Promise<PrimerPaymentMethodTokenData> in
                PrimerDelegateProxy.primerHeadlessUniversalCheckoutTokenizationDidStart(for: self.paymentMethodType)
                let tokenizationService: TokenizationServiceProtocol = TokenizationService()
                return tokenizationService.tokenize(requestBody: requestBody)
            }
            .then { paymentMethodTokenData -> Promise<PrimerCheckoutData?> in
                self.paymentMethodTokenData = paymentMethodTokenData
                return self.startPaymentFlow(withPaymentMethodTokenData: paymentMethodTokenData)
            }
            .done { checkoutData in
                if PrimerSettings.current.paymentHandling == .auto, let checkoutData = checkoutData {
                    PrimerDelegateProxy.primerDidCompleteCheckoutWithData(checkoutData)
                }
            }
            .catch { error in
                ErrorHandler.handle(error: error)
                PrimerHeadlessUniversalCheckout.current.delegate?.primerHeadlessUniversalCheckoutDidFail?(withError: error)
            }
        }
        
        private func validateInputData() -> Promise<Void> {
            return Promise { seal in
                var errors: [PrimerError] = []
                for inputElementType in self.requiredInputElementTypes {
                    if self.inputElements.filter({ $0.type == inputElementType }).isEmpty {
                        let err = PrimerError.missingPrimerInputElement(inputElementType: inputElementType, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        errors.append(err)
                    }
                }
                
                if !errors.isEmpty {
                    let err = PrimerError.underlyingErrors(errors: errors, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    seal.reject(err)
                    return
                }
                
                for inputElement in inputElements {
                    if !inputElement.isValid {
                        let err = PrimerError.invalidValue(key: "input-element", value: inputElement.type.rawValue, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        errors.append(err)
                    }
                }
                
                if !errors.isEmpty {
                    let err = PrimerError.underlyingErrors(errors: errors, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    seal.reject(err)
                    return
                }
                
                seal.fulfill()
            }
        }
        
        private func buildRequestBody() throws -> Promise<Request.Body.Tokenization> {
            switch self.paymentMethodType {
            case PrimerPaymentMethodType.paymentCard.rawValue:
                return makeCardRequestBody()
            case PrimerPaymentMethodType.adyenBancontactCard.rawValue:
                return makeCardRedirectRequestBody()
            default:
                let err = PrimerError.unsupportedPaymentMethod(paymentMethodType: paymentMethodType, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                throw err
            }
        }
                
        private func makeCardRedirectRequestBody() -> Promise<Request.Body.Tokenization> {
            return Promise { seal in
                
                guard let cardnumberField = inputElements.filter({ $0.type == .cardNumber }).first as? PrimerInputTextField,
                      let expiryDateField = inputElements.filter({ $0.type == .expiryDate }).first as? PrimerInputTextField,
                      let cardholderNameField = inputElements.filter({ $0.type == .cardholderName }).first as? PrimerInputTextField
                else {
                    let err = PrimerError.invalidValue(key: "input-element", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                guard cardnumberField.isValid,
                      expiryDateField.isValid,
                      cardholderNameField.isValid,
                      let cardNumber = cardnumberField._text,
                      let expiryDate = expiryDateField._text,
                      let cardholderName = cardholderNameField._text
                else {
                    let err = PrimerError.invalidValue(key: "input-element", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                let expiryArr = expiryDate.components(separatedBy: expiryDateField.type.delimiter!)
                let currentYearAsString = Date().yearComponentAsString
                let milleniumAndCenturyOfCurrentYearAsString = currentYearAsString.prefix(upTo: currentYearAsString.index(currentYearAsString.startIndex, offsetBy: 2))

                let expiryMonth = expiryArr[0]
                let expiryYear = "\(milleniumAndCenturyOfCurrentYearAsString)\(expiryArr[1])"

                guard let configId = AppState.current.apiConfiguration?.getConfigId(for: paymentMethodType) else {
                    let err = PrimerError.missingPrimerConfiguration(
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                let cardOffSessionPaymentInstrument = CardOffSessionPaymentInstrument(paymentMethodConfigId: configId,
                                                                                   paymentMethodType: paymentMethodType,
                                                                                   number: PrimerInputElementType.cardNumber.clearFormatting(value: cardNumber) as! String,
                                                                                   expirationMonth: expiryMonth,
                                                                                   expirationYear: expiryYear,
                                                                                   cardholderName: cardholderName)
                
                seal.fulfill(Request.Body.Tokenization(paymentInstrument: cardOffSessionPaymentInstrument))
            }
        }
        
        private func makeCardRequestBody() -> Promise<Request.Body.Tokenization> {
            return Promise { seal in
                
                guard let cardnumberField = inputElements.filter({ $0.type == .cardNumber }).first as? PrimerInputTextField,
                      let expiryDateField = inputElements.filter({ $0.type == .expiryDate }).first as? PrimerInputTextField,
                      let cvvField = inputElements.filter({ $0.type == .cvv }).first as? PrimerInputTextField
                else {
                    let err = PrimerError.invalidValue(key: "input-element", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                
                guard cardnumberField.isValid,
                      expiryDateField.isValid,
                      cvvField.isValid,
                      let cardNumber = cardnumberField._text,
                      let expiryDate = expiryDateField._text,
                      let cvv = cvvField._text
                else {
                    let err = PrimerError.invalidValue(key: "input-element", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                    return
                }
                                
                let expiryArr = expiryDate.components(separatedBy: expiryDateField.type.delimiter!)
                let currentYearAsString = Date().yearComponentAsString
                let milleniumAndCenturyOfCurrentYearAsString = currentYearAsString.prefix(upTo: currentYearAsString.index(currentYearAsString.startIndex, offsetBy: 2))

                let expiryMonth = expiryArr[0]
                let expiryYear = "\(milleniumAndCenturyOfCurrentYearAsString)\(expiryArr[1])"
                
                var cardholderName: String?
                if let cardholderNameField = inputElements.filter({ $0.type == .cardholderName }).first as? PrimerInputTextField {
                    if !cardholderNameField.isValid {
                        let err = PrimerError.invalidValue(key: "cardholder-name", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        ErrorHandler.handle(error: err)
                        seal.reject(err)
                        return
                    }
                    
                    cardholderName = cardholderNameField._text
                }
                
                let paymentInstrument = CardPaymentInstrument(
                    number: PrimerInputElementType.cardNumber.clearFormatting(value: cardNumber) as! String,
                    cvv: cvv,
                    expirationMonth: expiryMonth,
                    expirationYear: expiryYear,
                    cardholderName: cardholderName)
                
                seal.fulfill(Request.Body.Tokenization(paymentInstrument: paymentInstrument))
            }
        }
        
        func startPaymentFlow(withPaymentMethodTokenData paymentMethodTokenData: PrimerPaymentMethodTokenData) -> Promise<PrimerCheckoutData?> {
            return Promise { seal in
                firstly {
                    self.startPaymentFlowAndFetchDecodedClientToken(withPaymentMethodTokenData: paymentMethodTokenData)
                }
                .done { decodedJWTToken in
                    if let decodedJWTToken = decodedJWTToken {
                        firstly {
                            self.handleDecodedClientTokenIfNeeded(decodedJWTToken)
                        }
                        .done { resumeToken in
                            if let resumeToken = resumeToken {
                                firstly {
                                    self.handleResumeStepsBasedOnSDKSettings(resumeToken: resumeToken)
                                }
                                .done { checkoutData in
                                    seal.fulfill(checkoutData)
                                }
                                .catch { err in
                                    seal.reject(err)
                                }
                            } else {
                                seal.fulfill(nil)
                            }
                        }
                        .catch { err in
                            seal.reject(err)
                        }
                    } else {
                        seal.fulfill(self.paymentCheckoutData)
                    }
                }
                .catch { err in
                    seal.reject(err)
                }
            }
        }
        
        internal func handlePrimerWillCreatePaymentEvent(_ paymentMethodData: PrimerPaymentMethodData) -> Promise<Void> {
            return Promise { seal in
                if PrimerInternal.shared.intent == .vault {
                    seal.fulfill()
                } else {
                    let checkoutPaymentMethodType = PrimerCheckoutPaymentMethodType(type: paymentMethodData.type)
                    let checkoutPaymentMethodData = PrimerCheckoutPaymentMethodData(type: checkoutPaymentMethodType)
                    
                    PrimerDelegateProxy.primerWillCreatePaymentWithData(checkoutPaymentMethodData, decisionHandler: { paymentCreationDecision in
                        switch paymentCreationDecision.type {
                        case .abort(let errorMessage):
                            let error = PrimerError.merchantError(message: errorMessage ?? "", userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                            seal.reject(error)
                        case .continue:
                            seal.fulfill()
                        }
                    })
                }
            }
        }
        
        // This function will do one of the two following:
        //     - Wait a response from the merchant, via the delegate function. The response can be:
        //         - A new client token
        //         - Success
        //         - Error
        //     - Perform the payment internally, and get a response from our BE. The response will
        //       be a Payment response. The can contain:
        //         - A required action with a new client token
        //         - Be successful
        //         - Has failed
        //
        // Therefore, return:
        //     - A decoded client token
        //     - nil for success
        //     - Reject with an error
        func startPaymentFlowAndFetchDecodedClientToken(withPaymentMethodTokenData paymentMethodTokenData: PrimerPaymentMethodTokenData) -> Promise<DecodedJWTToken?> {
            return Promise { seal in
                if PrimerSettings.current.paymentHandling == .manual {
                    PrimerDelegateProxy.primerDidTokenizePaymentMethod(paymentMethodTokenData) { resumeDecision in
                        switch resumeDecision.type {
                        case .succeed:
                            seal.fulfill(nil)
                            
                        case .continueWithNewClientToken(let newClientToken):
                            let apiConfigurationModule = PrimerAPIConfigurationModule()
                            
                            firstly {
                                apiConfigurationModule.storeRequiredActionClientToken(newClientToken)
                            }
                            .done {
                                guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                                    let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                                    ErrorHandler.handle(error: err)
                                    throw err
                                }
                                
                                seal.fulfill(decodedJWTToken)
                            }
                            .catch { err in
                                seal.reject(err)
                            }
                            
                        case .fail(let message):
                            var merchantErr: Error!
                            if let message = message {
                                let err = PrimerError.merchantError(message: message, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                                merchantErr = err
                            } else {
                                merchantErr = NSError.emptyDescriptionError
                            }
                            seal.reject(merchantErr)
                        }
                    }

                } else {
                    guard let paymentMethodTokenString = paymentMethodTokenData.token else {
                        let paymentMethodTokenError = PrimerError.invalidValue(key: "resumePaymentId", value: "Payment method token not valid", userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        ErrorHandler.handle(error: paymentMethodTokenError)
                        throw paymentMethodTokenError
                    }
                    
                    firstly {
                        self.handleCreatePaymentEvent(paymentMethodTokenString)
                    }
                    .done { paymentResponse -> Void in
                        guard paymentResponse != nil else {
                            let err = PrimerError.invalidValue(key: "paymentResponse", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                            throw err
                        }

                        self.paymentCheckoutData = PrimerCheckoutData(payment: PrimerCheckoutDataPayment(from: paymentResponse!))
                        self.resumePaymentId = paymentResponse!.id
                        
                        if let requiredAction = paymentResponse!.requiredAction {
                            let apiConfigurationModule = PrimerAPIConfigurationModule()
                            
                            firstly {
                                apiConfigurationModule.storeRequiredActionClientToken(requiredAction.clientToken)
                            }
                            .done {
                                guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                                    let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                                    ErrorHandler.handle(error: err)
                                    throw err
                                }
                                
                                seal.fulfill(decodedJWTToken)
                            }
                            .catch { err in
                                seal.reject(err)
                            }
                            
                        } else {
                            seal.fulfill(nil)
                        }
                    }
                    .catch { err in
                        seal.reject(err)
                    }
                }
            }
        }
        
        func handleDecodedClientTokenIfNeeded(_ decodedJWTToken: DecodedJWTToken) -> Promise<String?> {
            return Promise { seal in
                if decodedJWTToken.intent == RequiredActionName.threeDSAuthentication.rawValue {
        #if canImport(Primer3DS)
                    guard let paymentMethodTokenData = paymentMethodTokenData else {
                        let err = InternalError.failedToDecode(message: "Failed to find paymentMethod", userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        let containerErr = PrimerError.failedToPerform3DS(error: err, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        ErrorHandler.handle(error: containerErr)
                        seal.reject(containerErr)
                        return
                    }
                    
                    let threeDSService = ThreeDSService()
                    threeDSService.perform3DS(paymentMethodTokenData: paymentMethodTokenData, protocolVersion: decodedJWTToken.env == "PRODUCTION" ? .v1 : .v2, sdkDismissed: nil) { result in
                        switch result {
                        case .success(let resumeToken):
                            DispatchQueue.main.async {
                                seal.fulfill(resumeToken)
                            }
                            
                        case .failure(let err):
                            let containerErr = PrimerError.failedToPerform3DS(error: err, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                            ErrorHandler.handle(error: containerErr)
                            seal.reject(containerErr)
                        }
                    }
        #else
                    let err = PrimerError.failedToImport3DS(
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
        #endif
                    
                } else if decodedJWTToken.intent == RequiredActionName.processor3DS.rawValue {
                    if let redirectUrlStr = decodedJWTToken.redirectUrl,
                       let redirectUrl = URL(string: redirectUrlStr),
                       let statusUrlStr = decodedJWTToken.statusUrl,
                       let statusUrl = URL(string: statusUrlStr),
                       decodedJWTToken.intent != nil {
                        
                        DispatchQueue.main.async {
                            PrimerUIManager.primerRootViewController?.enableUserInteraction(true)
                        }
                        
                        firstly {
                            self.presentWebRedirectViewControllerWithRedirectUrl(redirectUrl)
                        }
                        .then { () -> Promise<String> in
                            let pollingModule = PollingModule(url: statusUrl)
                            return pollingModule.start()
                        }
                        .done { resumeToken in
                            seal.fulfill(resumeToken)
                        }
                        .catch { err in
                            seal.reject(err)
                        }
                    } else {
                        let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        ErrorHandler.handle(error: err)
                        seal.reject(err)
                    }
                    
                } else if decodedJWTToken.intent?.contains("_REDIRECTION") == true {
                    if let redirectUrlStr = decodedJWTToken.redirectUrl,
                       let redirectUrl = URL(string: redirectUrlStr),
                       let statusUrlStr = decodedJWTToken.statusUrl,
                       let statusUrl = URL(string: statusUrlStr),
                       decodedJWTToken.intent != nil {
                        
                        DispatchQueue.main.async {
                            PrimerUIManager.primerRootViewController?.enableUserInteraction(true)
                        }
                        
                        var pollingModule: PollingModule? = PollingModule(url: statusUrl)
                        
                        firstly {
                            self.presentWebRedirectViewControllerWithRedirectUrl(redirectUrl)
                        }
                        .then { () -> Promise<String> in
                            self.webViewCompletion = { (id, err) in
                                if let err = err {
                                    pollingModule?.cancel(withError: err)
                                    pollingModule = nil
                                }
                            }
                            return pollingModule!.start()
                        }
                        .done { resumeToken in
                            seal.fulfill(resumeToken)
                        }
                        .ensure {
                            PrimerInternal.shared.dismiss()
                        }
                        .catch { err in
                            if let primerErr = err as? PrimerError {
                                pollingModule?.cancel(withError: primerErr)
                            } else {
                                let err = PrimerError.underlyingErrors(errors: [err], userInfo: nil, diagnosticsId: UUID().uuidString)
                                ErrorHandler.handle(error: err)
                                pollingModule?.cancel(withError: err)
                            }
                            
                            pollingModule = nil
                            seal.reject(err)
                        }
                        
                    } else {
                        let error = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        seal.reject(error)
                    }

                } else {
                    let err = PrimerError.invalidValue(key: "resumeToken", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    seal.reject(err)
                }
            }
        }
        
        private func presentWebRedirectViewControllerWithRedirectUrl(_ redirectUrl: URL) -> Promise<Void> {
            return Promise { seal in
                self.webViewController = SFSafariViewController(url: redirectUrl)
                self.webViewController!.delegate = self
                
                self.webViewCompletion = { (id, err) in
                    if let err = err {
                        seal.reject(err)
                    }
                }
                
                DispatchQueue.main.async {
                    if PrimerUIManager.primerRootViewController == nil {
                        firstly {
                            PrimerUIManager.prepareRootViewController()
                        }
                        .done {
                            PrimerUIManager.primerRootViewController?.present(self.webViewController!, animated: true, completion: {
                                DispatchQueue.main.async {
                                    seal.fulfill()
                                }
                            })
                        }
                        .catch { _ in }
                    } else {
                        PrimerUIManager.primerRootViewController?.present(self.webViewController!, animated: true, completion: {
                            DispatchQueue.main.async {
                                seal.fulfill()
                            }
                        })
                    }
                    
                }
            }
        }
        
        // Create payment with Payment method token

        private func handleCreatePaymentEvent(_ paymentMethodData: String) -> Promise<Response.Body.Payment?> {
            return Promise { seal in
                let createResumePaymentService: CreateResumePaymentServiceProtocol = CreateResumePaymentService()
                createResumePaymentService.createPayment(paymentRequest: Request.Body.Payment.Create(token: paymentMethodData)) { paymentResponse, error in
                    guard error == nil else {
                        seal.reject(error!)
                        return
                    }
                    
                    guard let status = paymentResponse?.status, status != .failed else {
                        seal.reject(PrimerError.paymentFailed(
                            description: "Failed to create/resume payment",
                            userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                            diagnosticsId: UUID().uuidString))
                        return
                    }
                    
                    if let paymentFailureReason = paymentResponse?.paymentFailureReason,
                    let paymentErrorCode = PrimerPaymentErrorCode(rawValue: paymentFailureReason),
                       let error = PrimerError.simplifiedErrorFromErrorID(paymentErrorCode, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"]) {
                        seal.reject(error)
                        return
                    }
                                    
                    seal.fulfill(paymentResponse)
                }
            }
        }
        
        func handleResumeStepsBasedOnSDKSettings(resumeToken: String) -> Promise<PrimerCheckoutData?> {
            return Promise { seal in
                if PrimerSettings.current.paymentHandling == .manual {
                    PrimerDelegateProxy.primerDidResumeWith(resumeToken) { resumeDecision in
                        switch resumeDecision.type {
                        case .fail(let message):
                            var merchantErr: Error!
                            if let message = message {
                                let err = PrimerError.merchantError(message: message, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                                merchantErr = err
                            } else {
                                merchantErr = NSError.emptyDescriptionError
                            }
                            seal.reject(merchantErr)

                        case .succeed:
                            seal.fulfill(nil)

                        case .continueWithNewClientToken:
                            seal.fulfill(nil)
                        }
                    }
                    
                } else {
                    guard let resumePaymentId = self.resumePaymentId else {
                        let resumePaymentIdError = PrimerError.invalidValue(key: "resumePaymentId", value: "Resume Payment ID not valid", userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                        ErrorHandler.handle(error: resumePaymentIdError)
                        seal.reject(resumePaymentIdError)
                        return
                    }
                    
                    firstly {
                        self.handleResumePaymentEvent(resumePaymentId, resumeToken: resumeToken)
                    }
                    .done { paymentResponse -> Void in
                        guard let paymentResponse = paymentResponse else {
                            let err = PrimerError.invalidValue(key: "paymentResponse", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                            ErrorHandler.handle(error: err)
                            throw err
                        }
                        
                        self.paymentCheckoutData = PrimerCheckoutData(payment: PrimerCheckoutDataPayment(from: paymentResponse))
                        seal.fulfill(self.paymentCheckoutData)
                    }
                    .catch { err in
                        seal.reject(err)
                    }
                }
            }
        }
        
        // Resume payment with Resume payment ID
        
        private func handleResumePaymentEvent(_ resumePaymentId: String, resumeToken: String) -> Promise<Response.Body.Payment?> {
            
            return Promise { seal in
                
                let createResumePaymentService: CreateResumePaymentServiceProtocol = CreateResumePaymentService()
                createResumePaymentService.resumePaymentWithPaymentId(resumePaymentId, paymentResumeRequest: Request.Body.Payment.Resume(token: resumeToken)) { paymentResponse, error in
                    
                    guard error == nil else {
                        seal.reject(error!)
                        return
                    }
                    
                    guard let status = paymentResponse?.status, status != .failed else {
                        seal.reject(PrimerError.paymentFailed(
                            description: "Failed to create/resume payment",
                            userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                            diagnosticsId: UUID().uuidString))
                        return
                    }
                    
                    if let paymentFailureReason = paymentResponse?.paymentFailureReason,
                    let paymentErrorCode = PrimerPaymentErrorCode(rawValue: paymentFailureReason),
                       let error = PrimerError.simplifiedErrorFromErrorID(paymentErrorCode, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"]) {
                        seal.reject(error)
                        return
                    }
                                    
                    seal.fulfill(paymentResponse)
                }
            }
        }
        
        // MARK: - INPUT ELEMENTS DELEGATE
        
        public func inputElementShouldFocus(_ sender: PrimerInputElement) -> Bool {
            guard let senderTextField = sender as? PrimerInputTextField else { return true }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return true }
            
            if let shouldFocus = inputElementContainer.value?.delegate.inputElementShouldFocus?(sender) {
                return shouldFocus
            } else {
                return true
            }
        }
        
        public func inputElementDidFocus(_ sender: PrimerInputElement) {
            guard let senderTextField = sender as? PrimerInputTextField else { return }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return }
            inputElementContainer.value?.delegate.inputElementDidFocus?(sender)
        }
        
        public func inputElementShouldBlur(_ sender: PrimerInputElement) -> Bool {
            guard let senderTextField = sender as? PrimerInputTextField else { return true }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return true }
            
            if let shouldBlur = inputElementContainer.value?.delegate.inputElementShouldBlur?(sender) {
                return shouldBlur
            } else {
                return true
            }
        }
        
        public func inputElementDidBlur(_ sender: PrimerInputElement) {
            guard let senderTextField = sender as? PrimerInputTextField else { return }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return }
            inputElementContainer.value?.delegate.inputElementDidBlur?(sender)
        }
        
        public func inputElementValueDidChange(_ sender: PrimerInputElement) {
            guard let senderTextField = sender as? PrimerInputTextField else { return }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return }
            inputElementContainer.value?.delegate.inputElementValueDidChange?(sender)
        }
        
        public func inputElementDidDetectType(_ sender: PrimerInputElement, type: Any?) {
            guard let senderTextField = sender as? PrimerInputTextField else { return }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return }
            
            if let cvvTextField = self.inputElements.filter({ $0.type == .cvv }).first as? PrimerInputTextField {
                cvvTextField.detectedValueType = type
            }
            
            inputElementContainer.value?.delegate.inputElementDidDetectType?(sender, type: type)
        }
        
        public func inputElementValueIsValid(_ sender: PrimerInputElement, isValid: Bool) {
            guard let senderTextField = sender as? PrimerInputTextField else { return }
            guard let inputElementContainer = originalInputElementsContainers?.filter({ ($0.value?.element as? PrimerInputTextField) == senderTextField }).first else { return }
            inputElementContainer.value?.delegate.inputElementValueIsValid?(sender, isValid: isValid)
            
            DispatchQueue.global(qos: .userInitiated).async {
                var tmpIsFormValid: Bool
                let inputElementsValidation = self.inputElements.compactMap({ $0.isValid })
                tmpIsFormValid = !inputElementsValidation.contains(false)
                
                if tmpIsFormValid != self.isCardFormValid {
                    self.isCardFormValid = tmpIsFormValid
                }
            }
        }
    }
}

extension PrimerHeadlessUniversalCheckout.CardFormUIManager: ResumeHandlerProtocol {
    
    // MARK: - RESUME HANDLER
    
    public func handle(newClientToken clientToken: String) {
        self.handle(clientToken)
    }
    
    public func handle(error: Error) {}
    
    public func handleSuccess() {}
}

extension PrimerHeadlessUniversalCheckout.CardFormUIManager {
    
    private func handle(_ clientToken: String) {
        
        if PrimerAPIConfigurationModule.clientToken != clientToken {
            let apiConfigurationModule = PrimerAPIConfigurationModule()
            
            firstly {
                apiConfigurationModule.storeRequiredActionClientToken(clientToken)
            }
            .done {
                DispatchQueue.main.async {
                    self.continueHandleNewClientToken(clientToken)
                }
            }
            .catch { err in
                var primerErr: PrimerError!
                if let err = err as? PrimerError {
                    primerErr = err
                } else {
                    primerErr = PrimerError.generic(message: err.localizedDescription, userInfo: nil, diagnosticsId: UUID().uuidString)
                }
                
                ErrorHandler.handle(error: primerErr)
                PrimerDelegateProxy.primerDidFailWithError(primerErr, data: nil) { errorDecision in
                    // FIXME: Handle decision for HUC
                }
            }
        } else {
            self.continueHandleNewClientToken(clientToken)
        }
    }
    
    private func continueHandleNewClientToken(_ clientToken: String) {
        
        if let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken,
           decodedJWTToken.intent == RequiredActionName.threeDSAuthentication.rawValue {
            
#if canImport(Primer3DS)
            guard let paymentMethod = paymentMethod else {
                DispatchQueue.main.async {
                    let err = InternalError.failedToDecode(message: "Failed to find paymentMethod", userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    let containerErr = PrimerError.failedToPerform3DS(error: err, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    self.handle(error: containerErr)
                }
                return
            }
            
            let threeDSService = ThreeDSService()
            PrimerInternal.shared.intent = .checkout
            
            threeDSService.perform3DS(paymentMethodTokenData: paymentMethod, protocolVersion: decodedJWTToken.env == "PRODUCTION" ? .v1 : .v2, sdkDismissed: nil) { result in
                switch result {
                case .success(let resumeToken):
                    DispatchQueue.main.async {
                        PrimerDelegateProxy.primerDidResumeWith(resumeToken) { resumeDecision in

                        }
                    }
                    
                case .failure(let err):
                    log(logLevel: .error, message: "Failed to perform 3DS with error \(err as NSError)")
                    let containerErr = PrimerError.failedToPerform3DS(error: err, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: containerErr)
                    DispatchQueue.main.async {
                        PrimerDelegateProxy.primerDidFailWithError(containerErr, data: nil) { errorDecision in

                        }
                    }
                }
            }
#else
            DispatchQueue.main.async {
                let err = PrimerError.failedToImport3DS(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                PrimerDelegateProxy.primerDidFailWithError(err, data: nil) { errorDecision in
                    // FIXME: handle the err
                }
            }
#endif
            
        } else {
            let err = PrimerError.invalidValue(key: "resumeToken", value: nil, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
            ErrorHandler.handle(error: err)
            
            DispatchQueue.main.async {
                PrimerHeadlessUniversalCheckout.current.delegate?.primerHeadlessUniversalCheckoutDidFail?(withError: err)
            }
        }
    }
}

extension PrimerHeadlessUniversalCheckout.CardFormUIManager: SFSafariViewControllerDelegate {
    
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        if let webViewCompletion = webViewCompletion {
            // Cancelled
            let err = PrimerError.cancelled(
                paymentMethodType: self.paymentMethodType,
                userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                diagnosticsId: UUID().uuidString)
            
            ErrorHandler.handle(error: err)
            webViewCompletion(nil, err)
        }
        
        webViewCompletion = nil
    }
}

#endif
