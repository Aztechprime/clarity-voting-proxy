;; membership-registry
;; A contract to manage member tiers and associated voting rights in a decentralized governance system.
;; This contract allows for the creation of different membership tiers with configurable voting power,
;; and supports member management across these tiers.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-MEMBER-EXISTS (err u101))
(define-constant ERR-MEMBER-NOT-FOUND (err u102))
(define-constant ERR-TIER-EXISTS (err u103))
(define-constant ERR-TIER-NOT-FOUND (err u104))
(define-constant ERR-INVALID-MULTIPLIER (err u105))
(define-constant ERR-INVALID-TIER-NAME (err u106))

;; Data space definitions

;; Contract owner who has administrative privileges
(define-data-var contract-owner principal tx-sender)

;; Tier structure: defines membership levels and their voting power multipliers
(define-map tiers
  { tier-name: (string-ascii 20) }  ;; Key: tier name (e.g., "Core", "Contributor", "Community")
  { 
    voting-power-multiplier: uint,  ;; Voting power multiplier for members in this tier
    active: bool                    ;; Whether this tier is currently active
  }
)

;; Member structure: stores member information and their current tier
(define-map members
  { address: principal }            ;; Key: member's wallet address
  {
    tier-name: (string-ascii 20),   ;; Current membership tier
    join-height: uint,              ;; Block height when the member joined
    last-tier-change: uint,         ;; Block height of last tier change
    active: bool                    ;; Whether this member is currently active
  }
)

;; Member history: tracks changes to a member's status over time
(define-map member-history
  { 
    address: principal,
    action-height: uint
  }
  {
    action-type: (string-ascii 20), ;; Type of action (e.g., "join", "promote", "demote", "suspend")
    previous-tier: (string-ascii 20),
    new-tier: (string-ascii 20),
    initiated-by: principal
  }
)

;; Total count of members per tier
(define-map tier-member-counts
  { tier-name: (string-ascii 20) }
  { count: uint }
)

;; Total members in the registry
(define-data-var total-members uint u0)

;; Private functions

;; Add or update a historical record for a member
(define-private (add-member-history 
                  (member-address principal) 
                  (action-type (string-ascii 20))
                  (previous-tier (string-ascii 20))
                  (new-tier (string-ascii 20)))
  (map-insert member-history
    { address: member-address, action-height: block-height }
    {
      action-type: action-type,
      previous-tier: previous-tier,
      new-tier: new-tier,
      initiated-by: tx-sender
    }
  )
)

;; Update the count of members in a tier
(define-private (update-tier-count 
                  (tier-name (string-ascii 20)) 
                  (delta int))
  (let ((current-count (default-to u0 (get count (map-get? tier-member-counts { tier-name: tier-name })))))
    (map-set tier-member-counts
      { tier-name: tier-name }
      { count: (if (< delta i0)
                   (if (> (to-uint (abs delta)) current-count) 
                       u0 
                       (- current-count (to-uint (abs delta))))
                   (+ current-count (to-uint delta))) }
    )
  )
)

;; Check if sender is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Read-only functions

;; Get information about a specific tier
(define-read-only (get-tier-info (tier-name (string-ascii 20)))
  (map-get? tiers { tier-name: tier-name })
)

;; Get information about a specific member
(define-read-only (get-member-info (member-address principal))
  (map-get? members { address: member-address })
)

;; Check if an address is a registered member
(define-read-only (is-member (address principal))
  (match (map-get? members { address: address })
    member (get active member)
    false
  )
)

;; Get the voting power for a specific member
(define-read-only (get-voting-power (member-address principal))
  (match (map-get? members { address: member-address })
    member-info (if (get active member-info)
                    (match (map-get? tiers { tier-name: (get tier-name member-info) })
                      tier-info (if (get active tier-info)
                                    (get voting-power-multiplier tier-info)
                                    u0)
                      u0)
                    u0)
    u0
  )
)

;; Get count of members in a tier
(define-read-only (get-tier-member-count (tier-name (string-ascii 20)))
  (default-to u0 (get count (map-get? tier-member-counts { tier-name: tier-name })))
)

;; Get total members count
(define-read-only (get-total-members)
  (var-get total-members)
)

;; Public functions

