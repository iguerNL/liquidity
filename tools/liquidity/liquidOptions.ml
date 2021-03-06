(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2017 - OCamlPro SAS                                   *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)


let verbosity =
  ref
    (try int_of_string (Sys.getenv "LIQUID_VERBOSITY")
     with
     | Not_found -> 0
     | _ -> 1 (* LIQUID_DEBUG not a number *)
    )

let peephole = ref true
let keepon = ref false
let typeonly = ref false
let parseonly = ref false
let singleline = ref false
let annotmic = ref true
let annotafter = ref true (* XXX: Disable when Tezos is fixed *)

let tezos_node = ref "127.0.0.1:8732"

let source = ref (None : string option)
let amount = ref "0"
let fee = ref "5"

let private_key = ref (None : string option)
