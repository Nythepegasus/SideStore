//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import Foundation
import Network

import AltStoreCore

@objc(SendAppOperation)
class SendAppOperation: ResultOperation<()>
{
    let context: InstallAppOperationContext
    
    private let dispatchQueue = DispatchQueue(label: "com.sidestore.SendAppOperation")
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let resignedApp = self.context.resignedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // self.context.resignedApp.fileURL points to the app bundle, but we want the .ipa.
        let app = AnyApp(name: resignedApp.name, bundleIdentifier: self.context.bundleIdentifier, url: resignedApp.fileURL)
        let fileURL = InstalledApp.refreshedIPAURL(for: app)
        
        print("AFC App `fileURL`: \(fileURL.absoluteString)")
        
        let ns_bundle = NSString(string: app.bundleIdentifier)
        let ns_bundle_ptr = UnsafeMutablePointer<CChar>(mutating: ns_bundle.utf8String)

        if let data = NSData(contentsOf: fileURL) {
            let pls = UnsafeMutablePointer<UInt8>.allocate(capacity: data.length)
            for (index, data) in data.enumerated() {
                pls[index] = data
            }
            var attempts = 10
            let res = minimuxer_yeet_app_afc(ns_bundle_ptr, pls, UInt(data.length))
            while (attempts != 0 && res != 0){
                print("minimuxer_yeet_app_afc `res` != 0, retry #\(attempts)")
                let res = minimuxer_yeet_app_afc(ns_bundle_ptr, pls, UInt(data.length))
                attempts -= 1
            }
            if res == 0 {
                print("minimuxer_yeet_app_afc `res` == \(res)")
                self.progress.completedUnitCount += 1
                self.finish(.success(()))
            } else {
                self.finish(.failure(minimuxer_to_operation(code: res)))
            }
            
        } else {
            self.finish(.failure(ALTServerError(.underlyingError)))
        }
    }
}
