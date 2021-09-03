//
//  PaymentResponse.swift
//  PrimerSDK
//
//  Created by Evangelos Pittas on 3/9/21.
//

import Foundation

@objc
public enum PaymentStatus: Int, Codable {
    case pending = 0
    case failed
    case authorized
    case settling
    case partiallySettled
    case settled
    case declined
    case cancelled
    
    public init?(strValue: String) {
        switch strValue.uppercased() {
        case "PENDING":
            self = .pending
        case "FAILED":
            self = .failed
        case "AUTHORIZED":
            self = .authorized
        case "SETTLING":
            self = .settling
        case "PARTIALLY_SETTLED":
            self = .partiallySettled
        case "SETTLED":
            self = .settled
        case "DECLINED":
            self = .declined
        case "CANCELLED":
            self = .cancelled
        default:
            return nil
        }
    }
}

@objc
public enum RequiredActionName: Int, Codable {
    case threeDSAuthentication = 0
    case usePrimerSDK
    case unknown = 1000
    
    public init?(strValue: String) {
        switch strValue.uppercased() {
        case "3DS_AUTHENTICATION":
            self = .threeDSAuthentication
        case "USE_PRIMER_SDK":
            self = .usePrimerSDK
        default:
            return nil
        }
    }
}

@objc
public protocol PaymentResponseProtocol {
    var id: String { get }
    var date: String { get }
    var status: PaymentStatus { get }
    var requiredAction: RequiredActionProtocol? { get }
}

@objc
public protocol RequiredActionProtocol {
    var name: RequiredActionName { get }
    var description: String { get }
    var clientToken: String? { get }
}
