import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("swift-psl_PublicSuffixList.bundle").path
        let buildPath = "/Users/nathantracey/Library/Application Support/Dia/User Data/Profile 3/AgentServer/contexts/165EE830-9C2E-43CD-A390-1CA86CCFE7B1/work/Emerald-Ad-Blocker-main/src/BuildTool/.build/arm64-apple-macosx/debug/swift-psl_PublicSuffixList.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}