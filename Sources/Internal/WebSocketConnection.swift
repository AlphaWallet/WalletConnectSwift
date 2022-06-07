//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import Foundation
import Starscream
import Network

class WebSocketConnection {
    let url: WCURL
    private let socket: WebSocket
    
    private var isConnected: Bool = false
    
    private let onConnect: (() -> Void)?
    private let onDisconnect: ((Error?) -> Void)?
    private let onTextReceive: ((String) -> Void)?
    
    private var requestSerializer: RequestSerializer = JSONRPCSerializer()
    private var responseSerializer: ResponseSerializer = JSONRPCSerializer()
    
    // serial queue for receiving the calls.
    private let serialCallbackQueue: DispatchQueue

    var isOpen: Bool {
        return isConnected
    }
    
    init(url: WCURL,
         onConnect: (() -> Void)?,
         onDisconnect: ((Error?) -> Void)?,
         onTextReceive: ((String) -> Void)?) {
        self.url = url
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onTextReceive = onTextReceive
        serialCallbackQueue = DispatchQueue(label: "org.walletconnect.swift.connection-\(url.bridgeURL)-\(url.topic)")
        
        self.socket = WebSocket(request: URLRequest(url: url.bridgeURL), engine: WSEngine(transport: FoundationTransport(), certPinner: FoundationSecurity()))
        self.socket.callbackQueue = serialCallbackQueue
        self.socket.delegate = self
    }
 
    func open() {
        self.socket.connect()
    }
    
    func close(closeCode: UInt16 = CloseCode.normal.rawValue) {
        self.socket.disconnect(closeCode: closeCode)
    }
    
    func send(_ text: String) {
        guard isConnected else { return }
        socket.write(string: text)
        log(text)
    }
    
    private func log(_ text: String) {
        if let request = try? requestSerializer.deserialize(text, url: url).json().string {
            LogService.shared.log("WC: ==> \(request)")
        } else if let response = try? responseSerializer.deserialize(text, url: url).json().string {
            LogService.shared.log("WC: ==> \(response)")
        } else {
            LogService.shared.log("WC: ==> \(text)")
        }
    }
}

extension WebSocketConnection: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            LogService.shared.log("WC: <== connected")
            isConnected = true
            onConnect?()
        case .disconnected:
            didDisconnect(with: nil)
        case .error(let error):
            didDisconnect(with: error)
        case .cancelled:
            didDisconnect(with: nil)
        case .text(let string):
            onTextReceive?(string)
        case .ping:
            LogService.shared.log("WC: <== ping")
            LogService.shared.log("WC: ==> pong client.respondToPingWithPong: \(client.respondToPingWithPong == true)")
            break
        case .pong:
            LogService.shared.log("WC: <== pong")
        case .reconnectSuggested:
            LogService.shared.log("WC: <== reconnectSuggested") //TODO: Should we?
        case .binary, .viabilityChanged:
            break
        }
    }
    
    private func didDisconnect(with error: Error? = nil) {
        LogService.shared.log("WC: <== disconnected")
        if let error = error {
            LogService.shared.log("^------ with error: \(error)")
        }
        self.isConnected = false
        onDisconnect?(error)
    }
}
