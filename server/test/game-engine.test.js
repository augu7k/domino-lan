import test from "node:test";
import assert from "node:assert/strict";
import { createRound, legalSides, playTile, passTurn } from "../src/game-engine.js";

const players = [0, 1, 2, 3].map((seat) => ({ id: `p${seat}`, name: `P${seat}`, seat }));
function roomWithHands(hands) {
  const seats = players.map((p) => ({ ...p, socket: null }));
  return {
    code: "123456", seats, gameStarted: true,
    game: {
      hands: hands.map((hand) => hand.map(([first, second]) => ({ first, second }))),
      board: [{ first: 6, second: 6, leftPip: 6, rightPip: 6 }],
      currentSeat: 0, consecutivePasses: 0, teamScores: [0, 0],
      isFinished: false, result: null,
    },
  };
}

test("creates a unique 28-tile double-six deck and deals seven to each player", () => {
  const state = createRound(players);
  assert.equal(state.hands.length, 4);
  assert.deepEqual(state.hands.map((hand) => hand.length), [7, 7, 7, 7]);
  const all = state.hands.flat().map((t) => `${t.first}|${t.second}`);
  assert.equal(new Set(all).size, 28);
  assert.ok(state.hands[state.currentSeat].some((t) => t.first === 6 && t.second === 6));
});

test("legal opening is the 6-6 and legal side detection handles both ends", () => {
  const state = { board: [], isFinished: false };
  assert.deepEqual(legalSides(state, { first: 6, second: 6 }), ["right"]);
  assert.deepEqual(legalSides(state, { first: 1, second: 6 }), []);
  state.board.push({ leftPip: 2, rightPip: 5 });
  assert.deepEqual(legalSides(state, { first: 2, second: 4 }), ["left"]);
  assert.deepEqual(legalSides(state, { first: 3, second: 5 }), ["right"]);
  assert.deepEqual(legalSides(state, { first: 2, second: 5 }), ["left", "right"]);
});

test("rejects wrong turn, opponent tiles, and nonmatching sides", () => {
  const room = roomWithHands([[[1, 6]], [[0, 0]], [[2, 2]], [[3, 3]]]);
  assert.throws(() => playTile(room, 1, { first: 0, second: 0 }, "right"), /ليس دورك/);
  assert.throws(() => playTile(room, 0, { first: 0, second: 0 }, "right"), /ليس في يدك/);
  assert.throws(() => playTile(room, 0, { first: 1, second: 6 }, "middle"), /لا يطابق/);
});

test("accepts a move, orients it, advances turn, and awards opposing pips when hand empties", () => {
  const room = roomWithHands([[[3, 6]], [[0, 0]], [[2, 2]], [[4, 4]]]);
  playTile(room, 0, { first: 3, second: 6 }, "right");
  assert.equal(room.game.board.at(-1).leftPip, 6);
  assert.equal(room.game.board.at(-1).rightPip, 3);
  assert.equal(room.game.currentSeat, 0);
  assert.equal(room.game.isFinished, true);
  assert.equal(room.game.result.winningTeam, 0);
  assert.equal(room.game.result.pointsAwarded, 8);
  assert.deepEqual(room.game.teamScores, [8, 0]);
});

test("requires all four passes to finish a blocked round and awards the lower-pip team", () => {
  const room = roomWithHands([[[0, 0]], [[1, 1]], [[2, 2]], [[3, 3]]]);
  for (let seat = 0; seat < 4; seat++) passTurn(room, seat);
  assert.equal(room.game.isFinished, true);
  assert.equal(room.game.result.reason, "blocked");
  assert.equal(room.game.result.winningTeam, 0);
  assert.equal(room.game.result.pointsAwarded, 8);
  assert.deepEqual(room.game.teamScores, [8, 0]);
});

test("rejects a pass when the current player has a legal move", () => {
  const room = roomWithHands([[[1, 6]], [[0, 0]], [[2, 2]], [[3, 3]]]);
  assert.throws(() => passTurn(room, 0), /لا يمكنك التمرير/);
});
