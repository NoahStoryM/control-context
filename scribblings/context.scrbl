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

This package provides @racket[label], @racket[goto], and @racket[cc]
(short for @racket[current-continuation]), which are simpler, more
direct alternatives to @racket[call/cc].

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

Additionally, the package provides three operators for constructing
@tech{context-frozen thunks}—values of type @racket[(¬ (¬ a))] that
freeze the current evaluation context and can later be triggered via
@racket[call/cc] as double negation elimination:

@itemlist[
  @item{@racket[wait/fc] is the core primitive. It captures the current
  evaluation context and hands a @emph{future} continuation—one that
  does not yet exist at capture time—to a user-supplied function
  @racket[proc]. Whatever @racket[proc] returns is delivered to that
  future continuation. When @racket[proc] itself has type
  @racket[(¬ (¬ a))], @racket[wait/fc] has type @racket[(¬ (¬ a)) → (¬ (¬ a))],
  making frozen contexts directly composable.}

  @item{@racket[return/cc] is @racket[wait/fc] specialized to plain
  thunks: it ignores the future continuation and simply evaluates
  @racket[thk] in the captured context, delivering the result
  automatically.}

  @item{@racket[return-with-values] is the trivial, purely functional
  @deftech{Double Negation Introduction} (DNI): it wraps values of type
  @racket[a] into a function of type @racket[(¬ (¬ a))] without
  capturing any evaluation context. No continuations, no side effects.}
]

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

@defproc[(wait-for-future-continuation
          [proc (-> (-> any/c ... none/c) any)]
          [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)])
         (-> (-> any/c ... none/c) none/c)]{

The core operator for constructing @tech{context-frozen thunks}.

Takes a function @racket[proc] of type @racket[(→ (¬ a) a)] and
captures the current evaluation context, returning a
@tech{context-frozen thunk} of type @racket[(¬ (¬ a))].

When the returned @tech{context-frozen thunk} is invoked with a continuation
@racket[k] (typically via @racket[call/cc] as double negation elimination),
control jumps back to the evaluation context where @racket[wait/fc] was
originally called. There, @racket[proc] is called with @racket[k] as
the @emph{future continuation}—a continuation that did not yet exist
when @racket[wait/fc] was evaluated. Whatever @racket[proc] returns is
delivered to @racket[k] via @racket[call-with-values].

This means the computation in @racket[proc] runs with the @emph{original}
exception handlers, @racket[dynamic-wind] guards, @racket[parameterize]
bindings, and other context-sensitive state, while still reflecting the
@emph{current} variable environment.

When @racket[proc] always invokes @racket[k] (i.e., @racket[proc] has
type @racket[(¬ (¬ a))]), the type of @racket[wait/fc] becomes
@racket[(→ (¬ (¬ a)) (¬ (¬ a)))], making frozen contexts directly
@bold{composable}: the output of one @racket[wait/fc] call can serve
as the @racket[proc] argument of another.

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[cc]:

@racketblock[
(: wait/fc (∀ (a) (→* ((→ (¬ a) a)) (Prompt-TagTop) (¬ (¬ a)))))
(define (wait/fc proc [prompt-tag (default-continuation-prompt-tag)])
  (define first? #t)
  (define k (cc prompt-tag))
  (unless first? (call-with-values (λ () (proc k)) k))
  (set! first? #f)
  k)
]
}

@defproc[(wait/fc
          [proc (-> (-> any/c ... none/c) any)]
          [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)])
         (-> (-> any/c ... none/c) none/c)]{

An alias for @racket[wait-for-future-continuation].
}

@defproc[(return-with-current-continuation
          [thk (-> any)]
          [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)])
         (-> (-> any/c ... none/c) none/c)]{

Takes a thunk of type @racket[(→ a)] and returns
a @deftech{context-frozen thunk}—a continuation of type @racket[(¬ (¬ a))]
that captures the current evaluation context.

@racket[return/cc] is @racket[wait/fc] specialized to the case where
the body is a plain thunk @racket[thk]. The future continuation is
ignored. For cases where the body needs access to the future
continuation—for example, to compose frozen contexts—use
@racket[wait/fc] directly.

The optional @racket[prompt-tag] argument specifies which continuation
prompt to capture up to, defaulting to
@racket[(default-continuation-prompt-tag)].

Implementation using @racket[wait/fc]:

@racketblock[
(: return/cc (∀ (a) (→* ((→ a)) (Prompt-TagTop) (¬ (¬ a)))))
(define (return/cc thk [prompt-tag (default-continuation-prompt-tag)])
  (wait/fc (λ (_) (thk)) prompt-tag))
]
}

@defproc[(return/cc
          [thk (-> any)]
          [prompt-tag continuation-prompt-tag? (default-continuation-prompt-tag)])
         (-> (-> any/c ... none/c) none/c)]{

An alias for @racket[return-with-current-continuation].
}

