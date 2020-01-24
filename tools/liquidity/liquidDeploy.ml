(****************************************************************************)
(*                               Liquidity                                  *)
(*                                                                          *)
(*                  Copyright (C) 2017-2019 OCamlPro SAS                    *)
(*                                                                          *)
(*                    Authors: Fabrice Le Fessant                           *)
(*                             Alain Mebsout                                *)
(*                             David Declerck                               *)
(*                                                                          *)
(*  This program is free software: you can redistribute it and/or modify    *)
(*  it under the terms of the GNU General Public License as published by    *)
(*  the Free Software Foundation, either version 3 of the License, or       *)
(*  (at your option) any later version.                                     *)
(*                                                                          *)
(*  This program is distributed in the hope that it will be useful,         *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of          *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           *)
(*  GNU General Public License for more details.                            *)
(*                                                                          *)
(*  You should have received a copy of the GNU General Public License       *)
(*  along with this program.  If not, see <https://www.gnu.org/licenses/>.  *)
(****************************************************************************)

open LiquidTypes
open Dune_Network_Lib (* for crypto *)

type from =
  | From_strings of string list
  | From_files of string list

type bm_id =
  | Bm_id of int
  | Bm_name of int * string

type ('id, 'const) big_map_diff_item =
  | Big_map_add of { id : 'id;
                     key_hash : string;
                     key : 'const;
                     value : 'const }
  | Big_map_remove of { id : 'id;
                        key_hash : string;
                        key : 'const }
  | Big_map_delete of { id : 'id }
  | Big_map_alloc of { id : 'id }
  | Big_map_copy of { source_id : 'id;
                      destination_id : 'id }

type ('id, 'const) big_map_diff = ('id, 'const) big_map_diff_item list

type liq_big_map_diff = (bm_id, typed_const) big_map_diff_item list

type stack_item =
  | StackConst of typed_const
  | StackCode of int

type trace_item = {
  loc : location option;
  gas : int;
  stack : (stack_item * string option) list;
}

type trace = trace_item array

type internal_operation =
  | Reveal of string
  | Transaction of {
      amount : string;
      destination : string;
      entrypoint : string;
      parameters : typed_const option;
    }
  | Origination of {
      delegate: string option ;
      script: (typed_contract * typed_const) option ;
      balance: string ;
    }
  | Delegation of string option

type operation = {
  source : string;
  nonce : int;
  op : internal_operation;
}

exception RequestError of int * string
exception ResponseError of string
exception RuntimeError of error * trace option
exception LocalizedError of error
exception RuntimeFailure of error * string option * trace option

module type S = sig
  type 'a t
  val run : from -> string -> string -> string ->
    (operation list * LiquidTypes.typed_const * liq_big_map_diff) t
  val run_debug : from -> string -> string -> string ->
    (operation list * LiquidTypes.typed_const * liq_big_map_diff * trace) t
  val init_storage : from -> string list -> LiquidTypes.encoded_const t
  val forge_deploy_script :
    source:string -> from -> string list ->
    (string * string * LiquidToMicheline.loc_table) t
  val forge_deploy :
    from -> string list -> string t
  val deploy :
    from -> string list -> (string * (string, exn) result) t
  val get_storage : from -> string -> LiquidTypes.typed_const t
  val get_big_map_value :
    from -> bm_id * LiquidTypes.datatype * LiquidTypes.datatype -> string ->
    LiquidTypes.typed_const option t
  val forge_call_parameter :
    from -> string -> string -> string * LiquidToMicheline.loc_table
  val forge_call : from -> string -> string -> string -> string t
  val call : from -> string -> string -> string ->
    (string * (unit, exn) result) t
  val activate : secret:string -> string t
  val inject : operation:string -> signature:string -> string t
  val pack : ?liquid:from -> const:string -> ty:string -> string t
end

module ExprHash = struct
  let prefix = "\013\044\064\027" (* expr(54) *)
  include Blake2B.Make(Base58)(struct
      let name = "script_expr"
      let title = "A script expression hash"
      let b58check_prefix = prefix
      let size = None
    end)
end

open Lwt

module Network_sync = struct
  let writer_callback a d =
    Buffer.add_string a d;
    String.length d

  let initialize_connection host path =
    let url = Printf.sprintf "%s%s" host path in
    let r = Buffer.create 16384
    and c = Curl.init () in
    Curl.set_timeout c 30;      (* Timeout *)
    Curl.set_sslverifypeer c false;
    Curl.set_sslverifyhost c Curl.SSLVERIFYHOST_EXISTENCE;
    Curl.set_writefunction c (writer_callback r);
    Curl.set_tcpnodelay c true;
    Curl.set_verbose c false;
    Curl.set_post c false;
    Curl.set_url c url; r,c

  let post ?(content_type = "application/json") host path data =
    let r, c = initialize_connection host path in
    Curl.set_post c true;
    Curl.set_httpheader c [ "Content-Type: " ^ content_type ];
    Curl.set_postfields c data;
    Curl.set_postfieldsize c (String.length data);
    Curl.perform c;
    let rc = Curl.get_responsecode c in
    Curl.cleanup c;
    rc, (Buffer.contents r)

  let get ?(content_type = "application/json") host path =
    let r, c = initialize_connection host path in
    Curl.set_post c false;
    Curl.set_httpheader c [ "Content-Type: " ^ content_type ];
    Curl.perform c;
    let rc = Curl.get_responsecode c in
    Curl.cleanup c;
    rc, (Buffer.contents r)
end

module Network = struct
  let writer_callback a d =
    Buffer.add_string a d;
    String.length d

  let initialize_connection host path =
    let url = Printf.sprintf "%s%s" host path in
    let r = Buffer.create 16384
    and c = Curl.init () in
    Curl.set_timeout c 30;      (* Timeout *)
    Curl.set_sslverifypeer c false;
    Curl.set_sslverifyhost c Curl.SSLVERIFYHOST_EXISTENCE;
    Curl.set_writefunction c (writer_callback r);
    Curl.set_tcpnodelay c true;
    Curl.set_verbose c false;
    Curl.set_post c false;
    Curl.set_url c url; r,c

  let post ?(content_type = "application/json") host path data =
    let r, c = initialize_connection host path in
    Curl.set_post c true;
    Curl.set_httpheader c [ "Content-Type: " ^ content_type ];
    Curl.set_postfields c data;
    Curl.set_postfieldsize c (String.length data);
    Curl_lwt.perform c >>= fun cc ->
    (* if cc <> Curl.CURLE_OK then
     *   raise (RequestError
     *            (Printf.sprintf "[%d] [%s] Curl exception: %s\n%!"
     *                (Curl.errno cc) host path))
     * else *)
    let rc = Curl.get_responsecode c in
    Curl.cleanup c;
    Lwt.return (rc, (Buffer.contents r))

  let get ?(content_type = "application/json") host path =
    let r, c = initialize_connection host path in
    Curl.set_post c false;
    Curl.set_httpheader c [ "Content-Type: " ^ content_type ];
    Curl_lwt.perform c >>= fun cc ->
    (* if cc <> Curl.CURLE_OK then
     *   raise (RequestError
     *            (Printf.sprintf "[%d] [%s] Curl exception: %s\n%!"
     *                (Curl.errno cc) host path))
     * else *)
    let rc = Curl.get_responsecode c in
    Curl.cleanup c;
    Lwt.return (rc, (Buffer.contents r))
end

(*      (Ezjsonm.to_string ~minify:false (Ezjsonm.from_string data)); *)

let curl_call meth f data path =
  let host = !LiquidOptions.node in
  if !LiquidOptions.verbosity > 0 then
    Printf.eprintf "\n%s to %s%s:\n--------------\n<<<%s>>>\n%!"
      meth host path data;
  try
    f host path data >>= fun (status, json) ->
    if !LiquidOptions.verbosity > 0 then begin
      Printf.eprintf "\nNode Response %d:\n------------------\n<<<%s>>>\n%!"
        status json;
    end;
    if status <> 200 then raise (RequestError (status, json));
    return json
  with Curl.CurlException (code, i, s) (* as exn *) ->
    raise (RequestError (Curl.errno code, s))

let curl_post ~data path =
  curl_call "POST" Network.post data path

let curl_get path =
  curl_call "GET" (fun host path data -> Network.get host path) "" path


let post = ref curl_post
let get = ref curl_get


(* let error_string_of_michelson_error json =
 *   let errors =  Ezjsonm.get_list Error_monad.error_of_json json in
 *   let fmt = Format.str_formatter in
 *   Michelson_v1_error_reporter.report_error
 *     ~details:false
 *     ~show_source:false
 *     fmt
 *     errors;
 *   Format.flush_str_formatter () *)

let error_schema =
  lazy (
    Lwt.catch
      (fun () -> !get "/errors" >|= Ezjsonm.from_string)
      (function
        | RequestError _ | Not_found -> return @@ `O []
        | exn -> Lwt.fail exn)
  )


let memo_stack_code_cpt = ref 0
let memo_stack_code_tbl = Hashtbl.create 19
let reset_memo_stack_code () =
  memo_stack_code_cpt := 0;
  Hashtbl.clear memo_stack_code_tbl
let memo_stack_code e =
  try Hashtbl.find memo_stack_code_tbl e
  with Not_found ->
    let cpt = !memo_stack_code_cpt in
    incr memo_stack_code_cpt;
    Hashtbl.add memo_stack_code_tbl e cpt;
    cpt

let name_of_var_annot = function
  | None -> None
  | Some annot ->
    try Scanf.sscanf annot "@%s" (function
        | "" -> None
        | s -> Some s
      )
    with Scanf.Scan_failure _ | End_of_file -> None

let convert_const env ?ty e =
  let mic_e, loc = match ty with
    | Some ty -> LiquidFromMicheline.convert_const_type env e ty
    | None -> LiquidFromMicheline.convert_const_notype env e in
  let nod_e = LiquidInterp.decompile_const loc mic_e in
  let syn_e = LiquidDecomp.decompile_const nod_e in
  let tenv =
    empty_typecheck_env ~warnings:false
      LiquidTypes.dummy_contract_sig
      (LiquidFromParsetree.initial_env "") in
  LiquidCheck.typecheck_const tenv ?expected_ty:ty ~loc syn_e
  (* |> LiquidEncode.encode_const tenv.env tenv.t_contract_sig *)
  |> LiquidSimplify.simplify_const
  (* |> LiquidDecode.decode_const *)
  |> LiquidUntype.untype_const

let convert_stack env stack_expr =
  List.map (fun (e, annot) ->
      let name = name_of_var_annot annot in
      try StackConst (convert_const env e), name
      with _ -> StackCode (memo_stack_code e), name
    ) stack_expr

let trace_of_json env ~loc_table ?(error=false) trace_r =
  let trace_expr =
    Ezjsonm.get_list (fun step ->
        let loc = Ezjsonm.find step ["location"] |> Ezjsonm.get_int in
        let gas = Ezjsonm.find step ["gas"]
                  |> Ezjsonm.get_string |> int_of_string in
        let stack =
          Ezjsonm.find step ["stack"]
          |> Ezjsonm.get_list (fun s ->
              Ezjsonm.find s ["item"] |> LiquidToMicheline.const_of_ezjson,
              try Some (Ezjsonm.find s ["annot"] |> Ezjsonm.get_string)
              with Not_found -> None
            )
        in
        (loc, gas, stack)
      ) trace_r
  in
  (* Workaround bud in current betanet *)
  let trace_expr = match trace_expr with
    | (loc1, _, _) :: (loc2, _, _) :: _ when loc2 < loc1 -> List.rev trace_expr
    | _ -> trace_expr in
  let trace_expr = match List.rev trace_expr with
    | ((loc, gas, _) :: _) as rtrace_expr when error ->
      let extra = (loc + 1, gas, []) in
      List.rev (extra :: rtrace_expr)
    | _ -> trace_expr in
  let l =
    List.map (fun (loc, gas, stack) ->
        let loc =  match List.assoc_opt loc loc_table with
          | Some (loc, _) -> Some loc
          | None -> None
        in
        (* we don't know the liquidity type of elements in the stack *)
        let stack = convert_stack env stack in
        { loc; gas; stack }
      ) trace_expr in
  reset_memo_stack_code ();
  Array.of_list l

let loc_table_to_map loc_table =
  List.fold_left (fun m (pos, (loc, _)) ->
      IntMap.add pos loc m
    ) IntMap.empty loc_table

let fail_msg_of_err loc ~loc_table err =
  let json = Ezjsonm.find err ["with"] in
  let err_loc, _ (* failwith_ty *) = List.assoc loc loc_table in
  let env = { (LiquidMichelineTypes.empty_env err_loc.loc_file)
              with loc_table = loc_table_to_map loc_table } in
  let failed_with_expr = LiquidToMicheline.const_of_ezjson json in
  let failed_with = convert_const env failed_with_expr in
  err_loc, Some (LiquidPrinter.Liquid.string_of_const failed_with)

let error_trace_of_err loc ~loc_table err =
  let err_loc, _ = List.assoc loc loc_table in
  try
    let json = Ezjsonm.find err ["trace"] in
    let env = { (LiquidMichelineTypes.empty_env err_loc.loc_file)
                with loc_table = loc_table_to_map loc_table } in
    let trace = trace_of_json env ~loc_table ~error:true json in
    err_loc, Some trace
  with Not_found -> err_loc, None

let raise_error_from_l ?loc_table err_msg l =
  let default_error () =
    let last_descr = match List.rev l with
      | (_, _, _, _, Some descr, _) :: _ -> "\n  " ^ descr
      | _ -> ""
    in
    let err_l =
      List.map (fun (kind, id, _, title, descr, _) ->
          match title with
          | Some t -> t
          | None -> Printf.sprintf "%s: %s" kind id
        ) l
      |> String.concat "\n- "
    in
    Printf.sprintf "in %s\n- %s%s" err_msg err_l last_descr
  in
  match loc_table with
  | None -> raise (ResponseError (default_error ()))
  | Some loc_table ->
    let err_msg = Printf.sprintf "in %s" err_msg in
    try
      List.iter (fun (kind, id, loc, title, descr, err) ->
          let is_rejected =
            match String.rindex_opt id '.' with
            | None -> false
            | Some i ->
              match String.sub id i (String.length id - i) with
              | ".script_rejected" | ".scriptRejectedRuntimeError" -> true
              | _ -> false
          in
          match loc, kind, is_rejected with
          | Some loc, "temporary", true ->
            let err_loc, fail_str = fail_msg_of_err loc ~loc_table err in
            let _, trace = error_trace_of_err loc ~loc_table err in
            raise (RuntimeFailure ({err_msg; err_loc}, fail_str, trace))
          | Some loc, "temporary", _ ->
            let title = match title with Some t -> t | None -> id in
            let err_msg = String.concat "\n- " [err_msg; title] in
            let err_loc, trace = error_trace_of_err loc ~loc_table err in
            raise (RuntimeError ({err_msg; err_loc}, trace))
          | Some loc, _, _ ->
            let err_loc, _ = List.assoc loc loc_table in
            let err_msg = default_error () in
            raise (LocalizedError {err_msg; err_loc})
          | _ -> ()
        ) l;
      raise (ResponseError (default_error ()))
    with Not_found -> raise (ResponseError (default_error ()))

let extract_errors_from_json r schema =
  try
    let schema_l = Ezjsonm.find schema ["oneOf"] in
    try
      Ezjsonm.find r ["error"], schema_l
    with Not_found ->
    match Ezjsonm.get_list (fun x -> x) r with
    | err :: _ ->
      begin try
          let r = Ezjsonm.find err ["ecoproto"] in
          let id = Ezjsonm.find err ["id"] |> Ezjsonm.get_string in
          let schema_l =
            schema_l
            |> Ezjsonm.get_list (fun s ->
                try
                  let s_id =
                    Ezjsonm.find s ["properties"; "id"; "enum"]
                    |> Ezjsonm.get_list Ezjsonm.get_string
                    |> function [s] -> s | _ -> assert false
                  in
                  if s_id <> id then
                    None
                  else
                    Some (Ezjsonm.find s
                            ["properties"; "ecoproto"; "items"; "oneOf"])
                with Not_found -> None
              )
            |> List.find (function None -> false | Some _ -> true)
            |> function None -> assert false | Some s -> s
          in
          r, schema_l
        with Not_found  -> r, schema_l
      end
    | [] -> raise (ResponseError ("Could not parse error"))
    | exception Ezjsonm.Parse_error _ -> r, schema_l
  with Not_found -> r, schema

let rec descr_of_id id schema =
  try
    schema
    |> Ezjsonm.get_list (fun s ->
        try
          let schema = Ezjsonm.find s ["oneOf"] in
          descr_of_id id schema
        with Not_found ->
        try
          let s_id =
            Ezjsonm.find s ["properties"; "id"; "enum"]
            |> Ezjsonm.get_list Ezjsonm.get_string
            |> function [s] -> s | _ -> assert false
          in
          if s_id <> id then
            None, None
          else (
            let t =
              try Some (Ezjsonm.find s ["title"] |> Ezjsonm.get_string)
              with Not_found -> None
            in
            let d =
              try Some (Ezjsonm.find s ["description"] |> Ezjsonm.get_string)
              with Not_found -> None
            in
            (t, d)
          )
        with Not_found ->
          None, None
      )
    |> List.find (function Some _, _ | _, Some _ -> true | _ -> false)
  with Not_found | Ezjsonm.Parse_error _ ->
    None, None

let raise_response_error ?loc_table msg r =
  Lazy.force error_schema >>= fun error_schema ->
  let err, schema = extract_errors_from_json r error_schema in
  let l =
    try
      Ezjsonm.get_list (fun err ->
          let kind = Ezjsonm.find err ["kind"] |> Ezjsonm.get_string in
          if kind = "generic" then begin
            let err = Ezjsonm.find err ["error"] |> Ezjsonm.get_string in
            raise (ResponseError err)
          end;
          let id = Ezjsonm.find err ["id"] |> Ezjsonm.get_string in
          let title, descr = descr_of_id id schema in
          let loc =
            try Some (Ezjsonm.find err ["location"] |> Ezjsonm.get_int)
            with Not_found ->
            try Some (Ezjsonm.find err ["loc"] |> Ezjsonm.get_int)
            with Not_found -> None
          in
          kind, id, loc, title, descr, err
        ) err
    with Ezjsonm.Parse_error _ -> []
  in
  raise_error_from_l ?loc_table msg l


let send_post ?loc_table ~data path =
  Lwt.catch
    (fun () -> !post ~data path)
    (function
      | RequestError (code, res) as exn ->
        begin try raise_response_error ?loc_table path (Ezjsonm.from_string res)
          with Ezjsonm.Parse_error _ | Not_found -> Lwt.fail exn
        end
      | exn -> Lwt.fail exn
    )

let send_get ?loc_table path =
  Lwt.catch
    (fun () -> !get path)
    (function
      | RequestError (code, res) as exn ->
        begin try raise_response_error ?loc_table path (Ezjsonm.from_string res)
          with Ezjsonm.Parse_error _ | Not_found -> Lwt.fail exn
        end
      | exn -> Lwt.fail exn
    )


let mk_json_obj fields =
  fields
  |> List.map (fun (f,v) -> "\"" ^ f ^ "\":" ^ v)
  |> String.concat ","
  |> fun fs -> "{" ^ fs ^ "}"

let mk_json_arr l = "[" ^ String.concat "," l ^ "]"


let compile_liquid liquid =
  let ocaml_asts = match liquid with
    | From_strings ss ->
      List.map (fun s ->
          "liquidity_buffer",
          LiquidFromParsetree.structure_of_string ~filename:"liquidity_buffer"
            s) ss
    | From_files files ->
      List.map (fun f -> f, LiquidFromParsetree.read_file f) files
  in
  let syntax_ast = LiquidFromParsetree.translate_multi ocaml_asts in
  let contract_sig = full_sig_of_contract syntax_ast in
  let typed_ast = LiquidCheck.typecheck_contract
      ~warnings:true ~decompiling:false syntax_ast in
  let encoded_ast, to_inline =
    LiquidEncode.encode_contract ~annot:true typed_ast in
  let live_ast = LiquidSimplify.simplify_contract encoded_ast to_inline in
  let pre_michelson = LiquidMichelson.translate live_ast in
  let pre_michelson =
    if !LiquidOptions.peephole then
      LiquidPeephole.simplify pre_michelson
    else
      pre_michelson
  in
  let pre_init = match live_ast.c_init with
    | None -> None
    | Some init ->
      let inputs_infos = init.init_args in
      Some (
        LiquidInit.compile_liquid_init live_ast.ty_env contract_sig init,
        inputs_infos)
  in
  ( syntax_ast, pre_michelson, pre_init )

let decompile_michelson code =
  let env = LiquidMichelineTypes.empty_env "mic_code" in
  let c = LiquidFromMicheline.convert_contract env code in
  let c = LiquidClean.clean_contract c in
  let c = LiquidInterp.interp c in
  let c = LiquidDecomp.decompile env c in
  let annoted_tz, type_annots, types = LiquidFromMicheline.infos_env env in
  let typed_ast = LiquidCheck.typecheck_contract ~warnings:false ~decompiling:true c in
  let encode_ast, to_inline =
    LiquidEncode.encode_contract ~decompiling:true typed_ast in
  let live_ast = LiquidSimplify.simplify_contract
      ~decompile_annoted:annoted_tz encode_ast to_inline in
  let multi_ast = LiquidDecode.decode_contract live_ast in
  let untyped_ast = LiquidUntype.untype_contract multi_ast in
  untyped_ast

let get_json_string s =
  try Scanf.sscanf s "%S" (fun x -> x)
  with _ -> raise Not_found

let get_json_int s =
  try Scanf.sscanf s "%d" (fun x -> x)
  with _ ->
  try Scanf.sscanf s "\"%d\"" (fun x -> x)
  with _ -> raise Not_found

let get_counter source =
  send_get
    (Printf.sprintf "/chains/main/blocks/head/context/contracts/%s/counter"
       source)
  >>= fun r ->
  try
    get_json_int r |> return
  with Not_found ->
    raise_response_error "get_counter" (Ezjsonm.from_string r)

let get_next_counter source =
  match !LiquidOptions.counter with
  | None ->
    get_counter source >>= fun counter ->
    return (counter+1)
  | Some counter -> return counter

let get_head_hash () =
  send_get "/chains/main/blocks/head/header" >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    Ezjsonm.find r ["hash"] |> Ezjsonm.get_string |> return
  with Not_found ->
    raise_response_error "get_head_hash" r

type head = {
  head_hash : string;
  head_chain_id : string;
}

let get_head () =
  send_get "/chains/main/blocks/head" >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    let head_hash = Ezjsonm.find r ["hash"] |> Ezjsonm.get_string in
    let head_chain_id = Ezjsonm.find r ["chain_id"] |> Ezjsonm.get_string in
    return { head_hash; head_chain_id }
  with Not_found ->
    raise_response_error "get_head" r

let get_manager_key source =
  send_get
    (Printf.sprintf "/chains/main/blocks/head/context/contracts/%s/manager_key"
       source)
  >>= fun r ->
  try
    try
      let r = Ezjsonm.from_string r in
      Ezjsonm.find r ["key"]
      |> Ezjsonm.get_string
      |> return
    with _->
      get_json_string r |> return
  with Not_found ->
    raise_response_error "get_manager_key" (Ezjsonm.from_string r)

let get_manager source =
  send_get
    (Printf.sprintf "/chains/main/blocks/head/context/contracts/%s/manager"
       source)
  >>= fun r ->
  try
    get_json_string r |> return
  with Not_found ->
    raise_response_error "get_manager" (Ezjsonm.from_string r)

type constants = {
  hard_gas_limit_per_operation : int;
  hard_storage_limit_per_operation : int;
}

let get_constants () =
  send_get "/chains/main/blocks/head/context/constants" >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    {
      hard_gas_limit_per_operation =
        Ezjsonm.find r ["hard_gas_limit_per_operation"]
        |> Ezjsonm.get_string
        |> int_of_string;
      hard_storage_limit_per_operation =
        Ezjsonm.find r ["hard_storage_limit_per_operation"]
        |> Ezjsonm.get_string
        |> int_of_string;
    }
    |> return
  with Not_found ->
    raise_response_error "get_constants" r

let get_predecessor () =
  send_get "/chains/main/blocks/head/header" >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    Ezjsonm.find r ["predecessor"] |> Ezjsonm.get_string |> return
  with Not_found ->
    raise_response_error "get_predecessor" r

let get_protocol () =
  send_get "/chains/main/blocks/head/header" >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    Ezjsonm.find r ["protocol"] |> Ezjsonm.get_string |> return
  with Not_found ->
    raise_response_error "get_protocol" r

let operation_of_json ~head r =
  let env = LiquidMichelineTypes.empty_env "operation" in
  let source = Ezjsonm.(find r ["source"] |> get_string) in
  let nonce = Ezjsonm.(find r ["nonce"] |> get_int) in
  let kind = Ezjsonm.(find r ["kind"] |> get_string) in
  let op = match kind with
    | "reveal" -> Reveal Ezjsonm.(find r ["public_key"] |> get_string)
    | "transaction" ->
      let open Ezjsonm in
      Transaction {
        amount = find r ["amount"] |> get_string;
        destination = find r ["destination"] |> get_string;
        entrypoint =
          (try find r ["parameters"; "entrypoint"]
            |> Ezjsonm.get_string
          with Not_found -> "default");
        parameters =
          try find r ["parameters"; "value"]
              |> LiquidToMicheline.const_of_ezjson
              |> convert_const env
              |> Option.some
          with Not_found -> None;
      }
    | "origination" ->
      let open Ezjsonm in
      let script =
        try
          let code =
            find r ["script"; "code"]
            |> LiquidToMicheline.contract_of_ezjson
            |> decompile_michelson in
          let storage =
            find r ["script"; "storage"]
            |> LiquidToMicheline.const_of_ezjson
            |> (fun e -> convert_const env e ~ty:code.storage)
          in
          Some (code, storage)
        with Not_found -> None in
      Origination {
        script;
        balance = find r ["balance"] |> get_string;
        delegate =
          Option.try_with (fun () -> find r ["delegate"] |> get_string);
      }
    | "delegation" ->
      Delegation Ezjsonm.(
          Option.try_with (fun () -> find r ["delegate"] |> get_string);
        )
    | _ -> failwith kind in
  { source; nonce; op }

let decode_big_map_diff_item json =
  let get_id m json =
    Ezjsonm.find json [m] |> Ezjsonm.get_string |> int_of_string in
  match Ezjsonm.find json ["action"] |> Ezjsonm.get_string with
  | "update" ->
    let id = get_id "big_map" json in
    let key_hash = Ezjsonm.find json ["key_hash"] |> Ezjsonm.get_string in
    let key = Ezjsonm.find json ["key"] |> LiquidToMicheline.const_of_ezjson in
    let value =
      try Some (Ezjsonm.find json ["value"] |> LiquidToMicheline.const_of_ezjson)
      with Not_found -> None in
    (match value with
     | Some value -> Big_map_add { id; key_hash; key; value }
     | None -> Big_map_remove { id; key_hash; key }
    )
  | "remove" ->
    let id = get_id "big_map" json in
    Big_map_delete { id }
  | "alloc" ->
    let id = get_id "big_map" json in
    Big_map_alloc { id }
  | "copy" ->
    let source_id = get_id "source_big_map" json in
    let destination_id = get_id "destination_big_map" json in
    Big_map_copy { source_id; destination_id }
  | a -> failwith ("unknown action in big map diff : " ^ a)

let decode_big_map json = Ezjsonm.get_list decode_big_map_diff_item json

let rec list_big_maps name acc storage storage_ty =
  match storage, storage_ty with
  | CBigMap BMId i, Tbigmap (k, v) ->
    let id = LiquidNumber.int_of_integer i in
    let id = match name with
     | Some name -> Bm_name (id, name)
     | None -> Bm_id id in
    (id, k, v) :: acc
  | ( CUnit
    | CBool _
    | CInt _
    | CNat _
    | CTez _
    | CTimestamp _
    | CString _
    | CBytes _
    | CKey _
    | CNone
    | CSignature _
    | CKey_hash _
    | CAddress _
    | CLambda _), _ -> acc
  | CTuple l, Ttuple tys ->
    List.fold_left2 (list_big_maps name) acc l tys
  | CSome c, Toption ty
  | CLeft c, Tor (ty, _)
  | CRight c, Tor (_, ty) ->
    list_big_maps name acc c ty
  | CMap l, Tmap (tk, tv) ->
    List.fold_left (fun acc (k, v) ->
        let acc = list_big_maps name acc k tk in
        list_big_maps name acc v tv
      ) acc l
  | CList l, Tlist ty
  | CSet l, Tset ty ->
    List.fold_left (fun acc c -> list_big_maps name acc c ty) acc l
  | CRecord l, Trecord (_, tys) ->
    List.fold_left2 (fun acc (field, c) (_, ty) ->
        let name = match name with
          | None -> Some field
          | Some name -> Some (String.concat "." [name; field]) in
        list_big_maps name acc c ty
      ) acc l tys
  | CConstr (n, c), Tsum (_, tys) ->
    List.fold_left (fun acc (c_name, ty) ->
          if c_name <> n then acc
          else
            let name = match name with
              | None -> Some c_name
              | Some name -> Some (String.concat "." [name; c_name]) in
            list_big_maps name acc c ty
      ) acc tys
  | _, _ -> acc

let list_big_maps storage storage_ty =
  list_big_maps None [] storage storage_ty

let big_map_info storage storage_ty id =
  list_big_maps storage storage_ty
  |> List.find_opt (fun ((Bm_id i | Bm_name (i, _)), _, _) -> i = id)

let id_of_info id info = match info with
  | None -> Bm_id id
  | Some (id, _, _) -> id

let convert_big_map_diff_item env storage storage_ty = function
  | Big_map_add { id; key_hash; key; value } ->
    let info = big_map_info storage storage_ty id in
    let id = id_of_info id info in
    let key, value = match info with
      | None ->
        convert_const env key,
        convert_const env value
      | Some (_, tk, tv) ->
        convert_const env key ~ty:tk,
        convert_const env value ~ty:tv in
    Big_map_add { id; key_hash; key; value }
  | Big_map_remove { id; key_hash; key } ->
    let info = big_map_info storage storage_ty id in
    let id = id_of_info id info in
    let key = match info with
      | None -> convert_const env key
      | Some (_, tk, _) -> convert_const env key ~ty:tk in
    Big_map_remove { id; key_hash; key }
  | Big_map_delete { id } ->
    let info = big_map_info storage storage_ty id in
    let id = id_of_info id info in
    Big_map_delete { id }
  | Big_map_alloc { id } ->
    let info = big_map_info storage storage_ty id in
    let id = id_of_info id info in
    Big_map_alloc { id }
  | Big_map_copy { source_id; destination_id } ->
    let source_info = big_map_info storage storage_ty source_id in
    let source_id = id_of_info source_id source_info in
    let destination_info = big_map_info storage storage_ty destination_id in
    let destination_id = id_of_info destination_id destination_info in
    Big_map_copy { source_id; destination_id }

let convert_big_map_diff env storage storage_ty l =
  List.map (convert_big_map_diff_item env storage storage_ty) l

let decode_convert_big_map_diff env storage storage_ty json_opt =
  match json_opt with
  | None -> []
  | Some json ->
    decode_big_map json
    |> convert_big_map_diff env storage storage_ty

let run_pre ?(debug=false)
    contract pre_michelson source entry_name input storage =
  let rpc = if debug then "trace_code" else "run_code" in
  let env = contract.ty_env in
  let storage_ty = contract.storage in
  let c, loc_table =
    LiquidToMicheline.convert_contract ~expand:true pre_michelson in
  let input_m = LiquidMichelson.compile_const input in
  let input_t = LiquidToMicheline.convert_const ~expand:true input_m in
  let storage_m = LiquidMichelson.compile_const storage in
  let storage_t = LiquidToMicheline.convert_const ~expand:true storage_m in
  let contract_json = LiquidToMicheline.json_of_contract c in
  let input_json = LiquidToMicheline.json_of_const input_t in
  let storage_json = LiquidToMicheline.json_of_const storage_t in
  get_head () >>= fun head ->
  let run_fields = [
    "script", contract_json;
    "entrypoint", Printf.sprintf "%S" entry_name;
    "input", input_json;
    "storage", storage_json;
    "amount", Printf.sprintf "%S" !LiquidOptions.amount;
    "chain_id", Printf.sprintf "%S" head.head_chain_id;
  ] @ (match source with
      | None -> []
      | Some source -> [ "source", Printf.sprintf "%S" source ]
    ) in
  let run_json = mk_json_obj run_fields in
  send_post ~loc_table ~data:run_json
    (Printf.sprintf "/chains/main/blocks/head/helpers/scripts/%s" rpc)
  >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    let storage_r = Ezjsonm.find r ["storage"] in
    let operations_r = Ezjsonm.find r ["operations"] in
    let operations = Ezjsonm.get_list (operation_of_json ~head) operations_r in
    let big_map_diff_r =
      try Some (Ezjsonm.find r ["big_map_diff"])
      with Not_found -> None
    in
    let trace_r =
      if not debug then None
      else Some (Ezjsonm.find r ["trace"])
    in
    let storage_expr = LiquidToMicheline.const_of_ezjson storage_r in
    let env = LiquidMichelineTypes.empty_env env.filename in
    let storage = convert_const env storage_expr ~ty:storage_ty in
    let big_map_diff = decode_convert_big_map_diff env storage storage_ty big_map_diff_r in
    (* TODO parse returned operations *)
    let trace = match trace_r with
      | None -> None
      | Some trace_r -> Some (trace_of_json env ~loc_table trace_r)
    in
    return (operations, storage, big_map_diff, trace)
  with Not_found ->
    raise_response_error ~loc_table "run" r


let run ~debug liquid entry_name input_string storage_string =
  let contract , pre_michelson, _ = compile_liquid liquid in
  let entry =
    try
      List.find (fun e -> e.entry_sig.entry_name = entry_name) contract.entries
    with Not_found ->
      invalid_arg @@ "Contract has no entry point " ^ entry_name
  in
  let contract_sig = full_sig_of_contract contract in
  let parameter =
    LiquidData.translate { contract.ty_env with filename = "run_input" }
      contract_sig input_string entry.entry_sig.parameter
  in
  let storage =
    LiquidData.translate { contract.ty_env with filename = "run_storage" }
      contract_sig storage_string contract.storage
  in
  run_pre ~debug contract
    pre_michelson !LiquidOptions.source entry_name parameter storage

let run_debug liquid entry_name input_string storage_string =
  run ~debug:true liquid entry_name input_string storage_string
  >>= function
  | (nbops, sto, big_diff, Some trace) ->
    Lwt.return (nbops, sto, big_diff, trace)
  | _ -> assert false

let run liquid entry_name input_string storage_string =
  run ~debug:false liquid entry_name input_string storage_string
  >>= fun (nbops, sto, big_diff, _) ->
  Lwt.return (nbops, sto, big_diff)

let get_storage liquid address =
  let syntax_ast, _, _ = compile_liquid liquid in
  send_get
    (Printf.sprintf
       "/chains/main/blocks/head/context/contracts/%s/storage"
       address)
  >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    let storage_expr = LiquidToMicheline.const_of_ezjson r in
    let env = LiquidMichelineTypes.empty_env syntax_ast.ty_env.filename in
    return
      (try convert_const env storage_expr ~ty:syntax_ast.storage
       with LiquidTypes.LiquidError _ ->
         Format.eprintf "Could not convert constant to contract storage type.@.";
         convert_const env storage_expr)
  with Not_found ->
    raise_response_error "get_storage" r

let get_big_map_value liquid big_map_info key =
  let contract , pre_michelson, _ = compile_liquid liquid in
  let contract_sig = full_sig_of_contract contract in
  let ((Bm_id id | Bm_name (id, _)), key_ty, val_ty) = big_map_info in
  let key =
    LiquidData.translate { contract.ty_env with filename = "big_map_key" }
      contract_sig key key_ty
  in
  let key_m = LiquidMichelson.compile_const key in
  let key_t = LiquidToMicheline.convert_const ~expand:true key_m in
  let key_json = LiquidToMicheline.json_of_const key_t in
  let key_ty_t = LiquidToMicheline.convert_type key_ty in
  let key_ty_json = LiquidToMicheline.json_of_const key_ty_t in

  let data_fields = [
    "data", key_json;
    "type", key_ty_json;
  ] in
  let data = mk_json_obj data_fields in
  send_post ~data "/chains/main/blocks/head/helpers/scripts/pack_data"
  >>= fun r ->
  let r = Ezjsonm.from_string r in
  let packed_key_hex = Ezjsonm.find r ["packed"] |> Ezjsonm.get_string in
  let packed_key = Hex.to_bytes (`Hex packed_key_hex) in
  let hash_key_b58 =
    ExprHash.hash_bytes [Bigstring.of_bytes packed_key]
    |> ExprHash.to_b58check in
  send_get (Printf.sprintf "/chains/main/blocks/head/context/big_maps/%d/%s"
              id hash_key_b58)
  >>= function
  | "null\n" | "null" -> return_none
  | r ->
    let r = Ezjsonm.from_string r in
    try
      let expr = LiquidToMicheline.const_of_ezjson r in
      let env = LiquidMichelineTypes.empty_env "big_map_value" in
      return_some
        (try convert_const env expr ~ty:val_ty
         with LiquidTypes.LiquidError _ ->
           Format.eprintf "Could not convert constant to value type.@.";
           convert_const env expr)
    with Not_found ->
      raise_response_error "get_big_map_value" r

let is_revealed source =
  send_get
    (Printf.sprintf
       "/chains/main/blocks/head/context/contracts/%s/manager_key"
       source)
  >>= function
  | "null\n" | "null" -> return false
  | r ->
    try
      let r = Ezjsonm.from_string r in
      try
        ignore (Ezjsonm.find r ["key"]);
        return true
      with Not_found ->
        return false
    with _ ->
      ignore (get_json_string r);
      return true


let get_public_key_hash_from_secret_key sk =
  let pk = Sodium.Sign.secret_key_to_public_key sk in
  match !LiquidOptions.network with
  | Tezos_network ->
    pk
    |> Ed25519.Public_key_hash_tezos.of_public_key
    |> Ed25519.Public_key_hash_tezos.to_b58check
  | Dune_network ->
    pk
    |> Ed25519.Public_key_hash_dune.of_public_key
    |> Ed25519.Public_key_hash_dune.to_b58check

let get_public_key_from_secret_key sk =
  sk
  |> Sodium.Sign.secret_key_to_public_key
  (* Replace by this when tezos is fixed *)
  (* |> Ed25519.Secret_key.to_public_key *)
  |> Ed25519.Public_key.to_b58check

let big_map_elements id big_map_diff =
  List.fold_left (fun acc -> function
      | Big_map_add { id = (Bm_id i | Bm_name (i, _)); key; value } when id = i ->
        (key, value) :: acc
      | _ -> acc
    ) [] big_map_diff |> List.rev

let rec replace_init_big_maps big_map_diff storage =
  let replace = replace_init_big_maps big_map_diff in
  match storage with
  | CBigMap BMId id ->
    CBigMap (BMList (big_map_elements (LiquidNumber.int_of_integer id) big_map_diff))
  | ( CBigMap BMList _
    | CUnit
    | CBool _
    | CInt _
    | CNat _
    | CTez _
    | CTimestamp _
    | CString _
    | CBytes _
    | CKey _
    | CNone
    | CSignature _
    | CKey_hash _
    | CAddress _
    | CLambda _) as c -> c
  | CTuple l -> CTuple (List.map replace l)
  | CSome c -> CSome (replace c)
  | CLeft c -> CLeft (replace c)
  | CRight c -> CRight (replace c)
  | CMap l -> CMap (List.map (fun (k, v) -> replace k, replace v) l)
  | CList l -> CList (List.map replace l)
  | CSet l -> CSet (List.map replace l)
  | CRecord l -> CRecord (List.map (fun (f, v) -> f, replace v) l)
  | CConstr (n, c) -> CConstr (n, replace c)


let init_storage ?source liquid init_params_strings =
  let source = match source with
    | Some _ -> source
    | None -> !LiquidOptions.source
  in
  let syntax_ast, pre_michelson, pre_init_infos = compile_liquid liquid in
  let contract_sig = full_sig_of_contract syntax_ast in
  let pre_init, init_infos = match pre_init_infos with
    | None -> raise (ResponseError "init_storage: Missing init")
    | Some pre_init_infos -> pre_init_infos
  in
  match pre_init with
  | LiquidInit.Init_constant c ->
    if init_params_strings <> [] then
      raise (ResponseError "init_storage: Constant storage, no inputs needed");
    return c
  | LiquidInit.Init_code (syntax_c, c) ->
    let init_params =
      try
        List.map2 (fun input_str (input_name,_, input_ty) ->
            LiquidData.translate { syntax_ast.ty_env with filename = input_name }
              contract_sig input_str input_ty
          ) init_params_strings init_infos
      with Invalid_argument _ ->
        raise
          (ResponseError
             (Printf.sprintf
                "init_storage: init storage needs %d arguments, but was given %d"
                (List.length init_infos) (List.length init_params_strings)
             ))
    in
    let eval_input_storage =
      try
        LiquidData.default_empty_const syntax_ast.storage
      with Not_found -> failwith "could not construct dummy storage for eval"
    in
    let eval_input_parameter = match init_params with
      | [] -> CUnit
      | [x] -> x
      | _ -> CTuple init_params
    in

    run_pre syntax_ast c source "default"
      eval_input_parameter eval_input_storage
    >>= fun (_, eval_init_storage, big_map_diff, _) ->
    (* Add elements of big map *)
    let eval_init_storage = replace_init_big_maps big_map_diff eval_init_storage in
    if !LiquidOptions.verbosity > 0 then
      Printf.eprintf "Evaluated initial storage: %s\n%!"
        (LiquidPrinter.Liquid.string_of_const eval_init_storage);
    return (LiquidEncode.encode_const
              syntax_ast.ty_env contract_sig eval_init_storage)

let dummy_sign = "edsigtXomBKi5CTRf5cjATJWSyaRvhfYNHqSUGrn4SdbYRcGwQ\
                  rUGjzEfQDTuqHhuA8b2d8NarZjz8TRf65WkpQmo423BtomS8Q"

let minimal_fees = Z.of_int 100
let nanotez_per_gas_unit = Z.of_int 100
let nanotez_per_byte = Z.of_int 1000
let to_nanotez m = Z.mul (Z.of_int 1000) m
let of_nanotez n = Z.div (Z.add (Z.of_int 999) n) (Z.of_int 1000)

let compute_fees ~gas_limit ~size =
  let minimal_fees_in_nanotez = to_nanotez minimal_fees in
  let fees_for_gas_in_nanotez =
    Z.mul nanotez_per_gas_unit (Z.of_int gas_limit) in
  let fees_for_size_in_nanotez = Z.mul nanotez_per_byte (Z.of_int size) in
  let fees_in_nanotez =
    Z.add minimal_fees_in_nanotez @@
    Z.add fees_for_gas_in_nanotez fees_for_size_in_nanotez in
  of_nanotez fees_in_nanotez

let compute_gas_limit ~fee ~size =
  let minimal_fees_in_nanotez = to_nanotez minimal_fees in
  let fees_for_size_in_nanotez = Z.mul nanotez_per_byte (Z.of_int size) in
  let fee_in_nanotez = to_nanotez fee in
  let fees_for_gas_in_nanotez =
    Z.sub fee_in_nanotez @@
    Z.add minimal_fees_in_nanotez fees_for_size_in_nanotez in
  Z.div fees_for_gas_in_nanotez nanotez_per_gas_unit
  |> Z.to_int
  |> max 0

let estimate_gas_storage ~loc_table ?head data =
  begin match head with
    | Some head -> return head
    | None -> get_head ()
  end >>= fun head ->
  let data = ([
      "operation", data;
      "chain_id", Printf.sprintf "%S" head.head_chain_id;
    ]) |> mk_json_obj in
  send_post ~loc_table ~data
    "/chains/main/blocks/head/helpers/scripts/run_operation"
  >>= fun r ->
  let r = Ezjsonm.from_string r in
  let contents =
    Ezjsonm.find r ["contents"] |> Ezjsonm.get_list (fun o -> o) in
  let res = match contents with
    | [ x (* reveal *) ; y ] ->
      assert (Ezjsonm.find x ["kind"] |> Ezjsonm.get_string = "reveal");
      y
    | [ y ] -> y
    | _ -> invalid_arg "estimate_gas_storage" in
  let result = Ezjsonm.find res ["metadata"; "operation_result" ] in
  let status =
    Ezjsonm.find result ["status"] |> Ezjsonm.get_string in
  match status with
  | "failed" ->
    let errors =
      try Ezjsonm.find result ["errors"]
      with Not_found -> `A [] in
    raise_response_error ~loc_table status errors
  | "applied" ->
    let consumed_gas =
      try Ezjsonm.find result ["consumed_gas"]
          |> Ezjsonm.get_string |> int_of_string (* |> (+) 100 *)
      with Not_found -> 0 in
    let consumed_storage =
      try Ezjsonm.find result ["paid_storage_size_diff"]
          |> Ezjsonm.get_string |> int_of_string (* |> (+) 10 *)
      with Not_found -> 0 in
    let allocated_dest =
      try Ezjsonm.find result ["allocated_destination_contract"]
          |> Ezjsonm.get_bool
      with Not_found -> false in
    let nb_originated =
      try Ezjsonm.find result ["originated_contracts"]
          |> Ezjsonm.get_list (fun _ -> ()) |> List.length
      with Not_found -> 0 in
    let allocated = nb_originated + if allocated_dest then 1 else 0 in
    let consumed_storage = allocated * 257 + consumed_storage in
    let internal_ops =
      try
        Ezjsonm.find res ["metadata"; "internal_operation_results" ]
        |> Ezjsonm.get_list (fun o -> o)
      with Not_found -> [] in
    let consumed_gas, consumed_storage =
      List.fold_left (fun (gas, storage) op ->
        let result =  Ezjsonm.find op ["result"] in
        let consumed_gas =
          try Ezjsonm.find result ["consumed_gas"]
              |> Ezjsonm.get_string |> int_of_string
          with Not_found -> 0 in
        let consumed_storage =
          try Ezjsonm.find result ["paid_storage_size_diff"]
              |> Ezjsonm.get_string |> int_of_string
          with Not_found -> 0 in
        (gas + consumed_gas, storage + consumed_storage)
      ) (consumed_gas, consumed_storage) internal_ops in
    Format.printf "gas limit: %d\nstorage limit: %d@." consumed_gas consumed_storage;
    return (consumed_gas, consumed_storage)
  | _ -> failwith status

let forge_deploy_script ~source liquid init_params_strings =
  let syntax_ast, pre_michelson, _ = compile_liquid liquid in
  init_storage ~source liquid init_params_strings >>= fun init_storage ->
  let c, loc_table =
    LiquidToMicheline.convert_contract ~expand:true pre_michelson in
  let init_storage_m = LiquidMichelson.compile_const init_storage in
  let init_storage_t =
    LiquidToMicheline.convert_const ~expand:true init_storage_m in
  let contract_json = LiquidToMicheline.json_of_contract c in
  let init_storage_json = LiquidToMicheline.json_of_const init_storage_t in
  return (contract_json, init_storage_json, loc_table)

let rec forge_deploy_json ?head ?source ?public_key
    ?fee ?gas_limit ?storage_limit ?real_op_size
    liquid init_params_strings =
  let source = match source, !LiquidOptions.source with
    | Some source, _ | _, Some source -> source
    | None, None -> raise (ResponseError "forge_deploy: Missing source")
  in
  forge_deploy_script ~source liquid init_params_strings
  >>= fun (contract_json, init_storage_json, loc_table) ->
  let script_json = [
    "code", contract_json;
    "storage", init_storage_json
  ] |> mk_json_obj
  in
  begin match head with
    | Some head -> return head
    | None -> get_head ()
  end >>= fun head ->
  get_constants ()
  >>= fun { hard_gas_limit_per_operation; hard_storage_limit_per_operation } ->
  get_next_counter source >>= fun counter ->
  is_revealed source >>= fun source_revealed ->
  let storage_limit = match storage_limit with
    | Some l -> l
    | None -> hard_storage_limit_per_operation in
  let gas_limit = match gas_limit with
    | Some l -> l
    | None -> hard_gas_limit_per_operation in
  let computed_fee = match real_op_size with
    | None -> Z.zero
    | Some size ->
      let gas_limit =
        if source_revealed then gas_limit else gas_limit + 10000 in
      compute_fees ~gas_limit ~size
  in
  let computed_fee = match fee with
    | None -> Z.to_string computed_fee
    | Some fee when Z.compare (Z.of_string fee) computed_fee < 0 ->
      Format.kasprintf failwith
        "Fee too low, operation would never be included: given %s, but required \
         at least %s in fee."
        LiquidNumber.(liq_of_tez @@ tez_of_mic_mutez (Z.of_string fee))
        LiquidNumber.(liq_of_tez @@ tez_of_mic_mutez computed_fee)
    | Some fee -> fee in
  let origination_json counter = [
    "kind", "\"origination\"";
    "source", Printf.sprintf "%S" source;
    "fee", Printf.sprintf "%S" computed_fee;
    "counter", Printf.sprintf "\"%d\"" counter;
    "gas_limit", Printf.sprintf "\"%d\"" gas_limit;
    "storage_limit", Printf.sprintf "\"%d\"" storage_limit;
    "balance", Printf.sprintf "%S" !LiquidOptions.amount;
    "script", script_json;
  ] |> mk_json_obj
  in
  let operations = match source_revealed, public_key with
    | true, _ -> [origination_json counter]
    | false, None -> failwith "Missing public key for revelation"
    | false, Some edpk ->
      let reveal_json = [
        "kind", "\"reveal\"";
        "source", Printf.sprintf "%S" source;
        "fee", "\"0\"";
        "counter", Printf.sprintf "\"%d\"" counter;
        "gas_limit", "\"10000\"";
        "storage_limit", "\"0\"";
        "public_key", Printf.sprintf "%S" edpk;
      ] |> mk_json_obj
      in
      [reveal_json; origination_json (counter + 1)]
  in
  let operations_json = mk_json_arr operations in
  let data = ([
      "branch", Printf.sprintf "%S" head.head_hash;
      "contents", operations_json;
    ] @ if real_op_size = None then
        ["signature", Printf.sprintf "%S" dummy_sign ]
      else
        []
    ) |> mk_json_obj
  in
  match real_op_size with
  | None ->
    return (data, operations_json, loc_table)
  | Some size ->
    send_post ~loc_table ~data
      "/chains/main/blocks/head/helpers/forge/operations"
    >>= fun r ->
    let op = get_json_string r in
    let actual_size = String.length op / 2 + 64 in
    if actual_size <= size then begin
      Format.printf "computed fee %s@." computed_fee;
      return (data, operations_json, loc_table)
    end else
      (* Fix point to estimate size of operation which depends on fees
         which depends on size of operation *rolleyes* *)
      forge_deploy_json ~head ~source ?public_key ~real_op_size:actual_size
        ?fee ~gas_limit ~storage_limit
        liquid init_params_strings


let forge_deploy ?head ?source ?public_key
    liquid init_params_strings =
  forge_deploy_json ?head ?source ?public_key
    liquid init_params_strings >>= fun (data, _, loc_table) ->
  estimate_gas_storage ~loc_table ?head data >>= fun (est_gas_limit, est_storage_limit) ->
  let gas_limit = match !LiquidOptions.gas_limit with
    | None -> est_gas_limit
    | Some l -> l in
  let storage_limit = match !LiquidOptions.storage_limit with
    | None -> est_storage_limit
    | Some l -> l in
  forge_deploy_json ?head ?source ?public_key ~real_op_size:0
    ?fee:!LiquidOptions.fee ~gas_limit ~storage_limit
    liquid init_params_strings
  >>= fun (data, operations_json, loc_table) ->
  send_post ~loc_table ~data
    "/chains/main/blocks/head/helpers/forge/operations"
  >>= fun r ->
  try
    let op = get_json_string r in
    return (op, operations_json, loc_table)
  with Not_found ->
    raise_response_error ~loc_table "forge_deploy" (Ezjsonm.from_string r)

let hash msg =
  Blake2B.(to_bytes (hash_bytes [MBytes.of_string "\x03"; msg]))

let sign sk op_b =
  Ed25519.sign sk (hash op_b)

let inject_operation ?(force=false) ?loc_table ?sk ~head json_op op =
  let op_b = MBytes.of_string (Hex.to_string op) in
  get_protocol () >>= fun protocol ->
  let signed_op, op_hash, data = match sk with
    | None ->
      let op_hash =
        Operation_hash.to_b58check @@
        Operation_hash.hash_bytes [ op_b ] in
      op, op_hash, [[
          "protocol", Printf.sprintf "%S" protocol;
          "branch", Printf.sprintf "%S" head.head_hash;
          "contents", json_op;
        ] |> mk_json_obj] |> mk_json_arr

    | Some sk ->
      let signature_b = sign sk op_b in
      let signature = Ed25519.Signature.to_b58check signature_b in
      let signed_op_b = MBytes.concat "" [op_b; signature_b] in
      let signed_op = Hex.of_string (MBytes.to_string signed_op_b) in
      let op_hash =
        Operation_hash.to_b58check @@
        Operation_hash.hash_bytes [ signed_op_b ] in
      signed_op, op_hash, [[
          "protocol", Printf.sprintf "%S" protocol;
          "branch", Printf.sprintf "%S" head.head_hash;
          "contents", json_op;
          "signature", Printf.sprintf "%S" signature;
        ] |> mk_json_obj] |> mk_json_arr
  in
  send_post ?loc_table ~data
    "/chains/main/blocks/head/helpers/preapply/operations"
  >>= fun r ->
  let r = Ezjsonm.from_string r in
  (try
     let r =
       match Ezjsonm.get_list (fun x -> x) r with
       | r :: _ -> r | [] -> assert false in
     let contents =
       Ezjsonm.find r ["contents"] |> Ezjsonm.get_list (fun o -> o) in
     Lwt_list.map_p (fun o ->
         try
           match Ezjsonm.(find o ["kind"] |> get_string) with
           | "activate_account" -> return_ok []
           | _ ->
             let result = Ezjsonm.find o ["metadata"; "operation_result" ] in
             let status =
               Ezjsonm.find result ["status"] |> Ezjsonm.get_string in
             match status with
             | "failed" ->
               let errors =
                 try Ezjsonm.find result ["errors"]
                 with Not_found -> `A [] in
               begin try
                   raise_response_error ?loc_table status errors
                 with exn -> return_error exn
               end
             | "backtracked" | "skipped" ->
               return_error (Failure status)
             | "applied" ->
               let contracts =
                 try
                   Ezjsonm.find result ["originated_contracts"]
                   |> Ezjsonm.get_list Ezjsonm.get_string
                 with Not_found -> [] in
               return_ok contracts
             | _ -> return_error (Failure status)
         with Not_found -> return_error (Failure "operation_result")
       ) contents
   with Not_found ->
     raise_response_error ?loc_table "inject (preapply/operations)" r
  ) >>= fun result ->
  if not force then
    (* Don't inject if there is an error *)
    List.iter (function
        | Error exn -> raise exn
        | Ok _ -> ()) result;
  let data = Printf.sprintf "%S" (Hex.show signed_op) in
  send_post ?loc_table ~data "/injection/operation" >>= fun r ->
  (try
     get_json_string r |> return
   with Not_found ->
     raise_response_error ?loc_table "inject (/injection/operation)"
       (Ezjsonm.from_string r)
  ) >>= fun injected_op_hash ->
  assert (injected_op_hash = op_hash);
  return (injected_op_hash, result)


let deploy liquid init_params_strings =
  let sk = match !LiquidOptions.private_key with
    | None -> raise (ResponseError "deploy: Missing private key")
    | Some sk -> match Ed25519.Secret_key.of_b58check sk with
      | Ok sk -> sk
      | Error _ -> raise (ResponseError "deploy: Bad private key")
  in
  let source = match !LiquidOptions.source with
    | Some source -> source
    | None -> get_public_key_hash_from_secret_key sk
  in
  let public_key = get_public_key_from_secret_key sk in
  get_head () >>= fun head ->
  forge_deploy ~head ~source ~public_key
    liquid init_params_strings
  >>= fun (op, op_json, loc_table) ->
  inject_operation ~loc_table ~sk ~head op_json (`Hex op) >>= function
  | op_h, [Ok [c]] -> return (op_h, Ok c)
  | op_h, [Ok _; Ok [c]] -> return (op_h, Ok c) (* with revelation *)
  | op_h, (Error e :: _ | _ :: Error e :: _) -> return (op_h, Error e)
  | _ -> raise (ResponseError "deploy (inject)")

let forge_call_parameter liquid entry_name input_string =
  let contract, pre_michelson, pre_init_infos = compile_liquid liquid in
  let contract_sig = full_sig_of_contract contract in
  let entry =
    try
      List.find (fun e -> e.entry_sig.entry_name = entry_name) contract.entries
    with Not_found ->
      invalid_arg @@ "Contract has no entry point " ^ entry_name
  in
  let parameter =
    LiquidData.translate { contract.ty_env with filename = "call_parameter" }
      contract_sig input_string entry.entry_sig.parameter
  in
  let _, loc_table =
    LiquidToMicheline.convert_contract ~expand:true pre_michelson in
  let parameter_m = LiquidMichelson.compile_const parameter in
  let parameter_t = LiquidToMicheline.convert_const ~expand:true parameter_m in
  LiquidToMicheline.json_of_const parameter_t, loc_table

let rec forge_call_json ?head ?source ?public_key
    ?fee ?gas_limit ?storage_limit ?real_op_size
    liquid address entry_name input_string =
  let source = match source, !LiquidOptions.source with
    | Some source, _ | _, Some source -> source
    | None, None -> raise (ResponseError "forge_call: Missing source")
  in
  let arg_json, loc_table =
    forge_call_parameter liquid entry_name input_string in
  let parameter_json = [
    "entrypoint", Printf.sprintf "%S" entry_name;
    "value", arg_json
  ] |> mk_json_obj
  in
  begin match head with
    | Some head -> return head
    | None -> get_head ()
  end >>= fun head ->
  get_constants ()
  >>= fun { hard_gas_limit_per_operation; hard_storage_limit_per_operation } ->
  get_next_counter source >>= fun counter ->
  is_revealed source >>= fun source_revealed ->
  let storage_limit = match storage_limit with
    | Some l -> l
    | None -> hard_storage_limit_per_operation in
  let gas_limit = match gas_limit with
    | Some l -> l
    | None -> hard_gas_limit_per_operation in
  let computed_fee = match real_op_size with
    | None -> Z.zero
    | Some size ->
      let gas_limit =
        if source_revealed then gas_limit else gas_limit + 10000 in
      compute_fees ~gas_limit ~size
  in
  let computed_fee = match fee with
    | None -> Z.to_string computed_fee
    | Some fee when Z.compare (Z.of_string fee) computed_fee < 0 ->
      Format.kasprintf failwith
        "Fee too low, operation would never be included: given %s, but required \
         at least %s in fee."
        LiquidNumber.(liq_of_tez @@ tez_of_mic_mutez (Z.of_string fee))
        LiquidNumber.(liq_of_tez @@ tez_of_mic_mutez computed_fee)
    | Some fee -> fee in
  let transaction_json counter = [
    "kind", "\"transaction\"";
    "source", Printf.sprintf "%S" source;
    "fee", Printf.sprintf "%S" computed_fee;
    "counter", Printf.sprintf "\"%d\"" counter;
    "gas_limit", Printf.sprintf "\"%d\"" gas_limit;
    "storage_limit", Printf.sprintf "\"%d\"" storage_limit;
    "amount", Printf.sprintf "%S" !LiquidOptions.amount;
    "destination", Printf.sprintf "%S" address;
    "parameters", parameter_json;
  ] |> mk_json_obj
  in
  let operations = match source_revealed, public_key with
    | true, _ -> [transaction_json counter]
    | false, None -> failwith "Missing public key for revelation"
    | false, Some edpk ->
      let reveal_json = [
        "kind", "\"reveal\"";
        "source", Printf.sprintf "%S" source;
        "fee", "\"0\"";
        "counter", Printf.sprintf "\"%d\"" counter;
        "gas_limit", "\"10000\"";
        "storage_limit", "\"0\"";
        "public_key", Printf.sprintf "%S" edpk;
      ] |> mk_json_obj
      in
      [reveal_json; transaction_json (counter + 1)]
  in
  let operations_json = mk_json_arr operations in
  let data = ([
      "branch", Printf.sprintf "%S" head.head_hash;
      "contents", operations_json;
    ] @ if real_op_size = None then
        ["signature", Printf.sprintf "%S" dummy_sign ]
      else
        []
    ) |> mk_json_obj
  in
  match real_op_size with
  | None ->
    return (data, operations_json, loc_table)
  | Some size ->
    send_post ~loc_table ~data
      "/chains/main/blocks/head/helpers/forge/operations"
    >>= fun r ->
    let op = get_json_string r in
    let actual_size = String.length op / 2 + 64 in
    if actual_size <= size then begin
      Format.printf "computed fee %s@." computed_fee;
      return (data, operations_json, loc_table)
    end else
      (* Fix point to estimate size of operation which depends on fees
         which depends on size of operation *rolleyes* *)
      forge_call_json ~head ~source ?public_key ~real_op_size:actual_size
        ?fee ~gas_limit ~storage_limit
        liquid address entry_name input_string


let forge_call ?head ?source ?public_key
    liquid address entry_name input_string =
  forge_call_json ?head ?source ?public_key
    liquid address entry_name input_string >>= fun (data, _, loc_table) ->
  estimate_gas_storage ~loc_table ?head data >>= fun (est_gas_limit, est_storage_limit) ->
  let gas_limit = match !LiquidOptions.gas_limit with
    | None -> est_gas_limit
    | Some l -> l in
  let storage_limit = match !LiquidOptions.storage_limit with
    | None -> est_storage_limit
    | Some l -> l in
  forge_call_json ?head ?source ?public_key ~real_op_size:0
    ?fee:!LiquidOptions.fee ~gas_limit ~storage_limit
    liquid address entry_name input_string
  >>= fun (data, operations_json, loc_table) ->
  send_post ~loc_table ~data
    "/chains/main/blocks/head/helpers/forge/operations"
  >>= fun r ->
  try
    let op = get_json_string r in
    return (op, operations_json, loc_table)
  with Not_found ->
    raise_response_error ~loc_table "forge_call" (Ezjsonm.from_string r)

let call liquid address entry_name parameter_string =
  let sk = match !LiquidOptions.private_key with
    | None -> raise (ResponseError "call: Missing private key")
    | Some sk -> match Ed25519.Secret_key.of_b58check sk with
      | Ok sk -> sk
      | Error _ -> raise (ResponseError "call: Bad private key")
  in
  let source = match !LiquidOptions.source with
    | Some source -> source
    | None -> get_public_key_hash_from_secret_key sk
  in
  let public_key = get_public_key_from_secret_key sk in
  get_head () >>= fun head ->
  forge_call ~head ~source ~public_key
    liquid address entry_name parameter_string
  >>= fun (op, op_json, loc_table) ->
  inject_operation ~loc_table ~sk ~head op_json (`Hex op) >>= function
  | op_h, [Ok []] -> return (op_h, Ok ())
  | op_h, [Ok _; Ok []] -> return (op_h, Ok ()) (* with revelation *)
  | op_h, (Error e :: _ | _ :: Error e :: _) -> return (op_h, Error e)
  | _ -> raise (ResponseError "call (inject)")


let reveal sk =
  let source = get_public_key_hash_from_secret_key sk in
  let public_key = get_public_key_from_secret_key sk in
  get_head () >>= fun head ->
  get_next_counter source >>= fun counter ->
  let reveal_json = [
    "kind", "\"reveal\"";
    "source", Printf.sprintf "%S" source;
    "fee", "\"0\"";
    "counter", Printf.sprintf "\"%d\"" counter;
    "gas_limit", "\"10000\"";
    "storage_limit", "\"0\"";
    "public_key", Printf.sprintf "%S" public_key;
  ] |> mk_json_obj
  in
  let operations_json = mk_json_arr [reveal_json] in
  let data = [
    "branch", Printf.sprintf "%S" head.head_hash;
    "contents", operations_json;
  ] |> mk_json_obj
  in
  send_post ~data "/chains/main/blocks/head/helpers/forge/operations"
  >>= fun r ->
  (try
     get_json_string r |> return_some
   with Not_found ->
     return_none
  ) >>= function
  | Some op ->
    inject_operation ~sk ~head operations_json (`Hex op) >>= fun _ ->
    return_unit
  | None ->
    return_unit


let activate ~secret =
  let sk = match !LiquidOptions.private_key with
    | None -> raise (ResponseError "activate: Missing private key")
    | Some sk -> match Ed25519.Secret_key.of_b58check sk with
      | Ok sk -> sk
      | Error _ -> raise (ResponseError "activate: Bad private key")
  in
  let source = match !LiquidOptions.source with
    | Some source -> source
    | None -> get_public_key_hash_from_secret_key sk
  in
  get_head () >>= fun head ->
  let activate_json = [
    "kind", "\"activate_account\"";
    "pkh", Printf.sprintf "%S" source;
    "secret", Printf.sprintf "%S" secret;
  ] |> mk_json_obj
  in
  let operations_json = mk_json_arr [activate_json] in
  let data = [
    "branch", Printf.sprintf "%S" head.head_hash;
    "contents", operations_json;
  ] |> mk_json_obj
  in
  send_post ~data "/chains/main/blocks/head/helpers/forge/operations"
  >>= fun r ->
  (try
     get_json_string r |> return
   with Not_found ->
     raise_response_error "forge activation" (Ezjsonm.from_string r)
  ) >>= fun op ->
  inject_operation ~sk ~head operations_json (`Hex op) >>= function
  | op_h, [Ok []] -> return op_h
  | _, _ -> raise (ResponseError "activation (inject)")


(* operation is an hexa string, signature is "edsig..." of 0x03..., where
   [...] is the hexa string of operation. *)
let inject ~operation ~signature =
  let signature =
    match Ed25519.Signature.of_b58check signature with
    | Error _ -> failwith "cannot decode signature"
    | Ok signature_b ->
      Hex.show (Hex.of_string (MBytes.to_string signature_b))
  in
  let b = Buffer.create 1000 in
  Buffer.add_char b '"';
  for i = 0 to String.length operation -1 do
    let c = operation.[i] in
    match c with
    | '0'..'9' | 'a' .. 'f' | 'A'..'F' -> Buffer.add_char b c
    | ' ' | '\n' | '\t' -> ()
    | _ ->
      Printf.eprintf "Error: illegal characher '%s' in operation hexa\n%!"
        (Char.escaped c);
      exit 2
  done;
  Buffer.add_string b signature;
  Buffer.add_char b '"';
  let data = Buffer.contents b in
  send_post "/injection/operation" ~data >>= fun r ->
  try
    get_json_string r |> return
  with Not_found ->
    raise_response_error "inject (/injection/operation)"
      (Ezjsonm.from_string r)


let pack ?liquid ~const ~ty =
  let env, csig = match liquid with
    | Some liquid ->
      let syntax_ast, _, _ = compile_liquid liquid in
      { syntax_ast.ty_env with filename = "input" },
      full_sig_of_contract syntax_ast
    | None ->
      LiquidFromParsetree.initial_env "input",
      LiquidTypes.dummy_contract_sig
  in
  let ty =
    LiquidFromParsetree.translate_type env (LiquidFromParsetree.type_of_string ty) in
  let const = LiquidData.translate env csig const ty in
  (* LiquidCheck.check_const_type ~to_tez:LiquidPrinter.tez_of_liq noloc
   *   ty const in *)
  let const_m = LiquidMichelson.compile_const const in
  let const_t = LiquidToMicheline.convert_const ~expand:true const_m in
  let const_json = LiquidToMicheline.json_of_const const_t in
  let ty_m = LiquidToMicheline.convert_type (LiquidEncode.encode_type ty) in
  (* same syntax for const and types*)
  let ty_json = LiquidToMicheline.json_of_const ty_m in
  let pack_fields = [
    "data", const_json;
    "type", ty_json;
  ] in
  let pack_json = mk_json_obj pack_fields in
  send_post ~data:pack_json "/chains/main/blocks/head/helpers/scripts/pack_data"
  >>= fun r ->
  try
    let r = Ezjsonm.from_string r in
    let bytes = Ezjsonm.find r ["packed"] |> Ezjsonm.get_string in
    return ("0x" ^ bytes)
  with Not_found ->
    raise_response_error "pack" (Ezjsonm.from_string r)


(* Withoud optional argument head *)
module Async = struct
  type 'a t = 'a Lwt.t

  let init_storage liquid init_params_strings =
    init_storage liquid init_params_strings

  let forge_deploy_script ~source liquid init_params_strings =
    forge_deploy_script ~source liquid init_params_strings

  let forge_deploy liquid init_params_strings =
    forge_deploy liquid init_params_strings
    >>= fun (op, _, _) -> return op

  let forge_call_parameter = forge_call_parameter

  let forge_call liquid address entry_name parameter_string =
    forge_call liquid address entry_name parameter_string
    >>= fun (op, _, _) -> return op

  let run liquid entry_name input_string storage_string =
    run liquid entry_name input_string storage_string

  let run_debug liquid entry_name input_string storage_string =
    run_debug liquid entry_name input_string storage_string

  let deploy liquid init_params_strings =
    deploy liquid init_params_strings

  let get_storage liquid address =
    get_storage liquid address

  let get_big_map_value liquid bm_id key =
    get_big_map_value liquid bm_id key

  let call liquid address parameter_string =
    call liquid address parameter_string

  let activate ~secret =
    activate ~secret

  let inject ~operation ~signature =
    inject ~operation ~signature

  let pack ?liquid ~const ~ty =
    pack ?liquid ~const ~ty

end

module Sync = struct
  type 'a t = 'a

  let init_storage liquid init_params_strings =
    Lwt_main.run (init_storage liquid init_params_strings)

  let forge_deploy_script ~source liquid init_params_strings =
    Lwt_main.run (forge_deploy_script ~source liquid init_params_strings)

  let forge_deploy liquid init_params_strings =
    Lwt_main.run (forge_deploy liquid init_params_strings
                  >>= fun (op, _, _) -> return op)

  let forge_call_parameter = forge_call_parameter

  let forge_call liquid address entry_name parameter_string =
    Lwt_main.run (forge_call liquid address entry_name parameter_string
                  >>= fun (op, _, _) -> return op)

  let run liquid entry_name input_string storage_string =
    Lwt_main.run (run liquid entry_name input_string storage_string)

  let run_debug liquid entry_name input_string storage_string =
    Lwt_main.run (run_debug liquid entry_name input_string storage_string)

  let deploy liquid init_params_strings =
    Lwt_main.run (deploy liquid init_params_strings)

  let get_storage liquid address =
    Lwt_main.run (get_storage liquid address)

  let get_big_map_value liquid bm_id key =
    Lwt_main.run (get_big_map_value liquid bm_id key)

  let call liquid address entry_name parameter_string =
    Lwt_main.run (call liquid address entry_name parameter_string)

  let activate ~secret =
    Lwt_main.run (activate ~secret)

  let inject ~operation ~signature =
    Lwt_main.run (inject ~operation ~signature)

  let pack ?liquid ~const ~ty =
    Lwt_main.run (pack ?liquid ~const ~ty)

end

let forge_call_arg ?(entry_name="default") liquid input_string =
  let contract, pre_michelson, pre_init_infos = compile_liquid liquid in
  let contract_sig = full_sig_of_contract contract in
  let entry =
    try
      List.find (fun e -> e.entry_sig.entry_name = entry_name) contract.entries
    with Not_found ->
      invalid_arg @@ "Contract has no entry point " ^ entry_name
  in
  let parameter =
    LiquidData.translate { contract.ty_env with filename = "call_parameter" }
      contract_sig input_string entry.entry_sig.parameter
  in
  let param_m = LiquidMichelson.compile_const parameter in
  LiquidToMicheline.(string_of_const @@ convert_const ~expand:false param_m)
