//
//  NetworkService.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/6/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

public protocol Services {
    var network: any NetworkService { get }
}

public protocol NetworkService {
    var session: URLSession { get }
    var sessionNoCache: URLSession { get }
    var backgroundSession: URLSession { get }
}
 
public struct DefaultServices: Services {
    public var network: NetworkService = AltNetworkService()
}

let AppServices = DefaultServices()

final public class AltNetworkDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate  {
    public override init() {
        super.init()
    }
    
    public struct Options: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let redirect = Options(rawValue: 1 << 0)
        public static let all: Options = [.redirect]
    }
    
    var options: Options = .all
    
//    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
//        if options.contains(.redirect) {
//            completionHandler(request)
//        } else {
//            completionHandler(nil)
//        }
//    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        if options.contains(.redirect) {
            return request
        } else {
            return nil
        }
    }
}

public final class AltNetworkService: NetworkService {
    let delegate = AltNetworkDelegate()
    
    lazy var delegateQueue: OperationQueue = {
        let queue = OperationQueue.init()
        queue.name = "com.sidestore.NetworkService.serialOperationQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    public lazy var session: URLSession = {
        let configuration: URLSessionConfiguration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpShouldUsePipelining = true
        let session = URLSession.init(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
        return session
    }()
    
    public lazy var sessionNoCache: URLSession = {
        let configuration: URLSessionConfiguration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession.init(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
        return session
    }()
    
    static let backgroundSessionIdentifier = "SideStoreBackgroundSession"
    
    public lazy var backgroundSession: URLSession = {
        let configuration: URLSessionConfiguration = URLSessionConfiguration.background(withIdentifier: AltNetworkService.backgroundSessionIdentifier)
        let session = URLSession.init(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return session
    }()
}
