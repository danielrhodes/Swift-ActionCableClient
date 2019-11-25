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

enum SerializationError : Swift.Error {
    case json
    case encoding
    case protocolViolation
}

public enum ReceiveError : Swift.Error {
    case invalidIdentifier
    case unknownChannel
    case decoding
    case invalidFormat
    case unknownMessageType
}

public enum TransmitError : Swift.Error {
    case notConnected
    case notSubscribed
}

public enum ConnectionError : Swift.Error {
    case notFound(Error)
    case goingAway(Error)
    case refused(Error)
    case sslHandshake(Error)
    case unknownDomain(Error)
    case closed(Error)
    case protocolViolation(Error)
    case unknown(Error)
    case none
    
    var recoverable : Bool {
        switch self {
        case .notFound: return false
        case .goingAway: return false
        case .refused: return true
        case .sslHandshake: return false
        case .unknownDomain: return false
        case .protocolViolation: return false
        case .closed: return false
        case .unknown: return true
        case .none: return false
        }
    }
  
    init(from error: Swift.Error) {
      let error_code: Int
      if let ws_error = error as? WSError {
        error_code = ws_error.code
      } else {
        error_code = error._code
      }
      
      switch error_code {
      case 2: self = ConnectionError.unknownDomain(error)
      case 61: self = ConnectionError.refused(error)
      case 404: self = ConnectionError.notFound(error)
      case 1000: self = ConnectionError.closed(error)
      case 1002: self = ConnectionError.protocolViolation(error)
      case 1003: self = ConnectionError.protocolViolation(error)
      case 1005: self = ConnectionError.unknown(error)
      case 1007: self = ConnectionError.protocolViolation(error)
      case 1008: self = ConnectionError.protocolViolation(error)
      case 1009: self = ConnectionError.protocolViolation(error)
      case 9847: self = ConnectionError.sslHandshake(error)
      default:
        self = ConnectionError.unknown(error)
      }
    }
}