@defproc[(return-with-values [v any/c] ...) (-> (-> any/c ... none/c) none/c)]{

The purely functional @tech{Double Negation Introduction} (DNI).

Takes any number of values and returns a @tech{context-frozen thunk}
of type @racket[(¬ (¬ a))] that, when invoked with a continuation
@racket[k],simply delivers those values to @racket[k]. No continuation
is captured; no evaluation context is frozen.

@racketblock[
(: return-with-values (∀ (a) (→ a (¬ (¬ a)))))
(define (return-with-values . v*) (λ (k) (apply k v*)))
]

This is the logical fact that from @racket[a] we can always derive
@racket[(¬ (¬ a))]: given a value, we can always construct a
@tech{context-frozen thunk} that produces it, trivially, with no
context to freeze. Compare with @racket[wait/fc] and @racket[return/cc],
which do capture an evaluation context.
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

The @racket[wait/fc] operator creates @tech{context-frozen thunks}:
computations that run in the evaluation context where they were
@emph{defined}, not where they are @emph{called}. This freezes
exception handlers, @racket[dynamic-wind] guards, @racket[parameterize]
bindings, and other context-sensitive state, while ordinary mutable
variables remain live. @racket[return/cc] is the specialization of
@racket[wait/fc] to plain thunks. @racket[return-with-values] is the
degenerate case where no context is frozen at all.

@subsubsection{Freezing @racket[parameterize] Bindings}

A plain thunk evaluates in the caller's parameter context. A
@tech{context-frozen thunk} always evaluates in its birth context,
regardless of what @racket[parameterize] bindings are active at the
call site. With @racket[wait/fc], the future continuation is available
to @racket[proc], which decides what value to return:

@racketblock[
(define a (make-parameter 1))
(define b 111)
(define f (wait/fc (λ (_) (* (a) b))))
(displayln (call/cc f))
(code:comment "=> 111  (a=1, b=111)")
(set! b 222)
(displayln (call/cc f))
(code:comment "=> 222  (a=1, b=222 — variable change is visible)")
(parameterize ([a 2])
  (displayln (call/cc f)))
(code:comment "=> 222  (a=1, b=222 — parameterize at call site is invisible)")
]

Contrast with a plain thunk, which would yield @racket[444] in the last
case because @racket[(a)] would be @racket[2]. Also contrast with
@racket[return-with-values], which captures no context at all:

@racketblock[
(define g (return-with-values 42))
(parameterize ([a 99]) (displayln (call/cc g)))
(code:comment "=> 42  (no context frozen — the value was fixed at construction)")
]

@subsubsection{Freezing Exception Handlers}

The body of a @tech{context-frozen thunk} runs under the exception
handlers that were active at definition time, regardless of what
handlers are active at the call site:

@racketblock[
(define f
  (with-handlers ([exn:fail? (λ (e) (error "caught at birth"))])
    (wait/fc (λ (k) (error "boom")))))

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
    (λ () (wait/fc (λ (k) (displayln "[Body] evaluate thunk"))))
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

@subsubsection{Composing Frozen Contexts}

Since @racket[wait/fc] exposes the future continuation to @racket[proc],
frozen contexts can be @bold{composed}: when @racket[proc] has type
@racket[(¬ (¬ a))], @racket[wait/fc] has type @racket[(¬ (¬ a)) → (¬ (¬ a))],
so the output of one @racket[wait/fc] can serve directly as the
@racket[proc] argument of another.

The future continuation passes through each frozen layer
in sequence—like a relay baton—with each layer's @racket[dynamic-wind]
guards firing as control enters and exits:

@racketblock[
(code:comment "Time 1: In context C1, create W1")
(define W1
  (dynamic-wind
    (λ () (displayln "W1: Enter"))
    (λ () (wait/fc
           (λ (fc)
             (displayln "Reached the innermost context C1")
             (fc 'hello))))
    (λ () (displayln "W1: Exit"))))

(code:comment "Time 2: In context C2, wrap W1 in another layer")
(define W2
  (dynamic-wind
    (λ () (displayln "W2: Enter"))
    (λ () (wait/fc W1))
    (λ () (displayln "W2: Exit"))))

(code:comment "Time 3: In context C3, trigger W2")
(dynamic-wind
  (λ () (displayln "W3: Enter"))
  (λ () (displayln (call/cc W2)))
  (λ () (displayln "W3: Exit")))
]

Output:

@racketblock[
(code:comment "W1: Enter")
(code:comment "W1: Exit")
(code:comment "W2: Enter")
(code:comment "W2: Exit")
(code:comment "W3: Enter")
(code:comment "W3: Exit")
(code:comment "W2: Enter")
(code:comment "W2: Exit")
(code:comment "W1: Enter")
(code:comment "Reached the innermost context C1")
(code:comment "W1: Exit")
(code:comment "W3: Enter")
(code:comment "hello")
(code:comment "W3: Exit")
]

When @racket[(call/cc W2)] is invoked in C3, the future continuation
is delivered first to C2's frozen context, which forwards it to C1's
frozen context via @racket[W1]. The innermost @racket[proc] finally
receives the continuation and calls @racket[(fc 'hello)], sending
@racket['hello] all the way back to C3.
