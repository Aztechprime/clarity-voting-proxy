;; Voting Proxy Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-already-delegated (err u101))
(define-constant err-no-delegation (err u102))
(define-constant err-invalid-proposal (err u103))

;; Data Variables
(define-map delegations principal principal)
(define-map proposals uint {
    title: (string-ascii 50),
    votes-for: uint,
    votes-against: uint,
    active: bool
})
(define-data-var proposal-count uint u0)

;; Private Functions
(define-private (is-authorized (voter principal))
    (or 
        (is-eq tx-sender voter)
        (is-eq tx-sender (default-to tx-sender (map-get? delegations voter)))
    )
)

;; Public Functions
(define-public (delegate-vote (to principal))
    (let ((current-delegation (map-get? delegations tx-sender)))
        (if (is-none current-delegation)
            (begin
                (map-set delegations tx-sender to)
                (ok true))
            err-already-delegated
        )
    )
)

(define-public (revoke-delegation)
    (let ((current-delegation (map-get? delegations tx-sender)))
        (if (is-some current-delegation)
            (begin
                (map-delete delegations tx-sender)
                (ok true))
            err-no-delegation
        )
    )
)

(define-public (create-proposal (title (string-ascii 50)))
    (if (is-eq tx-sender contract-owner)
        (let ((id (var-get proposal-count)))
            (map-set proposals id {
                title: title,
                votes-for: u0,
                votes-against: u0,
                active: true
            })
            (var-set proposal-count (+ id u1))
            (ok id))
        err-not-authorized
    )
)

(define-public (vote (proposal-id uint) (vote-for bool))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) err-invalid-proposal))
    )
        (if (and 
                (get active proposal)
                (is-authorized tx-sender)
            )
            (begin
                (if vote-for
                    (map-set proposals proposal-id 
                        (merge proposal { votes-for: (+ (get votes-for proposal) u1) }))
                    (map-set proposals proposal-id 
                        (merge proposal { votes-against: (+ (get votes-against proposal) u1) }))
                )
                (ok true))
            err-not-authorized
        )
    )
)

;; Read-only Functions
(define-read-only (get-delegate (voter principal))
    (ok (map-get? delegations voter))
)

(define-read-only (get-proposal (proposal-id uint))
    (ok (map-get? proposals proposal-id))
)
