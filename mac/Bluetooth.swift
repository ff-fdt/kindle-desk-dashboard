import Foundation
import CoreBluetooth
import AppKit
import CryptoKit
import Security

// Protocol v2: challenge authentication and per-session AES-GCM snapshots.
let serviceID = CBUUID(string: "E07E1000-7A51-4C44-A65A-5D45534B0001")
let infoID = CBUUID(string: "E07E1001-7A51-4C44-A65A-5D45534B0001")
let controlID = CBUUID(string: "E07E1002-7A51-4C44-A65A-5D45534B0001")
let dataID = CBUUID(string: "E07E1003-7A51-4C44-A65A-5D45534B0001")
let commandID = CBUUID(string: "E07E1004-7A51-4C44-A65A-5D45534B0001")
let chunkSize = 160

struct Session {
    var payload: Data
    var revision: String
    var sha256: String
    var format: String
    var secret: SymmetricKey
    var plainDigest: String
    var telemetrySequence: UInt32 = 0
    var touches = Set<String>()
    var page = 0
    var accessed = Date()
}

final class DeskPeripheral: NSObject, CBPeripheralManagerDelegate {
    var manager: CBPeripheralManager!
    let root: URL
    let key: Data
    var sessions: [UUID: Session] = [:]
    var challenges: [UUID: (Data, Date)] = [:]
    var info: CBMutableCharacteristic!
    var dataCharacteristic: CBMutableCharacteristic!
    var streams: [UUID: (CBCentral, Int)] = [:]
    var timer: Timer?
    var lastAcknowledged: Double?
    var acknowledgedRevision: String?
    var lastRendered: Double?
    var state = "starting"
    var lastError: String?
    var latestRevision = ""
    var pendingRevision: Data?

    init(root: URL, key: Data) {
        self.root = root
        self.key = key
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil,
                                      options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }

    func status() {
        var report: [String: Any] = ["state": state, "at": Date().timeIntervalSince1970,
                                     "authenticated_sessions": sessions.count, "revision": latestRevision]
        if let at = lastAcknowledged { report["received_at"] = at }
        if let rev = acknowledgedRevision { report["received_revision"] = rev }
        if let at = lastRendered { report["rendered_at"] = at }
        if let error = lastError { report["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("bluetooth-status.json"), options: .atomic)
        }
    }

    func pin(format: String = "json", secret: SymmetricKey, previous: Session? = nil) -> Session? {
        let filename = format == "png" ? "device.png" : "snapshot.json"
        guard let plain = try? Data(contentsOf: root.appendingPathComponent(filename)),
              plain.count <= 262116 else { return nil }
        let digest = SHA256.hash(data: plain).map { String(format: "%02x", $0) }.joined()
        if let previous = previous, previous.plainDigest == digest,
           previous.format == format + "-aesgcm" { return previous }
        guard let data = try? AES.GCM.seal(plain, using: secret).combined else { return nil }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Session(payload: data, revision: String(sha.prefix(16)), sha256: sha,
                       format: format + "-aesgcm", secret: secret, plainDigest: digest,
                       telemetrySequence: previous?.telemetrySequence ?? 0, touches: previous?.touches ?? [])
    }

    func commandPacket(secret: SymmetricKey) -> Data {
        let actions = ["brightness": 1, "warmth": 2, "native_settings": 3, "dashboard": 4, "status": 5]
        guard let data = try? Data(contentsOf: root.appendingPathComponent("command.json")),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seq = value["seq"] as? String, seq.count == 16,
              let queued = value["queued_at"] as? Double, Date().timeIntervalSince1970 - queued < 120,
              seq.allSatisfy({ "0123456789abcdef".contains($0) }),
              let action = value["action"] as? String, let code = actions[action] else { return Data([0]) }
        let level = value["value"] as? Int ?? 0
        guard 0...24 ~= level else { return Data([0]) }
        var packet = Data(seq.utf8) + Data([UInt8(code), UInt8(level)])
        packet.append(Data(HMAC<SHA256>.authenticationCode(for: packet, using: secret)))
        return packet
    }

    func tick() {
        sessions = sessions.filter { Date().timeIntervalSince($0.value.accessed) < 300 }
        challenges = challenges.filter { Date().timeIntervalSince($0.value.1) < 60 }
        if let data = try? Data(contentsOf: root.appendingPathComponent("snapshot.json")) {
            let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if String(revision.prefix(16)) != latestRevision {
            latestRevision = String(revision.prefix(16))
            pendingRevision = Data(latestRevision.utf8)
            flushNotification()
            }
        }
        status()
    }

    func flushNotification() {
        guard manager.state == .poweredOn, let info = info, let data = pendingRevision else { return }
        let centrals = info.subscribedCentrals?.filter { sessions[$0.identifier] != nil } ?? []
        if centrals.isEmpty || manager.updateValue(data, for: info, onSubscribedCentrals: centrals) {
            pendingRevision = nil
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            state = "powered_on"
            info = CBMutableCharacteristic(type: infoID, properties: [.read, .notify], value: nil,
                                            permissions: [.readable])
            let control = CBMutableCharacteristic(type: controlID, properties: [.write], value: nil,
                                                   permissions: [.writeable])
            let data = CBMutableCharacteristic(type: dataID, properties: [.read, .notify], value: nil,
                                                permissions: [.readable])
            dataCharacteristic = data
            let command = CBMutableCharacteristic(type: commandID, properties: [.read], value: nil,
                                                  permissions: [.readable])
            let service = CBMutableService(type: serviceID, primary: true)
            service.characteristics = [info, control, data, command]
            peripheral.add(service)
        case .unauthorized: state = "permission_required"
        case .poweredOff: state = "bluetooth_off"
        case .unsupported: state = "unsupported"
        default: state = "initializing"
        }
        status()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            state = "service_error"; lastError = error.localizedDescription
        } else {
            peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceID],
                                          CBAdvertisementDataLocalNameKey: "Kindle Desk"])
        }
        status()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        state = error == nil ? "advertising" : "advertising_error"
        lastError = error?.localizedDescription
        status()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushNotification()
        flushStreams()
    }

    func flushStreams() {
        for id in Array(streams.keys) {
            guard let stream = streams[id], let session = sessions[id] else {
                streams.removeValue(forKey: id); continue
            }
            let central = stream.0
            var offset = stream.1
            let size = min(chunkSize, central.maximumUpdateValueLength - 4)
            guard size > 0 else { streams.removeValue(forKey: id); continue }
            while offset < session.payload.count {
                var little = UInt32(offset).littleEndian
                var packet = withUnsafeBytes(of: &little) { Data($0) }
                let end = min(offset + size, session.payload.count)
                packet.append(session.payload.subdata(in: offset..<end))
                if !manager.updateValue(packet, for: dataCharacteristic, onSubscribedCentrals: [central]) {
                    streams[id] = (central, offset); return
                }
                offset = end
            }
            streams.removeValue(forKey: id)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if sessions[request.central.identifier] == nil, request.characteristic.uuid == infoID {
            let id = request.central.identifier
            if request.offset == 0 || challenges[id] == nil {
                var nonce = Data(count: 16)
                let success = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
                guard success == errSecSuccess else { peripheral.respond(to: request, withResult: .unlikelyError); return }
                challenges[id] = (nonce, Date())
            }
            let nonce = challenges[id]!.0
            guard request.offset <= nonce.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
            request.value = nonce.subdata(in: request.offset..<nonce.count)
            peripheral.respond(to: request, withResult: .success); return
        }
        guard var session = sessions[request.central.identifier] else {
            peripheral.respond(to: request, withResult: .insufficientAuthorization); return
        }
        session.accessed = Date()
        sessions[request.central.identifier] = session
        let value: Data
        if request.characteristic.uuid == commandID {
            value = commandPacket(secret: session.secret)
        } else if request.characteristic.uuid == infoID {
            let metadata: [String: Any] = ["v": 2, "bytes": session.payload.count,
                "chunk": chunkSize, "pages": (session.payload.count + chunkSize - 1) / chunkSize,
                "revision": session.revision, "sha256": session.sha256, "format": session.format]
            value = try! JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        } else if request.characteristic.uuid == dataID {
            let start = session.page * chunkSize
            guard start < session.payload.count else {
                peripheral.respond(to: request, withResult: .invalidOffset); return
            }
            value = session.payload.subdata(in: start..<min(start + chunkSize, session.payload.count))
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound); return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset); return
        }
        request.value = value.subdata(in: request.offset..<value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first else { return }
        var data = Data()
        for part in requests {
            guard part.central.identifier == request.central.identifier,
                  part.characteristic.uuid == controlID, part.offset == data.count,
                  let fragment = part.value, data.count + fragment.count <= 64 else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength); return
            }
            data.append(fragment)
        }
        guard let op = data.first else {
            peripheral.respond(to: request, withResult: .invalidAttributeValueLength); return
        }
        let id = request.central.identifier
        if op == 0 && data.count == 1 {
            streams.removeValue(forKey: id)
            sessions.removeValue(forKey: id)
            challenges.removeValue(forKey: id)
        } else if op == 1 {
            guard let (challenge, created) = challenges.removeValue(forKey: id),
                  Date().timeIntervalSince(created) < 60 else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization); return
            }
            let authMessage = Data("kindle-desk-auth-v2".utf8) + challenge
            guard HMAC<SHA256>.isValidAuthenticationCode(data.dropFirst(), authenticating: authMessage,
                        using: SymmetricKey(data: key)) else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization); return
            }
            let derived = HMAC<SHA256>.authenticationCode(for: Data("kindle-desk-data-v2".utf8) + challenge,
                        using: SymmetricKey(data: key))
            guard let session = pin(secret: SymmetricKey(data: Data(derived))) else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization); return
            }
            sessions[id] = session
        } else {
            guard var session = sessions[id] else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization); return
            }
            if op == 2 || op == 5 {
                guard let fresh = pin(format: op == 5 ? "png" : "json", secret: session.secret, previous: session) else {
                    peripheral.respond(to: request, withResult: .unlikelyError); return
                }
                session = fresh
            } else if op == 8 && data.count == 54,
                HMAC<SHA256>.isValidAuthenticationCode(data.suffix(32), authenticating: data.prefix(22), using: session.secret),
                let seq = String(data: data.subdata(in: 1..<17), encoding: .utf8) {
                let report: [String: Any] = ["seq": seq, "code": Int(data[17]),
                    "brightness": data[18] == 255 ? NSNull() : Int(data[18]) as Any,
                    "warmth": data[19] == 255 ? NSNull() : Int(data[19]) as Any,
                    "mode": data[20] == 1 ? "native_settings" : "dashboard",
                    "ok": data[21] == 0, "observed_at": Date().timeIntervalSince1970]
                let existingData = try? Data(contentsOf: root.appendingPathComponent("device-status.json"))
                let existing = existingData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if existing?["seq"] as? String != seq,
                   let encoded = try? JSONSerialization.data(withJSONObject: report) {
                    try? encoded.write(to: root.appendingPathComponent("device-status.json"), options: .atomic)
                }
            } else if op == 9 && data.count == 42,
                HMAC<SHA256>.isValidAuthenticationCode(data.suffix(32), authenticating: data.prefix(10), using: session.secret) {
                let sequence = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[1+$1]) << ($1*8) }
                guard sequence > session.telemetrySequence,
                      (data[5] <= 100 || data[5] == 255), (data[6] <= 1 || data[6] == 255),
                      (data[7] <= 24 || data[7] == 255), (data[8] <= 24 || data[8] == 255), data[9] <= 1 else {
                    peripheral.respond(to: request, withResult: .unlikelyError); return
                }
                session.telemetrySequence = sequence
                let report: [String: Any] = ["battery_percent": data[5] == 255 ? NSNull() : Int(data[5]) as Any,
                    "charging": data[6] == 255 ? NSNull() : (data[6] == 1) as Any,
                    "brightness": data[7] == 255 ? NSNull() : Int(data[7]) as Any,
                    "warmth": data[8] == 255 ? NSNull() : Int(data[8]) as Any,
                    "mode": data[9] == 1 ? "native_settings" : "dashboard",
                    "observed_at": Date().timeIntervalSince1970]
                if let encoded = try? JSONSerialization.data(withJSONObject: report) {
                    try? encoded.write(to: root.appendingPathComponent("telemetry.json"), options: .atomic)
                }
            } else if op == 10 && data.count == 53,
                HMAC<SHA256>.isValidAuthenticationCode(data.suffix(32), authenticating: data.prefix(21), using: session.secret),
                let seq = String(data: data.subdata(in: 1..<17), encoding: .utf8),
                seq.allSatisfy({ "0123456789abcdef".contains($0) }) {
                let x = Int(data[17]) | Int(data[18]) << 8, y = Int(data[19]) | Int(data[20]) << 8
                guard x < 1236, y < 1648 else { peripheral.respond(to: request, withResult: .unlikelyError); return }
                let oldData = try? Data(contentsOf: root.appendingPathComponent("panel-event.json"))
                let old = oldData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if !session.touches.contains(seq), old?["seq"] as? String != seq {
                    session.touches.insert(seq)
                    let event: [String: Any] = ["seq": seq, "x": x, "y": y, "at": Date().timeIntervalSince1970]
                    if let encoded = try? JSONSerialization.data(withJSONObject: event) {
                        try? encoded.write(to: root.appendingPathComponent("panel-event.json"), options: .atomic)
                    }
                }
            } else if op == 7 && data.count == 1 {
                guard dataCharacteristic.subscribedCentrals?.contains(where: { $0.identifier == id }) == true else {
                    peripheral.respond(to: request, withResult: .unlikelyError); return
                }
                streams[id] = (request.central, 0)
            } else if op == 3 && data.count == 3 {
                let page = Int(data[1]) | Int(data[2]) << 8
                guard page * chunkSize < session.payload.count else {
                    peripheral.respond(to: request, withResult: .invalidOffset); return
                }
                session.page = page
            } else if (op == 4 || op == 6), data.count == 49,
                String(data: data.subdata(in: 1..<17), encoding: .utf8) == session.revision,
                HMAC<SHA256>.isValidAuthenticationCode(data.suffix(32), authenticating: data.prefix(17), using: session.secret) {
                if op == 4 {
                lastAcknowledged = Date().timeIntervalSince1970
                acknowledgedRevision = session.revision
                } else { lastRendered = Date().timeIntervalSince1970 }
            } else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength); return
            }
            session.accessed = Date()
            sessions[id] = session
        }
        peripheral.respond(to: request, withResult: .success)
        if op == 7 { DispatchQueue.main.async { [weak self] in self?.flushStreams() } }
        status()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard CommandLine.arguments.count >= 2 else { fatalError("Expected state directory") }
let stateURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let keyURL = stateURL.appendingPathComponent("pairing-key.bin")
let pairingKey = try Data(contentsOf: keyURL)
guard pairingKey.count == 32 else { fatalError("Pairing key must be exactly 32 bytes") }
let peripheral = DeskPeripheral(root: stateURL, key: pairingKey)
app.run()
