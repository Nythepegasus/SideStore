//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(FetchAnisetteDataOperation)
final class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>
{
    let context: OperationContext
    
    init(context: OperationContext)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        do {
            let fm = FileManager.default
            let documentsPath = fm.documentsDirectory.appendingPathComponent("adi.pb")
            print("ADI Path: \(documentsPath)")
            
            if !fm.fileExists(atPath: documentsPath.absoluteString) {
                self.fetchADIFile(session: URLSession.shared)
            }
            
            let url = AnisetteManager.currentURL
            DLOG("Anisette URL: %@", url.absoluteString)
            
            let session = URLSession.shared
            
            var postData = Data()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=ebd46b494f8b3f6926db4f30a3f371ae", forHTTPHeaderField: "Content-Type")

            // Get the raw data from the file.
            let rawData: Data = try Data(contentsOf: documentsPath)
            DLOG("adi.pb exists")
            postData.append("--ebd46b494f8b3f6926db4f30a3f371ae\r\n".data(using: .utf8)!)
            postData.append("Content-Disposition: form-data; name=\"adi.pb\"; filename=\"adi.pb\"\r\n\r\n".data(using: .utf8)!)
            for byte in rawData {
                postData.append(byte)
            }
            postData.append("\r\n--ebd46b494f8b3f6926db4f30a3f371ae\r\n".data(using: .utf8)!)
            let task = session.uploadTask(with: request, from: postData, completionHandler: { data, response, error in
                if let data = data {
                    do {
                        print(data)
                        // make sure this JSON is in the format we expect
                        // convert data to json
                        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                            // try to read out a dictionary
                            //for some reason serial number isn't needed but it doesn't work unless it has a value
                            let formattedJSON: [String: String] = ["machineID": json["X-Apple-I-MD-M"]!, "oneTimePassword": json["X-Apple-I-MD"]!, "localUserID": json["X-Apple-I-MD-LU"]!, "routingInfo": json["X-Apple-I-MD-RINFO"]!, "deviceUniqueIdentifier": json["X-Mme-Device-Id"]!, "deviceDescription": json["X-MMe-Client-Info"]!, "date": json["X-Apple-I-Client-Time"]!, "locale": json["X-Apple-Locale"]!, "timeZone": json["X-Apple-I-TimeZone"]!, "deviceSerialNumber": "1"]

                            if let anisette = ALTAnisetteData(json: formattedJSON) {
                                self.finish(.success(anisette))
                            }
                        }
                    } catch let error as NSError {
                        print("Failed to load: \(error.localizedDescription)")
                        self.finish(.failure(error))
                    }
                }
            })
            task.resume()
        } catch let error as NSError {
            self.fetchADIFile(session: URLSession.shared)
            return self.finish(.failure(error))
            
        }
    }
    
    func fetchADIFile(session: URLSession) {
        
        let fm = FileManager.default
        let documentsPath = fm.documentsDirectory.appendingPathComponent("adi.pb")

        print("ADI URL: \(AnisetteManager.currentURL.appendingPathComponent("adi_file").absoluteString)")
        
        let task = URLSession.shared.dataTask(with: AnisetteManager.currentURL.appendingPathComponent("adi_file")) { data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    let formattedJSON: [String: String] = ["machineID": json["X-Apple-I-MD-M"]!, "oneTimePassword": json["X-Apple-I-MD"]!, "localUserID": json["X-Apple-I-MD-LU"]!, "routingInfo": json["X-Apple-I-MD-RINFO"]!, "deviceUniqueIdentifier": json["X-Mme-Device-Id"]!, "deviceDescription": json["X-MMe-Client-Info"]!, "date": json["X-Apple-I-Client-Time"]!, "locale": json["X-Apple-Locale"]!, "timeZone": json["X-Apple-I-TimeZone"]!, "deviceSerialNumber": "1"]
                    if let anisette = ALTAnisetteData(json: formattedJSON) {
                        DLOG("Found anisette data instead of adi.pb file, fallback initiated")
                        
                        if let trustedURL = UserDefaults.shared.trustedServerURL {
                            print(trustedURL)
                            print(AnisetteManager.currentURLString)
                            if trustedURL == AnisetteManager.currentURLString {
                                return self.finish(.success(anisette))
                            }
                        }
                        
                        let alert = UIAlertController(title: "WARNING!", message: "We've detected you are using an older anisette server, using this server has a higher likelihood of locking your account, do you still want to continue?", preferredStyle: UIAlertController.Style.alert)
                        alert.addAction(UIAlertAction(title: "Continue", style: UIAlertAction.Style.destructive, handler: {action in
                            DLOG("Using older anisette method")
                            UserDefaults.shared.trustedServerURL = AnisetteManager.currentURLString
                            return self.finish(.success(anisette))
                        }))
                        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: {action in
                            DLOG("Cancelled the fallback operation")
                            return
                        }))
                        
                        let keyWindow = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
                        
                        DispatchQueue.main.async {
                            if let presentingController = keyWindow?.rootViewController?.presentedViewController {
                                presentingController.present(alert, animated: true)
                            } else {
                                keyWindow?.rootViewController?.present(alert, animated: true)
                            }
                        }
                    }
                }
            } catch _ as NSError {
                do {
                    try data.write(to: documentsPath)
                    DLOG("Wrote adi.pb file")
                    return
                } catch let error as NSError {
                    DLOG("ADI Write Error: %@", error.domain)
                    return self.finish(.failure(error))
                }
                
            }
        }
        
        task.resume()
    }
}
