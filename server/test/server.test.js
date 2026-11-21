import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { WebSocket } from "ws";
import { httpServer } from "../src/server.js";
import { createRound, playTile, passTurn, publicGameState } from "../src/game-engine.js";

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


function makeEngineRoom(hands, board, currentSeat = 0, teamScores = [0, 0]) {
  return {
    code: "123456",
    seats: Array.from({ length: 4 }, (_, seat) => ({
      id: `engine-player-${seat}`,
      name: `Player ${seat + 1}`,
      seat,
      socket: {},
    })),
    game: {
      hands,
      board,
      currentSeat,
      consecutivePasses: 0,
      teamScores: [...teamScores],
      isFinished: false,
      result: null,
    },
  };
}

test("double-six round contains all 28 unique tiles and deals seven to each player", () => {
  const players = Array.from({ length: 4 }, (_, seat) => ({ seat }));
  const round = createRound(players);
  const allTiles = round.hands.flat();
  assert.equal(allTiles.length, 28);
  assert.ok(round.hands.every((hand) => hand.length === 7));
  assert.equal(new Set(allTiles.map((tile) => `${tile.first}:${tile.second}`)).size, 28);
  assert.ok(round.hands[round.currentSeat].some((tile) => tile.first === 6 && tile.second === 6));
});

test("awards the opposing team's remaining pips when a player empties their hand", () => {
  const room = makeEngineRoom(
    [
      [{ first: 0, second: 6 }],
      [{ first: 3, second: 4 }],
      [{ first: 1, second: 1 }],
      [{ first: 2, second: 2 }],
    ],
    [{ first: 6, second: 6, leftPip: 6, rightPip: 6 }],
  );

  playTile(room, 0, { first: 0, second: 6 }, "right");

  assert.equal(room.game.isFinished, true);
  assert.deepEqual(room.game.result, {
    reason: "player_emptied_hand",
    winningTeam: 0,
    pointsAwarded: 11,
    teamRemainingPips: [2, 11],
  });
  assert.deepEqual(room.game.teamScores, [11, 0]);
});

test("ends a blocked round after four passes and awards the losing team's pips", () => {
  const room = makeEngineRoom(
    [
      [{ first: 1, second: 1 }],
      [{ first: 3, second: 3 }],
      [{ first: 2, second: 2 }],
      [{ first: 4, second: 4 }],
    ],
    [{ first: 0, second: 0, leftPip: 0, rightPip: 0 }],
  );

  for (let seat = 0; seat < 4; seat++) passTurn(room, seat);

  assert.equal(room.game.isFinished, true);
  assert.deepEqual(room.game.result, {
    reason: "blocked",
    winningTeam: 0,
    pointsAwarded: 14,
    teamRemainingPips: [6, 14],
  });
  assert.deepEqual(room.game.teamScores, [14, 0]);
});

test("does not allow a player to pass while holding a legal tile", () => {
  const room = makeEngineRoom(
    [
      [{ first: 0, second: 5 }],
      [{ first: 2, second: 2 }],
      [{ first: 3, second: 3 }],
      [{ first: 4, second: 4 }],
    ],
    [{ first: 0, second: 6, leftPip: 0, rightPip: 6 }],
  );

  assert.throws(() => passTurn(room, 0), /لا يمكنك التمرير/);
  assert.equal(room.game.currentSeat, 0);
  assert.equal(room.game.consecutivePasses, 0);
});


test("next round is host-only and carries the previous team scores forward", async () => {
  const clients = await Promise.all(Array.from({ length: 4 }, () => connect()));
  try {
    const acceptedHost = nextMessage(clients[0], "join_accepted");
    send(clients[0], "create_room", { playerName: "RoundHost" });
    const { room } = await acceptedHost;
    for (let index = 1; index < 4; index++) {
      const accepted = nextMessage(clients[index], "join_accepted");
      send(clients[index], "join_room", { roomCode: room.roomCode, playerName: `Round${index}` });
      await accepted;
    }
    for (let index = 1; index < 4; index++) {
      const snapshot = nextMessage(clients[index], "room_snapshot");
      send(clients[index], "set_ready", { ready: true });
      await snapshot;
    }
    const initialStates = clients.map((client) => nextMessage(client, "game_state"));
    send(clients[0], "start_game");
    const states = await Promise.all(initialStates);
    const roomRef = (await import("../src/server.js")).rooms.get(room.roomCode);
    roomRef.game.teamScores = [25, 40];
    roomRef.game.isFinished = true;

    const rejected = nextMessage(clients[1], "error");
    send(clients[1], "next_round");
    await assert.rejects(rejected, /المضيف وحده/);

    const nextStates = clients.map((client) => nextMessage(client, "game_state"));
    send(clients[0], "next_round");
    const updated = await Promise.all(nextStates);
    for (const state of updated) {
      assert.equal(state.game.roundNumber, 2);
      assert.deepEqual(state.game.teamScores, [25, 40]);
      assert.equal(state.game.isFinished, false);
      assert.equal(state.yourHand.length, 7);
    }
  } finally {
    for (const client of clients) client.close();
  }
});


test("round history records each result and carries it into the next round", () => {
  const room = makeEngineRoom(
    [
      [{ first: 0, second: 6 }],
      [{ first: 3, second: 4 }],
      [{ first: 1, second: 1 }],
      [{ first: 2, second: 2 }],
    ],
    [{ first: 6, second: 6, leftPip: 6, rightPip: 6 }],
  );
  room.game.roundNumber = 1;
  room.game.roundHistory = [];
  playTile(room, 0, { first: 0, second: 6 }, "right");
  assert.deepEqual(room.game.roundHistory, [{
    roundNumber: 1,
    reason: "player_emptied_hand",
    winningTeam: 0,
    pointsAwarded: 11,
    teamScores: [11, 0],
  }]);
  const next = createRound(
    room.seats.map(({ id, name, seat }) => ({ id, name, seat })),
    room.game.teamScores,
    2,
    room.game.roundHistory,
  );
  const publicState = publicGameState({ code: room.code, seats: room.seats, game: next });
  assert.equal(publicState.roundNumber, 2);
  assert.deepEqual(publicState.teamScores, [11, 0]);
  assert.deepEqual(publicState.roundHistory, room.game.roundHistory);
  assert.equal(next.roundHistory.length, 1);
});
