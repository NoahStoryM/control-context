#lang scribble/manual

@(require (for-label racket/base
                     racket/contract/base
                     racket/function
                     racket/sequence
                     (only-in typed/racket/base : ∀ ∪ → Nothing define-type)
                     data/queue
                     control/context)
          "utils.rkt")

@title{Evaluation Context}
@defmodule[control/context #:packages ("control-context")]
@author[@author+email["Noah Ma" "noahstorym@gmail.com"]]

@section{Overview}

This package provides @racket[label], @racket[goto], and @racket[cc]
(short for @racket[current-continuation]),
which are simpler, more direct alternatives to @racket[call/cc].

The key idea is that continuations can be understood through three
equivalent lenses, each with different trade-offs:

@itemlist[
  @item{@bold{First-class labels} (@racket[label] + @racket[goto])
  —
  conceptually the simplest, with a trivial type (@racket[Label]),
  but requires mutation (@racket[set!]) to communicate across jumps.}

  @item{@bold{Law of Excluded Middle + Law of Noncontradiction} (@racket[cc])
  —
  eliminates the need for mutation by returning a union type
  @racket[(LEM a)] = @racket[a] ∪ @racket[(¬ a)], at the cost of
  branching on whether you received a value or a continuation.}

  @item{@bold{Peirce's law} (@racket[call/cc])
  —
  eliminates both mutation and union types by delivering
  the continuation as an argument to a callback, at the cost of
  a more complex higher-order type signature.}
]

All three are equivalent in expressive power. This package provides
the first two as building blocks, and shows how @racket[call/cc] can
be defined in terms of them (and vice versa).

@section{API Reference}

@defproc[(label [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any/c]{

Captures the current position in the program and returns
a @racket[Label] value. A subsequent @racket[(goto l)] jumps back to
this point, causing @racket[label] to "return again".

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[call/cc]:

@racketblock[
(define (label [prompt-tag (default-continuation-prompt-tag)])
  (call/cc goto prompt-tag))
]

Implementation using @racket[cc]:

@racketblock[
(define (label [prompt-tag (default-continuation-prompt-tag)])
  (cc prompt-tag))
]
}

@defproc[(goto [k (-> any/c none/c)] [v any/c k]) none/c]{

Jumps to the label @racket[k], passing @racket[v] as the value
delivered at the jump target. If @racket[v] is omitted, it defaults to
@racket[k] itself—this is consistent with the interpretation that
@racket[goto] is itself a @racket[Label], since
@racket[Label] = @racket[(¬ Label)].

Equivalent definitions:

@racketblock[
(define (goto k [v k]) (k v))
]

Using @racket[cc]:

@racketblock[
(define (goto k [v k]) (cc k v))
]
}

@defproc*[([(current-continuation [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any/c]
           [(current-continuation [k (-> any/c ... none/c)] [v any/c] ...) none/c])]{

The core operator of this package, combining the Law of Excluded Middle
(@tech{LEM}) and the Law of Noncontradiction (@tech{LNC}) into a single procedure.

@bold{Zero arguments or prompt tag} (@deftech{LEM} — @racket[(∀ (a) (→ (∪ a (¬ a))))]):
Captures the current continuation and returns it as a function.
The first time @racket[(current-continuation)] is evaluated, it returns
a continuation of type @racket[(¬ a)] — a function that, when called
with a value of type @racket[a], jumps back to this point, causing
@racket[(current-continuation)] to "return again" with that value.
Thus the overall return type is @racket[(∪ a (¬ a))].

@bold{Continuation and values} (@deftech{LNC} — @racket[(∀ (a) (→ (¬ a) a ⊥))]):
Invokes the continuation @racket[k] with the given values @racket[v ...].
This never returns to the caller (return type @racket[⊥]).

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[call/cc]:

@racketblock[
(define current-continuation
  (case-λ
    [() (current-continuation (default-continuation-prompt-tag))]
    [(p)
     (if (continuation-prompt-tag? p)
         (call-with-current-continuation values p)
         (p))]
    [(k . v*) (apply k v*)]))
]

Implementation using @racket[label] and @racket[goto]:

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
An alias for @racket[current-continuation].
}

@subsection{Typed Racket Definitions}

The following type definitions are provided for use with Typed Racket.
They formalize the correspondence between control operators and
classical logic.

@deftype[⊥]{
The empty type, representing a computation that never produces a value
(i.e., diverges or transfers control elsewhere).
An alias for @racket[Nothing].

@racketblock[
(define-type ⊥ Nothing)
]
}

@deftypeconstr[(¬ a)]{
The negation of type @racket[a]: a function that consumes an @racket[a]
and never returns. In the Curry–Howard correspondence, this is
logical negation.

@racketblock[
(define-type (¬ a) (→ a ⊥))
]
}

@deftype[Label]{
The type of first-class labels. Defined as the fixed point of @racket[¬]:
a label is a function that accepts a label and never returns.

@racketblock[
(define-type Label (¬ Label))
]

This recursive type reflects the fact that @racket[goto] itself is
a @racket[Label].
}

@deftypeconstr[(LEM a)]{
The Law of Excluded Middle as a type: for any @racket[a], you either
have a value of type @racket[a] or a continuation of type
@racket[(¬ a)]. This is the return type of @racket[(cc)] when called
with zero arguments.

@racketblock[
(define-type (LEM a) (∪ a (¬ a)))
]
}

@section{Examples}

Each example is shown in multiple styles—using @racket[call/cc],
@racket[cc], and @racket[label]/@racket[goto]—to illustrate the
trade-offs between the three approaches.

@subsection{Loop}

A simple counted loop using a first-class label:

@racketblock[
(let ([x 0])
  (define loop (label))
  (set! x (add1 x))
  (when (< x 7) (goto loop))
  (displayln x))
]

@subsection{Early Return}

Short-circuiting a product computation when a zero is encountered.

Using @racket[call/cc]:

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

Using @racket[cc]:

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

Using @racket[label] and @racket[goto]:

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

David Madore's famous puzzle, which exploits the fact that
@racket[goto] is itself a @racket[Label]. Since
@racket[Label] = @racket[(¬ Label)], any label can be passed to
any other label.

@racketblock[
(let ([yin (label)])
  (display #\@)
  (let ([yang (label)])
    (display #\*)
    (yin yang)))
]

Using @racket[call/cc]:

@racketblock[
(let* ([kn   ((λ (k) (display #\@) k) (call/cc (λ (k) k)))]
       [kn+1 ((λ (k) (display #\*) k) (call/cc (λ (k) k)))])
  (kn kn+1))
]

Using @racket[cc]:

@racketblock[
(let ([kn (cc)])
  (display #\@)
  (let ([kn+1 (cc)])
    (display #\*)
    (cc kn kn+1)))
]

Using @racket[label] and @racket[goto]:

@racketblock[
(let* ([k #f] [k0 (label)])
  (unless k (set! k k0) (goto k))
  (display #\@)
  (let* ([kn k] [kn+1 (label)])
    (when (eq? kn k) (set! k kn+1) (goto k))
    (display #\*)
    (goto kn)))
]

CPS transform (no continuations at all):

@racketblock[
(define (k0 kn)
  (display #\@)
  (define (kn+1 k)
    (display #\*)
    (kn k))
  (kn+1 kn+1))
(k0 k0)
]

@subsection{Light-Weight Processes}

A simple cooperative multitasking scheduler. Multiple "threads" yield
control with pause and are round-robin scheduled through a queue.

Using @racket[call/cc]:

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

Using @racket[cc]:

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

Using @racket[label] and @racket[goto]:

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

McCarthy's amb operator for nondeterministic programming via
backtracking. The operator explores alternatives depth-first and
backtracks on failure.

Using @racket[call/cc]:

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

Using @racket[cc]:

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

Using @racket[label] and @racket[goto]:

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

All three produce @racket['("that" "thing" "grows" "slowly")].

@subsection{Defining @racket[call/cc]}

@racket[call/cc] can be defined in terms of @racket[cc]:

@racketblock[
(define (call/cc proc [prompt-tag (default-continuation-prompt-tag)])
  (define v* (cc prompt-tag))
  (if (list? v*)
      (apply values v*)
      (proc (λ vs (cc v* vs)))))
]

And in terms of @racket[label] and @racket[goto]:

@racketblock[
(define (call/cc proc [prompt-tag (default-continuation-prompt-tag)])
  (define v* #f)
  (define l (label prompt-tag))
  (if v*
      (apply values v*)
      (proc (λ vs (set! v* vs) (goto l)))))
]
