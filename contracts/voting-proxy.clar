;; Enhanced Voting Proxy Contract
;; A secure and flexible voting delegation and proposal management system
;; Features:
;; - Secure delegation mechanism
;; - Proposal lifecycle management
;; - Robust access controls
;; - Comprehensive tracking of voting power

;; Error Constants
(define-constant ERR_NOT_AUTHORIZED u100)
(define-constant ERR_ALREADY_DELEGATED u101)
(define-constant ERR_NO_DELEGATION u102)
(define-constant ERR_INVALID_PROPOSAL u103)
(define-constant ERR_PROPOSAL_EXPIRED u104)
(define-constant ERR_SELF_DELEGATION u105)
(define-constant ERR_DUPLICATE_VOTE u106)

;; Configuration Constants
(define-constant CONTRACT_OWNER tx-sender) ;; Contract Owner
(define-constant PROPOSAL_EXPIRATION_PERIOD u86400) ;; 24 hours in seconds
(define-constant MAX_PROPOSAL_TITLE_LENGTH u50)
(define-constant MAX_VOTING_POWER u1000000)

;; Data Structures
(define-map delegations 
    {
        voter: principal,        ;; Original voter
        delegate: principal      ;; Delegated principal
    }
    {
        delegation-time: uint,   ;; Timestamp of delegation
        vote-power: uint         ;; Delegated voting power
    }
)

(define-map proposals 
    uint
    {
        title: (string-ascii 50),
        creator: principal,       ;; Proposal creator
        votes-for: uint,
        votes-against: uint,
        total-vote-power: uint,   ;; Total voting power used
        max-vote-power: uint,     ;; Maximum possible vote power
        created-at: uint,         ;; Proposal creation timestamp
        active: bool,
        expires-at: uint          ;; Proposal expiration timestamp
    }
)

(define-data-var proposal-count uint u0)
(define-map voting-records 
    {
        voter: principal, 
        proposal-id: uint
    } 
    bool
)

;; Private Utility Functions
(define-private (is-valid-delegation (voter principal) (delegate principal))
    (and 
        (not (is-eq voter delegate))  ;; Prevent self-delegation
        (is-some (some delegate))     ;; Ensure valid delegate
    )
)

(define-private (is-proposal-active (proposal-id uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) false)))
        (and 
            (get active proposal)
            (< block-height (get expires-at proposal))
        )
    )
)

(define-private (is-authorized (voter principal))
    (or 
        (is-eq tx-sender voter)
        (is-some 
            (map-get? delegations 
                { 
                    voter: voter, 
                    delegate: tx-sender 
                }
            )
        )
    )
)

;; Public Functions for Delegation
(define-public (delegate-vote (to principal))
    (begin
        ;; Validate delegation parameters
        (asserts! (is-valid-delegation tx-sender to) (err ERR_SELF_DELEGATION))
        
        ;; Check for existing delegation
        (match (map-get? delegations { voter: tx-sender, delegate: to })
            existing-delegation 
                (err ERR_ALREADY_DELEGATED)
            
            ;; New delegation
            (begin
                (map-set delegations 
                    { voter: tx-sender, delegate: to }
                    {
                        delegation-time: block-height,
                        vote-power: u1  ;; Default voting power
                    }
                )
                (ok true)
            )
        )
    )
)

(define-public (revoke-delegation)
    (match (map-get? delegations { voter: tx-sender, delegate: contract-caller })
        delegation
        (begin
            (map-delete delegations { voter: tx-sender, delegate: contract-caller })
            (ok true)
        )
        (err ERR_NO_DELEGATION)
    )
)

;; Proposal Management
(define-public (create-proposal 
    (title (string-ascii 50)) 
    (expiration-blocks uint)
)
    (begin
        ;; Authorization and input validation
        (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR_NOT_AUTHORIZED))
        (asserts! (<= (len title) MAX_PROPOSAL_TITLE_LENGTH) (err ERR_INVALID_PROPOSAL))
        
        (let ((id (var-get proposal-count)))
            (map-set proposals id {
                title: title,
                creator: tx-sender,
                votes-for: u0,
                votes-against: u0,
                total-vote-power: u0,
                max-vote-power: MAX_VOTING_POWER,
                created-at: block-height,
                active: true,
                expires-at: (+ block-height expiration-blocks)
            })
            (var-set proposal-count (+ id u1))
            (ok id)
        )
    )
)

(define-public (vote (proposal-id uint) (vote-for bool))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) (err ERR_INVALID_PROPOSAL)))
        (voter tx-sender)
    )
        ;; Comprehensive validation
        (asserts! (is-proposal-active proposal-id) (err ERR_PROPOSAL_EXPIRED))
        (asserts! (is-authorized voter) (err ERR_NOT_AUTHORIZED))
        
        ;; Prevent duplicate voting
        (asserts! 
            (is-none (map-get? voting-records { voter: voter, proposal-id: proposal-id })) 
            (err ERR_DUPLICATE_VOTE)
        )
        
        (let ((current-vote-power u1))  ;; Base voting power
            (if vote-for
                (map-set proposals proposal-id 
                    (merge proposal { 
                        votes-for: (+ (get votes-for proposal) current-vote-power),
                        total-vote-power: (+ (get total-vote-power proposal) current-vote-power)
                    })
                )
                (map-set proposals proposal-id 
                    (merge proposal { 
                        votes-against: (+ (get votes-against proposal) current-vote-power),
                        total-vote-power: (+ (get total-vote-power proposal) current-vote-power)
                    })
                )
            )
            
            ;; Record voting participation
            (map-set voting-records 
                { voter: voter, proposal-id: proposal-id } 
                true
            )
            (print { event: "voting-record", voter: voter, proposal-id: proposal-id }) ;; Add logging for traceability
            
            (ok true)
        )
    )
)

;; Read-only Functions
(define-read-only (get-delegation-details (voter principal))
    (map-get? delegations { voter: voter, delegate: contract-caller })
)

(define-read-only (get-proposal-summary (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (calculate-total-voting-power (proposal-id uint))
    (let ((proposal (map-get? proposals proposal-id)))
        (match proposal
            p (ok (get total-vote-power p))
            (err ERR_INVALID_PROPOSAL)
        )
    )
)
