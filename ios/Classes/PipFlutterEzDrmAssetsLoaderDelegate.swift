//
//  PipFlutterEzDrmAssetsLoaderDelegate.swift
//  Runner
//
//  Created by vicky Leu on 2022/12/4.
//

import Foundation
import AVKit
import AVFoundation

class PipFlutterEzDrmAssetsLoaderDelegate : NSObject,AVAssetResourceLoaderDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    
    typealias Completion = (URL?) -> Void
    // MARK: - Properties
      // MARK: Public
      
      var completion: Completion?
    
    
    private var infoResponse:   URLResponse?
       private var urlSession:     URLSession?
       private lazy var mediaData  = Data()
       private var loadingRequests = [AVAssetResourceLoadingRequest]()
    
    
    
    private(set)var certificateURL:URL?
    private(set)var licenseURL:URL?
    private(set)var isPureVideo:Bool=false
    
    var assetId:String!
    
    private let DEFAULT_LICENSE_SERVER_URL:String! = "https://fps.ezdrm.com/api/licenses/"
    
    init(_ certificateURL:URL, _ licenseURL:URL?) {
        self.certificateURL = certificateURL
        self.licenseURL = licenseURL
        self.isPureVideo=false
        super.init()
        
    }
    override init() {
        self.certificateURL = nil
        self.licenseURL = nil
        self.isPureVideo=true
        super.init()
        
    }
    
    /*------------------------------------------
     **
     ** getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest
     **
     ** Takes the bundled SPC and sends it to the license server defined at licenseUrl or KEY_SERVER_URL (if licenseUrl is null).
     ** It returns CKC.
     ** ---------------------------------------*/
    func getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest(requestBytes:Data,  assetId:String,  customParams:String,  errorOut:Error) -> Data? {
        var decodedData:Data?
        
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
            certificate = try Data.init(contentsOf: self.certificateURL!)
        }catch {
        }
        return certificate
    }
    
    
    
