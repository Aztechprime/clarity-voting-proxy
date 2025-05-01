;; Define a trait for executable proposals
(define-trait proposal-trait
  (
    ;; Function that will be called when a proposal is executed
    ;; Takes proposal-id as parameter and returns a response
    (execute (uint) (response bool uint))
  )
) 