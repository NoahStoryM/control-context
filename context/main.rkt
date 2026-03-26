#lang typed/racket/base/optional

(define-type ⊥ Nothing)
(define-type (¬ a) (→ a ⊥))
(define-type Label (¬ Label))
(define-type (LEM a) (∪ a (¬ a)))
(provide ⊥ ¬ Label LEM)

(require/typed/provide "private/context.rkt"
  [absurd (∀ (a) (→ ⊥ a))]
  [label (→* () (Prompt-TagTop) Label)]
  [goto (∀ (a) (case→ (→ Label ⊥) (→ (¬ a) a ⊥)))]
  [current-continuation (∀ (a) (case→ (→* () (Prompt-TagTop) (∪ a (¬ a))) (→ (¬ a) a ⊥)))]
  [wait-for-future-continuation (∀ (a) (→* ((→ (¬ a) a)) (Prompt-TagTop) (¬ (¬ a))))]
  [return-with-current-continuation (∀ (a) (→* ((→ a)) (Prompt-TagTop) (¬ (¬ a))))]
  [return-with-values (∀ (a) (→ a (¬ (¬ a))))])
(provide (rename-out [current-continuation cc]
                     [wait-for-future-continuation wait/fc]
                     [return-with-current-continuation return/cc]))
