//
//  CallManager.swift
//  flutter_callkeep
//
//  Created by Hien Nguyen on 07/10/2021.
//

import CallKit
import Foundation

@available(iOS 10.0, *)
class CallManager: NSObject {
    private let callController = CXCallController()
    private var sharedProvider: CXProvider? = nil
    private(set) var calls = [Call]()

    func setSharedProvider(_ sharedProvider: CXProvider) {
        self.sharedProvider = sharedProvider
    }

    func startCall(_ data: Data) {
        let handle = CXHandle(type: getHandleType(data.handleType), value: data.handle)
        let uuid = UUID(uuidString: data.uuid)
        let startCallAction = CXStartCallAction(call: uuid!, handle: handle)
        startCallAction.isVideo = data.hasVideo
        let callTransaction = CXTransaction()
        callTransaction.addAction(startCallAction)
        // requestCall
        requestCall(callTransaction, action: "startCall", completion: { _ in
            // let callUpdate = CXCallUpdate()
            // callUpdate.remoteHandle = handle
            // callUpdate.supportsDTMF = data.supportsDTMF
            // callUpdate.supportsHolding = data.supportsHolding
            // callUpdate.supportsGrouping = data.supportsGrouping
            // callUpdate.supportsUngrouping = data.supportsUngrouping
            // callUpdate.hasVideo = data.hasVideo
            // callUpdate.localizedCallerName = data.callerName
            // // self.sharedProvider?.reportCall(with: uuid!, updated: callUpdate)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.sharedProvider?.reportOutgoingCall(with: uuid!, connectedAt: nil)
            }

            // self.sharedProvider?.reportOutgoingCall(with: uuid!, startedConnectingAt: nil)
            // self.sharedProvider?.reportOutgoingCall(with: uuid!, connectedAt: nil)
            print("Reported transaction")
        })
    }

    func requestSetMute(call: Call, muted: Bool, completion: @escaping (Error?) -> Void) {
        let action = CXSetMutedCallAction(call: call.uuid, muted: muted)
        let transaction = CXTransaction(action: action)

        print("callkeep - action \(muted)")

        callController.request(transaction) { error in
            completion(error)
        }
    }

    func connectCall(call: Call) {
        print("Connecting call with UUID: \(call.uuid.uuidString)")
        sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: nil)

        //   DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        //         // Show the call is connected after 10 seconds
        //         provider.reportOutgoingCall(with: uuid!, connectedAt: nil)
        //     }

        // let handle = CXHandle(type: getHandleType(data.handleType), value: data.handle)
        // let callUpdate: CXCallUpdate = CXCallUpdate()
        // callUpdate.remoteHandle = handle
        // callUpdate.supportsDTMF = data.supportsDTMF
        // callUpdate.supportsHolding = data.supportsHolding
        // callUpdate.supportsGrouping = data.supportsGrouping
        // callUpdate.supportsUngrouping = data.supportsUngrouping
        // callUpdate.hasVideo = data.hasVideo
        // callUpdate.localizedCallerName = data.callerName
        // self.sharedProvider?.reportCall(with: uuid!, updated: callUpdate)

        print("Call connected")
    }

    func endCall(call: Call) {
        let endCallAction = CXEndCallAction(call: call.uuid)
        let callTransaction = CXTransaction()
        callTransaction.addAction(endCallAction)

        print("callkeep - action \(endCallAction)")
        requestCall(callTransaction, action: "endCall")
    }

    func endAllCalls() {
        let calls = callController.callObserver.calls
        for call in calls {
            let endCallAction = CXEndCallAction(call: call.uuid)
            let callTransaction = CXTransaction()
            callTransaction.addAction(endCallAction)
            requestCall(callTransaction, action: "endAllCalls")
        }
    }

    func activeCalls() -> [[String: Any?]] {
        let calls = callController.callObserver.calls
        var json = [[String: Any?]]()
        for call in calls {
            let callItem = callWithUUID(uuid: call.uuid)
            if callItem != nil {
                let item: [String: Any?] = callItem!.data.toJSON()
                json.append(item)
            } else {
                let item: [String: String] = ["id": call.uuid.uuidString]
                json.append(item)
            }
        }
        return json
    }

    func setHold(call: Call, onHold: Bool) {
        let handleCall = CXSetHeldCallAction(call: call.uuid, onHold: onHold)
        let callTransaction = CXTransaction()
        callTransaction.addAction(handleCall)
        // requestCall
    }

    private func requestCall(_ transaction: CXTransaction, action: String, completion: ((Bool) -> Void)? = nil) {
        callController.request(transaction) { error in
            if let error = error {
                // fail
                print("Error requesting transaction: \(error)")
            } else {
                if action == "startCall" {
                    // push notification for Start Call
                } else if action == "endCall" || action == "endAllCalls" {
                    // push notification for End Call
                }
                completion?(error == nil)
                print("Requested transaction successfully: \(action)")
            }
        }
    }

    private func getHandleType(_ handleType: String?) -> CXHandle.HandleType {
        var typeDefault = CXHandle.HandleType.generic
        switch handleType {
        case "number":
            typeDefault = CXHandle.HandleType.phoneNumber
        case "email":
            typeDefault = CXHandle.HandleType.emailAddress
        default:
            typeDefault = CXHandle.HandleType.generic
        }
        return typeDefault
    }

    static let callsChangedNotification = Notification.Name("CallsChangedNotification")
    var callsChangedHandler: (() -> Void)?

    func callWithUUID(uuid: UUID) -> Call? {
        guard let idx = calls.firstIndex(where: { $0.uuid == uuid }) else { return nil }
        print("callkeep - found call \(calls[idx].uuid.uuidString)")
        return calls[idx]
    }

    func addCall(_ call: Call) {
        calls.append(call)
        call.stateDidChange = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.callsChangedHandler?()
            strongSelf.postCallNotification()
        }
        callsChangedHandler?()
        postCallNotification()
    }

    func updateCall(_ updatedCall: Call) {
        guard let idx = calls.firstIndex(where: { $0.uuid == updatedCall.uuid }) else { return }
        calls.replaceSubrange(idx ... idx, with: [updatedCall])
        callsChangedHandler?()
        postCallNotification()
    }

    func removeCall(_ call: Call) {
        guard let idx = calls.firstIndex(where: { $0 === call }) else { return }
        print("callkeep - removed call \(calls[idx].uuid.uuidString)")
        calls.remove(at: idx)
        callsChangedHandler?()
        postCallNotification()
    }

    func removeAllCalls() {
        calls.removeAll()
        callsChangedHandler?()
        postCallNotification()
    }

    private func postCallNotification() {
        NotificationCenter.default.post(name: type(of: self).callsChangedNotification, object: self)
    }
}
