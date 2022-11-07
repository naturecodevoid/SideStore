//
//  FetchSourceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltStoreCore
import Roxas

func matches(for regex: String, in text: String) -> [String] {

    do {
        let regex = try NSRegularExpression(pattern: regex)
        let results = regex.matches(in: text,
                                    range: NSRange(text.startIndex..., in: text))
        return results.map {
            String(text[Range($0.range, in: text)!])
        }
    } catch let error {
        print("invalid regex: \(error.localizedDescription)")
        return []
    }
}

func containsRedirect(_ response: URLResponse?, data: Data?) -> String? {
    if let httpResponse = response as? HTTPURLResponse {
        print("Request status code: \(httpResponse.statusCode)")
        print("Request headers: \(httpResponse.allHeaderFields.debugDescription)")

        guard let data = data else {
            print("Request error: missing data")
            return nil
        }
        let rawHttp = String(decoding: data, as: UTF8.self)
        let regex = "url=((https|http):\\/\\/[\\S]*)\">"
        guard var redirectURL = matches(for: regex, in: rawHttp).first else {
            return nil
        }
        redirectURL = redirectURL.replacingOccurrences(of: "url=", with: "")
        redirectURL = redirectURL.replacingOccurrences(of: "\">", with: "")
        print("redirectURL: \(redirectURL)")
        return redirectURL
    } else {
        return nil
    }
}

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>
{
    let sourceURL: URL
    let managedObjectContext: NSManagedObjectContext
    
    private let session: URLSession = AppServices.network.sessionNoCache
    
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter
    }()
    
    init(sourceURL: URL, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.sourceURL = sourceURL
        self.managedObjectContext = managedObjectContext
    }
    
    override func main()
    {
        super.main()
        loadSource(self.sourceURL)
    }
    
    private func loadSource(_ url: URL) {
        let dataTask = createDataTask(with: url)
        self.progress.addChild(dataTask.progress, withPendingUnitCount: 1)
        
        dataTask.resume()
    }
    
    private func createDataTask(with url: URL) -> URLSessionDataTask {
        let dataTask = self.session.dataTask(with: url) { (data, response, error) in
            // Test code for http redirect HTML, though seems I got jekyll/sidestore to work without this now - @JoeMatt
            if let error = error {
                print("Request error: \(error)")
                // TODO: Handle error
                self.finish(.failure(error))
                return
            }
            
            if let redirect = containsRedirect(response, data: data), let redirectURL = URL(string: redirect) {
                DispatchQueue.main.async {
                    self.loadSource(redirectURL)
                }
            } else {
                self.processJSON(data: data, response: response, error: error)
            }
        }
        return dataTask
    }
    
    private func processJSON(data: Data?, response: URLResponse?, error: Error?) {
        let childContext = DatabaseManager.shared.persistentContainer.newBackgroundContext(withParent: self.managedObjectContext)
        childContext.mergePolicy = NSOverwriteMergePolicy
        childContext.perform {
            do
            {
                let (data, _) = try Result((data, response), error).get()
                
                let decoder = AltStoreCore.JSONDecoder()
                decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
                    let container = try decoder.singleValueContainer()
                    let text = try container.decode(String.self)
                    
                    // Full ISO8601 Format.
                    self.dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
                    if let date = self.dateFormatter.date(from: text)
                    {
                        return date
                    }
                    
                    // Just date portion of ISO8601.
                    self.dateFormatter.formatOptions = [.withFullDate]
                    if let date = self.dateFormatter.date(from: text)
                    {
                        return date
                    }
                    
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date is in invalid format.")
                })
                
                decoder.managedObjectContext = childContext
                // Note: This may need to be response.url instead, to handle redirects @JoeMatt
                decoder.sourceURL = self.sourceURL
                
                let source = try decoder.decode(Source.self, from: data)
                let identifier = source.identifier
                
                try childContext.save()
                
                self.managedObjectContext.perform {
                    if let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), identifier), in: self.managedObjectContext)
                    {
                        self.finish(.success(source))
                    }
                    else
                    {
                        self.finish(.failure(OperationError.noSources))
                    }
                }
            }
            catch
            {
                self.managedObjectContext.perform {
                    self.finish(.failure(error))
                }
            }
        }
    }
}
