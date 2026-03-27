Mostly vibe-coded chess puzzle app written with OCaml Bonsai.

## Frontend build

- `web/app.js` is generated from `frontend/app.ml` (Bonsai/OCaml).
- Rebuild the browser bundle with:
  - `dune build --profile release web/app.js`
  - `dune build web/app.js` uses the dev profile and is much larger.

## Todo

- [x] Have a deployment process that builds binary to be run on Render/delete python
- [ ] Add email subscription to daily puzzle
- [ ] Add accounts and don't allow moving to next puzzle unless you pass existing puzzle
- [ ] Keep track of user Elos and give puzzles in their Elo range
- [ ] Optional coordinates on board
- [x] If you get it correct, add a link to a Lichess engine with the FEN