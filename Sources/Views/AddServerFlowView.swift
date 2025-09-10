import ComposableArchitecture
import DependencyClients
import Models
import SwiftUI

struct AddServerFlowView: View {
    let onSave: (SSHServerConfiguration) -> Void
    let onCancel: () -> Void
    
    @State private var currentStep = 1
    @State private var config = SSHServerConfiguration()
    @State private var showingFingerprintAlert = false
    @State private var isTestingConnection = false
    @State private var testResult: TestResult?
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(currentStep) / 4.0)
                    .progressViewStyle(.linear)
                    .padding()
                
                stepContent
                
                Spacer()
                
                stepActions
            }
            .navigationTitle(stepTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .alert("Verify Host Fingerprint", isPresented: $showingFingerprintAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Accept") {
                    currentStep = 4
                }
            } message: {
                Text("Please verify the host fingerprint matches your expected fingerprint for \(config.host).")
            }
        }
    }
    
    private var stepTitle: String {
        switch currentStep {
        case 1: return "Server Details"
        case 2: return "Authentication"
        case 3: return "Host Fingerprint"
        case 4: return "Test Connection"
        default: return "Add Server"
        }
    }
    
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 1:
                ServerDetailsStep(config: $config)
            case 2:
                AuthenticationStep(config: $config)
            case 3:
                FingerprintStep(config: config)
            case 4:
                TestConnectionStep(
                    config: config,
                    isTesting: $isTestingConnection,
                    testResult: testResult,
                    onTest: testConnection
                )
            default:
                EmptyView()
            }
        }
        .padding()
    }
    
    private var stepActions: some View {
        HStack {
            if currentStep > 1 {
                Button("Previous") {
                    currentStep -= 1
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if currentStep < 4 {
                Button("Next") {
                    nextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedToNextStep)
            } else {
                Button("Save") {
                    onSave(config)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding()
    }
    
    private var canProceedToNextStep: Bool {
        switch currentStep {
        case 1:
            return !config.name.isEmpty && !config.host.isEmpty
        case 2:
            return config.useKeyAuthentication ? !config.privateKeyPath.isEmpty : !config.password.isEmpty
        case 3:
            return true // Always allow proceeding from fingerprint step
        default:
            return false
        }
    }
    
    private var canSave: Bool {
        if case .success = testResult {
            return true
        }
        return false
    }
    
    private func nextStep() {
        switch currentStep {
        case 1:
            currentStep = 2
        case 2:
            currentStep = 3
        case 3:
            showingFingerprintAlert = true
        default:
            break
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = nil
        
        Task {
            do {
                try await SSHClient.testConnection(config)
                await MainActor.run {
                    self.testResult = .success
                    self.isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    self.testResult = .failure(error.localizedDescription)
                    self.isTestingConnection = false
                }
            }
        }
    }
}

struct ServerDetailsStep: View {
    @Binding var config: SSHServerConfiguration
    
    var body: some View {
        Form {
            Section("Server Information") {
                TextField("Name", text: $config.name)
                    .textContentType(.name)
                    .placeholder("My Server")
                
                TextField("Host/IP", text: $config.host)
                    .textContentType(.URL)
                    .placeholder("192.168.1.100")
                
                TextField("Port", value: $config.port, formatter: NumberFormatter())
                    .textContentType(.none)
            }
            
            Section("Connection") {
                TextField("Username", text: $config.username)
                    .textContentType(.username)
                    .placeholder("user")
            }
        }
    }
}

struct AuthenticationStep: View {
    @Binding var config: SSHServerConfiguration
    @State private var showPassword = false
    @State private var showKeyImporter = false
    
    var body: some View {
        Form {
            Section("Authentication Method") {
                Toggle("Use Key Authentication", isOn: $config.useKeyAuthentication)
            }
            
            if config.useKeyAuthentication {
                keyAuthenticationSection
            } else {
                passwordAuthenticationSection
            }
        }
        .sheet(isPresented: $showKeyImporter) {
            KeyImporterView { keyPath in
                config.privateKeyPath = keyPath
            }
        }
    }
    
    private var passwordAuthenticationSection: some View {
        Section("Password Authentication") {
            SecureField("Password", text: $config.password)
                .textContentType(.password)
        }
    }
    
    private var keyAuthenticationSection: some View {
        Section("Key Authentication") {
            HStack {
                TextField("Private Key Path", text: $config.privateKeyPath)
                    .textContentType(.none)
                    .disabled(true)
                
                Button("Import") {
                    showKeyImporter = true
                }
                .buttonStyle(.bordered)
            }
            
            Button("Generate New Key") {
                generateNewKey()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func generateNewKey() {
        // Placeholder for key generation
        config.privateKeyPath = "~/.ssh/id_ed25519"
    }
}

struct FingerprintStep: View {
    let config: SSHServerConfiguration
    @State private var fingerprint = "SHA256:abcd1234..."
    
    var body: some View {
        Form {
            Section("Host Fingerprint") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server: \(config.host)")
                        .font(.headline)
                    
                    Text("Fingerprint:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(fingerprint)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("Please verify this fingerprint matches the expected fingerprint for this server.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button("Accept and Continue") {
                    // Continue to next step handled by parent
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }
}

struct TestConnectionStep: View {
    let config: SSHServerConfiguration
    @Binding var isTesting: Bool
    let testResult: AddServerFlowView.TestResult?
    let onTest: () -> Void
    
    var body: some View {
        Form {
            Section("Connection Test") {
                VStack(spacing: 16) {
                    if isTesting {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            
                            Text("Testing connection to \(config.host)...")
                                .font(.headline)
                        }
                        .padding()
                    } else if let result = testResult {
                        switch result {
                        case .success:
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)
                                
                                Text("Connection Successful!")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                
                                Text("Server \(config.name) is ready to use.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            
                        case .failure(let error):
                            VStack(spacing: 12) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.red)
                                
                                Text("Connection Failed")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "network")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)
                            
                            Text("Ready to Test")
                                .font(.headline)
                            
                            Text("Click the button below to test the connection to your server.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Test Connection") {
                                onTest()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                }
            }
            
            if testResult != nil {
                Section {
                    Button("Test Again") {
                        onTest()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct KeyImporterView: View {
    let onImport: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFile: URL?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Import Private Key")
                    .font(.title2)
                
                Text("Select your private key file (typically ~/.ssh/id_ed25519 or id_rsa)")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let file = selectedFile {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 32))
                        
                        Text(file.lastPathComponent)
                            .font(.headline)
                        
                        Text(file.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Button("Select Key File") {
                        selectKeyFile()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Import") {
                        if let file = selectedFile {
                            onImport(file.path)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFile == nil)
                }
            }
            .padding()
            .navigationTitle("Import Key")
        }
    }
    
    private func selectKeyFile() {
        // Mock file selection - in real implementation would use UIDocumentPickerViewController
        selectedFile = URL(fileURLWithPath: "~/.ssh/id_ed25519")
    }
}

#Preview {
    AddServerFlowView(onSave: { _ in }, onCancel: {})
}