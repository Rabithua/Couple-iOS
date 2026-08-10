import AuthenticationServices
import Foundation
import UIKit

struct RegistrationCredentialResponse: Encodable, Sendable {
    struct Response: Encodable, Sendable {
        let clientDataJSON: String
        let attestationObject: String
        let transports: [String]
    }

    let id: String
    let rawId: String
    let response: Response
    let type = "public-key"
    let clientExtensionResults = ClientExtensionResults()
    let authenticatorAttachment = "platform"
}

struct AuthenticationCredentialResponse: Encodable, Sendable {
    struct Response: Encodable, Sendable {
        let clientDataJSON: String
        let authenticatorData: String
        let signature: String
        let userHandle: String?
    }

    let id: String
    let rawId: String
    let response: Response
    let type = "public-key"
    let clientExtensionResults = ClientExtensionResults()
    let authenticatorAttachment = "platform"
}

struct ClientExtensionResults: Encodable, Sendable {}

enum PasskeyError: LocalizedError {
    case malformedOptions
    case wrongCredentialType
    case missingAttestation
    case unavailable

    var errorDescription: String? {
        switch self {
        case .malformedOptions: "服务器返回的 Passkey 参数无效"
        case .wrongCredentialType: "系统返回了不支持的登录凭证"
        case .missingAttestation: "系统没有生成 Passkey 注册证明"
        case .unavailable: "此设备暂时无法使用 Passkey"
        }
    }
}

@MainActor
final class PasskeyService {
    private let coordinator = AuthorizationCoordinator()

    func register(options: PublicKeyCreationOptions) async throws -> RegistrationCredentialResponse {
        guard let challenge = Data(base64URLEncoded: options.challenge),
              let userID = Data(base64URLEncoded: options.user.id) else {
            throw PasskeyError.malformedOptions
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.rp.id
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: options.user.name,
            userID: userID
        )
        if #available(iOS 17.4, *) {
            request.excludedCredentials = options.excludeCredentials?.compactMap { descriptor in
                guard let id = Data(base64URLEncoded: descriptor.id) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            } ?? []
        }

        let authorization = try await coordinator.perform(request: request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw PasskeyError.wrongCredentialType
        }
        guard let attestation = credential.rawAttestationObject else {
            throw PasskeyError.missingAttestation
        }

        let credentialID = credential.credentialID.base64URLEncodedString()
        return RegistrationCredentialResponse(
            id: credentialID,
            rawId: credentialID,
            response: .init(
                clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                attestationObject: attestation.base64URLEncodedString(),
                transports: ["internal"]
            )
        )
    }

    func authenticate(options: PublicKeyRequestOptions) async throws -> AuthenticationCredentialResponse {
        guard let challenge = Data(base64URLEncoded: options.challenge) else {
            throw PasskeyError.malformedOptions
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.rpId
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = options.allowCredentials?.compactMap { descriptor in
            guard let id = Data(base64URLEncoded: descriptor.id) else { return nil }
            return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
        } ?? []

        let authorization = try await coordinator.perform(request: request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw PasskeyError.wrongCredentialType
        }

        let credentialID = credential.credentialID.base64URLEncodedString()
        return AuthenticationCredentialResponse(
            id: credentialID,
            rawId: credentialID,
            response: .init(
                clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                authenticatorData: credential.rawAuthenticatorData.base64URLEncodedString(),
                signature: credential.signature.base64URLEncodedString(),
                userHandle: credential.userID.isEmpty ? nil : credential.userID.base64URLEncodedString()
            )
        )
    }
}

@MainActor
private final class AuthorizationCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func perform(request: ASAuthorizationRequest) async throws -> ASAuthorization {
        guard continuation == nil else { throw PasskeyError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64.append(String(repeating: "=", count: 4 - remainder)) }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
