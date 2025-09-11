@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
func main() async {
    await OTAHostCLI.main()
}

if #available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *) {
    await main()
} else {
    fatalError("This app requires macOS 10.15 or later")
}