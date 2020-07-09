module Alg

(* An algebraic presentation of ALL using action trees. *)

open FStar.Tactics
open FStar.List.Tot
open FStar.Universe
module WF = FStar.WellFounded
module L = Lattice

type state = int

type empty =

type op =
  | Read
  | Write
  | Raise
  | Other of int

assume val other_inp : int -> Type
let op_inp : op -> Type =
 function
 | Read -> unit
 | Write -> state
 | Raise -> exn
 | Other i -> other_inp i

assume val other_out : int -> Type
let op_out : op -> Type =
 function
 | Read -> state
 | Write -> unit
 | Raise -> empty
 | Other i -> other_inp i

noeq
type tree0 (a:Type u#aa) : Type u#aa =
  | Return : a -> tree0 a
  | Op     : op:op -> i:(op_inp op) -> k:(op_out op -> tree0 a) -> tree0 a

type ops = list op

let rec abides #a (labs:ops) (f : tree0 a) : prop =
  begin match f with
  | Op a i k ->
    mem a labs /\ (forall o. (WF.axiom1 k o; abides labs (k o)))
  | Return _ -> True
  end

type tree (a:Type u#aa)
          (labs : list u#0 op)
  : Type u#aa
  =
  r:(tree0 a){abides labs r}

let rec interp_at (l1 l2 : ops) (l : op)
  : Lemma (mem l (l1@l2) == (mem l l1 || mem l l2))
          [SMTPat (mem l (l1@l2))]
  = match l1 with
    | [] -> ()
    | _::l1 -> interp_at l1 l2 l

let sublist (l1 l2 : ops) = forall x. mem x l1 ==> mem x l2

let rec sublist_at
  (l1 l2 : ops)
  : Lemma (sublist l1 (l1@l2) /\ sublist l2 (l1@l2))
          [SMTPatOr [[SMTPat (sublist l1 (l1@l2))];
                     [SMTPat (sublist l2 (l1@l2))]]]
  = match l1 with
    | [] -> ()
    | _::l1 -> sublist_at l1 l2

let sublist_at_self
  (l : ops)
  : Lemma (sublist l (l@l))
          [SMTPat (sublist l (l@l))]
  = ()
  
let rec abides_sublist_nopat #a (l1 l2 : ops) (c : tree0 a)
  : Lemma (requires (abides l1 c) /\ sublist l1 l2)
          (ensures (abides l2) c)
  = match c with
    | Return _ -> ()
    | Op a i k ->
      let sub o : Lemma (abides l2 (k o)) =
        FStar.WellFounded.axiom1 k o;
        abides_sublist_nopat l1 l2 (k o)
      in
      Classical.forall_intro sub

let abides_sublist #a (l1 l2 : ops) (c : tree0 a)
  : Lemma (requires (abides l1 c) /\ sublist l1 l2)
          (ensures (abides l2 c))
          [SMTPat (abides l2 c); SMTPat (sublist l1 l2)]
  = abides_sublist_nopat l1 l2 c

let trigger (p:Type0) : Lemma (p <==> p) = ()

let abides_at_self #a
  (l : ops)
  (c : tree0 a)
  : Lemma (abides (l@l) c <==>  abides l c)
          [SMTPat (abides (l@l) c)]
  = (* Trigger some patterns *)
    assert (sublist l (l@l));
    assert (sublist (l@l) l)

let abides_app #a (l1 l2 : ops) (c : tree0 a)
  : Lemma (requires (abides l1 c \/ abides l2 c))
          (ensures (abides (l1@l2) c))
          [SMTPat (abides (l1@l2) c)]
  = sublist_at l1 l2

(* Folding a computation tree *)
val fold_with (#a #b:_) (#labs : ops)
           (f:tree a labs)
           (v : a -> b)
           (h: (o:op{mem o labs} -> op_inp o -> (op_out o -> b) -> b))
           : b
let rec fold_with #a #b #labs f v h =
  match f with
  | Return x -> v x
  | Op act i k ->
    let k' (o : op_out act) : b =
       WF.axiom1 k o;
       fold_with #_ #_ #labs (k o) v h
    in
    h act i k'

let handler_ty_l (o:op) (b:Type) (labs:ops) =
  op_inp o -> (op_out o -> tree b labs) -> tree b labs

let handler_ty (labs0 : ops) (b:Type) (labs1 : ops) : Type =
  o:op{mem o labs0} -> handler_ty_l o b labs1

(* The most generic handling construct, we use it to implement bind.
It is actually just a special case of folding. *)
val handle_with (#a #b:_) (#labs0 #labs1 : ops)
           (f:tree a labs0)
           (v : a -> tree b labs1)
           (h: handler_ty labs0 b labs1)
           : tree b labs1
let handle_with f v h = fold_with f v h

let return (a:Type) (x:a)
  : tree a []
  = Return x

let bind (a b : Type)
  (#labs1 #labs2 : ops)
  (c : tree a labs1)
  (f : (x:a -> tree b labs2))
  : Tot (tree b (labs1@labs2))
  = handle_with #_ #_ #labs1 #(labs1@labs2) c f (fun act i k -> Op act i k)
  
let subcomp (a:Type)
  (labs1 labs2 : ops)
  (f : tree a labs1)
  : Pure (tree a labs2)
         (requires (sublist labs1 labs2))
         (ensures (fun _ -> True))
  = f

let if_then_else
  (a : Type)
  (labs1 labs2 : ops)
  (f : tree a labs1)
  (g : tree a labs2)
  (p : bool)
  : Type
  = tree a (labs1@labs2)

let _get : tree int [Read] = Op Read () Return
let _put (s:state) : tree unit [Write] = Op Write s Return

[@@allow_informative_binders]
total // need this for catch!!
reifiable
reflectable
layered_effect {
  Alg : a:Type -> ops  -> Effect
  with
  repr         = tree;
  return       = return;
  bind         = bind;
  subcomp      = subcomp;
  if_then_else = if_then_else
}


unfold
let pure_monotonic #a (wp : pure_wp a) : Type =
  forall p1 p2. (forall x. p1 x ==> p2 x) ==> wp p1 ==> wp p2

//unfold
//let sp #a (wp : pure_wp a) : pure_post a =
//  fun x -> ~ (wp (fun y -> ~(x == y)))

let lift_pure_eff
 (a:Type)
 (wp : pure_wp a)
 (f : eqtype_as_type unit -> PURE a wp)
 : Pure (tree a [])
        (requires (wp (fun _ -> True) /\ pure_monotonic wp))
        (ensures (fun _ -> True))
 = Return (f ())

sub_effect PURE ~> Alg = lift_pure_eff

let geneff (o : op) (i : op_inp o) : Alg (op_out o) [o] = Alg?.reflect (Op o i Return)

let get   : unit -> Alg int [Read] = geneff Read
let put   : state -> Alg unit [Write] = geneff Write
let raise : #a:_ -> exn -> Alg a [Raise] = fun e -> match geneff Raise e with

let _other_raise #a (e:exn) : Alg a [Raise] =  
  // Funnily enough, the version below succeeds from concluding
  // a==empty under the lambda since the context becomes inconsistent.
  // All good, just surprising.
  Alg?.reflect (Op Raise e Return)

exception Failure of string

let test0 (x y : int) : Alg int [Read; Raise] =
  let z = get () in
  if z < 0 then raise (Failure "error");
  x + y + z

let test1 (x y : int) : Alg int [Raise; Read; Write] =
  let z = get () in
  if x + z > 0
  then raise (Failure "asd")
  else (put 42; y - z)

let labpoly #labs (f g : unit -> Alg int labs) : Alg int labs =
  f () + g ()

// FIXME: putting this definition inside catch causes a blowup:
//
// Unexpected error
// Failure("Empty option")
// Raised at file "stdlib.ml", line 29, characters 17-33
// Called from file "ulib/ml/FStar_All.ml" (inlined), line 4, characters 21-24
// Called from file "src/ocaml-output/FStar_TypeChecker_Util.ml", line 874, characters 18-65
// Called from file "src/ocaml-output/FStar_TypeChecker_Common.ml", line 675, characters 34-38
// Called from file "src/ocaml-output/FStar_TypeChecker_Common.ml", line 657, characters 25-33
// Called from file "src/ocaml-output/FStar_TypeChecker_TcTerm.ml", line 2048, characters 30-68
// Called from file "src/basic/ml/FStar_Util.ml", line 24, characters 14-18
// ....

(* Explicit definition of catch *)
let rec catch0 #a #labs (t1 : tree a (Raise::labs))
                        (t2 : tree a labs)
  : tree a labs
  = match t1 with
    | Op Raise e _ -> t2
    | Op act i k ->
      let k' o : tree a labs =
        WF.axiom1 k o;
        catch0 (k o) t2
      in
      Op act i k'
    | Return v -> Return v

(* no rollback *)
let catch #a #labs
  (f : unit -> Alg a (Raise::labs))
  (g : unit -> Alg a labs)
  : Alg a labs
=
 Alg?.reflect begin
   catch0 (reify (f ())) (reify (g ()))
 end

(* Explcitly catching state *)
let rec _catchST #a #labs (t1 : tree a (Read::Write::labs)) (s0:state) : tree (a & int) labs =
  match t1 with
  | Return v -> Return (v, s0)
  | Op Write s k -> WF.axiom1 k (); _catchST (k ()) s
  | Op Read  _ k -> WF.axiom1 k s0; _catchST (k s0) s0
  | Op act i k ->
     let k' o : tree (a & int) labs =
       WF.axiom1 k o;
       _catchST #a #labs (k o) s0
     in
     Op act i k'

let catchST #a #labs
  (f : unit -> Alg a (Read::Write::labs))
  (s0 : state)
  : Alg (a & state) labs
=
 Alg?.reflect begin
   _catchST (reify (f ())) s0
 end

let g #labs () : Alg int labs = 42  //AR: 07/03: had to hoist after removing smt_reifiablep

let test_catch #labs (f : unit -> Alg int [Raise;Write]) : Alg int [Write] =
  catch f g

let test_catch2 (f : unit -> Alg int [Raise;Raise;Write]) : Alg int [Raise;Write] =
  catch f g

let interp_pure_tree #a (t : tree a []) : Tot a =
  match t with
  | Return x -> x

let interp_pure #a (f : unit -> Alg a []) : Tot a = interp_pure_tree (reify (f ()))

let rec interp_rd_tree #a (t : tree a [Read]) (s:state) : Tot a =
  match t with
  | Return x -> x
  | Op Read _ k ->
    FStar.WellFounded.axiom1 k s;
    interp_rd_tree (k s) s

let interp_rd #a (f : unit -> Alg a [Read]) (s:state) : Tot a = interp_rd_tree (reify (f ())) s

let rec interp_rdwr_tree #a (t : tree a [Read;Write]) (s:state) : Tot (a & state) =
  match t with
  | Return x -> (x, s)
  | Op Read _ k ->
    FStar.WellFounded.axiom1 k s;
    interp_rdwr_tree (k s) s
  | Op Write s k ->
    FStar.WellFounded.axiom1 k ();
    interp_rdwr_tree (k ()) s

let interp_rdwr #a (f : unit -> Alg a [Read;Write]) (s:state) : Tot (a & state) = interp_rdwr_tree (reify (f ())) s

let rec interp_read_raise_tree #a (t : tree a [Read;Raise]) (s:state) : either exn a =
  match t with
  | Return x -> Inr x
  | Op Read _ k ->
    FStar.WellFounded.axiom1 k s;
    interp_read_raise_tree (k s) s
  | Op Raise e k ->
    Inl e

let interp_read_raise_exn #a (f : unit -> Alg a [Read;Raise]) (s:state) : either exn a =
  interp_read_raise_tree (reify (f ())) s

let rec interp_all_tree #a (t : tree a [Read;Write;Raise]) (s:state) : Tot (option a & state) =
  match t with
  | Return x -> (Some x, s)
  | Op Read _ k ->
    FStar.WellFounded.axiom1 k s;
    interp_all_tree (k s) s
  | Op Write s k ->
    FStar.WellFounded.axiom1 k ();
    interp_all_tree (k ()) s
  | Op Raise e k ->
    (None, s)

let interp_all #a (f : unit -> Alg a [Read;Write;Raise]) (s:state) : Tot (option a & state) = interp_all_tree (reify (f ())) s

//let action_input (a:action 'i 'o) = 'i
//let action_output (a:action 'i 'o) = 'o
//
//let handler_ty (a:action _ _) (b:Type) (labs:list eff_label) =
//    action_input a ->
//    (action_output a -> tree b labs) -> tree b labs
//
//let dpi31 (#a:Type) (#b:a->Type) (#c:(x:a->b x->Type)) (t : (x:a & y:b x & c x y)) : a =
//  let (| x, y, z |) = t in x
//
//let dpi32 (#a:Type) (#b:a->Type) (#c:(x:a->b x->Type)) (t : (x:a & y:b x & c x y)) : b (dpi31 t) =
//  let (| x, y, z |) = t in y
//
//let dpi33 (#a:Type) (#b:a->Type) (#c:(x:a->b x->Type)) (t : (x:a & y:b x & c x y)) : c (dpi31 t) (dpi32 t) =
//  let (| x, y, z |) = t in z

  //handler_ty (dpi33 (action_of l)) b labs
  //F* complains this is not a function
  //let (| _, _, a |) = action_of l in
  //handler_ty a b labs

(* A generic handler for a (single) label l. Anyway a special case of
handle_with. *)
val handle (#a #b:_) (#labs:_) (o:op)
           (f:tree a (o::labs))
           (h:handler_ty_l o b labs)
           (v: a -> tree b labs)
           : tree b labs
let rec handle #a #b #labs l f h v =
  match f with
  | Return x -> v x
  | Op act i k ->
    if act = l
    then h i (fun o -> WF.axiom1 k o; handle l (k o) h v)
    else begin
      let k' o : tree b labs =
         WF.axiom1 k o;
         handle l (k o) h v
      in
      Op act i k'
    end

(* Easy enough to handle 2 labels at once. Again a special case of
handle_with too. *)
val handle2 (#a #b:_) (#labs:_) (l1 l2 : op)
           (f:tree a (l1::l2::labs))
           (h1:handler_ty_l l1 b labs)
           (h2:handler_ty_l l2 b labs)
           (v : a -> tree b labs)
           : tree b labs
let rec handle2 #a #b #labs l1 l2 f h1 h2 v =
  match f with
  | Return x -> v x
  | Op act i k ->
    if act = l1
    then h1 i (fun o -> WF.axiom1 k o; handle2 l1 l2 (k o) h1 h2 v)
    else if act = l2
    then h2 i (fun o -> WF.axiom1 k o; handle2 l1 l2 (k o) h1 h2 v)
    else begin
      let k' o : tree b labs =
         WF.axiom1 k o;
         handle2 l1 l2 (k o) h1 h2 v
      in
      Op act i k'
    end

let catch0' #a #labs (t1 : tree a (Raise::labs))
                     (t2 : tree a labs)
  : tree a labs
  = handle Raise t1 (fun i k -> t2) (fun x -> Return x)

let catch0'' #a #labs (t1 : tree a (Raise::labs))
                      (t2 : tree a labs)
  : tree a labs
  = handle_with t1
                (fun x -> Return x)
                (function Raise -> (fun i k -> t2)
                        | act -> (fun i k -> Op act i k))

let fmap #a #b #labs (f : a -> b) (t : tree a labs) : tree b labs =
  bind _ _ #_ #labs t (fun x -> Return (f x))

let join #a #labs (t : tree (tree a labs) labs) : tree a labs =
  bind _ _ t (fun x -> x)

let app #a #b #labs (t : tree (a -> b) labs) (x:a) : tree b labs =
  fmap (fun f -> f x) t

let frompure #a (t : tree a []) : a =
  match t with
  | Return x -> x

(* Handling Read/Write into the state monad. There is some noise in the
handler, but it's basically interpreting [Read () k] as [\s -> k s s]
and similarly for Write. The only tricky thing is the stacking of [tree]
involved. *)
let catchST2 #a #labs (f : tree a (Read::Write::labs))
  : tree (state -> tree (a & state) labs) labs
  = handle2 Read Write f
            (fun _ k -> Return (fun s -> bind _ _ (k s)  (fun f -> f s)))
            (fun s k -> Return (fun _ -> bind _ _ (k ()) (fun f -> f s)))
            (fun x ->   Return (fun s0 -> Return (x, s0)))

(* Since this is a monad, we can apply the internal function and
then collapse the computations to get a more familiar looking catchST *)
let catchST2' #a #labs (f : tree a (Read::Write::labs)) (s0:state)
  : tree (a & state) labs
  = join (app (catchST2 f) s0)

(* And of course into a pure tree if no labels remain *)
let catchST2_emp #a
  (f : tree a (Read::Write::[]))
  : state -> a & state
  = fun s0 -> frompure (catchST2' f s0)

let baseop = o:op{not (Other? o)}

let trlab : o:baseop -> L.eff_label = function
  | Read  -> L.RD
  | Write  -> L.WR
  | Raise -> L.EXN

let trlab' = function
  | L.RD  -> Read
  | L.WR  -> Write
  | L.EXN -> Raise

let trlabs  = List.Tot.map trlab
let trlabs' = List.Tot.map trlab'

let rec lab_corr (l:baseop) (ls:list baseop)
  : Lemma (mem l ls <==> mem (trlab l) (trlabs ls))
          [SMTPat (mem l ls)] // needed for interp_into_lattice_tree below
  = match ls with
    | [] -> ()
    | l1::ls -> lab_corr l ls

(* Tied to the particular tree of Lattice.fst *)

(* no datatype subtyping *)
let fixup : list baseop -> ops = List.Tot.map #baseop #op (fun x -> x)

let rec fixup_corr (l:baseop) (ls:list baseop)
  : Lemma (mem l (fixup ls) <==> mem l ls)
          [SMTPat (mem l (fixup ls))]
  = match ls with
    | [] -> ()
    | l1::ls -> fixup_corr l ls
    
let rec fixup_no_other (l:op{Other? l}) (ls:list baseop)
  : Lemma (mem l (fixup ls) <==> False)
          [SMTPat (mem l (fixup ls))]
  = match ls with
    | [] -> ()
    | l1::ls -> fixup_no_other l ls

// This would be a lot nicer if it was done in L.EFF itself,
// but the termination proof fails since it has no logical payload.
let rec interp_into_lattice_tree #a (#labs:list baseop)
  (t : tree a (fixup labs))
  : L.repr a (trlabs labs)
  = match t with
    | Return x -> L.return _ x
    | Op Read i k ->
      L.bind _ _ _ _ (reify (L.get i))
       (fun x -> WF.axiom1 k x;
              interp_into_lattice_tree #a #labs (k x))
    | Op Write i k ->
      L.bind _ _ _ _ (reify (L.put i))
       (fun x -> WF.axiom1 k x;
              interp_into_lattice_tree #a #labs (k x))
    | Op Raise i k ->
      L.bind _ _ _ _ (reify (L.raise ()))
       (fun x -> WF.axiom1 k x;
              interp_into_lattice_tree #a #labs (k x))

let interp_into_lattice #a (#labs:list baseop)
  (f : unit -> Alg a (fixup labs))
  : Lattice.EFF a (trlabs labs)
  = Lattice.EFF?.reflect (interp_into_lattice_tree (reify (f ())))

// This is rather silly: we reflect and then reify. Maybe define interp_into_lattice
// directly?
let interp_full #a (#labs:list baseop)
  (f : unit -> Alg a (fixup labs))
  : Tot (f:(state -> Tot (option a & state)){Lattice.abides f (Lattice.interp (trlabs labs))})
  = reify (interp_into_lattice #a #labs f)


(* Doing it directly. *)

type sem0 (a:Type) : Type = state -> Tot (either exn a & state)

let abides' (f : sem0 'a) (labs:list baseop) : prop =
    (mem Read  labs \/ (forall s0 s1. fst (f s0) == fst (f s1)))
  /\ (mem Write labs \/ (forall s0. snd (f s0) == s0))
  /\ (mem Raise labs \/ (forall s0. Inr? (fst (f s0))))

type sem (a:Type) (labs : list baseop) = r:(sem0 a){abides' r labs}

let rec interp_sem #a (#labs:list baseop) (t : tree a (fixup labs)) : sem a labs =
  match t with
  | Return x -> fun s0 -> (Inr x, s0)
  | Op Read _ k ->
    (* Needs this trick for termination. Trying to call axiom1 within
     * `r` messes up the refinement about Read. *)
    let k : (s:state -> (r:(tree a (fixup labs)){r << k})) = fun s -> WF.axiom1 k s; k s in
    let r : sem a labs = fun s0 -> interp_sem #a #labs (k s0) s0 in
    r
  | Op Write s k ->
    WF.axiom1 k ();
    fun s0 -> interp_sem #a #labs (k ()) s
  | Op Raise e k -> fun s0 -> (Inl e, s0)

(* Way back: from the pure ALG into the free one, necessarilly giving
a fully normalized tree *)

let interp_from_lattice_tree #a #labs
  (t : L.repr a labs)
  : tree a [Read;Raise;Write] // conservative
  = Op Read () (fun s0 ->
     let (r, s1) = t s0 in
     match r with
     | Some x -> Op Write s1 (fun _ -> Return x)
     | None   -> Op Write s1 (fun _ -> Op Raise (Failure "") (fun x -> match x with))) // empty match

let read_handler (b:Type)
                 (labs:ops)
                 (s0:state)
   : handler_ty_l Read b labs
   = fun _ k -> k s0

let handle_read (a:Type)
                (labs:ops)
                (f:tree a (Read::labs))
                (h:handler_ty_l Read a labs)
   : tree a labs
   = handle Read f h (fun x -> Return x)


let weaken #a #labs l (f:tree a labs) : tree a (l::labs) =
  assert(l::labs == [l]@labs);
  f

let write_handler (a:Type)
                  (labs:ops)
  : handler_ty_l Write a labs
  = fun s k -> handle_read a labs (weaken Read (k())) (read_handler a labs s)


let handle_write (a:Type)
                (labs:ops)
                (f:tree a (Write::labs))
   : tree a labs
   = handle Write f (write_handler a labs) (fun x -> Return x)

let handle_st (a:Type)
              (labs: ops)
              (f:tree a (Write::Read::labs))
              (s0:state)
   : tree a labs
   = handle_read _ _ (handle_write _ _ f) (fun _ k -> k s0)


let widen_handler (#b:_) (#labs0 #labs1:_)
                  (h:handler_ty labs0 b labs1)
    : handler_ty (labs0@labs1) b labs1
    = fun op i k ->
       if mem op labs0 then h op i k
       else Op op i k
                  
let handle_sub (#a #b:_) (#labs0 #labs1:_)
               (f:tree a (labs0@labs1))
               (v: a -> tree b labs1)
               (h:handler_ty labs0 b labs1)
    : tree b labs1
    = handle_with f v (widen_handler h)


let widen_handler_1 (#b:_) (#o:op) (#labs1:_)
                       (h:handler_ty_l o b labs1)
    : handler_ty (o::labs1) b labs1
    = fun op' i k ->
       if op'=o then h i k
       else Op op' i k

let handle_one (#a:_) (#o:op) (#labs1:_)
               (f:tree a (o::labs1))
               (h:handler_ty_l o a labs1)
    : tree a labs1
    = handle_with f (fun x -> Return x) (widen_handler_1 h)

let append_single (a:Type) (x:a) (l:list a)
  : Lemma (x::l == [x]@l)
          [SMTPat (x::l)]
  = ()
let handle_raise #a #labs (f : tree a (Raise::labs)) (g : tree a labs)
   : tree a labs
   = handle_one f (fun _ _ -> g)
let handle_read' (#a:Type)  (#labs:ops) (f:tree a (Read::labs)) (s:state)
   : tree a labs
   = handle_one f (fun _ k -> k s)
let handle_write' (#a:Type)  (#labs:ops) (f:tree a (Write::labs))
   : tree a labs
   = handle_one f (fun s k -> handle_read' (k()) s)

let try_catch #a #labs (f:unit -> Alg a (Raise::labs)) (g:unit -> Alg a labs)
  : Alg a labs
  = Alg?.reflect (handle_raise (reify (f())) (reify (g())))

let handle_raise_none #a () : Alg (option a & state) [Read] = let s = get () in None, s

let handle_return #a (x:a) : tree (option a & state) [Write;Read] =
   Op Read () (fun s -> Return (Some x, s))

let handler_raise #a : handler_ty ([Raise]@[Write;Read]) (option a & state) ([Write]@[Read]) =
  fun o i k -> 
    match o with
    | Raise -> Op Read () (fun s -> Return (None, s))
    | _ -> Op o i k
    
let handler_raise_write #a : handler_ty [Raise; Write] (option a & state) ([Write]@[Read]) =
  fun o i k -> 
    match o with
    | Raise -> Op Read () (fun s -> Return (None, s))
    | Write -> handle_write' (k())

let run_tree #a (f:tree a ([Raise;Write;Read])) (s0:state) : option a & state =
  match handle_read'  (handle_write' (handle_with f handle_return handler_raise)) s0 with 
  | Return x -> x
  
let run #a #labs (f:unit -> Alg a ([Raise;Write;Read])) (s0:state) : option a & state =
  run_tree (reify (f())) s0
  

let run_tree2 #a (f:tree a ([Raise;Write;Read])) (s0:state) : option a & state =
  let t' =
    (* Inference bug? *)
    handle_with #_ #(state -> tree _ _) #_ #_
              f (fun x -> Return (fun s0 -> Return (Some x, s0)))
                (function Read  -> fun _ k -> Return (fun s -> bind _ _ (k s)  (fun f -> f s))
                        | Write -> fun s k -> Return (fun _ -> bind _ _ (k ()) (fun f -> f s))
                        | Raise -> fun e k -> Return (fun s -> Return (None, s)))
  in
  frompure (frompure t' s0)

let run_tree2' #a (f:tree a ([Raise;Write;Read])) (s0:state) : option a & state =
  fold_with #_ #(state -> option a & state) #_
            f (fun x s0 -> (Some x, s0))
              (function Read -> fun () k s0 -> k s0 s0
                      | Write -> fun s k _ -> k () s
                      | Raise -> fun e k s0 -> (None, s0)) s0
  
let run2 #a #labs (f:unit -> Alg a ([Raise;Write;Read])) (s0:state) : option a & state =
  run_tree2 (reify (f())) s0

let hty_l (o:op) (b:Type) (labs:ops) =
  op_inp o -> (op_out o -> Alg b labs) -> Alg b labs

let hty (labs0 : ops) (b:Type) (labs1 : ops) : Type =
  o:op{mem o labs0} -> hty_l o b labs1










#set-options "--debug Alg --debug_level High"


let min (a:Type) : hty_l Raise (state -> Alg (option a & state) []) []
  = fun s k ->
     //let r =
       fun s -> (None, s)
     //in
     //r

(*****



let reflect_k #a #b #labs1 (k : op_out a -> tree b labs1)
  : op_out a -> Alg b labs1
  = fun o -> Alg?.reflect (k o)
  
let reify_k #a #b #labs1 (k : op_out a -> Alg b labs1)
  : op_out a -> tree b labs1
  = fun o -> reify (k o)
  
let hty_to_handler_ty #labs0 #b #labs1 (h:hty labs0 b labs1) : handler_ty labs0 b labs1=
  fun a i k -> reify (h a i (reflect_k k))
  
let handler_ty_to_hty #labs0 #b #labs1 (h:handler_ty labs0 b labs1) : hty labs0 b labs1=
  fun a i k -> Alg?.reflect (h a i (reify_k k))
  
let ehandle_with (#a #b:_) (#labs0 #labs1 : ops)
           (f : unit -> Alg a labs0)
           (v : a -> Alg b labs1)
           (h: hty labs0 b labs1)
  : Alg b labs1
  =
  let t : tree a labs0 = reify (f ()) in
  let v : a -> tree b labs1 = fun x -> reify (v x) in
  let h : handler_ty labs0 b labs1 = hty_to_handler_ty h in
  Alg?.reflect (handle_with t v h)

let hh #a #labs (g : unit -> Alg a labs) : hty (Raise::labs) a labs =
    (function Raise -> fun _ k -> g ()
            | op   -> fun i k -> k (geneff op i))

    let exnvc #a #labs (x:a) : Alg a labs =
      x
      
let try_catch' : (#a:_) -> (#labs:_) -> 
                 (f : (unit -> Alg a (Raise::labs))) ->
                 (g:unit -> Alg a labs) -> Alg a labs
                 by (dump "")
  = fun #a #labs f g ->
    ehandle_with #a #a #(Raise::labs) #labs
                 f
                 (exnvc #a #labs)
                 (hh #a #labs g)

let vc #a : a -> Alg (state -> Alg (option a & state) []) [] =
  fun x -> let f = fun s -> (Some x, s) in f

let stexn_tree_handler (a:Type) : handler_ty [Write;Read;Raise] (state -> tree (option a & state) []) [] =
  (function Read  -> (fun _ k -> Return (fun s -> bind _ _ (k s)  (fun f -> f s)))
          | Write -> (fun s k -> Return (fun _ -> bind _ _ (k ()) (fun f -> f s)))
          | Raise -> (fun s k -> Return (fun s -> Return (None, s))))
          
let stexn_alg_handler (a:Type)
  : hty [Raise; Write] (state -> Alg (option a & state) []) []
  =
  (function
          | Raise -> (fun s k -> let r = (fun s -> (None, s)) in r))

let stexn_value_case (a:Type) : a -> tree (state -> tree (option a & state) []) [] =
  (fun x -> Return (fun s0 -> Return (Some x, s0)))

let refl_value_case (#a #b #labs : _) (v : (a -> tree b labs)) : a -> Alg b labs =
  fun x -> Alg?.reflect (v x)

let cheating0 #a (f: unit -> Alg a [Raise; Write; Read]) : Alg (state -> tree (option a & state) []) [] =
  ehandle_with #_ #_ #[Raise;Write;Read] #_
               f
               (refl_value_case (stexn_value_case a))
               (handler_ty_to_hty (stexn_tree_handler a))
                 
let cheating1 #a (f: unit -> Alg a [Raise; Write; Read]) : Alg (state -> tree (option a & state) []) [] =
  ehandle_with f
               (fun (x:a) -> _)
               (handler_ty_to_hty (stexn_tree_handler a))


let hh #a (o:op{mem o [Raise; Read]}) (i:op_inp o) (k : op_out o -> Alg (state -> Alg (option a & state) []) [])
  : Alg (state -> Alg (option a & state) []) []
  = match o with
    | Raise -> let f = fun s -> (None, s) in f
    | Read  -> let r (s:state)
                : Alg (option a & state) []
                = let f = k s in f s
              in r


    | Write -> fun _ -> let f = k () in f i

let run_tree2'' #a (f: unit -> Alg a [Raise; Write; Read]) : Alg (state -> Alg (option a & state) []) [] =
  ehandle_with #a #(state -> Alg (option a & state) []) #[Raise; Write; Read] #[]
    f vc hh



  ehandle_with f (fun x s -> (Some x, s))
                 (function Read () k s -> k s s
                         | Write s k _ -> k () s
                         | Raise e k s -> (None, s))
                