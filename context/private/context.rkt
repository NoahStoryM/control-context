#lang racket/base

(provide absurd
         goto label
         current-continuation
         return-with-current-continuation)


(define absurd (case-λ))

(define (goto k [v k])
  (if (procedure? k)
      (raise-result-error 'goto "none/c" (k v))
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
        (raise-result-error 'current-continuation "none/c" (p))]
       [else
        (raise-argument-error 'current-continuation "(or/c continuation-prompt-tag? (-> none/c))" p)])]
    [(k v1      ) (raise-result-error 'current-continuation "none/c" (k v1      ))]
    [(k v1 v2   ) (raise-result-error 'current-continuation "none/c" (k v1 v2   ))]
    [(k v1 v2 v3) (raise-result-error 'current-continuation "none/c" (k v1 v2 v3))]
    [(k . v*    ) (raise-result-error 'current-continuation "none/c" (apply k v*))]))

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
