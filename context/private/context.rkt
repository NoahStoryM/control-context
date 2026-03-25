#lang racket/base

(provide goto label current-continuation)


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
       [(procedure? p)
        (raise-result-error 'current-continuation "none/c" (p))]
       [else
        (raise-argument-error 'current-continuation "(or/c continuation-prompt-tag? (-> any/c none/c))" p)])]
    [(k v1      ) (raise-result-error 'current-continuation "none/c" (k v1      ))]
    [(k v1 v2   ) (raise-result-error 'current-continuation "none/c" (k v1 v2   ))]
    [(k v1 v2 v3) (raise-result-error 'current-continuation "none/c" (k v1 v2 v3))]
    [(k . v*    ) (raise-result-error 'current-continuation "none/c" (apply k v*))]))
