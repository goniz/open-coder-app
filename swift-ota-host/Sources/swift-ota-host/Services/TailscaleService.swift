import Foundation

struct TailscaleService {
    static func getStatus() -> TailscaleStatus {
        // Try common paths for tailscale
        let tailscalePaths = ["/opt/homebrew/bin/tailscale", "/usr/bin/tailscale", "/usr/local/bin/tailscale"]
        var output: String?
        
        for path in tailscalePaths {
            if let result = ShellService.runIgnoringErrors("\(path) status --json") {
                output = result
                break
            }
        }
        
        guard let output = output else {
            Logger.warn("Tailscale not available")
            return TailscaleStatus.notRunning
        }
        
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selfInfo = json["Self"] as? [String: Any] else {
            return TailscaleStatus.notRunning
        }
        
        let machineName = selfInfo["HostName"] as? String ?? ""
        let tailnetName = (json["MagicDNSSuffix"] as? String ?? "").replacingOccurrences(of: ".ts.net", with: "")
        let hostname = "\(machineName).\(tailnetName).ts.net"
        
        return TailscaleStatus(
            isRunning: true,
            hostname: hostname,
            machineName: machineName,
            tailnetName: tailnetName
        )
    }
}