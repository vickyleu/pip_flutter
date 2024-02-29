import Foundation

extension URL {
    var specialSchemeURL: URL {
        var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: false)!

        // 判断是否是 http 或 https
        if urlComponents.scheme == "http" {
            // 修改 scheme 为 myscheme
            urlComponents.scheme = "myscheme"
        } else if urlComponents.scheme == "https" {
            // 修改 scheme 为 myschemes
            urlComponents.scheme = "myschemes"
        }

        // 获取修改后的 URL
        return urlComponents.url!
    }

    var originalSchemeURL: URL {
        var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: false)!

        // 判断是否是 myscheme 或 myschemes
        if urlComponents.scheme == "myscheme" {
            // 修改 myscheme 为 http
            urlComponents.scheme = "http"
        } else if urlComponents.scheme == "myschemes" {
            // 修改 myschemes 为 https
            urlComponents.scheme = "https"
        }
        // 获取修改后的 URL
        return urlComponents.url!
    }
}


func createImage(from byteArray: [UInt8]) -> UIImage? {
    // 将 UInt8 数组转换为 Data
    let imageData = Data(byteArray)

    // 使用 Data 创建 UIImage
    if let image = UIImage(data: imageData) {
        return image
    } else {
        print("Failed to create UIImage from data")
        return nil
    }
}

// 从UIImage获取像素数据的扩展
extension UIImage {
    func scaleImage(toSize newSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: newSize)
        
        let scaledImage = renderer.image { (context) in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return scaledImage
    }

    func toUint8List() -> [UInt8]? {
        guard let cgImage = self.cgImage else {
            return nil
        }

        guard let data = self.pngData() else {
            return nil
        }
        // new constructor:
        let pixelData = [UInt8](data)

//        // …or old style through pointers:
//        let pixelData = data.withUnsafeBytes {
//            [UInt8](UnsafeBufferPointer(start: $0, count: data.count))
//        }
        return pixelData
    }
}
