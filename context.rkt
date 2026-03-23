#lang typed/racket/base/optional

(define-type ⊥ Nothing)
(define-type (¬ a) (→ a ⊥))
(define-type Label (¬ Label))
(define-type (LEM a) (∪ a (¬ a)))
(provide ⊥ ¬ Label LEM)

(require/typed/provide "private/context.rkt"
  [label (→* () (Prompt-TagTop) Label)]
  [goto (∀ (a) (case→ (→ Label ⊥) (→ (¬ a) a ⊥)))]
  [current-continuation (∀ (a) (case→ (→* () (Prompt-TagTop) (∪ a (¬ a))) (→ (¬ a) a ⊥)))])
(provide (rename-out [current-continuation cc]))
