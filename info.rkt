#lang info

(define license 'MIT)
(define collection "control")
(define version "1.0")

(define pkg-desc "The simpler, more direct alternatives to `call/cc`")

(define deps
  '("base"
    "typed-racket-lib"))
(define build-deps
  '("at-exp-lib"
    "scribble-lib"
    "rackunit-lib"
    "rackunit-typed"
    "racket-doc"
    "typed-racket-doc"
    "data-doc"))

(define scribblings '(("scribblings/context.scrbl")))

(define clean '("compiled" "private/compiled"))
(define test-omit-paths '(#px"^((?!/tests/).)*$"))
