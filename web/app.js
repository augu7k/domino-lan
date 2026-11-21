const $ = (selector) => document.querySelector(selector);
const installButton = $("#installButton");
const connectButton = $("#connectButton");
const connectionStatus = $("#connectionStatus");
const notice = $("#notice");
let installPrompt = null;
let socket = null;
let room = null;
let player = null;
let game = null;
let yourHand = [];
let selectedTile = null;
let serverEndpoint = localStorage.getItem("domino.serverUrl") || "";
let savedSession = null;
try { savedSession = JSON.parse(localStorage.getItem("domino.session") || "null"); } catch {}
$("#serverUrl").value = serverEndpoint;
$("#playerName").value = localStorage.getItem("domino.playerName") || "";

function showNotice(title, message) {
  notice.replaceChildren();
  const strong = document.createElement("strong");
  strong.textContent = title;
  const p = document.createElement("p");
  p.textContent = message;
  notice.append(strong, p);
}
function setConnected(connected, label) {
  connectionStatus.textContent = label || (connected ? "متصل بالخادم" : "غير متصل");
  connectionStatus.classList.toggle("connected", connected);
  $("#createButton").disabled = !connected;
  $("#joinButton").disabled = !connected;
  connectButton.textContent = connected ? "إعادة الاتصال" : "اتصال";
}
function endpointToWebSocket(value) {
  const url = new URL(value.trim());
  if (url.protocol === "https:") url.protocol = "wss:";
  else if (url.protocol === "http:") url.protocol = "ws:";
  if (url.protocol !== "wss:" && url.protocol !== "ws:") throw new Error("استخدم رابط https أو http أو ws أو wss.");
  url.pathname = url.pathname.replace(/\/$/, "");
  if (!url.pathname.endsWith("/ws")) url.pathname += "/ws";
  return url.toString();
}
function send(type, payload = {}) {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    showNotice("لا يوجد اتصال", "اتصل بالخادم أولاً ثم أعد المحاولة.");
    return;
  }
  socket.send(JSON.stringify({ v: 1, type, payload }));
}
function connect() {
  const value = $("#serverUrl").value.trim();
  if (!value) return showNotice("عنوان الخادم مطلوب", "أدخل رابط الخادم الذي تم نشره.");
  let url;
  try { url = endpointToWebSocket(value); }
  catch (error) { return showNotice("رابط غير صحيح", error.message); }
  if (socket) socket.close();
  serverEndpoint = value;
  localStorage.setItem("domino.serverUrl", value);
  setConnected(false, "جارٍ الاتصال…");
  socket = new WebSocket(url);
  socket.addEventListener("open", () => {
    setConnected(true);
    showNotice("تم الاتصال", "يمكنك إنشاء غرفة أو الانضمام إلى غرفة موجودة.");
    if (savedSession?.server === serverEndpoint && savedSession.roomCode && savedSession.resumeToken) {
      send("reconnect", { roomCode: savedSession.roomCode, resumeToken: savedSession.resumeToken });
    }
  });
  socket.addEventListener("message", (event) => {
    let message;
    try { message = JSON.parse(event.data); } catch { return; }
    handleMessage(message);
  });
  socket.addEventListener("close", () => setConnected(false, "انقطع الاتصال"));
  socket.addEventListener("error", () => showNotice("تعذر الاتصال", "تحقق من رابط الخادم ومن نشر الخدمة."));
}
function handleMessage(message) {
  const p = message.payload || {};
  switch (message.type) {
    case "join_accepted":
      room = p.room;
      player = p.player;
      savedSession = { server: serverEndpoint, roomCode: room.roomCode, resumeToken: p.resumeToken };
      localStorage.setItem("domino.session", JSON.stringify(savedSession));
      renderRoom();
      break;
    case "room_snapshot":
    case "player_reconnected":
    case "player_disconnected":
      room = p;
      renderRoom();
      break;
    case "game_started":
      room = p;
      $("#roomPanel").hidden = true;
      break;
    case "game_state":
      game = p.game;
      yourHand = Array.isArray(p.yourHand) ? p.yourHand : [];
      selectedTile = null;
      renderGame();
      break;
    case "error":
      showNotice("تعذر تنفيذ الطلب", p.message || "حدث خطأ غير معروف.");
      break;
    case "pong":
      break;
  }
}
function renderRoom() {
  if (!room) return;
  $("#lobbyPanel").hidden = true;
  $("#roomPanel").hidden = false;
  $("#gamePanel").hidden = Boolean(room.gameStarted);
  $("#roomCodeLabel").textContent = room.roomCode;
  const list = $("#playersList");
  list.replaceChildren();
  room.players.forEach((entry, index) => {
    const item = document.createElement("div");
    item.className = "player-seat";
    const name = document.createElement("strong");
    name.textContent = entry ? entry.name : "بانتظار لاعب";
    const meta = document.createElement("span");
    meta.textContent = entry ? (entry.isHost ? "المضيف" : entry.isReady ? "جاهز" : "لم يستعد") : "المقعد " + (index + 1);
    const status = document.createElement("i");
    status.className = "seat-dot " + (entry?.connected ? "online" : entry ? "offline" : "");
    item.append(name, meta, status);
    list.append(item);
  });
  const mine = room.players.find((entry) => entry?.id === player?.id);
  const isHost = Boolean(mine?.isHost);
  $("#readyButton").hidden = isHost || room.gameStarted;
  $("#readyButton").disabled = !mine || room.gameStarted;
  $("#readyButton").textContent = mine?.isReady ? "إلغاء الاستعداد" : "أنا جاهز";
  $("#startButton").hidden = !isHost;
  $("#startButton").disabled = !isHost || room.players.some((entry) => !entry || !entry.isReady);
  if (room.gameStarted) $("#roomPanel").hidden = true;
}
const pipPatterns = {
  0: [],
  1: [4],
  2: [0, 8],
  3: [0, 4, 8],
  4: [0, 2, 6, 8],
  5: [0, 2, 4, 6, 8],
  6: [0, 2, 3, 5, 6, 8]
};
function createDominoElement(first, second, className, tagName = "span") {
  const tile = document.createElement(tagName);
  tile.className = className;
  tile.setAttribute("aria-label", first + " على " + second);
  for (const value of [first, second]) {
    const half = document.createElement("span");
    half.className = "domino-half";
    const active = new Set(pipPatterns[value] || []);
    for (let position = 0; position < 9; position++) {
      const pip = document.createElement("span");
      pip.className = active.has(position) ? "pip" : "pip pip-empty";
      half.append(pip);
    }
    tile.append(half);
  }
  const divider = document.createElement("span");
  divider.className = "domino-divider";
  tile.insertBefore(divider, tile.children[1]);
  return tile;
}
function tileLabel(tile) { return tile.first + " | " + tile.second; }
function canPlayTile(tile) {
  if (!game) return false;
  if (!game.board.length) return tile.first === 6 && tile.second === 6;
  const left = game.board[0].leftPip;
  const right = game.board.at(-1).rightPip;
  return tile.first === left || tile.second === left ||
    tile.first === right || tile.second === right;
}
function renderGame() {
  if (!game) return;
  $("#lobbyPanel").hidden = true;
  $("#roomPanel").hidden = true;
  $("#gamePanel").hidden = false;
  const current = game.players[game.currentSeat];
  $("#turnLabel").textContent = current ? current.name + (current.id === player?.id ? " (دورك)" : "") : "—";
  $("#score0").textContent = game.teamScores[0];
  $("#score1").textContent = game.teamScores[1];
  $("#gameMessage").textContent = game.isFinished ? "انتهت الجولة." : current?.id === player?.id ? "اختر حجراً صالحاً للعب." : "انتظر دور اللاعب الآخر.";
  const board = $("#board");
  board.replaceChildren();
  if (!game.board.length) {
    const empty = document.createElement("span");
    empty.className = "board-empty";
    empty.textContent = "ابدأ بحجر 6 | 6";
    board.append(empty);
  } else {
    game.board.forEach((tile) => {
      board.append(createDominoElement(tile.leftPip, tile.rightPip, "domino-tile board-tile"));
    });
  }
  const hand = $("#hand");
  hand.replaceChildren();
  $("#handCount").textContent = yourHand.length + " أحجار";
  yourHand.forEach((tile) => {
    const button = createDominoElement(
      tile.first,
      tile.second,
      "domino-tile hand-tile" + (selectedTile && selectedTile.first === tile.first && selectedTile.second === tile.second ? " selected" : ""),
      "button"
    );
    button.type = "button";
    button.disabled = game.isFinished || game.currentSeat !== player?.seat;
    button.addEventListener("click", () => chooseTile(tile));
    hand.append(button);
  });
  const isMyTurn = game.currentSeat === player?.seat;
  const hasLegalMove = yourHand.some(canPlayTile);
  $("#passButton").disabled = game.isFinished || !isMyTurn || hasLegalMove;
  $("#passButton").hidden = game.isFinished || hasLegalMove || !isMyTurn;

  if (game.isFinished && game.result) {
    const result = game.result;
    $("#roundResult").hidden = false;
    $("#roundResult").textContent = result.winningTeam === null
      ? "تعادل بسبب انسداد اللعب. لم تُضف نقاط."
      : "فاز الفريق " + (result.winningTeam + 1) + " · النقاط المضافة: " + result.pointsAwarded;
  } else {
    $("#roundResult").hidden = true;
  }
}
function chooseTile(tile) {
  selectedTile = tile;
  const choices = $("#moveChoices");
  choices.replaceChildren();
  const sides = [];
  if (!game.board.length) {
    if (tile.first === 6 && tile.second === 6) sides.push("right");
  } else {
    const left = game.board[0].leftPip;
    const right = game.board.at(-1).rightPip;
    if (tile.first === left || tile.second === left) sides.push("left");
    if (tile.first === right || tile.second === right) sides.push("right");
  }
  if (!sides.length) {
    showNotice("حجر غير صالح", "هذا الحجر لا يطابق الطرفين المفتوحين.");
    choices.hidden = true;
    renderGame();
    return;
  }
  if (sides.length === 1) {
    send("play_tile", { tile: { first: tile.first, second: tile.second }, side: sides[0] });
    choices.hidden = true;
    return;
  }
  choices.hidden = false;
  for (const side of sides) {
    const button = document.createElement("button");
    button.className = "small-button";
    button.textContent = side === "left" ? "الطرف الأيسر" : "الطرف الأيمن";
    button.addEventListener("click", () => {
      send("play_tile", { tile: { first: tile.first, second: tile.second }, side });
      choices.hidden = true;
    });
    choices.append(button);
  }
  renderGame();
}
$("#connectButton").addEventListener("click", connect);
$("#createButton").addEventListener("click", () => {
  const name = $("#playerName").value.trim();
  if (!name) return showNotice("اسم اللاعب مطلوب", "اكتب اسمك قبل إنشاء الغرفة.");
  localStorage.setItem("domino.playerName", name);
  send("create_room", { playerName: name });
});
$("#joinButton").addEventListener("click", () => {
  const name = $("#playerName").value.trim();
  const code = $("#roomCode").value.trim();
  if (!name) return showNotice("اسم اللاعب مطلوب", "اكتب اسمك قبل الانضمام.");
  if (!/^\d{6}$/.test(code)) return showNotice("رمز الغرفة غير صحيح", "أدخل الرمز المكوّن من ستة أرقام.");
  localStorage.setItem("domino.playerName", name);
  send("join_room", { roomCode: code, playerName: name });
});
$("#readyButton").addEventListener("click", () => {
  const mine = room?.players.find((entry) => entry?.id === player?.id);
  send("set_ready", { ready: !mine?.isReady });
});
$("#startButton").addEventListener("click", () => send("start_game"));
$("#passButton").addEventListener("click", () => send("pass_turn"));
$("#copyCodeButton").addEventListener("click", async () => {
  try { await navigator.clipboard.writeText(room.roomCode); showNotice("تم النسخ", "تم نسخ رمز الغرفة."); }
  catch { showNotice("رمز الغرفة", room.roomCode); }
});
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
  window.addEventListener("load", () => navigator.serviceWorker.register("./sw.js").catch((error) => console.error(error)));
}
