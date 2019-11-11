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

internal class JSONSerializer {
    static let nonStandardMessageTypes: [MessageType] = [.ping, .welcome]

    static func serialize(_ channel: Channel, command: Command, data: ActionPayload?) throws -> String {
        do {
            var commandDict: [String: Any] = [
                "command": command.string,
                "identifier": channel.identifier
            ]

            if let realData = data {
                let JSONData = try JSONSerialization.data(withJSONObject: realData, options: JSONSerialization.WritingOptions(rawValue: 0))
                guard let dataString = NSString(data: JSONData, encoding: String.Encoding.utf8.rawValue)
                else { throw SerializationError.json }

                commandDict["data"] = dataString
            }

            let CmdJSONData = try JSONSerialization.data(withJSONObject: commandDict, options: JSONSerialization.WritingOptions(rawValue: 0))
            guard let JSONString = NSString(data: CmdJSONData, encoding: String.Encoding.utf8.rawValue)
            else { throw SerializationError.json }

            return JSONString as String
        } catch {
            throw SerializationError.json
        }
    }

    static func deserialize(_ string: String) throws -> Message {
        do {
            guard let JSONData = string.data(using: String.Encoding.utf8) else { throw SerializationError.json }

            guard let JSONObj = try JSONSerialization.jsonObject(with: JSONData, options: .allowFragments) as? [String: AnyObject]
            else { throw SerializationError.json }

            var messageType: MessageType = .unrecognized
            if let typeObj = JSONObj["type"], let typeString = typeObj as? String {
                messageType = MessageType(string: typeString)
            }

            let channelName: String? = JSONObj["identifier"] as? String

            switch messageType {
            // Subscriptions
            case .confirmSubscription, .rejectSubscription, .cancelSubscription, .hibernateSubscription:
                guard let _ = channelName
                else { throw SerializationError.protocolViolation }

                return Message(channelName: channelName,
                               actionName: nil,
                               messageType: messageType,
                               data: nil,
                               error: nil)

            // Welcome/Ping messages
            case .welcome, .ping:
                return Message(channelName: nil,
                               actionName: nil,
                               messageType: messageType,
                               data: nil,
                               error: nil)
            case .message, .unrecognized:
                var messageActionName: String?
                var messageValue: AnyObject?
                var messageError: Swift.Error?

                do {
                    // No channel name was extracted from identifier
                    guard let _ = channelName
                    else { throw SerializationError.protocolViolation }

                    // No message was extracted from identifier
                    guard let messageObj = JSONObj["message"]
                    else { throw SerializationError.protocolViolation }

                    if let actionObj = messageObj["action"], let actionStr = actionObj as? String {
                        messageActionName = actionStr
                    }

                    messageValue = messageObj
                } catch {
                    messageError = error
                }

                return Message(channelName: channelName!,
                               actionName: messageActionName,
                               messageType: MessageType.message,
                               data: messageValue,
                               error: messageError)
            }
        } catch {
            throw error
        }
    }
}
