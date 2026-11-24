import CryptoKit
import Foundation

// Verify a release archive against the public key embedded in the app, independently of the CI secret.
guard CommandLine.arguments.count == 4 else {
    fputs("Usage: verify_update <archive> <base64-signature> <public-key-file>\n", stderr)
    exit(2)
}
do {
    let arguments = CommandLine.arguments
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
    let encodedKey = try String(contentsOfFile: arguments[3], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let signature = Data(base64Encoded: arguments[2]), let keyData = Data(base64Encoded: encodedKey) else {
        throw NSError(domain: "UpdateVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid key or signature encoding"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: data) else {
        throw NSError(domain: "UpdateVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: "Update signature does not match the app's public key"])
    }
    print("Update signature verified against the embedded public key")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
