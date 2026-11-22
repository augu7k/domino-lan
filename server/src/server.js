import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname } from "node:path";
import { randomInt, randomUUID, randomBytes, timingSafeEqual } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { createRound, playTile, passTurn, publicGameState } from "./game-engine.js";

const PORT = Number(process.env.PORT || 8080);
const MAX_ROOMS = Number(process.env.MAX_ROOMS || 500);
const ROOM_TTL_MS = Number(process.env.ROOM_TTL_MS || 6 * 60 * 60 * 1000);
const rooms = new Map();
const sockets = new Map();
const json = (socket, type, payload = {}) => {
  if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ v: 1, type, payload }));
};
const safeName = (value) => typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, 20) : "";
const validCode = (value) => typeof value === "string" && /^\d{6}$/.test(value);
const token = () => randomBytes(32).toString("hex");
const sameToken = (a, b) => {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
};
function makeCode() {
  for (let attempt = 0; attempt < 30; attempt++) {
    const code = String(randomInt(100000, 1000000));
    if (!rooms.has(code)) return code;
  }
  throw new Error("Room code space is busy");
}
function publicRoom(room) {
  return {
    roomCode: room.code, gameStarted: room.gameStarted,
    players: room.seats.map((p) => p ? {
      id: p.id, name: p.name, seat: p.seat, team: p.seat % 2,
      isHost: p.isHost, isReady: p.isReady,
      connected: Boolean(p.socket?.readyState === WebSocket.OPEN),
    } : null),
  };
}
function broadcast(room, type = "room_snapshot") {
  const payload = publicRoom(room);
  for (const player of room.seats) if (player?.socket) json(player.socket, type, payload);
}
function broadcastGame(room, type = "game_state") {
  const state = publicGameState(room);
  for (const player of room.seats) {
    if (player?.socket) json(player.socket, type, {
      game: state,
      yourHand: room.game.hands[player.seat].map((tile) => ({ ...tile })),
    });
  }
}
function reject(socket, code, message, requestId) {
  json(socket, "error", { code, message, requestId: requestId ?? null });
}
function getRoom(code) { return validCode(code) ? rooms.get(code) : undefined; }
function sessionFor(socket) {
  const session = sockets.get(socket);
  const room = session && rooms.get(session.roomCode);
  const player = room?.seats.find((p) => p?.id === session.playerId);
  return room && player ? { room, player } : null;
}
function attachPlayer(socket, room, player) {
  if (player.socket && player.socket !== socket && player.socket.readyState === WebSocket.OPEN) {
    player.socket.close(4001, "Session resumed on another connection");
  }
  player.socket = socket;
  player.lastSeenAt = Date.now();
  sockets.set(socket, { roomCode: room.code, playerId: player.id });
}
function sendAccepted(player, room) {
  json(player.socket, "join_accepted", {
    room: publicRoom(room),
    player: { id: player.id, name: player.name, seat: player.seat, team: player.seat % 2 },
    resumeToken: player.resumeToken,
  });
  if (room.gameStarted) {
    json(player.socket, "game_state", {
      game: publicGameState(room),
      yourHand: room.game.hands[player.seat].map((tile) => ({ ...tile })),
    });
  }
}
function createRoom(socket, payload) {
  if (rooms.size >= MAX_ROOMS) return reject(socket, "SERVER_FULL", "الخادم ممتلئ حالياً.");
  const name = safeName(payload.playerName);
  if (!name) return reject(socket, "INVALID_NAME", "أدخل اسماً من حرف إلى 20 حرفاً.");
  const code = makeCode();
  const player = { id: randomUUID(), name, seat: 0, isHost: true, isReady: true, resumeToken: token(), socket, lastSeenAt: Date.now() };
  const room = { code, seats: [player, null, null, null], gameStarted: false, game: null, createdAt: Date.now() };
  rooms.set(code, room);
  sockets.set(socket, { roomCode: code, playerId: player.id });
  sendAccepted(player, room);
  broadcast(room);
}
function joinRoom(socket, payload) {
  const room = getRoom(payload.roomCode);
  if (!room) return reject(socket, "ROOM_NOT_FOUND", "الغرفة غير موجودة أو انتهت صلاحيتها.");
  if (room.gameStarted) return reject(socket, "GAME_STARTED", "بدأت المباراة ولا يمكن الانضمام الآن.");
  const name = safeName(payload.playerName);
  if (!name) return reject(socket, "INVALID_NAME", "أدخل اسماً من حرف إلى 20 حرفاً.");
  if (room.seats.some((p) => p && p.name.toLocaleLowerCase() === name.toLocaleLowerCase())) {
    return reject(socket, "DUPLICATE_NAME", "هذا الاسم مستخدم في الغرفة.");
  }
  const seat = room.seats.findIndex((p) => p === null);
  if (seat < 0) return reject(socket, "ROOM_FULL", "الغرفة مكتملة بأربعة لاعبين.");
  const player = { id: randomUUID(), name, seat, isHost: false, isReady: false, resumeToken: token(), socket, lastSeenAt: Date.now() };
  room.seats[seat] = player;
  sockets.set(socket, { roomCode: room.code, playerId: player.id });
  sendAccepted(player, room);
  broadcast(room);
}
function resumeRoom(socket, payload) {
  const room = getRoom(payload.roomCode);
  if (!room) return reject(socket, "ROOM_NOT_FOUND", "الغرفة غير موجودة أو انتهت صلاحيتها.");
  const player = room.seats.find((p) => p && sameToken(p.resumeToken, payload.resumeToken));
  if (!player) return reject(socket, "RESUME_REJECTED", "تعذر استعادة الجلسة. تحقق من بيانات الاستعادة.");
  attachPlayer(socket, room, player);
  sendAccepted(player, room);
  broadcast(room, "player_reconnected");
}
function handleMessage(socket, raw) {
  let message;
  try { message = JSON.parse(raw.toString()); }
  catch { return reject(socket, "INVALID_JSON", "صيغة الرسالة غير صحيحة."); }
  if (!message || message.v !== 1 || typeof message.type !== "string" || !message.payload || typeof message.payload !== "object") {
    return reject(socket, "INVALID_MESSAGE", "بنية الرسالة غير صحيحة.", message?.requestId);
  }
  const p = message.payload;
  switch (message.type) {
    case "create_room": return createRoom(socket, p);
    case "join_room": return joinRoom(socket, p);
    case "reconnect": return resumeRoom(socket, p);
    case "set_ready": {
      const session = sessionFor(socket);
      if (!session) return reject(socket, "NOT_IN_ROOM", "انضم إلى غرفة أولاً.");
      const { room, player } = session;
      if (room.gameStarted) return reject(socket, "GAME_STARTED", "بدأت المباراة بالفعل.");
      if (player.isHost) return reject(socket, "HOST_READY_FIXED", "المضيف جاهز تلقائياً.");
      player.isReady = Boolean(p.ready);
      broadcast(room);
      return;
    }
    case "start_game": {
      const session = sessionFor(socket);
      if (!session) return reject(socket, "NOT_IN_ROOM", "انضم إلى غرفة أولاً.");
      const { room, player } = session;
      if (!player.isHost) return reject(socket, "HOST_ONLY", "المضيف وحده يستطيع بدء المباراة.");
      if (room.gameStarted) return reject(socket, "GAME_STARTED", "بدأت المباراة بالفعل.");
      if (room.seats.some((entry) => !entry) || room.seats.some((entry) => !entry.isReady)) {
        return reject(socket, "PLAYERS_NOT_READY", "يجب انضمام أربعة لاعبين واستعدادهم جميعاً.");
      }
      room.roundNumber = 1;
      room.game = createRound(room.seats.map((entry) => ({ id: entry.id, name: entry.name, seat: entry.seat })), [0, 0], room.roundNumber);
      room.gameStarted = true;
      room.startedAt = Date.now();
      broadcast(room, "game_started");
      broadcastGame(room, "game_state");
      return;
    }
    case "next_round": {
      const session = sessionFor(socket);
      if (!session) return reject(socket, "NOT_IN_ROOM", "انضم إلى غرفة أولاً.");
      const { room, player } = session;
      if (!player.isHost) return reject(socket, "HOST_ONLY", "المضيف وحده يستطيع بدء الجولة التالية.");
      if (!room.gameStarted || !room.game?.isFinished) {
        return reject(socket, "ROUND_NOT_FINISHED", "لا يمكن بدء جولة جديدة قبل انتهاء الجولة الحالية.");
      }
      room.roundNumber = (room.roundNumber || room.game.roundNumber || 1) + 1;
      room.game = createRound(
        room.seats.map((entry) => ({ id: entry.id, name: entry.name, seat: entry.seat })),
        room.game.teamScores,
        room.roundNumber,
        room.game.roundHistory,
      );
      broadcastGame(room, "game_state");
      return;
    }
    case "play_tile": {
      const session = sessionFor(socket);
      if (!session) return reject(socket, "NOT_IN_ROOM", "انضم إلى غرفة أولاً.");
      try {
        playTile(session.room, session.player.seat, p.tile, p.side);
        broadcastGame(session.room);
      } catch (error) { reject(socket, "INVALID_MOVE", error.message, message.requestId); }
      return;
    }
    case "pass_turn": {
      const session = sessionFor(socket);
      if (!session) return reject(socket, "NOT_IN_ROOM", "انضم إلى غرفة أولاً.");
      try {
        passTurn(session.room, session.player.seat);
        broadcastGame(session.room);
      } catch (error) { reject(socket, "INVALID_PASS", error.message, message.requestId); }
      return;
    }
    case "request_state": {
      const session = sessionFor(socket);
      if (!session) return reject(socket, "NOT_IN_ROOM", "انضم إلى غرفة أولاً.");
      if (session.room.gameStarted) {
        const { room, player } = session;
        json(socket, "game_state", {
          game: publicGameState(room),
          yourHand: room.game.hands[player.seat].map((tile) => ({ ...tile })),
        });
      } else sendAccepted(session.player, session.room);
      return;
    }
    case "ping": return json(socket, "pong", { at: Date.now(), requestId: message.requestId ?? null });
    case "leave_room": {
      const session = sessionFor(socket);
      if (session && !session.room.gameStarted && !session.player.isHost) {
        session.room.seats[session.player.seat] = null;
        broadcast(session.room);
      }
      sockets.delete(socket);
      return;
    }
    default: return reject(socket, "UNKNOWN_MESSAGE", "نوع الرسالة غير مدعوم.", message.requestId);
  }
}
const WEB_ROOT = resolve(process.cwd(), "../web");
const MIME_TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8", ".svg": "image/svg+xml",
  ".png": "image/png", ".ico": "image/x-icon"
};
const httpServer = createServer(async (request, response) => {
  const pathname = new URL(request.url || "/", "http://localhost").pathname;
  if (pathname === "/health") {
    response.writeHead(200, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
    response.end(JSON.stringify({ ok: true, service: "domino-lan", protocolVersion: 1, activeRooms: rooms.size }));
    return;
  }
  const relative = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const filePath = resolve(WEB_ROOT, relative);
  if (!filePath.startsWith(WEB_ROOT + "/") && filePath !== WEB_ROOT) {
    response.writeHead(403); response.end("forbidden"); return;
  }
  try {
    const data = await readFile(filePath);
    const assetExtension = extname(filePath).toLowerCase();
    const cacheControl = pathname === "/" || assetExtension === ".html" || assetExtension === ".js" || pathname.endsWith("/sw.js")
      ? "no-cache, no-store, must-revalidate"
      : "public, max-age=3600";
    response.writeHead(200, { "content-type": MIME_TYPES[assetExtension] || "application/octet-stream", "cache-control": cacheControl });
    response.end(data);
  } catch {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("not_found");
  }
});

const wss = new WebSocketServer({ server: httpServer, path: "/ws", maxPayload: 16 * 1024, perMessageDeflate: false });
wss.on("connection", (socket) => {
  socket.on("message", (raw) => handleMessage(socket, raw));
  socket.on("close", () => {
    const session = sockets.get(socket);
    sockets.delete(socket);
    if (!session) return;
    const room = rooms.get(session.roomCode);
    const player = room?.seats.find((entry) => entry?.id === session.playerId);
    if (player && player.socket === socket) {
      player.socket = null;
      player.lastSeenAt = Date.now();
      broadcast(room, "player_disconnected");
    }
  });
  socket.on("error", () => {});
});
const cleanup = setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    const newest = Math.max(...room.seats.filter(Boolean).map((player) => player.lastSeenAt));
    if (now - newest > ROOM_TTL_MS) rooms.delete(code);
  }
}, 60_000);
cleanup.unref();
httpServer.listen(PORT, "0.0.0.0", () => console.log(`Domino server listening on :${PORT}`));
export { httpServer, rooms };
