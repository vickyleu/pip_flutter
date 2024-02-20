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
