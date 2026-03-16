import { Chess } from 'https://unpkg.com/chess.js@1.5.1/dist/esm/chess.js';

(function () {
  'use strict';

  const PIECE_SYMBOLS = {
    w: { k: '\u2654', q: '\u2655', r: '\u2656', b: '\u2657', n: '\u2658', p: '\u2659' },
    b: { k: '\u265A', q: '\u265B', r: '\u265C', b: '\u265D', n: '\u265E', p: '\u265F' }
  };

  let game = null;
  let state = {
    puzzleId: null,
    fen: null,
    moveCount: 0,
    moveInputs: [],
    loading: false,
    loadError: null,
    checkLocked: false,
    isAnimating: false,
    transitionPhase: null,
    pendingPuzzle: null
  };

  const el = {
    loading: document.getElementById('loading'),
    error: document.getElementById('error'),
    errorText: document.getElementById('error-text'),
    retryBtn: document.getElementById('retry-btn'),
    puzzleArea: document.getElementById('puzzle-area'),
    board: document.getElementById('board'),
    pieceFloater: document.getElementById('piece-floater'),
    toPlay: document.getElementById('to-play'),
    moveRows: document.getElementById('move-rows'),
    checkBtn: document.getElementById('check-btn'),
    feedback: document.getElementById('feedback')
  };

  function getToPlayLabel(fen) {
    const parts = (fen || '').split(/\s/);
    return parts.length > 1 && parts[1] === 'b' ? 'Black to play' : 'White to play';
  }

  function buildMoveRows() {
    const fen = state.fen;
    const moveCount = state.moveCount;
    if (!fen || moveCount <= 0) return [];
    const parts = fen.split(/\s/);
    const whiteFirst = parts.length <= 1 || parts[1] !== 'b';
    const rows = [];
    let moveNumber = 1;
    let isWhite = whiteFirst;
    let inputIndex = 0;
    const rowMap = {};
    for (let i = 0; i < moveCount; i++) {
      if (!rowMap[moveNumber]) rowMap[moveNumber] = { moveNumber, white: null, black: null };
      if (isWhite) {
        rowMap[moveNumber].white = inputIndex++;
      } else {
        rowMap[moveNumber].black = inputIndex++;
      }
      if (isWhite) isWhite = false;
      else { isWhite = true; moveNumber++; }
    }
    return Object.keys(rowMap).sort((a, b) => Number(a) - Number(b)).map(n => ({
      moveNumber: Number(n),
      white: rowMap[n].white,
      black: rowMap[n].black
    }));
  }

  function renderBoard(fen, forTransition) {
    game = new Chess(fen);
    if (!game) return;
    const boardEl = el.board;
    boardEl.innerHTML = '';
    boardEl.classList.remove('transition-out', 'transition-in');
    const b = game.board();
    for (let rank = 0; rank < 8; rank++) {
      for (let file = 0; file < 8; file++) {
        const isLight = (rank + file) % 2 === 0;
        const sq = document.createElement('div');
        sq.className = 'square ' + (isLight ? 'light' : 'dark');
        sq.dataset.rank = rank;
        sq.dataset.file = file;
        const piece = b[rank][file];
        if (piece) {
          const sym = PIECE_SYMBOLS[piece.color][piece.type];
          sq.textContent = sym;
        }
        boardEl.appendChild(sq);
      }
    }
    if (!forTransition) {
      el.toPlay.textContent = getToPlayLabel(fen);
    }
  }

  function getSquareRect(rank, file) {
    const boardEl = el.board;
    const rect = boardEl.getBoundingClientRect();
    const cellW = rect.width / 8;
    const cellH = rect.height / 8;
    return {
      left: rect.left + file * cellW,
      top: rect.top + rank * cellH,
      width: cellW,
      height: cellH
    };
  }

  function renderMoveInputs() {
    const rows = buildMoveRows();
    el.moveRows.innerHTML = '';
    state.moveInputs = state.moveInputs.slice(0, rows.reduce((n, r) => n + (r.white !== null ? 1 : 0) + (r.black !== null ? 1 : 0), 0));
    while (state.moveInputs.length < (state.moveCount || 0)) state.moveInputs.push('');
    state.moveInputs = state.moveInputs.slice(0, state.moveCount);

    rows.forEach(row => {
      const rowEl = document.createElement('div');
      rowEl.className = 'move-row';
      rowEl.innerHTML = '<span class="move-num">' + row.moveNumber + '.</span>';
      const whiteInput = document.createElement('input');
      whiteInput.type = 'text';
      whiteInput.className = 'form-control form-control-sm move-input';
      whiteInput.placeholder = 'White';
      if (row.white !== null) {
        whiteInput.value = state.moveInputs[row.white] || '';
        whiteInput.dataset.index = row.white;
        whiteInput.addEventListener('input', function () {
          const i = parseInt(this.dataset.index, 10);
          if (i >= 0 && i < state.moveInputs.length) state.moveInputs[i] = this.value;
        });
        rowEl.appendChild(whiteInput);
      } else {
        const span = document.createElement('span');
        span.className = 'move-input';
        span.style.minWidth = '6rem';
        rowEl.appendChild(span);
      }
      const blackInput = document.createElement('input');
      blackInput.type = 'text';
      blackInput.className = 'form-control form-control-sm move-input';
      blackInput.placeholder = 'Black';
      if (row.black !== null) {
        blackInput.value = state.moveInputs[row.black] || '';
        blackInput.dataset.index = row.black;
        blackInput.addEventListener('input', function () {
          const i = parseInt(this.dataset.index, 10);
          if (i >= 0 && i < state.moveInputs.length) state.moveInputs[i] = this.value;
        });
        rowEl.appendChild(blackInput);
      } else {
        const span = document.createElement('span');
        span.className = 'move-input';
        span.style.minWidth = '6rem';
        rowEl.appendChild(span);
      }
      el.moveRows.appendChild(rowEl);
    });
  }

  function setUI() {
    if (state.loading && !state.puzzleId) {
      el.loading.style.display = 'block';
      el.error.style.display = 'none';
      el.puzzleArea.style.display = 'none';
      return;
    }
    el.loading.style.display = 'none';
    if (state.loadError) {
      el.errorText.textContent = state.loadError;
      el.error.style.display = 'block';
      el.puzzleArea.style.display = 'none';
      return;
    }
    el.error.style.display = 'none';
    el.puzzleArea.style.display = 'block';
    el.feedback.textContent = '';
    el.feedback.className = 'text-center mb-0';
    el.checkBtn.disabled = state.checkLocked || state.isAnimating;
  }

  function fetchPuzzle(transitionFromFen) {
    const isTransition = !!transitionFromFen;
    if (!isTransition) {
      state.loading = true;
      state.loadError = null;
    }
    setUI();

    fetch('/api/puzzle/daily')
      .then(function (res) {
        if (!res.ok) return res.text().then(function (t) { throw new Error(t || 'Server error'); });
        return res.json();
      })
      .then(function (data) {
        if (!isTransition) state.loading = false;
        state.loadError = null;
        state.puzzleId = data.id;
        state.fen = data.fen;
        state.moveCount = data.moveCount;
        state.moveInputs = Array(data.moveCount).fill('');
        state.checkLocked = false;

        if (isTransition && transitionFromFen) {
          state.pendingPuzzle = data;
          el.board.classList.add('transition-out');
          setTimeout(function () {
            renderBoard(data.fen);
            state.fen = data.fen;
            state.puzzleId = data.id;
            state.moveCount = data.moveCount;
            state.moveInputs = Array(data.moveCount).fill('');
            state.pendingPuzzle = null;
            renderMoveInputs();
            el.toPlay.textContent = getToPlayLabel(data.fen);
            el.board.classList.remove('transition-out');
            el.board.classList.add('transition-in');
            el.feedback.textContent = '';
            setTimeout(function () {
              el.board.classList.remove('transition-in');
              setUI();
            }, 400);
          }, 400);
        } else {
          renderBoard(data.fen);
          renderMoveInputs();
          setUI();
        }
      })
      .catch(function (err) {
        if (!isTransition) state.loading = false;
        state.loadError = err.message || 'Cannot reach server.';
        setUI();
      });
  }

  function animateSolution(moves, onDone) {
    if (!moves.length) { onDone(); return; }
    state.isAnimating = true;
    setUI();
    const boardEl = el.board;
    const floater = el.pieceFloater;
    let idx = 0;
    game = new Chess(state.fen);

    function runNext() {
      if (idx >= moves.length) {
        state.isAnimating = false;
        floater.style.display = 'none';
        const finalFen = game.fen();
        setTimeout(function () { onDone(finalFen); }, 1500);
        return;
      }
      const san = moves[idx];
      const fenBefore = game.fen();
      const move = game.move(san);
      if (!move) { idx++; setTimeout(runNext, 0); return; }
      const fromR = 8 - parseInt(move.from[1], 10);
      const fromF = move.from.charCodeAt(0) - 97;
      const toR = 8 - parseInt(move.to[1], 10);
      const toF = move.to.charCodeAt(0) - 97;
      const gameBefore = new Chess(fenBefore);
      const b = gameBefore.board();
      const piece = b[fromR][fromF];
      const sym = piece ? PIECE_SYMBOLS[piece.color][piece.type] : '';
      floater.textContent = sym;
      floater.style.display = 'flex';

      renderBoard(fenBefore);
      const rect = boardEl.getBoundingClientRect();
      const cellW = rect.width / 8;
      const cellH = rect.height / 8;
      const fromLeft = fromF * cellW;
      const fromTop = fromR * cellH;
      const toLeft = toF * cellW;
      const toTop = toR * cellH;

      floater.style.left = fromLeft + 'px';
      floater.style.top = fromTop + 'px';
      floater.style.width = cellW + 'px';
      floater.style.height = cellH + 'px';
      const firstSq = boardEl.querySelector('.square');
      floater.style.fontSize = firstSq ? getComputedStyle(firstSq).fontSize : '1.5rem';
      floater.classList.remove('animating');
      floater.offsetHeight;
      floater.classList.add('animating');
      floater.style.left = toLeft + 'px';
      floater.style.top = toTop + 'px';

      idx++;
      setTimeout(function () {
        renderBoard(game.fen());
        setTimeout(runNext, 120);
      }, 550);
    }
    runNext();
  }

  function checkAnswer() {
    if (!state.puzzleId || !state.fen || state.checkLocked || state.isAnimating) return;
    const moves = state.moveInputs.map(function (s) { return s.trim(); }).filter(Boolean);
    state.checkLocked = true;
    setUI();

    fetch('/api/puzzle/result', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ puzzle_id: state.puzzleId, moves: moves })
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data.correct) {
          el.feedback.textContent = 'Correct! Well done.';
          el.feedback.className = 'text-center mb-0 feedback-correct';
          animateSolution(moves, function (finalFen) {
            fetchPuzzle(finalFen);
          });
        } else {
          state.checkLocked = false;
          el.feedback.textContent = data.error || 'Incorrect. Try again.';
          el.feedback.className = 'text-center mb-0 feedback-error';
          setUI();
        }
      })
      .catch(function () {
        state.checkLocked = false;
        el.feedback.textContent = 'Cannot reach server.';
        el.feedback.className = 'text-center mb-0 feedback-error';
        setUI();
      });
  }

  el.retryBtn.addEventListener('click', function () { fetchPuzzle(); });
  el.checkBtn.addEventListener('click', checkAnswer);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { fetchPuzzle(); });
  } else {
    fetchPuzzle();
  }
})();
