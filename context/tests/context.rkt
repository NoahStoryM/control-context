#lang racket/base

(require rackunit
         racket/function
         racket/list
         racket/string
         data/queue
         "../main.rkt")

(displayln 'Start)

;; ============================================================
;; absurd
;; ============================================================

(test-begin
  ;; absurd accepts no arguments — it is (case-λ) with zero clauses
  (check-pred procedure? absurd)
  (check-eqv? (procedure-arity absurd) '())
  ;; calling absurd with any argument should raise an error
  (check-exn exn:fail:contract:arity? (λ () (absurd 42)))
  (check-exn exn:fail:contract:arity? (λ () (absurd))))

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
  (define (mul/label . r*)
    (define first? #t)
    (define result (*))
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

;; goto defaults v to k (self-application)
(test-begin
  (define x 0)
  (define l (label))
  (when (zero? x)
    (set! x 1)
    ;; (goto l) without second arg passes l to itself
    (goto l))
  (check-eqv? x 1))

;; ============================================================
;; current-continuation / cc — LEM + LNC
;; ============================================================

;; cc — early return
(test-begin
  (define (mul/cc . r*)
    (define result (cc))
    (if (continuation? result)
        (for/fold ([res 1])
                  ([r (in-list r*)])
          (if (zero? r)
              (cc result r)
              (* res r)))
        result))
  (check-eqv? (mul/cc 3 4 10) 120)
  (check-eqv? (mul/cc 3 0 10) 0)
  (check-eqv? (mul/cc) 1))

;; cc — LNC form (multi-argument invocation)
(test-begin
  (define result
    (let ([k (cc)])
      (if (continuation? k)
          (cc k 42)
          k)))
  (check-eqv? result 42))

;; cc — multiple values
(test-begin
  (define-values (a b)
    (call-with-values cc (case-λ [(k) (cc k 10 20)] [(a b) (values a b)])))
  ;; first time k is a continuation, so we jump back with 10 20
  ;; second time k=10, k=20 … but we receive them via values
  ;; Actually: cc returns the continuation first, then we call (cc k 10 20)
  ;; which makes cc "return again" with 10 and 20 as multiple values
  (check-eqv? a 10)
  (check-eqv? b 20))

;; cc — error on non-prompt-tag, non-procedure single argument
(test-begin
  (check-exn exn:fail:contract?
             (λ () (cc 42))))

;; ============================================================
;; label + goto with prompt tags
;; ============================================================

(test-begin
  (define tag (make-continuation-prompt-tag 'test))
  (define result
    (call-with-continuation-prompt
     (λ ()
       (define x 0)
       (define l (label tag))
       (set! x (add1 x))
       (when (< x 3) (goto l))
       x)
     tag))
  (check-eqv? result 3))

;; ============================================================
;; return-with-current-continuation / return/cc
;; ============================================================

;; basic: return/cc produces a callable frozen thunk
(test-begin
  (define f (return/cc (λ () 42)))
  (check-pred procedure? f)
  (check-eqv? (call/cc f) 42))

;; return/cc — variable environment remains live
(test-begin
  (define b 100)
  (define f (return/cc (λ () (* 2 b))))
  (check-eqv? (call/cc f) 200)
  (set! b 300)
  (check-eqv? (call/cc f) 600))

;; return/cc — parameterize bindings are frozen
(test-begin
  (define a (make-parameter 1))
  (define b 10)
  (define f
    (parameterize ([a 5])
      (return/cc (λ () (* (a) b)))))
  ;; birth context has a=5
  (check-eqv? (call/cc f) 50)
  (set! b 20)
  (check-eqv? (call/cc f) 100)
  ;; call-site parameterize is invisible
  (parameterize ([a 999])
    (check-eqv? (call/cc f) 100)))

;; return/cc — dynamic-wind guards are re-entered
(test-begin
  (define log '())
  (define f
    (dynamic-wind
      (λ () (set! log (cons 'in log)))
      (λ () (return/cc
             (λ () (set! log (cons 'body log)) 99)))
      (λ () (set! log (cons 'out log)))))
  ;; after definition: entered and exited the dynamic-wind once
  (check-equal? log '(out in))
  (set! log '())
  (define result (call/cc f))
  ;; calling re-enters the birth context and exits again
  (check-eqv? result 99)
  (check-equal? log '(out body in)))

;; return/cc — captured resources
(test-begin
  (define f
    (let ([p (open-input-string "hello")])
      (return/cc (λ () (read-line p)))))
  (check-equal? (call/cc f) "hello"))

;; return/cc — multiple values
(test-begin
  (define f
    (return/cc (λ () (values 1 2 3))))
  (define-values (a b c) (call/cc f))
  (check-eqv? a 1)
  (check-eqv? b 2)
  (check-eqv? c 3))

;; return/cc — with explicit prompt tag
(test-begin
  (define tag (make-continuation-prompt-tag 'ret))
  (define f
    (call-with-continuation-prompt
     (λ ()
       (return/cc (λ () 77) tag))
     tag))
  (define result
    (call-with-continuation-prompt
     (λ () (call/cc f tag))
     tag))
  (check-eqv? result 77))

;; ============================================================
;; Light-weight processes (integration test)
;; ============================================================

(test-begin
  (define output '())
  (let ([lwp-queue (make-queue)])
    (define (lwp thk)
      (enqueue! lwp-queue thk))
    (define (start)
      (when (non-empty-queue? lwp-queue)
        ((dequeue! lwp-queue))))
    (define (pause)
      (call/cc
       (λ (k)
         (enqueue! lwp-queue (λ () (k (void))))
         (start))))

    (lwp (λ () (let f ([n 3])
                 (when (> n 0)
                   (pause)
                   (set! output (cons 'a output))
                   (f (sub1 n))))))
    (lwp (λ () (let f ([n 3])
                 (when (> n 0)
                   (pause)
                   (set! output (cons 'b output))
                   (f (sub1 n))))))
    (start))
  (check-eqv? (length output) 5)
  (check-eqv? (count (λ (x) (eq? x 'a)) output) 3)
  (check-eqv? (count (λ (x) (eq? x 'b)) output) 2))

;; Light-weight processes with cc
(test-begin
  (define output '())
  (let ([lwp-queue (make-queue)])
    (define (lwp thk)
      (enqueue! lwp-queue thk))
    (define (start)
      (when (non-empty-queue? lwp-queue)
        ((dequeue! lwp-queue))))
    (define (pause)
      (define k (cc))
      (when (continuation? k)
        (enqueue! lwp-queue (λ () (cc k (void))))
        (start)))

    (lwp (λ () (let f ([n 3])
                 (when (> n 0)
                   (pause)
                   (set! output (cons 'a output))
                   (f (sub1 n))))))
    (lwp (λ () (let f ([n 3])
                 (when (> n 0)
                   (pause)
                   (set! output (cons 'b output))
                   (f (sub1 n))))))
    (start))
  (check-eqv? (length output) 5))

;; Light-weight processes with label + goto
(test-begin
  (define output '())
  (let ([lwp-queue (make-queue)])
    (define (lwp thk)
      (enqueue! lwp-queue thk))
    (define (start)
      (when (non-empty-queue? lwp-queue)
        ((dequeue! lwp-queue))))
    (define (pause)
      (define first? #t)
      (define l (label))
      (when first?
        (set! first? #f)
        (enqueue! lwp-queue (λ () (goto l)))
        (start)))

    (lwp (λ () (let f ([n 3])
                 (when (> n 0)
                   (pause)
                   (set! output (cons 'a output))
                   (f (sub1 n))))))
    (lwp (λ () (let f ([n 3])
                 (when (> n 0)
                   (pause)
                   (set! output (cons 'b output))
                   (f (sub1 n))))))
    (start))
  (check-eqv? (length output) 5))

;; ============================================================
;; Amb (integration test)
;; ============================================================

(test-begin
  (define result
    (let ([task* '()])
      (define (fail)
        (if (null? task*)
            (error "Amb tree exhausted")
            ((car task*))))
      (define (amb* . alt*)
        (call/cc
         (λ (task)
           (unless (null? alt*)
             (set! task* (cons task task*)))))
        (when (null? alt*) (fail))
        (define alt (car alt*))
        (set! alt* (cdr alt*))
        (when (null? alt*) (set! task* (cdr task*)))
        (alt))
      (define-syntax-rule (amb exp* ...) (amb* (λ () exp*) ...))

      (let ([w-1 (amb "the" "that" "a")]
            [w-2 (amb "frog" "elephant" "thing")]
            [w-3 (amb "walked" "treaded" "grows")]
            [w-4 (amb "slowly" "quickly")])
        (define (joins? left right)
          (equal?
           (string-ref left (sub1 (string-length left)))
           (string-ref right 0)))
        (unless (joins? w-1 w-2) (amb))
        (unless (joins? w-2 w-3) (amb))
        (unless (joins? w-3 w-4) (amb))
        (list w-1 w-2 w-3 w-4))))
  (check-equal? result '("that" "thing" "grows" "slowly")))

;; ============================================================
;; Yin-Yang puzzle (smoke test — just check it produces output)
;; ============================================================

(test-begin
  (define output (open-output-string))
  (define count 0)
  ;; Run the yin-yang puzzle but bail out after enough iterations
  (let/cc escape
    (parameterize ([current-output-port output])
      (let ([yin (label)])
        (display #\@)
        (set! count (add1 count))
        (when (> count 20) (escape (void)))
        (let ([yang (label)])
          (display #\*)
          (set! count (add1 count))
          (when (> count 20) (escape (void)))
          (goto yin yang)))))
  (define s (get-output-string output))
  ;; should start with @*@**@***
  (check-true (string-prefix? s "@*@**@***")))

;; ============================================================
;; Defining call/cc from cc (round-trip test)
;; ============================================================

(test-begin
  (define (my-call/cc proc)
    (define v* (cc))
    (if (list? v*)
        (apply values v*)
        (proc (λ vs (cc v* vs)))))
  ;; basic escape
  (check-eqv?
   (my-call/cc (λ (return) (return 42) 99))
   42)
  ;; normal return
  (check-eqv?
   (my-call/cc (λ (return) 7))
   7))

;; ============================================================
;; Defining call/cc from label + goto (round-trip test)
;; ============================================================

(test-begin
  (define (my-call/cc proc)
    (define v* #f)
    (define l (label))
    (if v*
        (apply values v*)
        (proc (λ vs (set! v* vs) (goto l)))))
  (check-eqv?
   (my-call/cc (λ (return) (return 42) 99))
   42)
  (check-eqv?
   (my-call/cc (λ (return) 7))
   7))

;; ============================================================
;; Error checking
;; ============================================================

;; goto with non-procedure should raise argument error
(test-begin
  (check-exn exn:fail:contract?
             (λ () (goto 42))))

;; label with non-prompt-tag should raise argument error
(test-begin
  (check-exn exn:fail:contract?
             (λ () (label 42))))

;; return/cc with non-procedure should raise argument error
(test-begin
  (check-exn exn:fail:contract?
             (λ () (return/cc 42))))

;; return/cc with wrong-arity procedure should raise argument error
(test-begin
  (check-exn exn:fail:contract?
             (λ () (return/cc (λ (x) x)))))

;; return/cc with non-prompt-tag second arg should raise argument error
(test-begin
  (check-exn exn:fail:contract?
             (λ () (return/cc (λ () 1) 42))))

(displayln 'Done)
