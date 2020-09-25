#light "off"
module FStar.VConfig

open FStar.All

(* A type storing all options relevant to verification, used as
the "format" for sigelt_opts and check_with (in reflection). *)

type vconfig = {
  initial_fuel                              : int;
  max_fuel                                  : int;
  initial_ifuel                             : int;
  max_ifuel                                 : int;
  detail_errors                             : bool;
  detail_hint_replay                        : bool;
  no_smt                                    : bool;
  quake_lo                                  : int;
  quake_hi                                  : int;
  quake_keep                                : bool;
  retry                                     : bool;
  smtencoding_elim_box                      : bool;
  smtencoding_nl_arith_repr                 : string;
  smtencoding_l_arith_repr                  : string;
  smtencoding_valid_intro                   : bool;
  smtencoding_valid_elim                    : bool;
  tcnorm                                    : bool;
  no_plugins                                : bool;
  no_tactics                                : bool;
  vcgen_optimize_bind_as_seq                : option<string>;
  z3cliopt                                  : list<string>;
  z3refresh                                 : bool;
  z3rlimit                                  : int;
  z3rlimit_factor                           : int;
  z3seed                                    : int;
  use_two_phase_tc                          : bool;
  trivial_pre_for_unannotated_effectful_fns : bool;
  reuse_hint_for                            : option<string>;
}
