#lang scribble/manual

@(require (for-label racket/base
                     racket/contract/base
                     racket/function
                     racket/sequence
                     (only-in typed/racket/base
                              : ∀ ∪ → →* case→
                              define-type
                              Nothing
                              Prompt-TagTop)
                     data/queue
                     control/context)
          "utils.rkt")

@title{Evaluation Context}
@defmodule[control/context #:packages ("control-context")]
@author[@author+email["Noah Ma" "noahstorym@gmail.com"]]

@section{Overview}

This package provides @racket[label], @racket[goto], @racket[cc]
(short for @racket[current-continuation]),
@racket[return/cc] (short for @racket[return-with-current-continuation]),
and @racket[absurd],
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

Additionally, the package provides @racket[return/cc], which combines
@racket[cc] and @racket[call/cc] to create @tech{context-frozen thunks}:
continuations of type @racket[(¬ (¬ a))] that, when invoked via
@racket[call/cc], evaluate their body in the @emph{original} evaluation
context (exception handlers, @racket[dynamic-wind] guards,
@racket[parameterize] bindings, etc.) while still reflecting the
@emph{current} variable environment.

@section{API Reference}

@defproc[(absurd) any]{

The @bold{Principle of Explosion} (@italic{ex falso quodlibet}):
from falsehood, anything follows.

It is a function that matches no arguments and therefore cannot be
invoked:

@racketblock[
(: absurd (∀ (b) (→ ⊥ b)))
(define absurd (case-λ))
]

}

@defproc[(label [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any/c]{

Captures the current position in the program and returns
a @racket[Label] value. A subsequent @racket[(goto l)] jumps back to
this point, causing @racket[label] to "return again".

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[call/cc]:

@racketblock[
(: label (→* () (Prompt-TagTop) Label))
(define (label [prompt-tag (default-continuation-prompt-tag)])
  (call/cc goto prompt-tag))
]

Implementation using @racket[cc]:

@racketblock[
(: label (→* () (Prompt-TagTop) Label))
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
(: goto (∀ (a) (case→ (→ Label ⊥) (→ (¬ a) a ⊥))))
(define (goto k [v k]) (k v))
]

Using @racket[cc]:

@racketblock[
(: goto (∀ (a) (case→ (→ Label ⊥) (→ (¬ a) a ⊥))))
(define (goto k [v k]) (cc k v))
]
}

@defproc*[([(current-continuation [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any]
           [(current-continuation [k (-> any/c ... none/c)] [v any/c] ...) none/c])]{

The core operator of this package, combining the Law of Excluded Middle
(@tech{LEM}) and the Law of Noncontradiction (@tech{LNC}) into a single procedure.

@bold{Zero arguments or prompt tag} (@deftech{LEM}):
Captures the current continuation and returns it as a function.
The first time @racket[(current-continuation)] is evaluated, it returns
a continuation of type @racket[(¬ a)] — a function that, when called
with a value of type @racket[a], jumps back to this point, causing
@racket[(current-continuation)] to "return again" with that value.
Thus the overall return type is @racket[(∪ a (¬ a))].

@bold{Continuation and values} (@deftech{LNC}):
Invokes the continuation @racket[k] with the given values @racket[v ...].
This never returns to the caller (return type @racket[⊥]).

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[call/cc]:

@racketblock[
(: current-continuation (∀ (a) (case→ (→* () (Prompt-TagTop) (∪ a (¬ a))) (→ (¬ a) a ⊥))))
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
(: current-continuation (∀ (a) (case→ (→* () (Prompt-TagTop) (∪ a (¬ a))) (→ (¬ a) a ⊥))))
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

@defproc*[([(cc [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)]) any]
           [(cc [k (-> any/c ... none/c)] [v any/c] ...) none/c])]{

An alias for @racket[current-continuation].
}

@defproc[(return-with-current-continuation
          [thk (-> any)]
          [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)])
         (-> (-> any/c ... none/c) none/c)]{

Takes a thunk of type @racket[(→ a)] and returns
a @deftech{context-frozen thunk}—a continuation of type @racket[(¬ (¬ a))]
that captures the current evaluation context.

When the returned continuation is invoked (typically via
@racket[call/cc] as double negation elimination), it jumps back to the
evaluation context where @racket[return/cc] was originally called,
evaluates @racket[thk] there, and delivers the result to the caller's
continuation. This means the computation in @racket[thk] runs with the
@emph{original} exception handlers, @racket[dynamic-wind] guards,
@racket[parameterize] bindings, and other context-sensitive state,
while still reflecting the @emph{current} variable environment.

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[cc]:

@racketblock[
(: return-with-current-continuation (∀ (a) (→* ((→ a)) (Prompt-TagTop) (¬ (¬ a)))))
(define (return-with-current-continuation thk [prompt-tag (default-continuation-prompt-tag)])
  (define first? #t)
  (define k (cc prompt-tag))
  (unless first? (call-with-values thk k))
  (set! first? #f)
  k)
]
}

@defproc[(return/cc
          [thk (-> any)]
          [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)])
         (-> (-> any/c ... none/c) none/c)]{

An alias for @racket[return-with-current-continuation].
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
(let ([kn (call/cc (λ (k) k))])
  (display #\@)
  (let ([kn+1 (call/cc (λ (k) k))])
    (display #\*)
    (kn kn+1)))
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

@subsection{Context-Frozen Thunks}

The @racket[return/cc] operator creates @tech{context-frozen thunks}:
computations that evaluate their body in the evaluation context where
they were @emph{defined}, not where they are @emph{called}. This
freezes exception handlers, @racket[dynamic-wind] guards,
@racket[parameterize] bindings, and other context-sensitive state,
while ordinary mutable variables remain live.

@subsubsection{Freezing @racket[parameterize] Bindings}

A plain thunk evaluates in the caller's parameter context, but
a @tech{context-frozen thunk} always evaluates in its birth context:

@racketblock[
(define a (make-parameter 1))
(define b 111)
(define f (return/cc (λ () (* (a) b))))
(displayln (call/cc f))
(code:comment "=> 111  (a=1, b=111)")
(set! b 222)
(displayln (call/cc f))
(code:comment "=> 222  (a=1, b=222 — variable change is visible)")
(parameterize ([a 2])
  (displayln (call/cc f)))
(code:comment "=> 222  (a=1, b=222 — parameterize at call site is invisible)")
]

Contrast with a plain thunk, which would yield @racket[444] in the
last case because @racket[(a)] would be @racket[2].

@subsubsection{Freezing Exception Handlers}

The body of a @racket[return/cc] thunk runs under the exception
handlers that were active at definition time, regardless of what
handlers are active at the call site:

@racketblock[
(define f
  (with-handlers ([exn:fail? (λ (e) (error "caught at birth"))])
    (return/cc (λ () (error "boom")))))

(code:comment "Calling from a context with a different handler:")
(with-handlers ([exn:fail? (λ (e) (error "caught at call site"))])
  (displayln (call/cc f)))
(code:comment "=> \"caught at birth\"  (call-site handler is bypassed)")
]

@subsubsection{Freezing @racket[dynamic-wind] Guards}

Entry and exit guards from the definition context are re-entered
when the frozen thunk is invoked:

@racketblock[
(define f
  (dynamic-wind
    (λ () (displayln "[Entry] enter birth context"))
    (λ () (return/cc (λ () (displayln "[Body] evaluate thunk"))))
    (λ () (displayln "[Exit] leave birth context"))))

(displayln "--- call ---")
(call/cc f)
(displayln "--- done ---")
(code:comment "Output:")
(code:comment "[Entry] enter birth context")
(code:comment "[Exit] leave birth context")
(code:comment "--- call ---")
(code:comment "[Entry] enter birth context")
(code:comment "[Body] evaluate thunk")
(code:comment "[Exit] leave birth context")
(code:comment "--- done ---")
]
