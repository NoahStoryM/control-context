#lang at-exp racket/base

(require scribble/manual)
(provide (all-defined-out))

(define-syntax-rule (deftypeconstr args ...)
  @defform[#:kind "type constructor" args ...])

(define-syntax-rule (deftypeconstr* args ...)
  @defform*[#:kind "type constructor" args ...])

(define-syntax-rule (deftypeconstr*/subs args ...)
  @defform*/subs[#:kind "type constructor" args ...])

(define-syntax-rule (deftype args ...)
  @defidform[#:kind "type" args ...])

(define-syntax-rule (deftypeform args ...)
  @defform[#:kind "type" args ...])

(define-syntax-rule (deftypeform* args ...)
  @defform*[#:kind "type" args ...])

(define-syntax-rule (deftypeform/none args ...)
  @defform/none[#:kind "type" args ...])

(define-syntax-rule (deftypeconstr/none args ...)
  @defform/none[#:kind "type constructor" args ...])
