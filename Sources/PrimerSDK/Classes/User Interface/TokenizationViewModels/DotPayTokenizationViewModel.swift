//
//  DotPayTokenizationViewModel.swift
//  PrimerSDK
//
//  Created by Admin on 8/11/21.
//

#if canImport(UIKit)

import UIKit

class DotPayTokenizationViewModel: PaymentMethodTokenizationViewModel {
    
    private var flow: PaymentFlow
    private var cardComponentsManager: CardComponentsManager!
    internal private(set) var banks: [Bank] = []
    internal private(set) var dataSource: [Bank] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    override lazy var title: String = {
        return "Dot Pay"
    }()
    
    override lazy var buttonTitle: String? = {
        switch config.type {
        case .dotPay:
            return nil
        default:
            assert(true, "Shouldn't end up in here")
            return nil
        }
    }()
    
    override lazy var buttonImage: UIImage? = {
        switch config.type {
        case .dotPay:
            return UIImage(named: "dot-pay-logo", in: Bundle.primerResources, compatibleWith: nil)
        default:
            assert(true, "Shouldn't end up in here")
            return nil
        }
    }()
    
    override lazy var buttonColor: UIColor? = {
        switch config.type {
        case .dotPay:
            return .white
        default:
            assert(true, "Shouldn't end up in here")
            return nil
        }
    }()
    
    override lazy var buttonTitleColor: UIColor? = {
        switch config.type {
        case .dotPay:
            return nil
        default:
            assert(true, "Shouldn't end up in here")
            return nil
        }
    }()
    
    override lazy var buttonBorderWidth: CGFloat = {
        switch config.type {
        case .dotPay:
            return 1.0
        default:
            assert(true, "Shouldn't end up in here")
            return 0.0
        }
    }()
    
    override lazy var buttonBorderColor: UIColor? = {
        switch config.type {
        case .dotPay:
            return .black
        default:
            assert(true, "Shouldn't end up in here")
            return nil
        }
    }()
    
    override lazy var buttonTintColor: UIColor? = {
        switch config.type {
        case .dotPay:
            return nil
        default:
            assert(true, "Shouldn't end up in here")
            return nil
        }
    }()
    
    override lazy var buttonFont: UIFont? = {
        return UIFont.systemFont(ofSize: 17.0, weight: .medium)
    }()
    
    override lazy var buttonCornerRadius: CGFloat? = {
        return 4.0
    }()
    
    private var tokenizationService: TokenizationServiceProtocol?
    
    required init(config: PaymentMethodConfig) {
        self.flow = Primer.shared.flow.internalSessionFlow.vaulted ? .vault : .checkout
        super.init(config: config)
    }
    
    override func validate() throws {
        let state: AppStateProtocol = DependencyContainer.resolve()
        let settings: PrimerSettingsProtocol = DependencyContainer.resolve()
        
        guard let decodedClientToken = state.decodedClientToken, decodedClientToken.isValid else {
            let err = PaymentException.missingClientToken
            _ = ErrorHandler.shared.handle(error: err)
            throw err
        }
    }
    
    internal var tokenizationCallback: ((_ paymentMethod: PaymentMethodToken?, _ err: Error?) -> Void)?
    
