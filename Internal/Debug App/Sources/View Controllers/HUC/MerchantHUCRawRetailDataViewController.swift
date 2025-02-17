//
//  MerchantHUCRawCardDataViewController.swift
//  PrimerSDK_Example
//
//  Created by Evangelos on 12/7/22.
//  Copyright © 2022 CocoaPods. All rights reserved.
//

import PrimerSDK
import UIKit

class MerchantHUCRawRetailDataViewController: UIViewController, PrimerHeadlessUniversalCheckoutDelegate {
    
    static func instantiate(paymentMethodType: String) -> MerchantHUCRawRetailDataViewController {
        let mpmvc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MerchantHUCRawRetailDataViewController") as! MerchantHUCRawRetailDataViewController
        mpmvc.paymentMethodType = paymentMethodType
        return mpmvc
    }
    
    var paymentMethodType: String!
    var paymentId: String?
    var activityIndicator: UIActivityIndicatorView?
    var rawData: PrimerRawData?
    private let cellIdentifier = "RetailDataTableViewCell"
    
    internal lazy var tableView: UITableView = {
                
        let tableView = UITableView()
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.rowHeight = 56
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()
    
    var selectedOutletIdentifier: String!
    var selectedIndexPath: IndexPath?
    var payButton: UIButton!
    var retailers: [RetailOutletsRetail] = [] {
        didSet {
            self.tableView.reloadData()
        }
    }
    
    var checkoutData: [String] = []
    var primerError: Error?
    var logs: [String] = []
    var primerRawDataManager: PrimerHeadlessUniversalCheckout.RawDataManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.addSubview(tableView)
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10).isActive = true
        self.tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10).isActive = true

        self.payButton = UIButton(frame: .zero)
        
        self.payButton.accessibilityIdentifier = "submit_btn"
        self.payButton.setTitle("Issue voucher", for: .normal)
        self.payButton.titleLabel?.adjustsFontSizeToFitWidth = true
        self.payButton.titleLabel?.minimumScaleFactor = 0.7
        self.payButton.backgroundColor = .black
        self.payButton.setTitleColor(.white, for: .normal)
        self.payButton.addTarget(self, action: #selector(issueVoucherButtonTapped), for: .touchUpInside)
        self.tableView.tableFooterView = self.payButton
        self.tableView.tableFooterView?.frame.size.height = 45

        PrimerHeadlessUniversalCheckout.current.delegate = self
        
        self.showLoadingOverlay()
        
        Networking.requestClientSession(requestBody: clientSessionRequestBody) { (clientToken, err) in
            if let err = err {
                self.showErrorMessage(err.localizedDescription)
 
            } else if let clientToken = clientToken {
                
                let settings = PrimerSettings(
                    paymentHandling: paymentHandling == .auto ? .auto : .manual,
                    paymentMethodOptions: PrimerPaymentMethodOptions(
                        urlScheme: "merchant://redirect",
                        applePayOptions: PrimerApplePayOptions(merchantIdentifier: "merchant.dx.team", merchantName: "Primer Merchant", isCaptureBillingAddressEnabled: false)
                    )
                )
                                
                PrimerHeadlessUniversalCheckout.current.start(withClientToken: clientToken, settings: settings, completion: { [weak self] (pms, err) in
                    self?.hideLoadingOverlay()
                })
            }
        }
        
        do {
            self.primerRawDataManager = try PrimerHeadlessUniversalCheckout.RawDataManager(paymentMethodType: self.paymentMethodType)
            primerRawDataManager.delegate = self
            primerRawDataManager.configure { [weak self] data, error in
                guard error == nil else {
                    self?.hideLoadingOverlay()
                    return
                }
                self?.retailers = (data as? RetailOutletsList)?.result ?? []
                self?.hideLoadingOverlay()
            }
        } catch {
            
        }
    }
    
    @IBAction func issueVoucherButtonTapped(_ sender: UIButton) {
        if paymentMethodType == "XENDIT_RETAIL_OUTLETS" {
            self.rawData = PrimerRawRetailerData(id: selectedOutletIdentifier)
            primerRawDataManager.rawData = self.rawData!
            primerRawDataManager.submit()
            self.showLoadingOverlay()
        }
    }
    
    // MARK: - HELPERS
    
    private func showLoadingOverlay() {
        DispatchQueue.main.async {
            if self.activityIndicator == nil {
                self.activityIndicator = UIActivityIndicatorView(frame: self.view.bounds)
                self.activityIndicator?.backgroundColor = .black.withAlphaComponent(0.2)
                self.activityIndicator?.color = .black
                self.view.addSubview(self.activityIndicator!)
            }
            self.activityIndicator?.startAnimating()
        }
    }
    
    private func hideLoadingOverlay() {
        DispatchQueue.main.async {
            self.activityIndicator?.stopAnimating()
            self.activityIndicator?.removeFromSuperview()
            self.activityIndicator = nil
        }
    }
}

