//
//  ViewController.swift
//  ElevenReader
//
//  Created by Malo Bourgon on 2026-01-13.
//

import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "com.malo.ElevenReader.Extension"

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                return
            }

            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show(\(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show(\(state.isEnabled), false)")
                }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let messageBody = message.body as? String else { return }

        switch messageBody {
        case "open-preferences":
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        case "sign-in":
            openSignInPage()
        default:
            break
        }
    }

    func openSignInPage() {
        // Open elevenreader.io/extension in Safari
        // The content script will intercept the auth token when user signs in
        webView.evaluateJavaScript("updateAuthStatus('Opening Safari... Sign in there, then use the extension.')")

        if let url = URL(string: "https://elevenreader.io/extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
