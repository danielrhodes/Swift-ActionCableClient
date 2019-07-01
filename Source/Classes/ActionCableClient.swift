//
//  Copyright (c) 2016 Daniel Rhodes <rhodes.daniel@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
//  USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import Starscream

public typealias ActionPayload = Dictionary<String, Any>

open class ActionCableClient {
  
    //MARK: Socket
    fileprivate(set) var socket : WebSocket
    
    /// Reconnection Strategy
    ///
    /// If a disconnection occurs, reconnnectionStrategy determines and calculates
    /// the time interval at which a retry happens.
    open var reconnectionStrategy : RetryStrategy = .logarithmicBackoff(maxRetries: 5, maxIntervalTime: 30.0)
    
    //MARK: Global Callbacks
    /// Will Connect
    ///
    /// Called when the client is about to connect
    open var willConnect: (() -> Void)?
    /// On Connected
    ///
    /// Called when the client has connected
    open var onConnected: (() -> Void)?
    /// On Disconnected
    ///
    /// Called when the client disconnected
    open var onDisconnected: ((ConnectionError?) -> Void)?
    /// Will Reconnect
    ///
    /// Called when the client is about to reconnect
    open var willReconnect: (() -> Bool)?
    /// On Rejected
    ///
    /// Called when the client has been rejected from connecting.
    open var onRejected: (() -> Void)?
    /// On Ping
    ///
    /// Called when the server pings the client
    open var onPing: (() -> Void)?
    
    // MARK: Channel Callbacks
    open var onChannelSubscribed: ((Channel) -> (Void))?
    open var onChannelUnsubscribed: ((Channel) -> (Void))?
    open var onChannelRejected: ((Channel) -> (Void))?
    open var onChannelReceive: ((Channel, Any?, Swift.Error?) -> Void)?
    
    //MARK: Properties
    open var isConnected : Bool { return socket.isConnected }
    open var url: Foundation.URL { return socket.currentURL }
    open var headers : [String: String]? {
        get { return socket.request.allHTTPHeaderFields }
        set {
            for (field, value) in newValue ?? [:] {
                socket.request.setValue(value, forHTTPHeaderField: field)
            }
        }
    }


    /// Initialize an ActionCableClient.
    ///
    /// Each client represents one connection to the server.
    ///
    /// This client must be retained somewhere, such as on the app delegate.
    ///
    ///  ```swift
    ///  let client = ActionCableClient(URL: NSURL(string: "ws://localhost:3000/cable")!)
    ///  ```

  public required init(url: URL) {
        /// Setup Initialize Socket
        socket = WebSocket(url: url)
        setupWebSocket()
}
    
    public required init(url: URL, headers: [String: String]? = nil, origin : String? = nil) {
        /// Setup Initialize Socket
        var request = URLRequest(url: url)
        
        if let origin = origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        
        for (field, value) in headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        socket = WebSocket(request: request)
        setupWebSocket()
    }
    
    /// Connect with the server
    @discardableResult
    open func connect() -> ActionCableClient {
        DispatchQueue.main.async {
          if let callback = self.willConnect {
            callback()
          }
          
          ActionCableConcurrentQueue.async {
            self.socket.connect()
            self.reconnectionState = nil
          }
        }
  
        return self
    }
  
    /// Disconnect from the server.
    open func disconnect() {
        manualDisconnectFlag = true
        socket.disconnect(forceTimeout: 0)
    }
    
    internal func reconnect() {
        DispatchQueue.main.async {
            var shouldReconnect = true
            if let callback = self.willReconnect {
                shouldReconnect = callback()
            }
            
            // Reconnection has been cancelled
            if (!shouldReconnect) {
                self.reconnectionState = nil
                return
            }
          
            if let callback = self.willConnect {
              callback()
            }
            
            ActionCableConcurrentQueue.async {
                self.socket.connect()
            }
        }
    }
  
    @discardableResult
    internal func transmit(_ data: ActionPayload? = nil, on channel: Channel, as command: Command) throws -> Bool {
        // First let's see if we can even encode this data
        
        let JSONString = try JSONSerializer.serialize(channel, command: command, data: data)
        
        //
        // If it's a message, let's see if we are subscribed first.
        //
        // It is important to check this one first, because if we are buffering
        // actions, we want to tell the channel it's not subscribed rather
        // than we are not connected.
        //
        
        if (command == Command.message) {
            guard channel.isSubscribed else { throw TransmitError.notSubscribed }
        }
      
        // Let's check if we are connected.
        guard isConnected else { throw TransmitError.notConnected }
      
        socket.write(string: JSONString) {
          //FINISHED!
        }
        
        return true
    }
    
    // MARK: Properties
    fileprivate var channelArray = Array<Channel>()
    fileprivate(set) var channels = Dictionary<String, Channel>()
    fileprivate var unconfirmedChannels = Dictionary<String, Channel>()
    