//    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
//        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
//    }
    
    // MARK: - AVAssetResourceLoaderDelegate
        
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            
            let assetURI = loadingRequest.request.url!.originalSchemeURL
            
            if !self.isPureVideo {
                let str = assetURI.absoluteString
                let index = str.index(str.endIndex, offsetBy: -36)
                let mySubstring = str[index...].utf8
                
                self.assetId = String(mySubstring)
                let scheme = assetURI.scheme
                var requestBytes:Data!
                var certificate:Data!
                if !((scheme == "skd")) {
                    return false
                }
                do {
                    certificate = try self.getAppCertificate(self.assetId)
                }catch  {
                    loadingRequest.finishLoading(with: NSError(domain: URLError.errorDomain, code: URLError.clientCertificateRejected.rawValue,userInfo: nil))
                }
                do {
                    try loadingRequest.streamingContentKeyRequestData(forApp: certificate, contentIdentifier: str.data(using: .utf8)!,options: nil)
                }catch {
                    loadingRequest.finishLoading(with: nil)
                    return true
                }
                
                let passthruParams = "?customdata=\(self.assetId)"
                var responseData:Data!
                var error:NSError!
                
                responseData = self.getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest(requestBytes: requestBytes, assetId: self.assetId, customParams: passthruParams, errorOut: error)
                if responseData != nil {
                    let dataRequest:AVAssetResourceLoadingDataRequest! = loadingRequest.dataRequest
                    dataRequest.respond(with: responseData)
                    loadingRequest.finishLoading()
                } else {
                    loadingRequest.finishLoading(with: error)
                }
            }else{
                if self.urlSession == nil {
                    self.urlSession = self.createURLSession()
                    let task = self.urlSession!.dataTask(with: assetURI)
                    task.resume()
                }
                self.loadingRequests.append(loadingRequest)
            }
            return true
        }
        
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
            if let index = self.loadingRequests.firstIndex(of: loadingRequest) {
                self.loadingRequests.remove(at: index)
            }
        }
        
    
    
    // MARK: - Public Methods
        
        func invalidate() {
            self.loadingRequests.forEach { $0.finishLoading() }
            self.invalidateURLSession()
        }
    
    
    // MARK: - URLSessionTaskDelegate
       
       func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
           var localFileURL: URL? = nil
           if let error = error {
               print("Failed to download media file with error: \(error)")
           } else {
               if let url = task.originalRequest?.url {
//                   print("task.originalRequest?.url==\(task.originalRequest?.url)")
                   localFileURL = self.saveMediaDataToLocalFile(url)
               }
           }
           
           DispatchQueue.main.async { [weak self] in
               self?.completion?(localFileURL)
               self?.invalidateURLSession()
           }
       }
       
       // MARK: - URLSessionDataDelegate
       
       func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
           self.infoResponse = response
           self.processRequests()
           
           completionHandler(.allow)
       }
       
       func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
           self.mediaData.append(data)
           self.processRequests()
       }
       
       // MARK: - Private Methods
       
       private func createURLSession() -> URLSession {
           let config = URLSessionConfiguration.default
           let operationQueue = OperationQueue()
           operationQueue.maxConcurrentOperationCount = 1
           return URLSession(configuration: config, delegate: self, delegateQueue: operationQueue)
       }
       
       private func invalidateURLSession() {
           self.urlSession?.invalidateAndCancel()
           self.urlSession = nil
       }
       
       private func isInfo(request: AVAssetResourceLoadingRequest) -> Bool {
           return request.contentInformationRequest != nil
       }

       private func fillInfoRequest(request: inout AVAssetResourceLoadingRequest, response: URLResponse) {
           request.contentInformationRequest?.isByteRangeAccessSupported = true
           request.contentInformationRequest?.contentType = response.mimeType
           request.contentInformationRequest?.contentLength = response.expectedContentLength
       }
       
       private func processRequests() {
           var finishedRequests = Set<AVAssetResourceLoadingRequest>()
           self.loadingRequests.forEach {
               var request = $0
               if self.isInfo(request: request), let response = self.infoResponse {
                   self.fillInfoRequest(request: &request, response: response)
               }
               if let dataRequest = request.dataRequest, self.checkAndRespond(forRequest: dataRequest) {
                   finishedRequests.insert(request)
                   request.finishLoading()
               }
           }
           
           self.loadingRequests = self.loadingRequests.filter { !finishedRequests.contains($0) }
       }
       
       private func checkAndRespond(forRequest dataRequest: AVAssetResourceLoadingDataRequest) -> Bool {
           let downloadedData          = self.mediaData
           let downloadedDataLength    = Int64(downloadedData.count)
           
           let requestRequestedOffset  = dataRequest.requestedOffset
           let requestRequestedLength  = Int64(dataRequest.requestedLength)
           let requestCurrentOffset    = dataRequest.currentOffset
           
           if downloadedDataLength < requestCurrentOffset {
               return false
           }
           
           let downloadedUnreadDataLength  = downloadedDataLength - requestCurrentOffset
           let requestUnreadDataLength     = requestRequestedOffset + requestRequestedLength - requestCurrentOffset
           let respondDataLength           = min(requestUnreadDataLength, downloadedUnreadDataLength)

           dataRequest.respond(with: downloadedData.subdata(in: Range(NSMakeRange(Int(requestCurrentOffset), Int(respondDataLength)))!))
           
           let requestEndOffset = requestRequestedOffset + requestRequestedLength
           
           return requestCurrentOffset >= requestEndOffset
       }
       
    private func saveMediaDataToLocalFile(_ url:URL) -> URL? {
           guard let docFolderURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
               return nil
           }
           let fileName = url.lastPathComponent
           let fileURL = docFolderURL.appendingPathComponent(fileName)
           
           if FileManager.default.fileExists(atPath: fileURL.path) {
               do {
                   try FileManager.default.removeItem(at: fileURL)
               } catch let error {
                   print("Failed to delete file with error: \(error)")
               }
           }
           
           do {
               try self.mediaData.write(to: fileURL)
           } catch let error {
               print("Failed to save data with error: \(error)")
               return nil
           }
           
           
           return fileURL
       }
    
}
