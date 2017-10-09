
type timestamp = string
type kind = Tez | Int
type integer = Z.t * kind
type tez = integer
type nat = integer
type key

type ('arg, 'res) contract = Contract of 'arg * 'res

module Tez : sig

  val of_string : string -> tez

  end = struct

  let of_string s =
    let (tezzies, centiles) =
      try
        let pos = String.index s '.' in
        let tezzies = String.sub s 0 pos in
        let len = String.length s in
        let centiles = "0" ^ String.sub s (pos+1) (len-pos-1) in
        Z.of_string tezzies, Z.of_string centiles
      with Not_found ->
        Z.of_string s, Z.of_int 0
    in
    Z.add (Z.mul (Z.of_int 100) tezzies) centiles, Tez

end

module Int : sig

  val of_string : string -> integer

end = struct

  let of_string n = Z.of_string n, Int

end

module Current : sig

  val amount : unit -> tez
  val fail : unit -> 'a
  val time : unit -> timestamp
  val balance : unit -> tez

end = struct

  let amount () = Z.of_int 100, Tez
  let fail () = assert false    (* TODO *)
  let time () = assert false    (* TODO *)
  let balance () = assert false (* TODO *)

end


module Array : sig
  val get : 'a -> integer -> 'b
  val set : 'a -> integer -> 'b -> 'a

end = struct (* Arrays are for tuples, not typable in OCaml *)

  let get t n =
    let n,_ = n in
    let n = Z.to_int n in
    Obj.magic (Obj.field (Obj.magic  t) n)

  let set t n x =
    let n,_ = n in
    let n = Z.to_int n in
    let t = Obj.repr t in
    let t = Obj.dup t in
    Obj.set_field t n (Obj.repr x);
    Obj.magic t

end

module Map : sig

  type ('key, 'value) map
  val empty : int -> ('key,'value) map
  val make : ('key * 'value) list -> ('key, 'value) map
  val reduce : ( ('key * 'value) * 'acc -> 'acc) ->
               ('key,'value) map -> 'acc -> 'acc

  val map : ( 'key * 'value -> 'res) ->
               ('key,'value) map ->
               ('key,'res) map

  val find : 'key -> ('key, 'value) map -> 'value option

  val update : 'key -> 'value option  -> ('key, 'value) map ->
               ('key, 'value) map

end = struct

  module ObjMap = Map.Make(struct
                            type t = Obj.t
                            let compare = compare
                            end)

  type ('key, 'value) map
  let empty _ = Obj.magic ObjMap.empty
  let make list =
    let map =
      List.fold_left (fun map (key,value) ->
          let key = Obj.repr key in
          let value = Obj.repr value in
          ObjMap.add key value map
        ) (empty 0) list
    in
    Obj.magic map

  let reduce f map acc =
    let f = (Obj.magic f : (Obj.t * 'value) * Obj.t -> Obj.t) in
    let acc = Obj.repr acc in
    let map = (Obj.magic map : 'value ObjMap.t) in
    let (acc : Obj.t) = ObjMap.fold (fun key value acc ->
                            f ( (key,value), acc )
                          ) map acc
    in
    Obj.magic acc

  let map f map =
    let f = (Obj.magic f : Obj.t * 'value -> 'value) in
    let map = (Obj.magic map : 'value ObjMap.t) in
    let map = ObjMap.map (fun key value -> f (key,value)) map in
    Obj.magic map

  let find key map =
    try
      let key = Obj.repr key in
      let map = (Obj.magic map : 'value ObjMap.t) in
      Some (ObjMap.find key map)
    with Not_found -> None

  let update key value map = assert false (* TODO *)

end
include Array (* Remove ? *)


type ('key,'value) map = ('key,'value) Map.map

module Set : sig

  type 'key set
  val empty : int -> 'key set
  val make : 'key list -> 'key set
  val update : 'key -> bool -> 'key set -> 'key set
  val mem : 'key -> 'key set -> bool
  val reduce : ( 'key * 'acc -> 'acc) ->
               'key set -> 'acc -> 'acc

end = struct

  module ObjSet = Set.Make(struct
                            type t = Obj.t
                            let compare = compare
                            end)

  type 'key set

  let empty _ = Obj.magic ObjSet.empty
  let make list =
    let set =
      List.fold_left (fun set key ->
          let key = Obj.repr key in
          ObjSet.add key set
        ) (empty 0) list
    in
    Obj.magic set
  let update key bool set =
    let key = Obj.repr key in
    let set = (Obj.magic set : ObjSet.t) in
    let set =
      if bool then
        ObjSet.add key set
      else
        ObjSet.remove key set
    in
    Obj.magic set
  let mem key set =
    let key = Obj.repr key in
    let set = (Obj.magic set : ObjSet.t) in
    ObjSet.mem key set

  let reduce f set acc =
    let f = (Obj.magic f : Obj.t * Obj.t -> Obj.t) in
    let acc = Obj.repr acc in
    let set = (Obj.magic set : ObjSet.t) in
    let (acc : Obj.t) = ObjSet.fold (fun key acc ->
                            f (key, acc )
                          ) set acc
    in
    Obj.magic acc

end

type 'key set = 'key Set.set

type int = integer

let (+) (x,unit) (y,_) = Z.add x y, unit
let (-) (x,unit) (y,_) = Z.sub x y, unit
let (@) = (^)


let ediv x y =
  try
    let (q, r) = Z.ediv_rem x y in
    Some (q, r)
  with _ -> None

let (/) (x,xu) (y,yu) =
  try
    let (q, r) = Z.ediv_rem x y in
    let (qu, ru) =
      match xu, yu with
        Tez, Tez -> Int, Tez
      | Tez, Int -> Tez, Tez
      | Int, Int -> Int, Int
      | _ -> assert false
    in
    Some ((q,qu), (r,ru))
  with _ -> None


module Lambda : sig
  val pipe : 'a -> ('a -> 'b) -> 'b
end = struct
  let pipe x f = f x
end

module Loop : sig
  val loop : ('a -> bool * 'a) -> 'a -> 'a
end = struct
  let rec loop f x =
    let (bool, ret) = f x in
    if bool then loop f ret
    else ret
end

let int x = x

module Contract : sig

  val call : ('arg, 'res) contract -> tez -> 'storage -> 'arg ->
             'res * 'storage

end = struct

  let call contract amount storage arg =
    assert false (* TODO *)

end

type ('a,'b) variant = Left of 'a | Right of 'b

module List : sig

  val reduce : ('a * 'b -> 'b) -> 'a list -> 'b -> 'b
  val map : ('a -> 'b) -> 'a list -> 'b list
  val rev : 'a list -> 'a list

end = struct

  let rec reduce f list b =
    match list with
    | [] -> b
    | a :: list ->
       reduce f list (f (a,b))

  let map = List.map
  let rev = List.rev

end

module Account : sig
  val default : key -> (unit,unit) contract
end = struct
  let default _ = assert false (* TODO *)
end
