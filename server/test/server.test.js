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


test("game state exposes only the receiving player's hand", async () => {
  const clients = await Promise.all(Array.from({ length: 4 }, () => connect()));
  try {
    const acceptedHost = nextMessage(clients[0], "join_accepted");
    send(clients[0], "create_room", { playerName: "HostSecure" });
    const { room } = await acceptedHost;
    for (let index = 1; index < 4; index++) {
      const accepted = nextMessage(clients[index], "join_accepted");
      send(clients[index], "join_room", { roomCode: room.roomCode, playerName: `Secure${index}` });
      await accepted;
    }
    for (let index = 1; index < 4; index++) {
      const snapshot = nextMessage(clients[index], "room_snapshot");
      send(clients[index], "set_ready", { ready: true });
      await snapshot;
    }
    const states = clients.map((client) => nextMessage(client, "game_state"));
    send(clients[0], "start_game");
    const received = await Promise.all(states);
    for (const payload of received) {
      assert.equal(payload.yourHand.length, 7);
      assert.equal(Object.hasOwn(payload.game, "hands"), false);
      assert.equal(Object.hasOwn(payload.game, "yourHand"), false);
      assert.equal(payload.game.remainingTiles.reduce((sum, count) => sum + count, 0), 28);
    }
    const uniqueHands = new Set(received.map((payload) =>
      payload.yourHand.map((tile) => `${tile.first}:${tile.second}`).sort().join(",")
    ));
    assert.equal(uniqueHands.size, 4);
  } finally {
    for (const client of clients) client.close();
  }
});


test("rejects a fifth player when all four seats are occupied", async () => {
  const clients = await Promise.all(Array.from({ length:  5 }, () => connect()));
  try {
    const acceptedHost = nextMessage(clients[0], "join_accepted");
    send(clients[0], "create_room", { playerName: "FullHost" });
    const { room } = await acceptedHost;
    for (let index = 1; index < 4; index++) {
      const accepted = nextMessage(clients[index], "join_accepted");
      send(clients[index], "join_room", { roomCode: room.roomCode, playerName: `Full${index}` });
      await accepted;
    }
    const rejected = nextMessage(clients[4], "error");
    send(clients[4], "join_room", { roomCode: room.roomCode, playerName: "Fifth" });
    await assert.rejects(rejected, /مكتملة/);
  } finally {
    for (const client of clients) client.close();
  }
});

test("reconnect restores the same seat and private hand during a game", async () => {
  const clients = await Promise.all(Array.from({ length: 4 }, () => connect()));
  let replacement;
  try {
    const acceptedHost = nextMessage(clients[0], "join_accepted");
    send(clients[0], "create_room", { playerName: "ResumeHost" });
    const host = await acceptedHost;
    const roomCode = host.room.roomCode;
    const resumeToken = host.resumeToken;
    for (let index = 1; index < 4; index++) {
      const accepted = nextMessage(clients[index], "join_accepted");
      send(clients[index], "join_room", { roomCode, playerName: `Resume${index}` });
      await accepted;
    }
    for (let index = 1; index < 4; index++) {
      const snapshot = nextMessage(clients[index], "room_snapshot");
      send(clients[index], "set_ready", { ready: true });
      await snapshot;
    }
    const initialStates = clients.map((client) => nextMessage(client, "game_state"));
    send(clients[0], "start_game");
    const initial = await Promise.all(initialStates);
    const originalHand = initial[0].yourHand;
    const disconnected = once(clients[0], "close");
    clients[0].close();
    await disconnected;

    replacement = await connect();
    const resumed = nextMessage(replacement, "join_accepted");
    const restoredState = nextMessage(replacement, "game_state");
    send(replacement, "reconnect", { roomCode, resumeToken });
    const accepted = await resumed;
    const state = await restoredState;
    assert.equal(accepted.player.seat, 0);
    assert.equal(accepted.player.name, "ResumeHost");
    assert.deepEqual(state.yourHand, originalHand);
    assert.equal(state.game.currentSeat, initial[0].game.currentSeat);
  } finally {
    for (const client of clients) client.close();
    replacement?.close();
  }
});

test("only the host can start a fully ready room", async () => {
  const clients = await Promise.all(Array.from({ length: 4 }, () => connect()));
  try {
    const acceptedHost = nextMessage(clients[0], "join_accepted");
    send(clients[0], "create_room", { playerName: "AuthorityHost" });
    const { room } = await acceptedHost;
    for (let index = 1; index < 4; index++) {
      const accepted = nextMessage(clients[index], "join_accepted");
      send(clients[index], "join_room", { roomCode: room.roomCode, playerName: `Authority${index}` });
      await accepted;
    }
    for (let index = 1; index < 4; index++) {
      const snapshot = nextMessage(clients[index], "room_snapshot");
      send(clients[index], "set_ready", { ready: true });
      await snapshot;
    }
    const rejected = nextMessage(clients[1], "error");
    send(clients[1], "start_game");
    await assert.rejects(rejected, /المضيف وحده/);
    const hostStarted = nextMessage(clients[0], "game_started");
    send(clients[0], "start_game");
    assert.equal((await hostStarted).gameStarted, true);
  } finally {
    for (const client of clients) client.close();
  }
});
