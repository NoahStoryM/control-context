#lang scribble/manual

@(require (for-label racket/base
                     racket/contract/base
                     racket/function
                     racket/sequence
                     (only-in typed/racket/base define-type → Nothing)
                     data/queue
                     control/context)
          "utils.rkt")

@title{Evaluation Context}
@defmodule[control/context #:packages ("control-context")]
@author[@author+email["Noah Ma" "noahstorym@gmail.com"]]

@section{Overview}

This package provides @racket[goto], @racket[label] and @racket[cc],
which are simpler, more direct alternatives to @racket[call/cc].

@section{API Reference}

@defproc[(goto [k (-> any/c none/c)] [v any/c k]) none/c]{
@racketblock[
(define (goto k [v k]) (k v))
]

@racketblock[
(define (goto k [v k]) (cc k v))
]
}

@defproc[(label [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any/c]{
@racketblock[
(define (label [prompt-tag (default-continuation-prompt-tag)])
  (call/cc goto prompt-tag))
]

@racketblock[
(define (label [prompt-tag (default-continuation-prompt-tag)])
  (cc prompt-tag))
]
}

@defproc*[([(current-continuation [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any/c]
           [(current-continuation [k (-> any/c ... none/c)] [v any/c] ...) none/c])]{
@racketblock[
(define current-continuation
  (case-λ
    [() (current-continuation (default-continuation-prompt-tag))]
    [(p) (if (continuation-prompt-tag? p) (call/cc values p) (p))]
    [(k . v*) (apply k v*)]))
]

@racketblock[
(define current-continuation
  (case-λ
    [() (current-continuation (default-continuation-prompt-tag))]
    [(p)
     (if (continuation-prompt-tag? p)
         (let* ([v* #f] [l (label p)])
           (if v*
               (apply values v*)
               (λ vs (set! v* vs) (goto l))))
         (p))]
    [(k . v*) (apply k v*)]))
]
}

@defproc*[([(cc [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any/c]
           [(cc [k (-> any/c ... none/c)] [v any/c] ...) none/c])]{
Is an alias for @racket[current-continuation].
}


@deftype[⊥]{
Is an alias for @racket[Nothing].

@racketblock[
(define-type ⊥ Nothing)
]
}

@deftypeconstr[(¬ a)]{
@racketblock[
(define-type (¬ a) (→ a ⊥))
]
}

@deftype[Label]{
Is the fixed point of @racket[¬].

@racketblock[
(define-type Label (¬ Label))
]
}

@deftypeconstr[(LEM a)]{
Is the Law of Excluded Middle.

@racketblock[
(define-type (LEM a) (∪ a (¬ a)))
]
}

@section{Examples}

@subsection{Loop}

@racketblock[
(let ([x 0])
  (define loop (label))
  (set! x (add1 x))
  (when (< x 7) (goto loop))
  (displayln x))
]

@subsection{Return}

@racketblock[
(define (mul . r*)
  (call/cc
   (λ (return)
     (for/fold ([res (*)] #:result (return res))
               ([r (in-list r*)])
       (if (zero? r)
           (return r)
           (* res r))))))
]

@racketblock[
(define (mul . r*)
  (define result (cc))
  (when (continuation? result)
    (for/fold ([res (*)] #:result (cc result res))
              ([r (in-list r*)])
      (if (zero? r)
          (cc result r)
          (* res r))))
  result)
]

@racketblock[
(define (mul . r*)
  (define first? #t)
  (define result (*))
  (define l (label))
  (when first?
    (set! first? #f)
    (for ([r (in-list r*)])
      (when (zero? r)
        (set! result r)
        (goto l))
      (set! result (* result r))))
  result)
]

@subsection{Yin-Yang Puzzle}

@racketblock[
(let* ([kn   ((λ (k) (display #\@) k) (call/cc (λ (k) k)))]
       [kn+1 ((λ (k) (display #\*) k) (call/cc (λ (k) k)))])
  (kn kn+1))
]

@racketblock[
(let ([kn (cc)])
  (display #\@)
  (let ([kn+1 (cc)])
    (display #\*)
    (cc kn kn+1)))
]

@racketblock[
(let* ([k #f] [k0 (label)])
  (unless k (set! k k0) (goto k))
  (display #\@)
  (let* ([kn k] [kn+1 (label)])
    (when (eq? kn k) (set! k kn+1) (goto k))
    (display #\*)
    (goto kn)))
]

@racketblock[
(define (k0 kn)
  (display #\@)
  (define (kn+1 k)
    (display #\*)
    (kn k))
  (kn+1 kn+1))
(k0 k0)
]

@subsection{Call with Current Continuation}

@racketblock[
(define (call/cc proc [prompt-tag (default-continuation-prompt-tag)])
  (define v* (cc prompt-tag))
  (if (list? v*)
      (apply values v*)
      (proc (λ vs (cc v* vs)))))
]

@racketblock[
(define (call/cc proc [prompt-tag (default-continuation-prompt-tag)])
  (define v* #f)
  (define l (label prompt-tag))
  (if v*
      (apply values v*)
      (proc (λ vs (set! v* vs) (goto l)))))
]

@subsection{Light-Weight Process}

@racketblock[
(let ([lwp-queue (make-queue)])
  (define (lwp thk)
    (enqueue! lwp-queue thk))
  (define (start)
    (when (non-empty-queue? lwp-queue)
      ((dequeue! lwp-queue))))
  (define (pause)
    (call/cc
     (λ (k)
       (enqueue! lwp-queue (λ () (k #f)))
       (start))))

  (lwp (λ () (let f () (pause) (display #\h) (f))))
  (lwp (λ () (let f () (pause) (display #\e) (f))))
  (lwp (λ () (let f () (pause) (display #\y) (f))))
  (lwp (λ () (let f () (pause) (display #\!) (f))))
  (lwp (λ () (let f () (pause) (newline)     (f))))
  (start))
]

@racketblock[
(let ([lwp-queue (make-queue)])
  (define (lwp thk)
    (enqueue! lwp-queue thk))
  (define (start)
    (when (non-empty-queue? lwp-queue)
      ((dequeue! lwp-queue))))
  (define (pause)
    (define k (cc))
    (when k
      (enqueue! lwp-queue (λ () (cc k #f)))
      (start)))

  (lwp (λ () (let f () (pause) (display #\h) (f))))
  (lwp (λ () (let f () (pause) (display #\e) (f))))
  (lwp (λ () (let f () (pause) (display #\y) (f))))
  (lwp (λ () (let f () (pause) (display #\!) (f))))
  (lwp (λ () (let f () (pause) (newline)     (f))))
  (start))
]

@racketblock[
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

  (lwp (λ () (let f () (pause) (display #\h) (f))))
  (lwp (λ () (let f () (pause) (display #\e) (f))))
  (lwp (λ () (let f () (pause) (display #\y) (f))))
  (lwp (λ () (let f () (pause) (display #\!) (f))))
  (lwp (λ () (let f () (pause) (newline)     (f))))
  (start))
]

@subsection{Ambiguous Operator}

@racketblock[
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
    (list w-1 w-2 w-3 w-4)))
]

@racketblock[
(let ([task* '()])
  (define (fail)
    (if (null? task*)
        (error "Amb tree exhausted")
        (cc (car task*) #f)))
  (define (amb* . alt*)
    (define task (cc))
    (when (null? alt*) (fail))
    (when task
      (set! task* (cons task task*)))
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
    (list w-1 w-2 w-3 w-4)))
]

@racketblock[
(let ([task* '()])
  (define (fail)
    (if (null? task*)
        (error "Amb tree exhausted")
        (goto (car task*))))
  (define (amb* . alt*)
    (define first? #t)
    (define task (label))
    (when (null? alt*) (fail))
    (when first?
      (set! first? #f)
      (set! task* (cons task task*)))
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
    (list w-1 w-2 w-3 w-4)))
]
