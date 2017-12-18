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

public enum RetryStrategy {
  
  case exponentialBackoff(maxRetries: Int, maxIntervalTime: TimeInterval)
  case logarithmicBackoff(maxRetries: Int, maxIntervalTime: TimeInterval)
  case linear(maxRetries: Int, intervalTime: Int)
  case none
  
  func calculateInterval(_ retries : Int) -> TimeInterval  {
    switch self {
    case .logarithmicBackoff(let maxRetries, let maxIntervalTime):
      if (retries > maxRetries) { return 0.0 }
      let interval = 5 * log(Double(retries))
      return TimeInterval(clamp(interval, lower: 0.1, upper: Double(maxIntervalTime)))
    case .exponentialBackoff(let maxRetries, let maxIntervalTime):
      if (retries > maxRetries) { return 0.0 }
      let interval = exp2(Double(retries))
      return TimeInterval(clamp(Double(interval), lower: 0.1, upper: Double(maxIntervalTime)))
    case .linear(let maxRetries, let intervalTime):
      if (retries > maxRetries) { return 0.0 }
      return TimeInterval(intervalTime)
    default:
      return 0.0
    }
  }
}

internal class RetryHandler : NSObject {
    var retries : Int = 0
    var strategy: RetryStrategy
    var callback: (() -> (Void))?
    var timer: Timer?
    
    internal required init(strategy : RetryStrategy) {
        self.strategy = strategy
    }
    
    func retry(_ callback: @escaping (() -> (Void)))  {
        self.retries += 1
        
        // Save callback
        self.callback = callback
      
        if let aTimer = self.timer { aTimer.invalidate() }
      
        // Calculate interval based on strategy
        let interval: TimeInterval = self.strategy.calculateInterval(self.retries)

        if (interval > 0.0) {
            self.timer = Timer.scheduledTimer(timeInterval: interval,
                target: self,
                selector: #selector(self.fire(_:)),
                userInfo: nil,
                repeats: false)
        }
    }
    
    @objc internal func fire(_ timer : Timer) {
      
        if let callback = self.callback {
            callback()
        }
    }
    
    deinit {
        // Clean Up
        if let timer = self.timer {
            timer.invalidate()
        }
    }
}