    /// Reconnection State
    /// This keeps our reconnection state around while we try to reconnect
    fileprivate var reconnectionState : RetryHandler?
    
    /// Manual Disconnect Flag
    ///
    /// This flag tells us if we decided to manually disconnect
    /// or it happened upstream.
    fileprivate var manualDisconnectFlag : Bool = false
}

//MARK: Channel Creation
extension ActionCableClient {
    /// Create and subscribe to a channel.
    ///
    /// - Parameters:
    ///     - name: The name of the channel. The name must match the class name on the server exactly. (e.g. RoomChannel)
    /// - Returns: a Channel
    
    public func create(_ name: String) -> Channel {
        let channel = create(name, identifier: nil, autoSubscribe: true, bufferActions: true)
        return channel
    }
    
    /// Create and subscribe to a channel.
    /// 
    /// - Parameters:
    ///     - name: The name of the channel. The name must match the class name on the server exactly. (e.g. RoomChannel)
    ///     - identifier: An optional Dictionary with parameters to be passed into the Channel on each request
    ///     - autoSubscribe: Whether to automatically subscribe to the channel. Defaults to true.
    /// - Returns: a Channel
    
    public func create(_ name: String, identifier: ChannelIdentifier?, autoSubscribe: Bool=true, bufferActions: Bool=true) -> Channel {
		
        var channelUID = name
        
        //if identifier isn't empty, fetch the first value as the channel unique identifier
        if let dictionary = identifier?.first {
            channelUID = dictionary.value as! String
        }
		
        // Look in existing channels and return that
        if let channel = channels[channelUID] { return channel }
        
        // Look in unconfirmed channels and return that
        if let channel = unconfirmedChannels[channelUID] { return channel }
        
        // Otherwise create a new one
        let channel = Channel(name: name,
            identifier: identifier,
            client: self,
            autoSubscribe: autoSubscribe,
            shouldBufferActions: bufferActions)
      
        self.unconfirmedChannels[channel.uid] = channel
      
        if (channel.autoSubscribe) {
          subscribe(channel)
        }
        
        return channel
    }
    
    public subscript(name: String) -> Channel {
        let channel = create(name, identifier: nil, autoSubscribe: true, bufferActions: true)
        return channel
    }
}

// MARK: Channel Subscriptions
extension ActionCableClient {
    
    public func subscribed(_ name: String) -> Bool {
        return self.channels.keys.contains(name)
    }
    
    internal func subscribe(_ channel: Channel) {
        // Is it already added and subscribed?
        if let existingChannel = channels[channel.uid] , (existingChannel == channel) {
            debugPrint("[ActionCableClient] channel exists and subscribed to");
          return
        }
      
        guard let channel = unconfirmedChannels[channel.uid]
          else { debugPrint("[ActionCableClient] Internal inconsistency error!"); return }
      
        do {
          try transmit(on: channel, as: Command.subscribe)
        } catch {
            debugPrint(error)
        }
    }
    
    internal func unsubscribe(_ channel: Channel) {
        do {
          try self.transmit(on: channel, as: Command.unsubscribe)
            
            let message = Message(channelName: channel.uid,
                                   actionName: nil,
                                  messageType: MessageType.cancelSubscription,
                                         data: nil,
                                        error: nil)
            
            onMessage(message)
        } catch {
            // There is a chance here the server could be down or not connected.
            // However, at this point the client will need to reconnect anyways
            // and will not resubscribe to the channel.
            debugPrint(error)
        }
    }
  
    @discardableResult
    internal func action(_ action: String, on channel: Channel, with data: ActionPayload?) throws -> Bool {
          var internalData : ActionPayload
          if let data = data {
              internalData = data
          } else {
              internalData = ActionPayload()
          }
          
          internalData["action"] = action
      
          return try transmit(internalData, on: channel, as: .message)
      }
}

// MARK: WebSocket Callbacks
extension ActionCableClient {
    
    fileprivate func setupWebSocket() {
        self.socket.onConnect = { [weak self] in self!.didConnect() } as (() -> Void)
        self.socket.onDisconnect = { [weak self] (error: Swift.Error?) in self!.didDisconnect(error) }
        self.socket.onText       = { [weak self] (text: String) in self!.onText(text) }
        self.socket.onData       = { [weak self] (data: Data) in self!.onData(data) }
        self.socket.onPong       = { [weak self] (data: Data?) in self!.didPong() }
    }
    
    fileprivate func didConnect() {
        
        // Clear Reconnection State: We successfull connected
        reconnectionState = nil
        
        if let callback = onConnected {
            DispatchQueue.main.async(execute: callback)
        }
        
        for (_, channel) in self.unconfirmedChannels {
            if channel.autoSubscribe {
                self.subscribe(channel)
            }
        }
    }
    
