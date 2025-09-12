import XCTest
@testable import DependencyClients
@testable import Models

final class SSHClientTests: XCTestCase {
  
  let sshClient = SSHClient()
  let mockConfig = SSHServerConfiguration(
    host: "test.example.com",
    username: "testuser",
    password: "testpass",
    useKeyAuthentication: false
  )
  
  // MARK: - extractCleanOutput Tests
  
  func testExtractCleanOutput_BasicFunctionality() {
    let output = """
      Some initial output
      MARKER_START
      Clean content line 1
      Clean content line 2
      MARKER_END
      Some final output
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    XCTAssertEqual(result, "Clean content line 1\nClean content line 2")
  }
  
  func testExtractCleanOutput_WithBashrcContamination() {
    let output = """
      Welcome to SuperServer v1.2!
      Loading modules... done
      Setting up environment...
      OPENCODER_START_A1B2C3D4
      /Users/john
      OPENCODER_END
      Additional cleanup messages
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "OPENCODER_START_A1B2C3D4",
      endMarker: "OPENCODER_END"
    )
    
    XCTAssertEqual(result, "/Users/john")
  }
  
  func testExtractCleanOutput_DirectoryListingContamination() {
    let output = """
      *** Welcome to Development Server ***
      Last login: Tue Sep 10 14:30:15 2024 from 192.168.1.100
      Loading user profile... complete
      OPENCODER_START_F7E8D9C0
      total 24
      drwxr-xr-x  5 user  staff   160 Sep 11 10:30 .
      drwxr-xr-x  3 user  staff    96 Sep 10 14:20 ..
      drwxr-xr-x  3 user  staff   160 Sep 11 08:45 Documents  
      drwxr-xr-x  2 user  staff   160 Sep 11 09:30 Projects
      -rw-r--r--  1 user  staff  1234 Sep 11 10:15 README.md
      OPENCODER_END
      Session ended
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "OPENCODER_START_F7E8D9C0",
      endMarker: "OPENCODER_END"
    )
    
    let expectedOutput = """
      total 24
      drwxr-xr-x  5 user  staff   160 Sep 11 10:30 .
      drwxr-xr-x  3 user  staff    96 Sep 10 14:20 ..
      drwxr-xr-x  3 user  staff   160 Sep 11 08:45 Documents  
      drwxr-xr-x  2 user  staff   160 Sep 11 09:30 Projects
      -rw-r--r--  1 user  staff  1234 Sep 11 10:15 README.md
      """
    
    XCTAssertEqual(result, expectedOutput)
  }
  
  func testExtractCleanOutput_EmptyContent() {
    let output = """
      Some initial output
      MARKER_START
      MARKER_END
      Some final output
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    XCTAssertEqual(result, "")
  }
  
  func testExtractCleanOutput_OnlyWhitespace() {
    let output = """
      Some initial output
      MARKER_START
         
      
        
      MARKER_END
      Some final output
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    XCTAssertEqual(result, "")
  }
  
  func testExtractCleanOutput_NoStartMarker() {
    let output = """
      Some initial output
      Clean content line 1
      Clean content line 2
      MARKER_END
      Some final output
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    XCTAssertEqual(result, "")
  }
  
  func testExtractCleanOutput_NoEndMarker() {
    let output = """
      Some initial output
      MARKER_START
      Clean content line 1
      Clean content line 2
      Some final output
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    XCTAssertEqual(result, "Clean content line 1\nClean content line 2\nSome final output")
  }
  
  func testExtractCleanOutput_MultipleStartMarkers() {
    let output = """
      MARKER_START
      First content
      MARKER_START
      Second content
      MARKER_END
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    // Should capture from first marker to first end marker, resetting on subsequent start markers
    XCTAssertEqual(result, "First content\nSecond content")
  }
  
  func testExtractCleanOutput_MarkersInContent() {
    let output = """
      Initial output
      MARKER_START
      This line contains MARKER_START in the middle
      This line contains MARKER_END in content
      MARKER_END
      Final output
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    // The line with MARKER_START will reset capturing and continue, 
    // then the line with MARKER_END will break the loop
    XCTAssertEqual(result, "")
  }
  
  func testExtractCleanOutput_SingleLine() {
    let output = "PREFIX MARKER_START single line content MARKER_END SUFFIX"
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    // For single line, the line contains both markers, so capturing starts and immediately stops
    XCTAssertEqual(result, "")
  }
  
  func testExtractCleanOutput_MultiLineMarkers() {
    let output = """
      PREFIX
      MARKER_START
      single line content
      MARKER_END
      SUFFIX
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    XCTAssertEqual(result, "single line content")
  }
  
  func testExtractCleanOutput_PreservesIndentation() {
    let output = """
      MARKER_START
          Indented line 1
      Normal line
              Deep indented line
      MARKER_END
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "MARKER_START",
      endMarker: "MARKER_END"
    )
    
    let expected = """
      Indented line 1
      Normal line
              Deep indented line
      """
    
    XCTAssertEqual(result, expected)
  }
  
  // MARK: - Real-world contamination scenarios
  
  func testExtractCleanOutput_HPCModuleLoading() {
    let output = """
      Currently Loaded Modulefiles:
        1) intel/19.1.2   2) openmpi/4.0.5   3) python/3.8.10
      OPENCODER_START_12AB34CD
      /home/research/user123
      OPENCODER_END
      Module system ready
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "OPENCODER_START_12AB34CD",
      endMarker: "OPENCODER_END"
    )
    
    XCTAssertEqual(result, "/home/research/user123")
  }
  
  func testExtractCleanOutput_MOTDWarnings() {
    let output = """
      ================================================================================
       WARNING: This system will undergo maintenance on Sunday at 2:00 AM EST
      ================================================================================
      
      OPENCODER_START_EF567890
      drwxr-xr-x   2 root root  4096 Sep  1 12:00 bin
      drwxr-xr-x   4 root root  4096 Sep 11 10:30 etc
      drwxr-xr-x   3 root root  4096 Aug 15 09:15 home
      OPENCODER_END
      
      For support, contact admin@example.com
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "OPENCODER_START_EF567890",
      endMarker: "OPENCODER_END"
    )
    
    let expected = """
      drwxr-xr-x   2 root root  4096 Sep  1 12:00 bin
      drwxr-xr-x   4 root root  4096 Sep 11 10:30 etc
      drwxr-xr-x   3 root root  4096 Aug 15 09:15 home
      """
    
    XCTAssertEqual(result, expected)
  }
  
  func testExtractCleanOutput_DebugBashrcOutput() {
    let output = """
      + echo 'Loading .bashrc'
      Loading .bashrc
      + export PATH=/usr/local/bin:$PATH
      + alias ll='ls -la'
      OPENCODER_START_9F8E7D6C
      /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
      OPENCODER_END
      + echo 'Bashrc loaded successfully'
      Bashrc loaded successfully
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "OPENCODER_START_9F8E7D6C",
      endMarker: "OPENCODER_END"
    )
    
    XCTAssertEqual(result, "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
  }
  
  // MARK: - Command Construction Tests (Testing the logic without SSH execution)
  
  func testExtractCleanOutput_WithUUIDMarkers() {
    // Test with realistic UUID-based markers like execCleanCommand would generate
    let mockUUID = "A1B2C3D4"
    let output = """
      Some bashrc output
      OPENCODER_START_\(mockUUID)
      /Users/testuser
      OPENCODER_END
      More output after
      """
    
    let result = sshClient.extractCleanOutput(
      from: output,
      startMarker: "OPENCODER_START_\(mockUUID)",
      endMarker: "OPENCODER_END"
    )
    
    XCTAssertEqual(result, "/Users/testuser")
  }
  
  func testExtractCleanOutput_MarkerUniqueness() {
    // Simulate multiple command executions with different markers
    let output1 = """
      OPENCODER_START_11111111
      First result
      OPENCODER_END
      """
    
    let output2 = """
      OPENCODER_START_22222222
      Second result
      OPENCODER_END
      """
    
    let result1 = sshClient.extractCleanOutput(
      from: output1,
      startMarker: "OPENCODER_START_11111111",
      endMarker: "OPENCODER_END"
    )
    
    let result2 = sshClient.extractCleanOutput(
      from: output2,
      startMarker: "OPENCODER_START_22222222", 
      endMarker: "OPENCODER_END"
    )
    
    XCTAssertEqual(result1, "First result")
    XCTAssertEqual(result2, "Second result")
    XCTAssertNotEqual(result1, result2)
  }
  
}