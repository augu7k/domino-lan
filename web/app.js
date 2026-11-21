const notice = document.querySelector("#modeNotice");
const installButton = document.querySelector("#installButton");
let installPrompt = null;

function explainMode(mode) {
  const messages = {
    online: ["اللعب عبر الإنترنت", "واجهة الويب جاهزة كبداية، لكن إنشاء الغرف والمباريات يحتاج إلى تشغيل خادم اللعبة وربطه بالتطبيق. لم يتم تفعيل الاتصال بعد."],
    local: ["اللعب المحلي", "وضع نقطة الاتصال يحتاج إلى قناة اتصال محلية متوافقة مع قيود متصفحات iPhone وAndroid. لم يتم تفعيل الاتصال المحلي بعد."]
  };
  const [title, description] = messages[mode];
  notice.innerHTML = "";
  const heading = document.createElement("strong");
  heading.textContent = title;
  const paragraph = document.createElement("p");
  paragraph.textContent = description;
  notice.append(heading, paragraph);
}

document.querySelector("#onlineButton").addEventListener("click", () => explainMode("online"));
document.querySelector("#localButton").addEventListener("click", () => explainMode("local"));

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  installPrompt = event;
  installButton.hidden = false;
});
installButton.addEventListener("click", async () => {
  if (!installPrompt) return;
  installPrompt.prompt();
  await installPrompt.userChoice;
  installPrompt = null;
  installButton.hidden = true;
});

if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch((error) => {
      console.error("Service worker registration failed", error);
    });
  });
}
