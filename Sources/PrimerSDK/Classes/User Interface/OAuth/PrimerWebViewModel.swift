//
//  PrimerWebViewModel.swift
//  PrimerSDK
//
//  Created by Carl Eriksson on 05/08/2021.
//

#if canImport(UIKit)

import UIKit

internal protocol PrimerWebViewModelProtocol: AnyObject {
    func onRedirect(with url: URL)
    func onDismiss()
}

internal class ApayaWebViewModel: PrimerWebViewModelProtocol {

    var result: Result<Apaya.WebViewResult, ApayaException>?
    
    private func setResult(_ value: Result<Apaya.WebViewResult, ApayaException>?) {
        result = value
    }

    func onRedirect(with url: URL) {
        setResult(Apaya.WebViewResult.create(from: url))
    }

    func onDismiss() {
        guard let result = result else { return }
        let state: AppStateProtocol = DependencyContainer.resolve()
        state.setApayaResult(result)
        setResult(nil)
    }
}

#endif
