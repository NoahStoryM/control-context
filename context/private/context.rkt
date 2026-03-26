#lang racket/base

(require racket/format racket/string)

(provide absurd
         goto label
         current-continuation
         wait-for-future-continuation
         return-with-current-continuation
         return-with-values)


(define expected:none/c (unquoted-printing-string "none/c"))
(define ((make-raise-results-error name) . v*)
  (raise-arguments-error
   name
   "contract violation"
   "expected" expected:none/c
   "results" (unquoted-printing-string (string-join (map ~v v*) "\n"))))
(define raise-results-error:goto (make-raise-results-error 'goto))
(define raise-results-error:cc (make-raise-results-error 'current-continuation))


(define absurd (case-λ))

(define (goto k [v k])
  (if (procedure? k)
      (call-with-values (λ () (k v)) raise-results-error:goto)
      (raise-argument-error 'goto "(-> any/c none/c)" k)))
(define (label [prompt-tag (default-continuation-prompt-tag)])
  (unless (continuation-prompt-tag? prompt-tag)
    (raise-argument-error 'label "continuation-prompt-tag?" prompt-tag))
  (call/cc values prompt-tag))

(define current-continuation
  (case-λ
    [() (call/cc values)]
    [(p)
     (cond
       [(continuation-prompt-tag? p)
        (call/cc values p)]
       [(and (procedure? p) (procedure-arity-includes? p 0))
        (call-with-values p raise-results-error:cc)]
       [else
        (raise-argument-error 'current-continuation "(or/c continuation-prompt-tag? (-> none/c))" p)])]
    [(k v1      ) (call-with-values (λ () (k v1      )) raise-results-error:cc)]
    [(k v1 v2   ) (call-with-values (λ () (k v1 v2   )) raise-results-error:cc)]
    [(k v1 v2 v3) (call-with-values (λ () (k v1 v2 v3)) raise-results-error:cc)]
    [(k . v*    ) (call-with-values (λ () (apply k v*)) raise-results-error:cc)]))

(define (wait-for-future-continuation proc [prompt-tag (default-continuation-prompt-tag)])
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'wait-for-future-continuation "(-> (-> any/c ... none/c) any)" proc))
  (unless (continuation-prompt-tag? prompt-tag)
    (raise-argument-error 'wait-for-future-continuation "continuation-prompt-tag?" prompt-tag))
  (define first? #t)
  (define k (call/cc values prompt-tag))
  (unless first? (call-with-values (λ () (proc k)) k))
  (set! first? #f)
  k)
(define (return-with-current-continuation thk [prompt-tag (default-continuation-prompt-tag)])
  (unless (and (procedure? thk) (procedure-arity-includes? thk 0))
    (raise-argument-error 'return-with-current-continuation "(-> any)" thk))
  (unless (continuation-prompt-tag? prompt-tag)
    (raise-argument-error 'return-with-current-continuation "continuation-prompt-tag?" prompt-tag))
  (define first? #t)
  (define k (call/cc values prompt-tag))
  (unless first? (call-with-values thk k))
  (set! first? #f)
  k)
(define (return-with-values . v*) (λ (k) (apply k v*)))
