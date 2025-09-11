import Foundation

struct Templates {
    static func manifestPlist(bundleId: String, version: String, title: String, ipaUrl: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>items</key>
            <array>
                <dict>
                    <key>assets</key>
                    <array>
                        <dict>
                            <key>kind</key>
                            <string>software-package</string>
                            <key>url</key>
                            <string>\(ipaUrl)</string>
                        </dict>
                    </array>
                    <key>metadata</key>
                    <dict>
                        <key>bundle-identifier</key>
                        <string>\(bundleId)</string>
                        <key>bundle-version</key>
                        <string>\(version)</string>
                        <key>kind</key>
                        <string>software</string>
                        <key>title</key>
                        <string>\(title)</string>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """
    }
    
    static func installHTML(appName: String, version: String, bundleId: String, installUrl: String, fileSize: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Install \(appName)</title>
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                    margin: 0; 
                    padding: 20px; 
                    background: #f5f5f7; 
                }
                .container { 
                    max-width: 600px; 
                    margin: 0 auto; 
                    background: white; 
                    border-radius: 12px; 
                    padding: 30px; 
                    box-shadow: 0 4px 12px rgba(0,0,0,0.1); 
                }
                .header { 
                    text-align: center; 
                    margin-bottom: 30px; 
                }
                .app-name { 
                    font-size: 28px; 
                    font-weight: 600; 
                    color: #1d1d1f; 
                    margin: 0; 
                }
                .version { 
                    font-size: 16px; 
                    color: #6e6e73; 
                    margin: 10px 0; 
                }
                .install-btn { 
                    display: block; 
                    background: #007AFF; 
                    color: white; 
                    text-decoration: none; 
                    padding: 16px 24px; 
                    border-radius: 8px; 
                    text-align: center; 
                    font-size: 18px; 
                    font-weight: 500; 
                    margin: 30px 0; 
                }
                .install-btn:hover { 
                    background: #0056CC; 
                }
                .info { 
                    background: #f6f6f6; 
                    border-radius: 8px; 
                    padding: 16px; 
                    margin: 20px 0; 
                }
                .info-item { 
                    margin: 8px 0; 
                }
                .label { 
                    font-weight: 500; 
                    color: #1d1d1f; 
                }
                .value { 
                    color: #6e6e73; 
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1 class="app-name">\(appName)</h1>
                    <div class="version">Version \(version)</div>
                </div>
                
                <a href="\(installUrl)" class="install-btn">Install App</a>
                
                <div class="info">
                    <div class="info-item">
                        <span class="label">Bundle ID:</span> 
                        <span class="value">\(bundleId)</span>
                    </div>
                    <div class="info-item">
                        <span class="label">File Size:</span> 
                        <span class="value">\(fileSize)</span>
                    </div>
                </div>
                
                <p style="text-align: center; color: #6e6e73; font-size: 14px; margin-top: 30px;">
                    Tap "Install App" above to install via iOS Safari
                </p>
            </div>
        </body>
        </html>
        """
    }
}

extension Int {
    func formatFileSize() -> String {
        let sizes = ["B", "KB", "MB", "GB"]
        if self == 0 { return "0 B" }
        let i = Int(log(Double(self)) / log(1024))
        let size = Double(self) / pow(1024, Double(i))
        return String(format: "%.1f %@", size, sizes[i])
    }
}