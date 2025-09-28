import Foundation

/// Helper function to properly escape shell arguments for remote execution.
public func escapeShellArgument(_ argument: String) -> String {
  let specialChars = CharacterSet(charactersIn: " \t\n\r'\"\\$`;&|()<>*?[]{}!")

  if argument.rangeOfCharacter(from: specialChars) != nil {
    let escaped = argument.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "'\(escaped)'"
  }

  return argument
}
