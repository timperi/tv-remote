import XCTest
@testable import ATVRemoteCore

final class ProtocolTests: XCTestCase {
    func testSHA256KnownAnswers() {
        XCTAssertEqual(SHA256Hash.digest(Data()).hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Hash.digest(Data("abc".utf8)).hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let longer = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        XCTAssertEqual(SHA256Hash.digest(longer).hex, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testPairingSecretMatchesPythonVector() {
        // Generated with the same byte rules as PoloChallengeResponse.getAlpha
        // and checked against hashlib.sha256. Nonce is the last four hex digits.
        let digest = PairingSecret.digest(
            clientModulus: Data([0xC0, 0xFF, 0xEE]),
            clientExponent: Data([0x01, 0x00, 0x01]),
            serverModulus: Data([0x12, 0x34, 0x56, 0x78, 0x90]),
            serverExponent: Data([0x01, 0x00, 0x01]),
            nonce: Data([0x1F, 0x2A])
        )
        XCTAssertEqual(digest.hex, "f8fa93afdb4f2c43c0d7beae16fdaef804c1d23a7556445294a50d99c5d798da")

        // A leading sign byte, the kind BigInteger.toByteArray() adds, must not change the hash.
        let padded = PairingSecret.digest(
            clientModulus: Data([0x00, 0xC0, 0xFF, 0xEE]),
            clientExponent: Data([0x00, 0x01, 0x00, 0x01]),
            serverModulus: Data([0x12, 0x34, 0x56, 0x78, 0x90]),
            serverExponent: Data([0x01, 0x00, 0x01]),
            nonce: Data([0x1F, 0x2A])
        )
        XCTAssertEqual(padded, digest)

        // First byte of this digest is 0xF8, so the TV would display F81F2A.
        let secret = try? PairingSecret.make(
            clientModulus: Data([0xC0, 0xFF, 0xEE]),
            clientExponent: Data([0x01, 0x00, 0x01]),
            serverModulus: Data([0x12, 0x34, 0x56, 0x78, 0x90]),
            serverExponent: Data([0x01, 0x00, 0x01]),
            code: "f81f2a"
        )
        XCTAssertEqual(secret, digest)
        XCTAssertThrowsError(try PairingSecret.make(
            clientModulus: Data([0xC0, 0xFF, 0xEE]),
            clientExponent: Data([0x01, 0x00, 0x01]),
            serverModulus: Data([0x12, 0x34, 0x56, 0x78, 0x90]),
            serverExponent: Data([0x01, 0x00, 0x01]),
            code: "AB1F2A"
        )) { error in
            XCTAssertEqual(error as? PairingSecretError, .checksumMismatch)
        }
        XCTAssertThrowsError(try PairingSecret.make(
            clientModulus: Data([0x01]),
            clientExponent: Data([0x03]),
            serverModulus: Data([0x01]),
            serverExponent: Data([0x03]),
            code: "12"
        )) { error in
            XCTAssertEqual(error as? PairingSecretError, .invalidCode)
        }
    }

    func testOddLengthModulusDoesNotCrash() {
        // 0x0ABC has an odd hex length. androidtvremote2's bytes.fromhex path
        // throws on that; the Java reference strips leading zeros and stays valid.
        let digest = PairingSecret.digest(
            clientModulus: Data([0x0A, 0xBC]),
            clientExponent: Data([0x03]),
            serverModulus: Data([0x80]),
            serverExponent: Data([0x01, 0x00, 0x01]),
            nonce: Data([0x11, 0x22])
        )
        XCTAssertEqual(digest.hex, "37fbc5600632995faf6456dde1c36c02bc9f4d569889da64736e0adb06355c9e")
    }

    func testPairingMessagesMatchProtobuf() {
        XCTAssertEqual(
            PairingMessages.request(clientName: "Room Remote").hex,
            "080210c80152180a0961747672656d6f7465120b526f6f6d2052656d6f7465"
        )
        XCTAssertEqual(PairingMessages.options().hex, "080210c801a201080a04080310061801")
        XCTAssertEqual(PairingMessages.configuration().hex, "080210c801f201080a04080310061001")
        let secret = PairingMessages.secret(Data(0..<32))
        XCTAssertEqual(secret.hex, "080210c801c202220a20000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        // service_name is field 1, ahead of the client name.
        XCTAssertTrue(PairingMessages.request(clientName: "Room Remote").hex.contains("0a0961747672656d6f7465"))
    }

    func testPairingMachineFullHandshake() {
        var machine = PairingMachine(clientName: "Room Remote")
        XCTAssertEqual(machine.openingMessage().hex, PairingMessages.request(clientName: "Room Remote").hex)

        let ack = step(machine.handle(hex("080210c8015a0d0a0b4c6976696e6720526f6f6d")))
        XCTAssertEqual(ack, .send(PairingMessages.options()))
        let configured = step(machine.handle(hex("080210c801a201081204080310061802")))
        XCTAssertEqual(configured, .send(PairingMessages.configuration()))
        let prompt = step(machine.handle(hex("080210c801fa0100")))
        XCTAssertEqual(prompt, .promptForCode)

        let submitted = step(machine.submit(
            code: "F81F2A",
            clientModulus: Data([0xC0, 0xFF, 0xEE]),
            clientExponent: Data([0x01, 0x00, 0x01]),
            serverModulus: Data([0x12, 0x34, 0x56, 0x78, 0x90]),
            serverExponent: Data([0x01, 0x00, 0x01])
        ))
        let digest = PairingSecret.digest(
            clientModulus: Data([0xC0, 0xFF, 0xEE]),
            clientExponent: Data([0x01, 0x00, 0x01]),
            serverModulus: Data([0x12, 0x34, 0x56, 0x78, 0x90]),
            serverExponent: Data([0x01, 0x00, 0x01]),
            nonce: Data([0x1F, 0x2A])
        )
        XCTAssertEqual(submitted, .send(PairingMessages.secret(digest)))

        let done = step(machine.handle(hex("080210c801ca02040a021122")))
        XCTAssertEqual(done, .paired)
        XCTAssertEqual(machine.phase, .success)
    }

    func testPairingRejectsBadStatusAndKeepsCodeEntryOpen() {
        var machine = PairingMachine(clientName: "Room Remote")
        _ = machine.handle(hex("080210c8015a00"))
        _ = machine.handle(hex("080210c801a201081204080310061802"))
        _ = machine.handle(hex("080210c801fa0100900301"))
        let retry = machine.submit(
            code: "000000",
            clientModulus: Data([0x01]),
            clientExponent: Data([0x01]),
            serverModulus: Data([0x01]),
            serverExponent: Data([0x01])
        )
        guard case .failed = retry else {
            return XCTFail("expected a failed step")
        }
        XCTAssertEqual(machine.phase, .awaitingCode)

        var failed = PairingMachine(clientName: "Room Remote")
        let bad = failed.handle(hex("0802109203"))
        guard case .failed(let message) = bad else { return XCTFail("expected failure") }
        XCTAssertTrue(message.contains("rejected"))
    }

    func testRemoteCommandsMatchProtobuf() {
        XCTAssertEqual(
            RemoteMessages.configure(features: .requested).hex,
            "0a1c08e704121718012201312a0961747672656d6f74653205312e302e30"
        )
        XCTAssertEqual(RemoteMessages.setActive(features: .requested).hex, "120308e704")
        XCTAssertEqual(RemoteMessages.key(.dpadCenter, direction: .short).hex, "520408171003")
        XCTAssertEqual(RemoteMessages.key(.power, direction: .short).hex, "5204081a1003")
        XCTAssertEqual(RemoteMessages.powerButton().hex, "5204081a1003")
        XCTAssertEqual(RemoteMessages.pingResponse(7).hex, "4a020807")
        XCTAssertEqual(RemoteMessages.pingResponse(0).hex, "4a00")
        XCTAssertEqual(RemoteMessages.text("hi", imeCounter: 4, fieldCounter: 9)?.hex, "aa0112080410091a0c08011208080110011a026869")
        XCTAssertEqual(RemoteMessages.text("a", imeCounter: 0, fieldCounter: 0)?.hex, "aa01091a07080112031a0161")
        XCTAssertNil(RemoteMessages.text("", imeCounter: 0, fieldCounter: 0))
        XCTAssertEqual(RemoteMessages.launch(AppLink.youtube).hex, "d205190a1768747470733a2f2f7777772e796f75747562652e636f6d")
        XCTAssertEqual(RemoteMessages.launch(AppLink.netflix).hex, "d2050c0a0a6e6574666c69783a2f2f")
        XCTAssertEqual(AppLink.normalize("com.netflix.ninja"), "market://launch?id=com.netflix.ninja")
        XCTAssertEqual(AppLink.normalize(" https://www.youtube.com "), "https://www.youtube.com")
    }

    func testPowerButtonStaysShortPowerWhenTheTVIsOn() {
        let power = RemoteMessages.powerButton()
        XCTAssertEqual(power, RemoteMessages.key(.power, direction: .short))
        XCTAssertEqual(power.hex, "5204081a1003")
        XCTAssertNotEqual(power, RemoteMessages.key(.sleep, direction: .short))
        XCTAssertNotEqual(power, RemoteMessages.key(.wakeup, direction: .short))
        XCTAssertNotEqual(power, RemoteMessages.key(.power, direction: .startLong))
        XCTAssertNotEqual(power, RemoteMessages.key(.power, direction: .endLong))
    }

    func testRemoteSessionUpdatesStateAndReplies() {
        var state = TVState()
        let configure = RemoteSession.handle(hex("0a4508ff0712400a064252415649411204536f6e7918012201312a24636f6d2e676f6f676c652e616e64726f69642e74762e72656d6f74652e736572766963653205312e322e33"), state: &state)
        XCTAssertEqual(configure, [RemoteMessages.configure(features: .requested)])
        XCTAssertEqual(state.manufacturer, "Sony")
        XCTAssertEqual(state.model, "BRAVIA")

        let active = RemoteSession.handle(hex("120308e704"), state: &state)
        XCTAssertEqual(active, [RemoteMessages.setActive(features: .requested)])

        _ = RemoteSession.handle(hex("c202020801"), state: &state)
        XCTAssertEqual(state.isOn, true)
        _ = RemoteSession.handle(hex("c20200"), state: &state)
        XCTAssertEqual(state.isOn, false)

        let ping = RemoteSession.handle(hex("4204082a1001"), state: &state)
        XCTAssertEqual(ping.first?.hex, "4a02082a")

        _ = RemoteSession.handle(hex("9203043064380c"), state: &state)
        XCTAssertEqual(state.volumeLevel, 12)
        XCTAssertEqual(state.volumeMax, 100)
        XCTAssertEqual(state.isMuted, false)
        _ = RemoteSession.handle(hex("92030430194001"), state: &state)
        XCTAssertEqual(state.volumeLevel, 0)
        XCTAssertEqual(state.volumeMax, 25)
        XCTAssertEqual(state.isMuted, true)

        _ = RemoteSession.handle(hex("a2012a0a285207596f7554756265621d636f6d2e676f6f676c652e616e64726f69642e796f75747562652e7476"), state: &state)
        XCTAssertEqual(state.currentApp, "com.google.android.youtube.tv")
        _ = RemoteSession.handle(hex("aa010408031008"), state: &state)
        XCTAssertEqual(state.imeCounter, 3)
        XCTAssertEqual(state.fieldCounter, 8)
    }

    func testFramingSplitsAnywhere() throws {
        let message = RemoteMessages.key(.home, direction: .short)
        let framed = FrameDecoder.frame(message)
        XCTAssertEqual(framed.hex, "06520408031003")

        var decoder = FrameDecoder()
        var collected: [Data] = []
        for byte in framed {
            collected.append(contentsOf: try decoder.feed(Data([byte])))
        }
        XCTAssertEqual(collected, [message])

        let first = hex("08080210c801fa0100")
        let second = hex("0b080210c801ca02030a01ab")
        var both = FrameDecoder()
        let together = try both.feed(first + second)
        XCTAssertEqual(together.count, 2)
        XCTAssertEqual(together[0].hex, "080210c801fa0100")
        XCTAssertEqual(together[1].hex, "080210c801ca02030a01ab")

        var splitHeader = FrameDecoder()
        XCTAssertEqual(try splitHeader.feed(Data([0x80])), [])
        let rest = Data([0x01]) + Data(repeating: 0x11, count: 128)
        XCTAssertEqual(try splitHeader.feed(rest), [Data(repeating: 0x11, count: 128)])
    }

    func testRSAPublicKeyParsing() {
        let pkcs1 = Data([0x30, 0x0B, 0x02, 0x04, 0x00, 0xC0, 0xFF, 0xEE, 0x02, 0x03, 0x01, 0x00, 0x01])
        let parsed = RSAPublicKey.parse(pkcs1)
        XCTAssertEqual(parsed?.modulus, Data([0xC0, 0xFF, 0xEE]))
        XCTAssertEqual(parsed?.exponent, Data([0x01, 0x00, 0x01]))

        let bare = Data([0x30, 0x09, 0x02, 0x02, 0x0A, 0xBC, 0x02, 0x03, 0x01, 0x00, 0x01])
        XCTAssertEqual(RSAPublicKey.parse(bare)?.modulus, Data([0x0A, 0xBC]))

        // SubjectPublicKeyInfo: algorithm identifier plus a bit string wrapping PKCS#1.
        var spki = Data([
            0x30, 0x1F,
            0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00,
            0x03, 0x0E, 0x00
        ])
        spki.append(pkcs1)
        XCTAssertEqual(RSAPublicKey.parse(spki)?.modulus, Data([0xC0, 0xFF, 0xEE]))
    }

    func testCertificateContainsTheKeyAndName() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 1
        components.day = 1
        let start = components.date!
        components.year = 2036
        let end = components.date!
        let pkcs1 = Data([0x30, 0x09, 0x02, 0x02, 0x0A, 0xBC, 0x02, 0x03, 0x01, 0x00, 0x01])
        let signature = Data(repeating: 0xAB, count: 8)
        let certificate = X509Certificate.make(
            commonName: "Room Remote",
            serial: 1000,
            notBefore: start,
            notAfter: end,
            pkcs1PublicKey: pkcs1,
            signature: signature
        )
        XCTAssertEqual(certificate.first, 0x30)
        XCTAssertTrue(certificate.hex.contains("170d3236303130313030303030305a"))
        XCTAssertTrue(certificate.hex.contains(Data("Room Remote".utf8).hex))
        XCTAssertTrue(certificate.hex.contains(pkcs1.hex))
        XCTAssertTrue(certificate.hex.contains("30060101ff020100"))
        XCTAssertTrue(certificate.range(of: Data([0x00]) + pkcs1) != nil)
        XCTAssertTrue(certificate.hex.hasSuffix(signature.hex))

        let tbs = X509Certificate.tbsCertificate(
            commonName: "Room Remote",
            serial: 1000,
            notBefore: start,
            notAfter: end,
            pkcs1PublicKey: pkcs1
        )
        XCTAssertTrue(certificate.range(of: tbs) != nil)
    }

    private func hex(_ value: String) -> Data {
        Data(hex: value)!
    }

    private func step(_ step: PairingStep) -> PairingStep {
        if case .send(let data) = step {
            return .send(data)
        }
        return step
    }
}
