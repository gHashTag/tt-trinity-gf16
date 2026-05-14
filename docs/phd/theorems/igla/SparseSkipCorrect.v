(* SparseSkipCorrect.v — L-S34 Sparse-Skip MAC correctness lemma
   Apache-2.0 · TRI-1 v2 · PhD Ch.5 Sparsity / BitNet b1.58 anchor
   
   Proves that if either operand is zero, the dot product is zero.
   This formalises the early-exit gate correctness property of sparse_skip_mac.v.
*)

Require Import Arith.

(* Abstract model of GF16 dot product over natural numbers.
   gf16_dot a b = a * b  (multiplication in N used as a model;
   the real GF16 field also satisfies 0*x = 0 by field axioms). *)
Definition gf16_dot (a b : nat) : nat := a * b.

(* sparse_skip_correct:
   If either operand is zero then the dot product is zero.
   This directly justifies the hardware optimisation: when the sparse-skip
   gate detects a zero operand, it may safely output 0 without invoking
   the multiplier array. *)
Theorem sparse_skip_correct :
  forall (a b : nat),
    (a = 0 \/ b = 0) -> gf16_dot a b = 0.
Proof.
  intros a b H.
  unfold gf16_dot.
  destruct H as [Ha | Hb].
  - (* a = 0 *)
    subst a. simpl. reflexivity.
  - (* b = 0 *)
    subst b. rewrite Nat.mul_0_r. reflexivity.
Qed.
