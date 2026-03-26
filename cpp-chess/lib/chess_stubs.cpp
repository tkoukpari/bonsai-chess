#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "chess.cpp"
#include <cstring>
#include <stdexcept>
#include <string>

#define Board_val(v) (*((chess::Board**)Data_custom_val(v)))

static void board_finalize(value v) {
  chess::Board* b = (chess::Board*)Data_custom_val(v);
  delete b;
}

static struct custom_operations board_ops = {
  "bonsai.chess.board",
  board_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

extern "C" {

CAMLprim value caml_chess_board_create(value fen_val) {
  CAMLparam1(fen_val);
  CAMLlocal2(result, some);
  const char* fen = String_val(fen_val);
  chess::Board* board = nullptr;
  try {
    board = new chess::Board(std::string(fen));
  } catch (const std::exception&) {
    CAMLreturn(Val_int(0));  /* None */
  }
  result = caml_alloc_custom(&board_ops, sizeof(chess::Board*), 0, 1);
  *(chess::Board**)Data_custom_val(result) = board;
  some = caml_alloc_small(2, 0);
  Field(some, 0) = result;
  CAMLreturn(some);
}

CAMLprim value caml_chess_board_push_uci(value board_val, value uci_val) {
  CAMLparam2(board_val, uci_val);
  chess::Board* board = Board_val(board_val);
  const char* uci = String_val(uci_val);
  try {
    chess::Move m = chess::Move::from_uci(std::string(uci));
    board->push(m);
  } catch (const std::exception&) {
    caml_failwith("invalid uci move");
  }
  CAMLreturn(Val_unit);
}

CAMLprim value caml_chess_board_fen(value board_val) {
  CAMLparam1(board_val);
  chess::Board* board = Board_val(board_val);
  std::string f = board->fen();
  CAMLreturn(caml_copy_string(f.c_str()));
}

CAMLprim value caml_chess_board_parse_san(value board_val, value san_val) {
  CAMLparam2(board_val, san_val);
  CAMLlocal1(result);
  chess::Board* board = Board_val(board_val);
  const char* san = String_val(san_val);
  try {
    chess::Move m = board->parse_san(std::string(san));
    std::string uci = m.uci();
    result = caml_alloc_small(2, 0);
    Field(result, 0) = caml_copy_string(uci.c_str());
  } catch (const std::invalid_argument& e) {
    std::string msg(e.what());
    result = caml_alloc_small(2, 1);
    const char* err =
      msg.find("ambiguous san") != std::string::npos ? "ambiguous" :
      msg.find("illegal san") != std::string::npos ? "illegal" : "invalid";
    Field(result, 0) = caml_copy_string(err);
  } catch (const std::exception&) {
    result = caml_alloc_small(2, 1);
    Field(result, 0) = caml_copy_string("invalid");
  }
  CAMLreturn(result);
}

}
