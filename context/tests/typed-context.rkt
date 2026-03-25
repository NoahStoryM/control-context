#lang typed/racket/base

(require racket/string
         typed/rackunit
         "../main.rkt")

(displayln 'Start)

;; ============================================================
;; absurd
;; ============================================================

(test-begin
  (check-pred procedure? absurd))

;; ============================================================
;; label + goto — loop
;; ============================================================

(test-begin
  (define x 0)
  (define loop (label))
  (set! x (add1 x))
  (when (< x 5) (goto loop))
  (check-eqv? x 5))

;; label + goto — factorial
(test-begin
  (define n 5)
  (define result 1)
  (define loop (label))
  (unless (zero? n)
    (set! result (* result n))
    (set! n (sub1 n))
    (goto loop))
  (check-eqv? result 120))

;; label + goto — early return
(test-begin
  (: mul/label (-> Integer * Integer))
  (define (mul/label . [r* : Integer *])
    (define first? #t)
    (define result : Integer 1)
    (define ret (label))
    (when first?
      (set! first? #f)
      (for ([r (in-list r*)])
        (when (zero? r)
          (set! result r)
          (goto ret))
        (set! result (* result r))))
    result)
  (check-eqv? (mul/label 3 4 10) 120)
  (check-eqv? (mul/label 3 0 10) 0)
  (check-eqv? (mul/label) 1))

;; ============================================================
;; current-continuation / cc
;; ============================================================

;; cc — capture and invoke
(test-begin
  (define result : Natural
    (let ([k : (LEM Natural) (cc)])
      (if (procedure? k)
          (cc k 42)
          k)))
  (check-eqv? result 42))

;; ============================================================
;; return-with-current-continuation / return/cc
;; ============================================================

;; basic
(test-begin
  (define f (return/cc (λ () 42)))
  (check-pred procedure? f)
  (check-eqv? (call/cc f) 42))

;; variable environment remains live
(test-begin
  (define b 100)
  (define f (return/cc (λ () (* 2 b))))
  (check-eqv? (call/cc f) 200)
  (set! b 300)
  (check-eqv? (call/cc f) 600))

;; parameterize bindings are frozen
(test-begin
  (define a (make-parameter 1))
  (define b 10)
  (define f
    (parameterize ([a 5])
      (return/cc (λ () (* (a) b)))))
  (check-eqv? (call/cc f) 50)
  (set! b 20)
  (check-eqv? (call/cc f) 100)
  (parameterize ([a 999])
    (check-eqv? (call/cc f) 100)))

;; dynamic-wind guards are re-entered
(test-begin
  (define log : (Listof Symbol) '())
  (define f
    (dynamic-wind
      (λ () (set! log (cons 'in log)))
      (λ () (return/cc
             (λ () (set! log (cons 'body log)) 99)))
      (λ () (set! log (cons 'out log)))))
  (check-equal? log '(out in))
  (set! log '())
  (define result (call/cc f))
  (check-eqv? result 99)
  (check-equal? log '(out body in)))

;; captured resources
(test-begin
  (define f
    (let ([p (open-input-string "hello")])
      (return/cc (λ () (read-line p)))))
  (check-equal? (call/cc f) "hello"))

;; ============================================================
;; Yin-Yang puzzle (smoke test)
;; ============================================================

(test-begin
  (define output (open-output-string))
  (define count 0)
  (let/cc escape : (Values)
    (parameterize ([current-output-port output])
      (let ([yin (label)])
        (display #\@)
        (set! count (add1 count))
        (when (> count 20) (escape))
        (let ([yang (label)])
          (display #\*)
          (set! count (add1 count))
          (when (> count 20) (escape))
          (goto yin yang)))))
  (define s (get-output-string output))
  (check-true (string-prefix? s "@*@**@***")))

(displayln 'Done)
