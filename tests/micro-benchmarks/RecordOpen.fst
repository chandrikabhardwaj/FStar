module RecordOpen

type ty = {x:int; y:bool}

let f (r:ty) : int =
  let open r as ty in
  if y then x else -x

let _ = assert (f ({x=3; y=true}) == 3)
let _ = assert (f ({x=3; y=false}) == -3)

type ty2 (t:Type) = {x:t; y:bool}

(* Arguments on the type are OK *)
let f2 (r:ty2 int) : int =
  let open r as ty2 in
  if y then x else -x

(* Shadowing as expected *)
let f3 (r:ty2 int) : unit =
  assume (r.x == 10);
  let x = 42 in
  let open r as ty2 in
  assert (x == 10)

(* Type error, could be better:

  A.fst(31,11-31,12): (Error 114) Type of pattern (A.ty) does not match type of scrutinee (A.ty2 Prims.int); head mismatch A.ty vs A.ty2
*)
[@@expect_failure [114]]
let f4 (r:ty2 int) : int =
  let open r as ty in
  if y then x else -x

(* Awful error: Mkint not found due to the hack... would be a lot
better to get "int is not a record" *)
[@@expect_failure [72]]
let f5 (r:ty2 int) : int =
  let open r as int in
  if y then x else -x

type indty =
  | Mkindty : x:int -> indty

(* We get a better here because Mkindty existed by chance.

A.fst(48,2-48,24): (Error 340) Not a record type: indty

Note the let open syntax does not work for 1-constructor inductives
(should it..?) *)
[@@expect_failure [340]]
let f6 (r:ty2 int) : int =
  let open r as indty in
  if y then x else -x