    internal lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }

        tableView.rowHeight = 41
        tableView.register(BankTableViewCell.self, forCellReuseIdentifier: BankTableViewCell.identifier)
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()
    
    internal lazy var searchBankTextField: PrimerSearchTextField? = {
        let textField = PrimerSearchTextField(frame: .zero)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 35).isActive = true
        textField.delegate = self
        textField.backgroundColor = UIColor(red: 36.0/255, green: 42.0/255, blue: 47.0/255, alpha: 0.03)
        textField.borderStyle = .none
        textField.layer.cornerRadius = 3.0
        textField.font = UIFont.systemFont(ofSize: 16.0)
        textField.placeholder = NSLocalizedString("search-bank-placeholder",
                                                        tableName: nil,
                                                        bundle: Bundle.primerResources,
                                                        value: "Search bank",
                                                        comment: "Search bank - Search bank textfield placeholder")
        textField.rightViewMode = .always
        return textField
    }()
    
    deinit {
        log(logLevel: .debug, message: "🧨 deinit: \(self) \(Unmanaged.passUnretained(self).toOpaque())")
    }
    
    @objc
    override func startTokenizationFlow() {
        super.startTokenizationFlow()
        
        do {
            try validate()
        } catch {
            DispatchQueue.main.async {
                Primer.shared.delegate?.checkoutFailed?(with: error)
                self.handleFailedTokenizationFlow(error: error)
            }
            return
        }
                
        let client: PrimerAPIClientProtocol = PrimerAPIClient()
        let request = AdyenDotPaySessionRequest(
            paymentMethodConfigId: config.id!,
            parameters: AdyenDotPaySessionRequestParameters())
        
        let state: AppStateProtocol = DependencyContainer.resolve()
        let decodedClientToken = state.decodedClientToken!
        
        client.adyenDotPayBanksList(clientToken: decodedClientToken, request: request) { result in
            switch result {
            case .failure(let err):
                print(err)
            case .success(let banks):
                self.banks = banks
                self.dataSource = banks
                let bsvc = BankSelectorViewController(viewModel: self)
                DispatchQueue.main.async {
                    Primer.shared.primerRootVC?.show(viewController: bsvc)
                }
            }
        }
        
        tokenizationCallback = { (paymentMethod, err) in
            if let err = err {
                self.handleFailedTokenizationFlow(error: err)
            } else if let paymentMethod = paymentMethod {
                self.handleSuccessfulTokenizationFlow()
            } else {
                assert(true, "Should never get in here.")
            }
        }
        
//        DispatchQueue.main.async {
//
//            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
//                let banksResponseStr: String =
//                """
//                [
//                    {
//                        "name": "ABN AMRO",
//                        "issuer": "0031",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0031@3x.png"
//                    },
//                    {
//                        "name": "ASN Bank",
//                        "issuer": "0761",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0761@3x.png"
//                    },
//                    {
//                        "name": "bunq",
//                        "issuer": "0802",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0802@3x.png"
//                    },
//                    {
//                        "name": "Handelsbanken",
//                        "issuer": "0804",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0804@3x.png"
//                    },
//                    {
//                        "name": "ING Bank",
//                        "issuer": "0721",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0721@3x.png"
//                    },
//                    {
//                        "name": "Knab",
//                        "issuer": "0801",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0801@3x.png"
//                    },
//                    {
//                        "name": "Rabobank",
//                        "issuer": "0021",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0021@3x.png"
//                    },
//                    {
//                        "name": "Regiobank",
//                        "issuer": "0771",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0771@3x.png"
//                    },
//                    {
//                        "name": "Revolut",
//                        "issuer": "0805",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0805@3x.png"
//                    },
//                    {
//                        "name": "SNS Bank",
//                        "issuer": "0751",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0751@3x.png"
//                    },
//                    {
//                        "name": "Triodos Bank",
//                        "issuer": "0511",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0511@3x.png"
//                    },
//                    {
//                        "name": "Van Lanschot Bankiers",
//                        "issuer": "0161",
//                        "logoUrl": "https://checkoutshopper-live.adyen.com/checkoutshopper/images/logos/small/ideal/0161@3x.png"
//                    }
//                ]
//                """
//                
//                do {
//                    let data = banksResponseStr.data(using: .utf8)
//                    let banks: [Bank] = try JSONParser().parse([Bank].self, from: data!)
//                    let bsvc = BankSelectorViewController(banks: banks, logo: UIImage(named: "dot-pay-logo", in: Bundle.primerResources, compatibleWith: nil))
//                    Primer.shared.primerRootVC?.show(viewController: bsvc)
//                } catch {
//                    print(error)
//                }
//            }
//        }
    }
    
    private func tokenize(bank: Bank) -> Promise<PaymentMethodToken> {
        return Promise { seal in
            self.tokenize(bank: bank) { paymentMethod, err in
                if let err = err {
                    seal.reject(err)
                } else if let paymentMethod = paymentMethod {
                    seal.fulfill(paymentMethod)
                } else {
                    assert(true, "Should always receive a payment method or an error")
                }
            }
        }
    }

    private func tokenize(bank: Bank, completion: @escaping (_ paymentMethod: PaymentMethodToken?, _ err: Error?) -> Void) {
        let state: AppStateProtocol = DependencyContainer.resolve()

        let req = AdyenDotPayTokenizationRequest(
            paymentInstrument: PaymentInstrument(
                paymentMethodConfigId: self.config.id!,
                sessionInfo: AdyenDotPaySessionInfo(issuer: bank.id),
                type: "OFF_SESSION_PAYMENT",
                paymentMethodType: "ADYEN_DOTPAY"))
        
        guard let clientToken = state.decodedClientToken else {
            completion(nil, PrimerError.clientTokenNull)
            return
        }
        
        let apiClient: PrimerAPIClientProtocol = DependencyContainer.resolve()
        apiClient.tokenizePaymentMethod(
            clientToken: clientToken,
            paymentMethodTokenizationRequest: req) { result in
                switch result {
                case .success(let paymentMethod):
                    self.paymentMethod = paymentMethod
                    completion(paymentMethod, nil)
                case .failure(let err):
                    completion(nil, err)
                }
            }
    }
    
}

extension DotPayTokenizationViewModel: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let bank = dataSource[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "BankTableViewCell", for: indexPath) as! BankTableViewCell
        cell.configure(viewModel: bank)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let bank = self.dataSource[indexPath.row]
        self.tokenize(bank: bank) { (paymentMethod, err) in
            if let err = err {
                self.tokenizationCallback?(nil, err)
            } else if let paymentMethod = paymentMethod {
                self.tokenizationCallback?(paymentMethod, nil)
            } else {
                assert(true, "Should never get in here.")
            }
        }
    }
}

extension DotPayTokenizationViewModel: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        var query: String
        
        if string.isEmpty {
            query = String((textField.text ?? "").dropLast())
        } else {
            query = (textField.text ?? "") + string
        }
        
        if query.isEmpty {
            dataSource = banks
            return true
        }
        
        var bankResults: [Bank] = []
        
        for bank in banks {
            if bank.name.lowercased().folding(options: .diacriticInsensitive, locale: nil).contains(query.lowercased().folding(options: .diacriticInsensitive, locale: nil)) == true {
                bankResults.append(bank)
            }
        }
        
        dataSource = bankResults
        
        return true
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        dataSource = banks
        return true
    }
}

#endif
