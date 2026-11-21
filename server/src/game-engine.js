import { randomInt } from "node:crypto";

export function createRound(players, teamScores = [0, 0], roundNumber = 1, roundHistory = []) {
  if (!Array.isArray(players) || players.length !== 4 ||
      new Set(players.map((p) => p.seat)).size !== 4 ||
      ![0, 1, 2, 3].every((seat) => players.some((p) => p.seat === seat))) {
    throw new Error("Exactly four players in seats 0–3 are required.");
  }
  if (!Array.isArray(teamScores) || teamScores.length !== 2 ||
      teamScores.some((score) => !Number.isInteger(score) || score < 0)) {
    throw new Error("Two non-negative team scores are required.");
  }
  if (!Number.isInteger(roundNumber) || roundNumber < 1) {
    throw new Error("A positive round number is required.");
  }
  if (!Array.isArray(roundHistory)) throw new Error("Round history must be an array.");

  const deck = [];
  for (let first = 0; first <= 6; first++) {
    for (let second = first; second <= 6; second++) deck.push({ first, second });
  }
  for (let i = deck.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }

  const hands = [[], [], [], []];
  deck.forEach((tile, index) => hands[index % 4].push(tile));
  const currentSeat = hands.findIndex((hand) =>
    hand.some((tile) => tile.first === 6 && tile.second === 6));
  if (currentSeat < 0) throw new Error("The 6-6 tile was not dealt.");

  return {
    hands,
    board: [],
    currentSeat,
    consecutivePasses: 0,
    teamScores: [...teamScores],
    roundNumber,
    roundHistory: roundHistory.map((entry) => ({ ...entry, teamScores: [...entry.teamScores] })),
    isFinished: false,
    result: null,
  };
}

export function legalSides(state, tile) {
  if (state.isFinished) return [];
  if (!state.board.length) {
    return tile.first === 6 && tile.second === 6 ? ["right"] : [];
  }
  const sides = [];
  if (tile.first === state.board[0].leftPip || tile.second === state.board[0].leftPip) sides.push("left");
  if (tile.first === state.board.at(-1).rightPip || tile.second === state.board.at(-1).rightPip) sides.push("right");
  return sides;
}

export function publicGameState(room) {
  const game = room.game;
  return {
    roomCode: room.code,
    players: room.seats.map((p) => p ? {
      id: p.id, name: p.name, seat: p.seat, team: p.seat % 2,
      connected: Boolean(p.socket),
    } : null),
    board: game.board.map((tile) => ({ ...tile })),
    currentSeat: game.currentSeat,
    consecutivePasses: game.consecutivePasses,
    teamScores: [...game.teamScores],
    roundNumber: game.roundNumber,
    roundHistory: (game.roundHistory ?? []).map((entry) => ({ ...entry, teamScores: [...entry.teamScores] })),
    remainingTiles: game.hands.map((hand) => hand.length),
    isFinished: game.isFinished,
    result: game.result ? { ...game.result } : null,
  };
}

function finishRound(room, winningTeam, reason) {
  const game = room.game;
  const remaining = [0, 0];
  for (const player of room.seats) {
    for (const tile of game.hands[player.seat]) remaining[player.seat % 2] += tile.first + tile.second;
  }
  let pointsAwarded = 0;
  if (winningTeam !== null) {
    pointsAwarded = remaining[1 - winningTeam];
    game.teamScores[winningTeam] += pointsAwarded;
  }
  game.isFinished = true;
  game.result = { reason, winningTeam, pointsAwarded, teamRemainingPips: remaining };
  game.roundHistory ??= [];
  game.roundHistory.push({
    roundNumber: game.roundNumber,
    reason,
    winningTeam,
    pointsAwarded,
    teamScores: [...game.teamScores],
  });
}

export function playTile(room, seat, tileInput, side) {
  const game = room.game;
  if (!game || game.isFinished) throw new Error("المباراة غير نشطة.");
  if (seat !== game.currentSeat) throw new Error("ليس دورك الآن.");
  if (!tileInput || !Number.isInteger(tileInput.first) || !Number.isInteger(tileInput.second) ||
      tileInput.first < 0 || tileInput.second > 6 || tileInput.first > tileInput.second) {
    throw new Error("بيانات الحجر غير صحيحة.");
  }
  const hand = game.hands[seat];
  const index = hand.findIndex((t) => t.first === tileInput.first && t.second === tileInput.second);
  if (index < 0) throw new Error("هذا الحجر ليس في يدك.");
  const tile = hand[index];
  const chosenSide = side ?? "right";
  if (!legalSides(game, tile).includes(chosenSide)) throw new Error("الحجر لا يطابق طرف السلسلة المختار.");

  if (!game.board.length) {
    game.board.push({ ...tile, leftPip: tile.first, rightPip: tile.second });
  } else if (chosenSide === "left") {
    const match = game.board[0].leftPip;
    const exposed = tile.first === match ? tile.second : tile.first;
    game.board.unshift({ ...tile, leftPip: exposed, rightPip: match });
  } else {
    const match = game.board.at(-1).rightPip;
    const exposed = tile.first === match ? tile.second : tile.first;
    game.board.push({ ...tile, leftPip: match, rightPip: exposed });
  }
  hand.splice(index, 1);
  game.consecutivePasses = 0;

  if (!hand.length) {
    finishRound(room, seat % 2, "player_emptied_hand");
  } else {
    game.currentSeat = (seat + 1) % 4;
  }
  return publicGameState(room);
}

export function passTurn(room, seat) {
  const game = room.game;
  if (!game || game.isFinished) throw new Error("المباراة غير نشطة.");
  if (seat !== game.currentSeat) throw new Error("ليس دورك الآن.");
  if (game.hands[seat].some((tile) => legalSides(game, tile).length)) {
    throw new Error("لا يمكنك التمرير ولديك حجر صالح للعب.");
  }
  game.consecutivePasses++;
  if (game.consecutivePasses >= 4) {
    const remaining = [0, 0];
    for (const player of room.seats) {
      for (const tile of game.hands[player.seat]) remaining[player.seat % 2] += tile.first + tile.second;
    }
    const winner = remaining[0] === remaining[1] ? null : remaining[0] < remaining[1] ? 0 : 1;
    finishRound(room, winner, "blocked");
  } else {
    game.currentSeat = (seat + 1) % 4;
  }
  return publicGameState(room);
}
