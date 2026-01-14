function show(enabled, useSettingsInsteadOfPreferences) {
  if (useSettingsInsteadOfPreferences) {
    document.getElementsByClassName("state-on")[0].innerText =
      "ElevenReader's extension is currently on. You can turn it off in the Extensions section of Safari Settings.";
    document.getElementsByClassName("state-off")[0].innerText =
      "ElevenReader's extension is currently off. You can turn it on in the Extensions section of Safari Settings.";
    document.getElementsByClassName("state-unknown")[0].innerText =
      "You can turn on ElevenReader's extension in the Extensions section of Safari Settings.";
    document.getElementsByClassName("open-preferences")[0].innerText =
      "Quit and Open Safari Settings…";
  }

  if (typeof enabled === "boolean") {
    document.body.classList.toggle(`state-on`, enabled);
    document.body.classList.toggle(`state-off`, !enabled);
  } else {
    document.body.classList.remove(`state-on`);
    document.body.classList.remove(`state-off`);
  }
}

function openPreferences() {
  webkit.messageHandlers.controller.postMessage("open-preferences");
}

function signIn() {
  webkit.messageHandlers.controller.postMessage("sign-in");
}

function updateAuthStatus(status) {
  const statusEl = document.querySelector(".auth-status");
  if (statusEl) {
    statusEl.innerText = status;
  }
}

document
  .querySelector("button.open-preferences")
  .addEventListener("click", openPreferences);
document.querySelector("button.sign-in").addEventListener("click", signIn);
