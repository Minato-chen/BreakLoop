import Foundation

/// 软件更新检查器（基于 GitHub Releases API，零依赖、原生极简）
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()
    
    public enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case newVersionAvailable(version: String, releaseNotes: String, downloadURL: URL)
        case failed(message: String)
    }
    
    @Published public var status: UpdateStatus = .idle
    @Published public var lastCheckTime: Date?
    
    public let currentVersion = "2.0.0"
    public let repoURL = URL(string: "https://github.com/Minato-chen/BreakLoop")!
    public let releasesURL = URL(string: "https://github.com/Minato-chen/BreakLoop/releases")!
    
    private init() {}
    
    public func checkForUpdates(isUserInitiated: Bool = true) {
        if status == .checking { return }
        status = .checking
        
        let apiURL = URL(string: "https://api.github.com/repos/Minato-chen/BreakLoop/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("BreakLoop-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lastCheckTime = Date()
                
                if let error = error {
                    if isUserInitiated {
                        self.status = .failed(message: "网络请求失败：\(error.localizedDescription)")
                    } else {
                        self.status = .idle
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.status = .failed(message: "未收到有效服务器响应")
                    return
                }
                
                // 若仓库尚未发布任何 release（404），则表示当前已是最新
                if httpResponse.statusCode == 404 {
                    self.status = .upToDate(version: self.currentVersion)
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.status = .upToDate(version: self.currentVersion)
                    return
                }
                
                let cleanTag = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let htmlUrlStr = json["html_url"] as? String ?? "https://github.com/Minato-chen/BreakLoop/releases"
                let targetURL = URL(string: htmlUrlStr) ?? self.releasesURL
                let body = json["body"] as? String ?? ""
                
                if self.isVersion(cleanTag, newerThan: self.currentVersion) {
                    self.status = .newVersionAvailable(version: tagName, releaseNotes: body, downloadURL: targetURL)
                } else {
                    self.status = .upToDate(version: self.currentVersion)
                }
            }
        }.resume()
    }
    
    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
