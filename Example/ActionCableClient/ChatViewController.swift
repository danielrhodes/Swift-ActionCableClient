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

import ActionCableClient
import SnapKit
import SwiftyJSON
import UIKit

class ChatViewController: UIViewController {
    static var MessageCellIdentifier = "MessageCell"
    static var ChannelIdentifier = "ChatChannel"
    static var ChannelAction = "talk"

    let client = ActionCableClient(url: URL(string: "wss://actioncable-echo.herokuapp.com/cable")!)

    var channel: Channel?

    var history: [ChatMessage] = Array()
    var name: String?

    var chatView: ChatView?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Chat"

        self.chatView = ChatView(frame: view.bounds)
        view.addSubview(self.chatView!)

        self.chatView?.snp.remakeConstraints({ (make) -> Void in
            make.top.bottom.left.right.equalTo(self.view)
        })

        self.chatView?.tableView.delegate = self
        self.chatView?.tableView.dataSource = self
        self.chatView?.tableView.separatorInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        self.chatView?.tableView.allowsSelection = false
        self.chatView?.tableView.register(ChatCell.self, forCellReuseIdentifier: ChatViewController.MessageCellIdentifier)

        self.chatView?.textField.delegate = self

        setupClient()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let alert = UIAlertController(title: "Chat", message: "What's Your Name?", preferredStyle: .alert)

        var nameTextField: UITextField?
        alert.addTextField(configurationHandler: { (textField: UITextField!) in
            textField.placeholder = "Name"
            // 🙏 Forgive me father, for I have sinned. 🙏
            nameTextField = textField
        })

        alert.addAction(UIAlertAction(title: "Start", style: UIAlertAction.Style.default) { (_: UIAlertAction) in
            self.name = nameTextField?.text
            self.chatView?.textField.becomeFirstResponder()
        })

        self.present(alert, animated: true, completion: nil)
    }
}

// MARK: ActionCableClient

extension ChatViewController {
    func setupClient() {
//        client.headers = ["Authorization": "Bearer SOME"]
        self.client.willConnect = {
            print("Will Connect")
        }

        self.client.onConnected = {
            print("Connected to \(self.client.url)")
            self.connectToChannel()
        }

        self.client.onDisconnected = { (error: ConnectionError?) in
            print("Disconected with error: \(String(describing: error))")
        }

        self.client.willReconnect = {
            print("Reconnecting to \(self.client.url)")
            return true
        }

        self.client.connect()
    }

    func connectToChannel() {
        let channelParams = ["room_id": "sports-room"]
        self.channel = client.create(ChatViewController.ChannelIdentifier, parameters: channelParams)
        self.channel?.onSubscribed = {
            print("💯 Subscribed to \(ChatViewController.ChannelIdentifier)")
        }

        self.channel?.onReceive = { (data: Any?, error: Error?) in
            if let error = error {
                print(error.localizedDescription)
                return
            }

            guard
                let realData = data as? [String: Any],
                let name = realData["name"] as? String,
                let message = realData["message"] as? String
            else {
                return
            }

            let msg = ChatMessage(name: name, message: message)
            self.history.append(msg)
            self.chatView?.tableView.reloadData()

            // Scroll to our new message!
            if msg.name == self.name {
                let indexPath = IndexPath(row: self.history.count - 1, section: 0)
                self.chatView?.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
            }
        }
    }

    func sendMessage(_ message: String) {
        let prettyMessage = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !prettyMessage.isEmpty {
            print("Sending Message: \(ChatViewController.ChannelIdentifier)#\(ChatViewController.ChannelAction)")
            _ = self.channel?.action(ChatViewController.ChannelAction, with:
                ["name": self.name!, "message": prettyMessage])
        }
    }
}

// MARK: UITextFieldDelegate

extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.sendMessage(textField.text!)
        textField.text = ""
        return true
    }
}

// MARK: UITableViewDelegate

extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let message = history[(indexPath as NSIndexPath).row]
        let attrString = message.attributedString()
        let width = self.chatView?.tableView.bounds.size.width
        let rect = attrString.boundingRect(with: CGSize(width: width! - (ChatCell.Inset * 2.0), height: CGFloat.greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return rect.size.height + (ChatCell.Inset * 2.0)
    }
}

// MARK: UITableViewDataSource

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.history.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.MessageCellIdentifier, for: indexPath) as! ChatCell
        let msg = history[(indexPath as NSIndexPath).row]
        cell.message = msg
        return cell
    }
}

// MARK: ChatMessage

struct ChatMessage {
    var name: String
    var message: String

    func attributedString() -> NSAttributedString {
        let messageString: String = "\(self.name) \(self.message)"
        let nameRange = NSRange(location: 0, length: self.name.count)
        let nonNameRange = NSRange(location: nameRange.length, length: messageString.count - nameRange.length)

        let string: NSMutableAttributedString = NSMutableAttributedString(string: messageString)
        string.addAttribute(NSAttributedString.Key.font,
                            value: UIFont.boldSystemFont(ofSize: 18.0),
                            range: nameRange)
        string.addAttribute(NSAttributedString.Key.font, value: UIFont.systemFont(ofSize: 18.0), range: nonNameRange)
        return string
    }
}
