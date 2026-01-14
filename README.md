# ElevenReader Safari Extension

A Safari port of the [ElevenReader Chrome extension](https://chromewebstore.google.com/detail/elevenreader/mahgnmmldchnmmdfkfcoindpgkadhhhc), which allows you to save web pages to your ElevenReader library for text-to-speech playback.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [How It Works](#how-it-works)
- [Chrome to Safari Conversion Guide](#chrome-to-safari-conversion-guide)
  - [Initial Conversion](#initial-conversion)
  - [Safari API Compatibility](#safari-api-compatibility)
  - [Webpage-to-Extension Communication](#webpage-to-extension-communication)
  - [Code Signing](#code-signing)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project converts the ElevenReader Chrome extension to a native Safari Web Extension. The conversion was performed by [Claude](https://claude.ai), Anthropic's AI assistant, which wrote all the Safari-specific code and this documentation. The conversion required solving several compatibility issues between Chrome and Safari's extension APIs, most notably around authentication.

**Features:**
- Save any web page to your ElevenReader library with one click
- Right-click context menu to save pages or selected text
- Visual notifications showing import status
- Automatic authentication via elevenreader.io

---

## Installation

### Prerequisites
- macOS 13 or later
- Safari 16 or later
- Xcode 14 or later (for building)
- An ElevenReader account

### Building from Source

1. Clone or download this repository
2. Open `ElevenReader/ElevenReader.xcodeproj` in Xcode
3. Select your Team in Signing & Capabilities for both targets:
   - `ElevenReader` (main app)
   - `ElevenReader Extension`
4. Choose "Development" as the Signing Certificate (not "Sign to Run Locally")
5. Build and run (⌘R)

### Enabling the Extension

1. Open Safari → Settings → Extensions
2. Enable "ElevenReader"
3. Grant necessary permissions when prompted

### Authentication

1. Visit elevenreader.io/extension in Safari
2. Sign in to your ElevenReader account
3. The extension will automatically capture your authentication token

---

## How It Works

Click the ElevenReader toolbar icon on any webpage to save it to your library. The extension:

1. Extracts the page content (HTML or PDF)
2. Sends it to the ElevenReader API
3. Shows a notification with a "Listen now" button

You can also right-click and select "Listen with ElevenReader" from the context menu.

---

## Chrome to Safari Conversion Guide

This section documents the technical challenges and solutions for converting a Chrome extension to Safari. It may be useful for anyone attempting a similar conversion.

### Initial Conversion

Apple provides an official conversion tool:

```bash
xcrun safari-web-extension-converter /path/to/chrome/extension \
  --project-location ./OutputDir \
  --app-name "YourAppName"
```

This creates an Xcode project with:
- A macOS host app (required for Safari extensions)
- The Safari Web Extension wrapper
- Converted extension resources

However, the auto-converted extension likely won't work out of the box due to API differences. **Manual review of all JavaScript files is required** - the converter preserves Chrome-specific code that will fail at runtime.

#### Bundle Identifier Mismatch

The converter may generate mismatched bundle identifiers, causing this build error:

```
Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier.
```

**Cause:** Different casing between parent app (`com.example.MyApp`) and extension (`com.example.myapp.Extension`).

**Fix:** Edit `project.pbxproj` to ensure the extension's bundle identifier matches the parent's casing exactly (e.g., `com.example.MyApp.Extension`).

---

### Safari API Compatibility

#### Background Script Format

**Problem:** Chrome Manifest V3 uses `service_worker` for background scripts. Safari doesn't support this.

**Solution:** Change `manifest.json` to use background scripts:

```json
// Before (Chrome MV3)
"background": {
  "service_worker": "background.js",
  "type": "module"
}

// After (Safari)
"background": {
  "scripts": ["background.js"],
  "persistent": false
}
```

#### Unsupported APIs

Safari doesn't support several Chrome APIs. Wrap them in conditional checks:

```javascript
// chrome.downloads
if (chrome.downloads && chrome.downloads.onChanged) {
  chrome.downloads.onChanged.addListener((e) => {
    // ... handler code
  });
}

// chrome.notifications
if (!chrome.notifications || !chrome.notifications.create) {
  console.log("Notifications not supported");
  return;
}
```

Remove unsupported entries from `manifest.json`:
- Permissions: `downloads`, `notifications`
- `externally_connectable` block
- `key` field (Chrome Web Store signing key)
- `update_url` field (Chrome Web Store auto-update)

---

### Webpage-to-Extension Communication

This was the most complex challenge. Many Chrome extensions use `externally_connectable` to receive messages directly from trusted websites:

```json
// Chrome manifest.json
"externally_connectable": {
  "matches": ["https://example.com/*"]
}
```

```javascript
// Website code
chrome.runtime.sendMessage(
  "extension-id-here",
  { type: "someMessage", data: "..." }
);

// Extension background.js
chrome.runtime.onMessageExternal.addListener((message, sender) => {
  // Handle message from website
});
```

**Safari doesn't support this.** Neither `externally_connectable` nor `onMessageExternal` work.

#### Why This Is Tricky

Your first instinct might be to read authentication tokens directly from the page's localStorage or cookies in a content script. **This won't work** for two reasons:

1. **Content scripts run in an isolated world** - They share the DOM with the page but have a separate JavaScript context. You cannot access `window.firebase`, page-level variables, or intercept the page's function calls from a content script.

2. **The token you can access may not be the right one** - In our case, the Firebase ID token in localStorage was accessible, but the API expected a *different* custom token that the website sends via `chrome.runtime.sendMessage`. We wasted significant debugging time on 401 errors before discovering the website uses two different tokens.

#### Solution: Page Context Injection

The solution is to inject code directly into the page's context (not the content script's isolated world):

**1. Content script injects a script tag:**

```javascript
// content.js
(function() {
  // Only run on the relevant domain
  if (!window.location.hostname.includes('example.com')) return;

  // Listen for messages from the injected script
  window.addEventListener('message', (event) => {
    if (event.source !== window) return;

    if (event.data && event.data.type === 'MY_EXTENSION_MESSAGE') {
      // Forward to background script
      chrome.runtime.sendMessage({
        type: 'fromWebsite',
        data: event.data.payload
      });
    }
  });

  // Inject script into page context
  const script = document.createElement('script');
  script.textContent = `
    (function() {
      // Create chrome.runtime if it doesn't exist
      if (!window.chrome) window.chrome = {};
      if (!window.chrome.runtime) window.chrome.runtime = {};

      // Intercept sendMessage calls
      window.chrome.runtime.sendMessage = function(...args) {
        // Parse arguments (handles multiple signatures)
        let message = typeof args[0] === 'string' ? args[1] : args[0];
        let callback = args[args.length - 1];

        // Forward to content script via postMessage
        window.postMessage({
          type: 'MY_EXTENSION_MESSAGE',
          payload: message
        }, '*');

        // Call callback to satisfy the website
        if (typeof callback === 'function') {
          setTimeout(() => callback({ success: true }), 0);
        }
      };
    })();
  `;
  (document.head || document.documentElement).appendChild(script);
  script.remove();
})();
```

**2. Background script receives the forwarded message:**

```javascript
// background.js
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'fromWebsite') {
    // Handle the message that originated from the website
    console.log('Received from website:', message.data);
    sendResponse({ success: true });
    return true;
  }
});
```

**Key insight:** By injecting a `<script>` tag, the code runs in the page's context where it can override `chrome.runtime.sendMessage`. The injected script communicates with the content script via `window.postMessage`, and the content script forwards to the background script via `chrome.runtime.sendMessage`.

#### Approaches That Don't Work

If you're trying to pass authentication from a website to your Safari extension, here are approaches we tried that **don't work**:

1. **Embedded WKWebView** - Opening the auth website in a WKWebView inside your host app and injecting JavaScript to intercept tokens. Fails because OAuth providers (Sign in with Apple, Google, etc.) block embedded WebViews for security reasons.

2. **`browser.runtime.sendNativeMessage`** - Safari's documentation suggests this API exists, but in practice it returns "not a function" in Safari Web Extensions. You cannot reliably communicate from background script to native app.

3. **Keychain storage via SafariWebExtensionHandler** - Even if you implement `getToken`/`setToken` handlers in `SafariWebExtensionHandler.swift` with Keychain storage, the background script can't call them because `sendNativeMessage` doesn't work.

4. **`SFSafariApplication.dispatchMessage`** - This only sends messages to content scripts in open Safari pages, not to the extension's background script storage. It cannot be used for app-to-extension token passing.

The page context injection approach documented above is the most reliable solution.

---

### Code Signing

#### The Problem

With "Sign to Run Locally" (ad-hoc signing), Safari treats the extension as unsigned. Users must enable "Allow Unsigned Extensions" in Safari's Develop menu on every launch.

#### The Solution

Use your Apple ID for signing (works with free accounts):

1. In Xcode, select each target
2. Go to Signing & Capabilities
3. Set Team to your Apple ID (Personal Team)
4. Set Signing Certificate to "Development"

This eliminates the need to re-enable unsigned extensions.

---

## Technical Details

### Token Flow (for this extension)

```
┌───────────────────────────────────────────────────────────────┐
│                   elevenreader.io website                     │
│ User signs in → Website calls chrome.runtime.sendMessage()    │
└─────────────────────────────┬─────────────────────────────────┘
                              ▼
┌───────────────────────────────────────────────────────────────┐
│ Injected Script: Intercepts sendMessage → window.postMessage()│
└─────────────────────────────┬─────────────────────────────────┘
                              ▼
┌───────────────────────────────────────────────────────────────┐
│ Content Script: Listens for postMessage → chrome.runtime.send │
└─────────────────────────────┬─────────────────────────────────┘
                              ▼
┌───────────────────────────────────────────────────────────────┐
│ Background Script: Receives token → chrome.storage.local.set()│
└───────────────────────────────────────────────────────────────┘
```

### Safari vs Chrome API Support

| Feature | Chrome | Safari | Workaround |
|---------|--------|--------|------------|
| Service Worker | ✅ | ❌ | Use background scripts |
| chrome.downloads | ✅ | ❌ | Conditional check, skip |
| chrome.notifications | ✅ | ❌ | Conditional check, fallback |
| externally_connectable | ✅ | ❌ | Page context injection |
| onMessageExternal | ✅ | ❌ | Page context injection |

---

## Troubleshooting

### Extension doesn't appear in Safari

- Ensure the extension is enabled in Safari → Settings → Extensions
- Verify both targets are signed with "Development" certificate

### "Allow Unsigned Extensions" required on every launch

Change from "Sign to Run Locally" to proper signing:
1. Set Team to your Apple ID
2. Set Signing Certificate to "Development"

### 401 Authentication Error / "The token is invalid"

If API calls fail with `{"detail": "The token is invalid"}`:

1. Visit elevenreader.io/extension in Safari
2. Sign out and sign back in
3. The content script will capture the new token

**Note:** If you're developing a similar extension and getting 401s despite having a token, make sure you're capturing the *correct* token. Some websites use multiple token systems (e.g., Firebase ID tokens for the website, but a separate custom token for their browser extension API).

### Debugging the Extension

To view background script console logs and errors:
1. Enable the Develop menu: Safari → Settings → Advanced → Show Develop menu
2. Develop → Web Extension Background Content → ElevenReader Extension

To debug content scripts, use the regular Web Inspector on the page (Develop → Show Web Inspector).

### Extension button does nothing

Check the background script console (Develop → Web Extension Background Content → ElevenReader Extension). Common issues:
- Not authenticated (visit elevenreader.io/extension)
- Content script blocked (check extension permissions)

---

## Credits

- Original Chrome extension by [ElevenLabs](https://elevenlabs.io)
- Safari conversion, Safari-specific code, and documentation by [Claude](https://claude.ai) (Anthropic's AI assistant)

## License

This is an unofficial port for personal use. The original ElevenReader extension is property of ElevenLabs.