;; Initialize the contract with default tiers
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    ;; Create default tiers
    (try! (create-tier "Core" u10 true))
    (try! (create-tier "Contributor" u5 true))
    (try! (create-tier "Community" u1 true))
    
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Create a new tier
(define-public (create-tier 
                 (tier-name (string-ascii 20)) 
                 (voting-multiplier uint) 
                 (active bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> (len tier-name) u0) ERR-INVALID-TIER-NAME)
    (asserts! (> voting-multiplier u0) ERR-INVALID-MULTIPLIER)
    (asserts! (is-none (map-get? tiers { tier-name: tier-name })) ERR-TIER-EXISTS)
    
    (map-set tiers
      { tier-name: tier-name }
      { 
        voting-power-multiplier: voting-multiplier,
        active: active
      }
    )
    
    (map-set tier-member-counts
      { tier-name: tier-name }
      { count: u0 }
    )
    
    (ok true)
  )
)

;; Update an existing tier
(define-public (update-tier 
                 (tier-name (string-ascii 20)) 
                 (voting-multiplier uint) 
                 (active bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> voting-multiplier u0) ERR-INVALID-MULTIPLIER)
    (asserts! (is-some (map-get? tiers { tier-name: tier-name })) ERR-TIER-NOT-FOUND)
    
    (map-set tiers
      { tier-name: tier-name }
      { 
        voting-power-multiplier: voting-multiplier,
        active: active
      }
    )
    
    (ok true)
  )
)

;; Register a new member
(define-public (register-member 
                 (member-address principal) 
                 (initial-tier (string-ascii 20)))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? members { address: member-address })) ERR-MEMBER-EXISTS)
    (asserts! (is-some (map-get? tiers { tier-name: initial-tier })) ERR-TIER-NOT-FOUND)
    
    (map-set members
      { address: member-address }
      {
        tier-name: initial-tier,
        join-height: block-height,
        last-tier-change: block-height,
        active: true
      }
    )
    
    (var-set total-members (+ (var-get total-members) u1))
    (update-tier-count initial-tier i1)
    (add-member-history member-address "join" "" initial-tier)
    
    (ok true)
  )
)

;; Change a member's tier (promote or demote)
(define-public (change-member-tier 
                 (member-address principal) 
                 (new-tier (string-ascii 20)))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (match (map-get? members { address: member-address })
      member-info 
        (begin
          (asserts! (is-some (map-get? tiers { tier-name: new-tier })) ERR-TIER-NOT-FOUND)
          (let ((current-tier (get tier-name member-info)))
            
            ;; Only update if the tier is actually changing
            (if (is-eq current-tier new-tier)
                (ok true)
                (begin
                  (map-set members
                    { address: member-address }
                    {
                      tier-name: new-tier,
                      join-height: (get join-height member-info),
                      last-tier-change: block-height,
                      active: (get active member-info)
                    }
                  )
                  
                  ;; Update tier counts
                  (update-tier-count current-tier (- i0 i1))
                  (update-tier-count new-tier i1)
                  
                  ;; Record the tier change
                  (add-member-history 
                    member-address 
                    (if (< (unwrap-panic (get-voting-power member-address)) 
                            (unwrap-panic (get voting-power-multiplier (map-get? tiers { tier-name: new-tier }))))
                        "promote"
                        "demote")
                    current-tier
                    new-tier)
                  
                  (ok true)
                ))
          )
        )
      ERR-MEMBER-NOT-FOUND
    )
  )
)

;; Activate or deactivate a member
(define-public (set-member-status 
                 (member-address principal) 
                 (active bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (match (map-get? members { address: member-address })
      member-info 
        (begin
          (let ((current-status (get active member-info))
                (current-tier (get tier-name member-info)))
            
            ;; Only update if the status is actually changing
            (if (is-eq current-status active)
                (ok true)
                (begin
                  (map-set members
                    { address: member-address }
                    {
                      tier-name: (get tier-name member-info),
                      join-height: (get join-height member-info),
                      last-tier-change: block-height,
                      active: active
                    }
                  )
                  
                  ;; If deactivating, decrement total and tier count
                  (if (and (not active) current-status)
                      (begin
                        (var-set total-members (- (var-get total-members) u1))
                        (update-tier-count current-tier (- i0 i1))
                        (add-member-history member-address "suspend" current-tier current-tier)
                      )
                      (if (and active (not current-status))
                          (begin
                            (var-set total-members (+ (var-get total-members) u1))
                            (update-tier-count current-tier i1)
                            (add-member-history member-address "reinstate" current-tier current-tier)
                          )
                          true)
                  )
                  
                  (ok true)
                ))
          )
        )
      ERR-MEMBER-NOT-FOUND
    )
  )
)