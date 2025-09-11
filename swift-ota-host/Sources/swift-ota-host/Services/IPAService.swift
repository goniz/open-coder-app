import Foundation
import ZIPFoundation

struct IPAService {
    static func findIPAFiles() throws -> [IPAInfo] {
        let fileManager = FileManager.default
        let currentURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        let contents = try fileManager.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let ipaFiles = try contents
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .compactMap { url -> IPAInfo? in
                guard let attributes = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                    return nil
                }
                
                do {
                    let metadata = try extractIPAMetadata(from: url.path)
                    return IPAInfo(
                        path: url.path,
                        bundleId: metadata.bundleId,
                        version: metadata.version,
                        displayName: metadata.displayName,
                        buildNumber: metadata.buildNumber,
                        size: attributes.fileSize ?? 0,
                        modifiedTime: attributes.contentModificationDate ?? Date()
                    )
                } catch {
                    Logger.warn("Failed to extract metadata from \(url.lastPathComponent): \(error)")
                    let fallbackName = url.deletingPathExtension().lastPathComponent
                    return IPAInfo(
                        path: url.path,
                        bundleId: "com.unknown.\(fallbackName)",
                        version: "1.0.0",
                        displayName: fallbackName,
                        buildNumber: "1",
                        size: attributes.fileSize ?? 0,
                        modifiedTime: attributes.contentModificationDate ?? Date()
                    )
                }
            }
        
        return ipaFiles.sorted { $0.modifiedTime > $1.modifiedTime }
    }
    
    static func extractIPAMetadata(from ipaPath: String) throws -> IPAMetadata {
        guard let archive = Archive(url: URL(fileURLWithPath: ipaPath), accessMode: .read) else {
            throw OTAError.invalidIPA
        }
        
        guard let infoPlistEntry = archive.first(where: { $0.path.contains(".app/Info.plist") }) else {
            throw OTAError.missingInfoPlist
        }
        
        var plistData = Data()
        _ = try archive.extract(infoPlistEntry) { data in
            plistData.append(data)
        }
        
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        
        guard let bundleId = plist?["CFBundleIdentifier"] as? String,
              !bundleId.isEmpty else {
            throw OTAError.missingInfoPlist
        }
        
        let version = plist?["CFBundleShortVersionString"] as? String ?? plist?["CFBundleVersion"] as? String ?? "1.0.0"
        let displayName = plist?["CFBundleDisplayName"] as? String ?? plist?["CFBundleName"] as? String ?? "Unknown App"
        let buildNumber = plist?["CFBundleVersion"] as? String
        
        return IPAMetadata(
            bundleId: bundleId,
            version: version,
            displayName: displayName,
            buildNumber: buildNumber
        )
    }
}