    fileprivate func didDisconnect(_ error: Swift.Error?) {
        
        var attemptReconnect: Bool = true
        var connectionError: ConnectionError?
        
        let channels = self.channels
        for (_, channel) in channels {
            let message = Message(channelName: channel.uid, actionName: nil, messageType: MessageType.hibernateSubscription, data: nil, error: nil)
            onMessage(message)
        }
        
        // Attempt Reconnection?
        if let unwrappedError = error {
          connectionError = ConnectionError(from: unwrappedError)
            attemptReconnect = connectionError!.recoverable
        }
        
        // Reconcile reconncetion attempt with manual disconnect
        attemptReconnect = !manualDisconnectFlag && attemptReconnect
        
        // disconnect() has not been called and error is
        // worthy of attempting a reconnect.
        if (attemptReconnect) {
            switch reconnectionStrategy {
            // We are going to need a retry handler (state machine) for these
            case .linear, .exponentialBackoff, .logarithmicBackoff:
                if reconnectionState == nil {
                    reconnectionState = RetryHandler(strategy: reconnectionStrategy)
                }
                
                reconnectionState?.retry {[weak self] in
                    self?.reconnect()
                }
                
                return
            // if strategy is None, we don't want to reconnect
            case .none: break
            }
        }
        
        
        // Clear Reconnetion State
        reconnectionState = nil
        
        // Fire Callbacks
        if let callback = onDisconnected {
            // Clear the Connection Error on a manual disconnect
            // as it will not seem accurate
            if manualDisconnectFlag { connectionError = nil }
            
            DispatchQueue.main.async(execute: { callback(connectionError) })
        }
        
        // Reset Manual Disconnect Flag
        manualDisconnectFlag = false
    }
    
    fileprivate func didPong() {
        // This never seems to fire with ActionCable!
    }
    
    fileprivate func onText(_ text: String) {
        ActionCableConcurrentQueue.async(execute: { () -> Void in
            do {
                let message = try JSONSerializer.deserialize(text)
                self.onMessage(message)
            } catch {
                print("[ActionCableClient] Error decoding message: \(error)")
            }
        })
    }
    
    fileprivate func onMessage(_ message: Message) {
            switch(message.messageType) {
            case .unrecognized:
                break
            case .welcome:
                break
            case .ping:
                if let callback = onPing {
                    DispatchQueue.main.async(execute: callback)
                }
            case .message:
                if let channel = channels[message.channelName!] {
                    // Notify Channel
                    channel.onMessage(message)
                    
                    if let callback = onChannelReceive {
                        DispatchQueue.main.async(execute: { callback(channel, message.data, message.error) } )
                    }
                }
            case .confirmSubscription:
                if let channel = unconfirmedChannels.removeValue(forKey: message.channelName!) {
                    self.channels.updateValue(channel, forKey: channel.uid)
                    
                    // Notify Channel
                    channel.onMessage(message)
                    
                    if let callback = onChannelSubscribed {
                        DispatchQueue.main.async(execute: { callback(channel) })
                    }
                }
            case .rejectSubscription:
                // Remove this channel from the list of unconfirmed subscriptions
                if let channel = unconfirmedChannels.removeValue(forKey: message.channelName!) {
                    
                    // Notify Channel
                    channel.onMessage(message)
                    
                    if let callback = onChannelRejected {
                        DispatchQueue.main.async(execute: { callback(channel) })
                    }
                }
            case .hibernateSubscription:
              if let channel = channels.removeValue(forKey: message.channelName!) {
                // Add channel into unconfirmed channels
                unconfirmedChannels[channel.uid] = channel
                
                // We want to treat this like an unsubscribe.
                fallthrough
              }
            case .cancelSubscription:
                if let channel = channels.removeValue(forKey: message.channelName!) {
                    
                    // Notify Channel
                    channel.onMessage(message)
                    
                    if let callback = onChannelUnsubscribed {
                        DispatchQueue.main.async(execute: { callback(channel) })
                    }
                }
            }
    }
    
    fileprivate func onData(_ data: Data) {
        debugPrint("Received NSData from ActionCable.")
    }
}

extension ActionCableClient : CustomDebugStringConvertible {
    public var debugDescription : String {
            return "ActionCableClient(url: \"\(socket.currentURL)\" connected: \(socket.isConnected) id: \(Unmanaged.passUnretained(self).toOpaque()))"
    }
}

extension ActionCableClient : CustomPlaygroundQuickLookable {
  public var customPlaygroundQuickLook: PlaygroundQuickLook {
        return PlaygroundQuickLook.url(socket.currentURL.absoluteString)
    }
}

extension ActionCableClient {
    func copyWithZone(_ zone: NSZone?) -> AnyObject! {
        assert(false, "This class doesn't implement NSCopying. ")
        return nil
    }
    
    func copy() -> AnyObject! {
        assert(false, "This class doesn't implement NSCopying")
        return nil
    }
}
