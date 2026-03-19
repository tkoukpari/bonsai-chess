import { Chess } from 'https://cdnjs.cloudflare.com/ajax/libs/chess.js/0.13.4/chess.min.js';

(function () {
  'use strict';

  let game = null;
  let board = null;
  let pendingBoardMoveEnd = null;
  let state = {
    puzzleId: null,
    fen: null,
    moveCount: 0,
    moveInputs: [],
    checkLocked: false,
    isAnimating: false
  };

  const el = {
    loading: document.getElementById('loading'),
    error: document.getElementById('error'),
    errorText: document.getElementById('error-text'),
    retryBtn: document.getElementById('retry-btn'),
    puzzleArea: document.getElementById('puzzle-area'),
    toPlay: document.getElementById('to-play'),
    moveRows: document.getElementById('move-rows'),
    checkBtn: document.getElementById('check-btn'),
    feedback: document.getElementById('feedback')
  };

  function toPlayLabel(fen) {
    var parts = (fen || '').split(/\s/);
    return parts.length > 1 && parts[1] === 'b' ? 'Black to play' : 'White to play';
  }

  function buildMoveRows() {
    var fen = state.fen;
    var mc = state.moveCount;
    if (!fen || mc <= 0) return [];
    var parts = fen.split(/\s/);
    var whiteFirst = parts.length <= 1 || parts[1] !== 'b';
    var moveNumber = parts.length >= 6 ? parseInt(parts[5], 10) || 1 : 1;
    var isWhite = whiteFirst;
    var inputIndex = 0;
    var rowMap = {};
    for (var i = 0; i < mc; i++) {
      if (!rowMap[moveNumber]) rowMap[moveNumber] = { moveNumber: moveNumber, white: null, black: null };
      if (isWhite) { rowMap[moveNumber].white = inputIndex++; }
      else { rowMap[moveNumber].black = inputIndex++; }
      if (isWhite) isWhite = false;
      else { isWhite = true; moveNumber++; }
    }
    return Object.keys(rowMap).sort(function (a, b) { return Number(a) - Number(b); }).map(function (n) {
      return { moveNumber: Number(n), white: rowMap[n].white, black: rowMap[n].black };
    });
  }

  function renderMoveInputs() {
    var rows = buildMoveRows();
    el.moveRows.innerHTML = '';
    while (state.moveInputs.length < state.moveCount) state.moveInputs.push('');
    state.moveInputs = state.moveInputs.slice(0, state.moveCount);

    rows.forEach(function (row) {
      var rowEl = document.createElement('div');
      rowEl.className = 'move-row';
      var numSpan = document.createElement('span');
      numSpan.className = 'move-num';
      numSpan.textContent = row.moveNumber + '.';
      rowEl.appendChild(numSpan);

      function makeInput(idx) {
        var inp = document.createElement('input');
        inp.type = 'text';
        inp.className = 'move-input';
        inp.autocomplete = 'off';
        if (idx !== null) {
          inp.value = state.moveInputs[idx] || '';
          inp.dataset.index = idx;
          inp.addEventListener('input', function () {
            var i = parseInt(this.dataset.index, 10);
            if (i >= 0 && i < state.moveInputs.length) state.moveInputs[i] = this.value;
          });
        } else {
          inp.disabled = true;
          inp.style.visibility = 'hidden';
        }
        return inp;
      }

      rowEl.appendChild(makeInput(row.white));
      rowEl.appendChild(makeInput(row.black));
      el.moveRows.appendChild(rowEl);
    });
  }

  function showLoading() {
    el.loading.style.display = 'block';
    el.error.style.display = 'none';
    el.puzzleArea.style.display = 'none';
  }

  function showError(msg) {
    el.loading.style.display = 'none';
    el.errorText.textContent = msg;
    el.error.style.display = 'block';
    el.puzzleArea.style.display = 'none';
  }

  function showPuzzle() {
    el.loading.style.display = 'none';
    el.error.style.display = 'none';
    el.puzzleArea.style.display = 'block';
  }

  function updateCheckBtn() {
    el.checkBtn.disabled = state.checkLocked || state.isAnimating;
  }

  function setFeedback(text, isCorrect) {
    el.feedback.textContent = text;
    if (!text) {
      el.feedback.className = 'mb-0';
    } else {
      el.feedback.className = 'mb-0 ' + (isCorrect ? 'feedback-correct' : 'feedback-error');
    }
  }

  function initBoard(fen) {
    game = new Chess(fen);
    var cfg = {
      position: fen,
      showNotation: false,
      // Use PNG pieces to avoid SVG repaint flashes during animations.
      pieceTheme: 'img/chesspieces/merida/{piece}.svg',
      moveSpeed: 600,
      snapbackSpeed: 600,
      snapSpeed: 100,
      trashSpeed: 200,
      appearSpeed: 200,
      onMoveEnd: function () {
        if (typeof pendingBoardMoveEnd === 'function') {
          var cb = pendingBoardMoveEnd;
          pendingBoardMoveEnd = null;
          cb();
        }
      }
    };
    if (board) {
      board.position(fen, false);
    } else {
      board = Chessboard('board', cfg);
      window.addEventListener('resize', function () { board.resize(); });
    }
  }

  function animateBoardToFen(fen, after) {
    // Defer DOM-heavy updates until Chessboard.js finishes animating,
    // to avoid jank / full-page repaints mid-animation.
    pendingBoardMoveEnd = typeof after === 'function' ? after : null;
    board.position(fen, true);
  }

  var puzzleApi = typeof window.BONSAI_PUZZLE_API === 'string' ? window.BONSAI_PUZZLE_API : '/api/puzzle';

  function fetchPuzzle() {
    showLoading();
    setFeedback('', false);

    fetch(puzzleApi)
      .then(function (res) {
        if (!res.ok) return res.text().then(function (t) { throw new Error(t || 'Server error'); });
        return res.json();
      })
      .then(function (data) {
        state.puzzleId = data.id;
        state.fen = data.fen;
        state.moveCount = data.moveCount;
        state.moveInputs = Array(data.moveCount).fill('');
        state.checkLocked = false;
        state.isAnimating = false;

        showPuzzle();
        initBoard(data.fen);
        requestAnimationFrame(function () {
          board.resize();
          el.toPlay.textContent = toPlayLabel(data.fen);
          renderMoveInputs();
          updateCheckBtn();
          setFeedback('', false);
        });
      })
      .catch(function (err) {
        showError(err.message || 'Cannot reach server.');
      });
  }

  function loadNextPuzzle() {
    fetch(puzzleApi)
      .then(function (res) {
        if (!res.ok) return res.text().then(function (t) { throw new Error(t || 'Server error'); });
        return res.json();
      })
      .then(function (data) {
        state.puzzleId = data.id;
        state.fen = data.fen;
        state.moveCount = data.moveCount;
        state.moveInputs = Array(data.moveCount).fill('');
        state.checkLocked = false;
        state.isAnimating = false;

        game = new Chess(data.fen);
        animateBoardToFen(data.fen, function () {
          el.toPlay.textContent = toPlayLabel(data.fen);
          renderMoveInputs();
          updateCheckBtn();
          setFeedback('', false);
        });
      })
      .catch(function () {
        state.checkLocked = false;
        state.isAnimating = false;
        updateCheckBtn();
        setFeedback('Could not load next puzzle.', false);
      });
  }

  function animateSolution(moves, onDone) {
    if (!moves.length) { onDone(); return; }
    state.isAnimating = true;
    updateCheckBtn();
    game = new Chess(state.fen);
    board.position(state.fen, false);
    var idx = 0;

    function runNext() {
      if (idx >= moves.length) {
        state.isAnimating = false;
        setTimeout(onDone, 1500);
        return;
      }
      var san = moves[idx];
      var move = game.move(san);
      if (!move) { idx++; runNext(); return; }
      pendingBoardMoveEnd = function () {
        idx++;
        setTimeout(runNext, 250);
      };
      board.move(move.from + '-' + move.to);
    }
    setTimeout(runNext, 500);
  }

  function checkAnswer() {
    if (!state.puzzleId || !state.fen || state.checkLocked || state.isAnimating) return;
    var moves = state.moveInputs.map(function (s) { return s.trim(); }).filter(Boolean);
    state.checkLocked = true;
    updateCheckBtn();

    fetch('/api/puzzle/result', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ puzzle_id: state.puzzleId, moves: moves })
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data.correct) {
          setFeedback('Correct! Well done.', true);
          animateSolution(moves, function () {
            loadNextPuzzle();
          });
        } else {
          state.checkLocked = false;
          updateCheckBtn();
          setFeedback(data.error || 'Incorrect. Try again.', false);
        }
      })
      .catch(function () {
        state.checkLocked = false;
        updateCheckBtn();
        setFeedback('Cannot reach server.', false);
      });
  }

  el.retryBtn.addEventListener('click', function () { fetchPuzzle(); });
  el.checkBtn.addEventListener('click', checkAnswer);

  fetchPuzzle();
})();
