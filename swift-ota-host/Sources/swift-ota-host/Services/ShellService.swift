import Foundation

struct ShellService {
    static func run(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        guard process.terminationStatus == 0 else {
            throw OTAError.serverStartFailed
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func runIgnoringErrors(_ command: String) -> String? {
        do {
            return try run(command)
        } catch {
            return nil
        }
    }
}