// MARK: - PRIMER HEADLESS UNIVERSAL CHECKOUT DELEGATE

// MARK: Auto Payment Handling

extension MerchantHUCRawRetailDataViewController {
    
    func primerHeadlessUniversalCheckoutDidCompleteCheckoutWithData(_ data: PrimerCheckoutData) {
        print("\n\nMERCHANT APP\n\(#function)\ndata: \(data)")
        self.logs.append(#function)
        
        if let checkoutDataDictionary = try? data.asDictionary(),
           let jsonData = try? JSONSerialization.data(withJSONObject: checkoutDataDictionary, options: .prettyPrinted),
           let jsonString = jsonData.prettyPrintedJSONString {
            self.checkoutData.append(jsonString as String)
        }
        
        self.hideLoadingOverlay()
        let rvc = MerchantResultViewController.instantiate(checkoutData: self.checkoutData, error: self.primerError, logs: self.logs)
        self.navigationController?.pushViewController(rvc, animated: true)
    }
}

// MARK: Manual Payment Handling

extension MerchantHUCRawRetailDataViewController {
    
    func primerHeadlessUniversalCheckoutDidTokenizePaymentMethod(_ paymentMethodTokenData: PrimerPaymentMethodTokenData, decisionHandler: @escaping (PrimerResumeDecision) -> Void) {
        print("\n\nMERCHANT APP\n\(#function)\npaymentMethodTokenData: \(paymentMethodTokenData)")
        self.logs.append(#function)
        
        Networking.createPayment(with: paymentMethodTokenData) { (res, err) in
            if let err = err {
                self.showErrorMessage(err.localizedDescription)
                self.hideLoadingOverlay()

            } else if let res = res {
                self.paymentId = res.id
                
                if res.requiredAction?.clientToken != nil {
                    decisionHandler(.continueWithNewClientToken(res.requiredAction!.clientToken))
                    
                } else {
                    self.hideLoadingOverlay()
                    let rvc = MerchantResultViewController.instantiate(checkoutData: self.checkoutData, error: self.primerError, logs: self.logs)
                    self.navigationController?.pushViewController(rvc, animated: true)
                }

            } else {
                assert(true)
            }
        }
    }
    
    func primerHeadlessUniversalCheckoutDidResumeWith(_ resumeToken: String, decisionHandler: @escaping (PrimerResumeDecision) -> Void) {
        print("\n\nMERCHANT APP\n\(#function)\nresumeToken: \(resumeToken)")
        self.logs.append(#function)
        
        Networking.resumePayment(self.paymentId!, withToken: resumeToken) { (res, err) in
            DispatchQueue.main.async {
                self.hideLoadingOverlay()
            }
            
            if let err = err {
                self.showErrorMessage(err.localizedDescription)
                decisionHandler(.fail(withErrorMessage: "Merchant App\nFailed to resume payment."))
            } else {
                decisionHandler(.succeed())
            }
            
            let rvc = MerchantResultViewController.instantiate(checkoutData: self.checkoutData, error: self.primerError, logs: self.logs)
            self.navigationController?.pushViewController(rvc, animated: true)
        }
    }
}

extension MerchantHUCRawRetailDataViewController: UITableViewDataSource, UITableViewDelegate {
    
    // MARK: - Table View delegate methods

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selectedIndexPath != nil {
            self.tableView.cellForRow(at: selectedIndexPath!)?.accessoryType = .none
        }
        selectedIndexPath = indexPath
        self.tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        let retailer = retailers[indexPath.row]
        selectedOutletIdentifier = retailer.id
        self.tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Select a retailer"
    }
    
    // MARK: - Table View data source methods
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return retailers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let retailer = retailers[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        tableView.cellForRow(at: indexPath)?.accessoryType = selectedIndexPath == indexPath ? .checkmark : .none
        if #available(iOS 14.0, *) {
            var content = cell.defaultContentConfiguration()
            content.text = retailer.name
            cell.contentConfiguration = content
        } else {
            // Fallback on earlier versions
        }
        
        return cell
    }
}


// MARK: Common

extension MerchantHUCRawRetailDataViewController {

