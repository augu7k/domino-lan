import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { WebSocket } from "ws";
import { httpServer } from "../src/server.js";

let base;
let wsUrl;
test.before(async () => {
  if (!httpServer.listening) await once(httpServer, "listening");
  const address = httpServer.address();
  base = `http://127.0.0.1:${address.port}`;
  wsUrl = `ws://127.0.0.1:${address.port}/ws`;
});
test.after(() => new Promise((resolve) => httpServer.close(resolve)));
function connect() {
  const socket = new WebSocket(wsUrl);
  return new Promise((resolve, reject) => {
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}
function nextMessage(socket, expectedType) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${expectedType}`)), 2000);
    const listener = (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.type !== expectedType && message.type !== "error") return;
      clearTimeout(timeout);
      socket.off("message", listener);
      if (message.type === "error") reject(new Error(message.payload.message));
      else resolve(message.payload);
    };
    socket.on("message", listener);
  });
}
function send(socket, type, payload = {}) { socket.send(JSON.stringify({ v: 1, type, payload })); }

test("health endpoint reports service status", async () => {
  const response = await fetch(`${base}/health`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).ok, true);
});
test("creates a room and fills four seats; host starts only when everyone is ready", async () => {
  const players = await Promise.all([connect(), connect(), connect(), connect()]);
  try {
    const hostAccepted = nextMessage(players[0], "join_accepted");
    send(players[0], "create_room", { playerName: "المضيف" });
    const host = await hostAccepted;
    const code = host.room.roomCode;
    assert.match(code, /^\d{6}$/);
    assert.equal(host.player.seat, 0);
    const names = ["الثاني", "الثالث", "الرابع"];
    for (let index = 1; index < 4; index++) {
      const accepted = nextMessage(players[index], "join_accepted");
      send(players[index], "join_room", { roomCode: code, playerName: names[index - 1] });
      assert.equal((await accepted).player.seat, index);
    }
    const rejectedStart = nextMessage(players[0], "error");
    send(players[0], "start_game");
    await assert.rejects(rejectedStart, /استعدادهم/);
    for (let index = 1; index < 4; index++) {
      const snapshot = nextMessage(players[index], "room_snapshot");
      send(players[index], "set_ready", { ready: true });
      await snapshot;
    }
    const started = nextMessage(players[0], "game_started");
    send(players[0], "start_game");
    const state = await started;
    assert.equal(state.gameStarted, true);
    assert.equal(state.players.length, 4);
  } finally {
    for (const player of players) player.close();
  }
});
test("rejects duplicate player names", async () => {
  const clients = await Promise.all(Array.from({ length: 3 }, () => connect()));
  try {
    const accepted = nextMessage(clients[0], "join_accepted");
    send(clients[0], "create_room", { playerName: "Host" });
    const { room } = await accepted;
    const joined = nextMessage(clients[1], "join_accepted");
    send(clients[1], "join_room", { roomCode: room.roomCode, playerName: "P1" });
    await joined;
    const duplicate = nextMessage(clients[2], "error");
    send(clients[2], "join_room", { roomCode: room.roomCode, playerName: "P1" });
    await assert.rejects(duplicate, /مستخدم/);
  } finally {
    for (const client of clients) client.close();
  }
});
