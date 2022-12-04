//
//  PipFlutterEzDrmAssetsLoaderDelegate.swift
//  Runner
//
//  Created by vicky Leu on 2022/12/4.
//

import Foundation
import AVKit
import AVFoundation

class PipFlutterEzDrmAssetsLoaderDelegate2 : NSObject {

   
    private(set)var certificateURL:URL
    private(set)var licenseURL:URL?
    
    var assetId:String!

    private let DEFAULT_LICENSE_SERVER_URL:String! = "https://fps.ezdrm.com/api/licenses/"

    init(_ certificateURL:URL, _ licenseURL:URL?) {
       super.init()
        self.certificateURL = certificateURL
        self.licenseURL = licenseURL
       
    }

    /*------------------------------------------
     **
     ** getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest
     **
     ** Takes the bundled SPC and sends it to the license server defined at licenseUrl or KEY_SERVER_URL (if licenseUrl is null).
     ** It returns CKC.
     ** ---------------------------------------*/
    func getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest(requestBytes:Data,  assetId:String,  customParams:String,  errorOut:Error) -> Data {
        var decodedData:Data
       
        var finalLicenseURL:URL
        if self.licenseURL != nil {
            finalLicenseURL = self.licenseURL!
        } else {
            finalLicenseURL = URL(string:DEFAULT_LICENSE_SERVER_URL)!
        }
        let ksmURL = URL(string:String(format:"\(finalLicenseURL)\(assetId)\(customParams)"))!
        var request = URLRequest.init(url: ksmURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField:"Content-type")
        request.httpBody = requestBytes
        var response: URLResponse?
        do {
            decodedData = try NSURLConnection.sendSynchronousRequest(request, returning: &response)
        }catch let error {
            print("SDK Error, SDK responded with Error: \(error)")
        }
        return decodedData
    }

    /*------------------------------------------
     **
     ** getAppCertificate
     **
     ** returns the apps certificate for authenticating against your server
     ** the example here uses a local certificate
     ** but you may need to edit this function to point to your certificate
     ** ---------------------------------------*/
    func getAppCertificate(_ string:String) -> Data? {
        var certificate:Data?
        do{
            certificate = try Data.init(contentsOf: self.certificateURL)
        }catch {
        }
        return certificate
    }

    func resourceLoader(resourceLoader:AVAssetResourceLoader!, shouldWaitForLoadingOfRequestedResource loadingRequest:AVAssetResourceLoadingRequest!) -> Bool {
        let assetURI = loadingRequest.request.url!
        let str = assetURI.absoluteString
        
        let mySubstring = str[(str.lengthOfBytes(using: .utf8) - 36)...]

        self.assetId = mySubstring
        let scheme = assetURI.scheme
        var requestBytes:Data!
        var certificate:Data!
        if !((scheme == "skd")) {
            return false
        }
        do {
            certificate = try self.getAppCertificate(self.assetId)
        }catch let error {
            loadingRequest.finishLoading(with: NSError(domain: URLError.errorDomain, code: URLError.clientCertificateRejected.rawValue,userInfo: nil))
        }
        do {
            try loadingRequest.streamingContentKeyRequestData(forApp: certificate, contentIdentifier: str.data(using: .utf8)!,options: nil)
        }catch let error {
            loadingRequest.finishLoading(with: nil)
            return true
        }

        let passthruParams = "?customdata=\(self.assetId)"
        var responseData:Data!
        var error:NSError!

        responseData = self.getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest(requestBytes: requestBytes, assetId: self.assetId, customParams: passthruParams, errorOut: error)
       
        if responseData != nil && responseData != nil && !responseData.dynamicType.isKindOfClass(NSNull.self) {
            let dataRequest:AVAssetResourceLoadingDataRequest! = loadingRequest.dataRequest
            dataRequest.respondWithData(responseData)
            loadingRequest.finishLoading()
        } else {
            loadingRequest.finishLoadingWithError(error)
        }

        return true
    }

    func resourceLoader(resourceLoader:AVAssetResourceLoader!, shouldWaitForRenewalOfRequestedResource renewalRequest:AVAssetResourceRenewalRequest!) -> Bool {
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource:renewalRequest)
    }
}