    func primerHeadlessUniversalCheckoutDidLoadAvailablePaymentMethods(_ paymentMethodTypes: [String]) {
        print("\n\nMERCHANT APP\n\(#function)")
        self.logs.append(#function)
    }
    
    func primerHeadlessUniversalCheckoutPreparationDidStart(for paymentMethodType: String) {
        print("\n\nMERCHANT APP\n\(#function)")
        self.logs.append(#function)
        self.showLoadingOverlay()
    }
    
    func primerHeadlessUniversalCheckoutTokenizationDidStart(for paymentMethodType: String) {
        print("\n\nMERCHANT APP\n\(#function)\npaymentMethodType: \(paymentMethodType)")
        self.logs.append(#function)
    }
    
    func primerHeadlessUniversalCheckoutPaymentMethodDidShow(for paymentMethodType: String) {
        print("\n\nMERCHANT APP\n\(#function)\npaymentMethodType: \(paymentMethodType)")
        self.logs.append(#function)
    }
    
    func primerHeadlessUniversalCheckoutDidReceiveAdditionalInfo(_ additionalInfo: PrimerCheckoutAdditionalInfo?) {
        print("\n\nMERCHANT APP\n\(#function)\nadditionalInfo: \(additionalInfo)")
        self.logs.append(#function)
        DispatchQueue.main.async {
            self.hideLoadingOverlay()
        }
    }
    
    func primerHeadlessUniversalCheckoutDidEnterResumePendingWithPaymentAdditionalInfo(_ additionalInfo: PrimerCheckoutAdditionalInfo?) {
        print("\n\nMERCHANT APP\n\(#function)\nadditionalInfo: \(additionalInfo)")
        self.logs.append(#function)
        if let checkoutDataDictionary = try? additionalInfo.asDictionary(),
           let jsonData = try? JSONSerialization.data(withJSONObject: checkoutDataDictionary, options: .prettyPrinted),
           let jsonString = jsonData.prettyPrintedJSONString {
            self.checkoutData.append(jsonString as String)
        }
        
        self.hideLoadingOverlay()
        let rvc = MerchantResultViewController.instantiate(checkoutData: self.checkoutData, error: self.primerError, logs: self.logs)
        self.navigationController?.pushViewController(rvc, animated: true)
    }
    
    func primerHeadlessUniversalCheckoutDidFail(withError err: Error) {
        print("\n\nMERCHANT APP\n\(#function)\nerror: \(err)")
        self.logs.append(#function)
        self.primerError = err
        DispatchQueue.main.async {
            self.hideLoadingOverlay()
        }
    }
    
    func primerHeadlessUniversalCheckoutClientSessionWillUpdate() {
        print("\n\nMERCHANT APP\n\(#function)")
        self.logs.append(#function)
    }
    
    func primerHeadlessUniversalCheckoutClientSessionDidUpdate(_ clientSession: PrimerClientSession) {
        print("\n\nMERCHANT APP\n\(#function)\nclientSession: \(clientSession)")
        self.logs.append(#function)
    }
    
    func primerHeadlessUniversalCheckoutWillCreatePaymentWithData(_ data: PrimerCheckoutPaymentMethodData, decisionHandler: @escaping (PrimerPaymentCreationDecision) -> Void) {
        print("\n\nMERCHANT APP\n\(#function)\ndata: \(data)")
        self.logs.append(#function)
        decisionHandler(.continuePaymentCreation())
    }
}

extension MerchantHUCRawRetailDataViewController: PrimerRawDataManagerDelegate {
    
    func primerRawDataManager(_ rawDataManager: PrimerHeadlessUniversalCheckout.RawDataManager, dataIsValid isValid: Bool, errors: [Error]?) {
        print("\n\nMERCHANT APP\n\(#function)\ndataIsValid: \(isValid)")
        self.logs.append(#function)
    }
    
    
    func primerRawDataManager(_ rawDataManager: PrimerHeadlessUniversalCheckout.RawDataManager, metadataDidChange metadata: [String : Any]?) {
        print("\n\nMERCHANT APP\n\(#function)\nmetadataDidChange: \(metadata)")
        self.logs.append(#function)
    }
}
