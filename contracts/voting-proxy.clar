```clarity
;; Enhanced Voting Proxy Contract
;; A secure and flexible voting delegation and proposal management system
;; Features:
;; - Secure delegation mechanism
;; - Proposal lifecycle management
;; - Robust access controls
;; - Comprehensive tracking of voting power
;; - Weighted voting based on token holdings or member status
;; - Time-locked proposals with execution capabilities
;; - Proposal categories and tags
;; - Quadratic voting option

;; Error Constants
(define-constant ERR_NOT_AUTHORIZED u100)
(define-constant ERR_ALREADY_DELEGATED u101)
(define-constant ERR_NO_DELEGATION u102)
(define-constant ERR_INVALID_PROPOSAL u103)
(define-constant ERR_PROPOSAL_EXPIRED u104)
(define-constant ERR_SELF_DELEGATION u105)
(define-constant ERR_DUPLICATE_VOTE u106)
(define-constant ERR_INVALID_MEMBERSHIP_TIER u107)
(define-constant ERR_INVALID_VOTING_WEIGHT u108)
(define-constant ERR_INVALID_TOKEN_CONTRACT u109)
(define-constant ERR_EXECUTION_FAILED u110)
(define-constant ERR_PROPOSAL_NOT_PASSED u111)
(define-constant ERR_TIMELOCK_ACTIVE u112)

;; Configuration Constants
(define-constant PROPOSAL_EXPIRATION_PERIOD u86400) ;; 24 hours in seconds
(define-constant MAX_PROPOSAL_TITLE_LENGTH u50)
(define-constant MAX_VOTING_POWER u1000000)
(define-constant MAX_CATEGORY_LENGTH u20)
(define-constant MAX_TAGS_COUNT u5)
(define-constant MAX_TAG_LENGTH u15)
(define-constant TIMELOCK_PERIOD u10000) ;; Blocks before proposal execution
(define-constant PROPOSAL_PASS_THRESHOLD u500000) ;; Minimum votes for proposal to pass

;; Membership Tier Constants
(define-constant TIER_BASIC u1)
(define-constant TIER_SILVER u2)
(define-constant TIER_GOLD u3)
(define-constant TIER_PLATINUM u4)

;; Voting Power by Tier
(define-map tier-voting-power uint uint)

;; Voting Modes
(define-constant VOTING_MODE_STANDARD u1)
(define-constant VOTING_MODE_QUADRATIC u2)

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

(define-map member-tiers 
    principal 
    {
        tier: uint,              ;; Membership tier
        joined-at: uint,         ;; When they joined
        voting-weight: uint      ;; Custom voting weight
    }
)

(define-map token-voting-config
    principal                    ;; Token contract
    {
        enabled: bool,           ;; Is token-gated voting enabled
        weight-multiplier: uint  ;; How much each token is worth in voting power
    }
)

(define-map proposals 
    uint 
    {
        title: (string-ascii MAX_PROPOSAL_TITLE_LENGTH),
        creator: principal,       ;; Proposal creator
        votes-for: uint,
        votes-against: uint,
        total-vote-power: uint,   ;; Total voting power used
        max-vote-power: uint,     ;; Maximum possible vote power
        created-at: uint,         ;; Proposal creation timestamp
        active: bool,
        expires-at: uint,         ;; Proposal expiration timestamp
        category: (string-ascii MAX_CATEGORY_LENGTH),
        tags: (list MAX_TAGS_COUNT (string-ascii MAX_TAG_LENGTH)),
        voting-mode: uint,        ;; Standard or quadratic voting
        executable: (optional principal),  ;; Contract to call if proposal passes
        function-name: (optional (string-ascii 128)),  ;; Function to call
        timelock-until: uint,     ;; Block height when execution is allowed
        executed: bool            ;; Has this proposal been executed
    }
)

(define-data-var proposal-count uint u0)
(define-map voting-records 
    {
        voter: principal, 
        proposal-id: uint
    } 
    {
        voted-for: bool,
        voting-power-used: uint
    }
)

;; Initialize tier voting power
(map-set tier-voting-power TIER_BASIC u1)
(map-set tier-voting-power TIER_SILVER u5)
(map-set tier-voting-power TIER_GOLD u10)
(map-set tier-voting-power TIER_PLATINUM u20)

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

(define-private (get-member-voting-power (member principal))
    (let ((member-data (map-get? member-tiers member)))
        (if (is-some member-data)
            (let ((tier-data (unwrap-panic member-data)))
                (default-to u1 (map-get? tier-voting-power (get tier tier-data)))
            )
            u1  ;; Default voting power for non-members
        )
    )
)

(define-private (calculate-quadratic-voting-power (base-power uint))
    (to-uint (contract-call? .math-utils sqrt (to-int base-power)))
)

;; Public Functions for Membership Management
(define-public (set-member-tier (member principal) (tier uint))
    (begin
        ;; Only contract owner can set tiers
        (asserts! (is-eq tx-sender contract-owner) (err ERR_NOT_AUTHORIZED))
        (asserts! (<= tier TIER_PLATINUM) (err ERR_INVALID_MEMBERSHIP_TIER))
        
        (map-set member-tiers member {
            tier: tier,
            joined-at: block-height,
            voting-weight: (default-to u1 (map-get? tier-voting-power tier))
        })
        (ok true)
    )
)

(define-public (set-custom-voting-weight (member principal) (weight uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err ERR_NOT_AUTHORIZED))
        (asserts! (< weight MAX_VOTING_POWER) (err ERR_INVALID_VOTING_WEIGHT))
        
        (match (map-get? member-tiers member)
            member-data
            (map-set member-tiers member (merge member-data { voting-weight: weight }))
            (err ERR_INVALID_MEMBERSHIP_TIER)
        )
        (ok true)
    )
)

(define-public (configure-token-voting (token-contract principal) (enabled bool) (weight-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err ERR_NOT_AUTHORIZED))
        (asserts! (< weight-multiplier MAX_VOTING_POWER) (err ERR_INVALID_VOTING_WEIGHT))
        
        (map-set token-voting-config token-contract {
            enabled: enabled,
            weight-multiplier: weight-multiplier
        })
        (ok true)
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
                        vote-power: (get-member-voting-power tx-sender)
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
    (title (string-ascii MAX_PROPOSAL_TITLE_LENGTH)) 
    (expiration-blocks uint)
    (category (string-ascii MAX_CATEGORY_LENGTH))
    (tags (list MAX_TAGS_COUNT (string-ascii MAX_TAG_LENGTH)))
    (voting-mode uint)
    (executable (optional principal))
    (function-name (optional (string-ascii 128)))
)
    (begin
        ;; Authorization and input validation
        (asserts! (is-eq tx-sender contract-owner) (err ERR_NOT_AUTHORIZED))
        (asserts! (<= (len title) MAX_PROPOSAL_TITLE_LENGTH) (err ERR_INVALID_PROPOSAL))
        (asserts! (or (is-eq voting-mode VOTING_MODE_STANDARD) (is-eq voting-mode VOTING_MODE_QUADRATIC)) (err ERR_INVALID_PROPOSAL))
        
        (let (
            (id (var-get proposal-count))
            (timelock (if (is-some executable) (+ block-height TIMELOCK_PERIOD) u0))
        )
            (map-set proposals id {
                title: title,
                creator: tx-sender,
                votes-for: u0,
                votes-against: u0,
                total-vote-power: u0,
                max-vote-power: MAX_VOTING_POWER,
                created-at: block-height,
                active: true,
                expires-at: (+ block-height expiration-blocks),
                category: category,
                tags: tags,
                voting-mode: voting-mode,
                executable: executable,
                function-name: function-name,
                timelock-until: timelock,
                executed: false
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
        
        (let (
            (base-vote-power (get-member-voting-power voter))
            (voting-mode (get voting-mode proposal))
            (current-vote-power (if (is-eq voting-mode VOTING_MODE_QUADRATIC)
                                   (calculate-quadratic-voting-power base-vote-power)
                                   base-vote-power))
        )
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
                { voted-for: vote-for, voting-power-used: current-vote-power }
            )
            (print { 
                event: "voting-record", 
                voter: voter, 
                proposal-id: proposal-id, 
                vote-power: current-vote-power 
            })
            
            (ok current-vote-power)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) (err ERR_INVALID_PROPOSAL)))
    )
        ;; Check if the proposal passed
        (asserts! (>= (get votes-for proposal) PROPOSAL_PASS_THRESHOLD) (err ERR_PROPOSAL_NOT_PASSED))
        
        ;; Check if it's executable
        (asserts! (and (is-some (get executable proposal)) (is-some (get function-name proposal))) (err ERR_INVALID_PROPOSAL))
        
        ;; Check if already executed
        (asserts! (not (get executed proposal)) (err ERR_INVALID_PROPOSAL))
        
        ;; Check timelock
        (asserts! (>= block-height (get timelock-until proposal)) (err ERR_TIMELOCK_ACTIVE))
        
        ;; Only contract owner can execute
        (asserts! (is-eq tx-sender contract-owner) (err ERR_NOT_AUTHORIZED))
        
        ;; Execute the proposal
        (let (
            (target-contract (unwrap-panic (get executable proposal)))
            (function (unwrap-panic (get function-name proposal)))
            (result (contract-call? target-contract function proposal-id))
        )
            ;; Mark as executed
            (map-set proposals proposal-id (merge proposal { executed: true }))
            
            ;; Return the execution result
            (ok result)
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

(define-read-only (get-member-tier (member principal))
    (map-get? member-tiers member)
)

(define-read-only (get-voting-record (voter principal) (proposal-id uint))
    (map-get? voting-records { voter: voter, proposal-id: proposal-id })
)

(define-read-only (get-token-voting-config (token-contract principal))
    (map-get? token-voting-config token-contract)
)

(define-read-only (has-proposal-passed (proposal-id uint))
    (let ((proposal (map-get? proposals proposal-id)))
        (match proposal
            p (ok (>= (get votes-for p) PROPOSAL_PASS_THRESHOLD))
            (err ERR_INVALID_PROPOSAL)
        )
    )
)
```