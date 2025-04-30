;; token-vote-power contract
;; This contract connects SIP-010 token holdings to voting power for governance systems.
;; It provides snapshot functionality to prevent last-minute vote buying and supports
;; both linear and non-linear voting power models, along with optional token lockups
;; for increased voting power.

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-TOKEN-OWNER (err u101))
(define-constant ERR-INVALID-TOKEN (err u102))
(define-constant ERR-SNAPSHOT-EXISTS (err u103))
(define-constant ERR-NO-SNAPSHOT (err u104))
(define-constant ERR-ALREADY-LOCKED (err u105))
(define-constant ERR-LOCK-EXPIRED (err u106))
(define-constant ERR-LOCK-NOT-EXPIRED (err u107))
(define-constant ERR-INVALID-LOCK-PERIOD (err u108))
(define-constant ERR-ZERO-AMOUNT (err u109))
(define-constant ERR-INSUFFICIENT-BALANCE (err u110))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant SECONDS-PER-DAY u86400) ;; 24 * 60 * 60
(define-constant SQRT-PRECISION u1000000) ;; Precision for square root calculation

;; Data maps
;; Map to track token contract deployments
(define-map supported-tokens 
  { token-contract: principal }
  { is-approved: bool, token-decimals: uint }
)

;; Store snapshots of token balances at specific block heights
(define-map balance-snapshots
  { token-contract: principal, proposal-id: uint, user: principal }
  { balance: uint }
)

;; Track proposal snapshots
(define-map proposal-snapshots
  { token-contract: principal, proposal-id: uint }
  { block-height: uint, snapshot-taken: bool }
)

;; Token lockups for increased voting power
(define-map token-lockups
  { token-contract: principal, user: principal }
  { 
    amount: uint,
    lock-until-height: uint,
    lock-multiplier: uint, ;; multiplier in basis points (100 = 1x, 150 = 1.5x)
    locked-at-height: uint
  }
)

;; Voting power model configuration
(define-map voting-power-config
  { token-contract: principal }
  {
    power-model: (string-ascii 20), ;; "linear" or "square-root"
    multiplier-enabled: bool
  }
)

;; Private functions

;; Calculate square root of a number (using babylonian method with fixed precision)
;; Uses a simple approximation algorithm with SQRT-PRECISION defined above
(define-private (sqrt (x uint))
  (if (is-eq x u0)
      u0
      (let ((precision SQRT-PRECISION))
        (let ((guess (/ (+ x u1) u2)))
          (let loop ((guess guess))
            (let ((next-guess (/ (+ guess (/ (* x precision) (* guess precision))) u2)))
              (if (< (abs (- next-guess guess)) u2)
                  (/ (* next-guess precision) precision)
                  (loop next-guess))))))))

(define-private (abs (a uint) (b uint))
  (if (> a b)
      (- a b)
      (- b a)))

;; Get SIP-010 token balance for an account
(define-private (get-token-balance (token-contract principal) (account principal))
  (contract-call? token-contract get-balance account))

;; Calculate voting power based on configured model and token amount
(define-private (calculate-voting-power (token-contract principal) (amount uint))
  (let ((config (default-to 
                  { power-model: "linear", multiplier-enabled: false }
                  (map-get? voting-power-config { token-contract: token-contract }))))
    (if (is-eq (get power-model config) "square-root")
        (sqrt amount)
        amount))) ;; Default linear model

;; Apply lock multiplier to voting power if enabled and user has locked tokens
(define-private (apply-lock-multiplier 
                 (token-contract principal) 
                 (user principal) 
                 (base-voting-power uint))
  (let ((config (default-to 
                  { power-model: "linear", multiplier-enabled: false }
                  (map-get? voting-power-config { token-contract: token-contract }))))
    (if (get multiplier-enabled config)
        (match (map-get? token-lockups { token-contract: token-contract, user: user })
          lockup-data 
            (let ((multiplier (get lock-multiplier lockup-data)))
              (if (> block-height (get lock-until-height lockup-data))
                  base-voting-power ;; Lock expired, no multiplier
                  (/ (* base-voting-power multiplier) u100))) ;; Apply multiplier (in basis points)
          base-voting-power) ;; No lockup found
        base-voting-power))) ;; Multiplier not enabled

;; Check if sender is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER))

;; Read-only functions

;; Get the current voting power for a user based on their token holdings
(define-read-only (get-current-voting-power (token-contract principal) (user principal))
  (match (map-get? supported-tokens { token-contract: token-contract })
    token-info
      (let ((balance (unwrap-panic (get-token-balance token-contract user))))
        (apply-lock-multiplier 
          token-contract 
          user 
          (calculate-voting-power token-contract balance)))
    (err u0))) ;; Token not supported

;; Get the voting power from a specific snapshot
(define-read-only (get-snapshot-voting-power 
                   (token-contract principal) 
                   (proposal-id uint) 
                   (user principal))
  (match (map-get? supported-tokens { token-contract: token-contract })
    token-info
      (match (map-get? proposal-snapshots 
                       { token-contract: token-contract, proposal-id: proposal-id })
        snapshot-info
          (if (get snapshot-taken snapshot-info)
              (match (map-get? balance-snapshots 
                               { token-contract: token-contract, 
                                 proposal-id: proposal-id, 
                                 user: user })
                balance-data
                  (apply-lock-multiplier 
                    token-contract 
                    user 
                    (calculate-voting-power token-contract (get balance balance-data)))
                (ok u0)) ;; No balance snapshot for this user
              ERR-NO-SNAPSHOT) ;; Snapshot not taken
        ERR-NO-SNAPSHOT) ;; Proposal snapshot doesn't exist
    ERR-INVALID-TOKEN)) ;; Token not supported

;; Get lock details for a user
(define-read-only (get-lock-details (token-contract principal) (user principal))
  (map-get? token-lockups { token-contract: token-contract, user: user }))

;; Check if token is supported
(define-read-only (is-token-supported (token-contract principal))
  (is-some (map-get? supported-tokens { token-contract: token-contract })))

;; Public functions

;; Add a supported token (only callable by contract owner)
(define-public (add-supported-token (token-contract principal) (token-decimals uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    ;; Verify this is a valid SIP-010 token by calling get-name
    (asserts! (is-ok (contract-call? token-contract get-name)) ERR-INVALID-TOKEN)
    (ok (map-set supported-tokens 
                { token-contract: token-contract }
                { is-approved: true, token-decimals: token-decimals }))))

;; Configure voting power model for a token
(define-public (configure-voting-power-model 
                (token-contract principal) 
                (power-model (string-ascii 20))
                (enable-multiplier bool))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-token-supported token-contract) ERR-INVALID-TOKEN)
    (asserts! (or (is-eq power-model "linear") (is-eq power-model "square-root")) 
              (err u111)) ;; Invalid power model
    (ok (map-set voting-power-config
                { token-contract: token-contract }
                { 
                  power-model: power-model,
                  multiplier-enabled: enable-multiplier
                }))))

;; Create a snapshot of token balances for a proposal
(define-public (create-snapshot (token-contract principal) (proposal-id uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-token-supported token-contract) ERR-INVALID-TOKEN)
    (asserts! (is-none (map-get? proposal-snapshots 
                                 { token-contract: token-contract, proposal-id: proposal-id }))
              ERR-SNAPSHOT-EXISTS)
    
    (ok (map-set proposal-snapshots
                { token-contract: token-contract, proposal-id: proposal-id }
                { block-height: block-height, snapshot-taken: true }))))

;; Add a user's balance to an existing snapshot (typically called in batch by admin after create-snapshot)
(define-public (add-to-snapshot (token-contract principal) (proposal-id uint) (user principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-token-supported token-contract) ERR-INVALID-TOKEN)
    
    (match (map-get? proposal-snapshots { token-contract: token-contract, proposal-id: proposal-id })
      snapshot-info
        (begin
          (asserts! (get snapshot-taken snapshot-info) ERR-NO-SNAPSHOT)
          (let ((balance (unwrap-panic (get-token-balance token-contract user))))
            (ok (map-set balance-snapshots
                        { 
                          token-contract: token-contract, 
                          proposal-id: proposal-id,
                          user: user
                        }
                        { balance: balance }))))
      ERR-NO-SNAPSHOT)))

;; Lock tokens for increased voting power
;; lock-period is in days, multiplier is in basis points (e.g., 150 = 1.5x)
(define-public (lock-tokens 
                (token-contract principal) 
                (amount uint) 
                (lock-period uint) 
                (multiplier uint))
  (begin
    (asserts! (is-token-supported token-contract) ERR-INVALID-TOKEN)
    (asserts! (> amount u0) ERR-ZERO-AMOUNT)
    (asserts! (>= (unwrap-panic (get-token-balance token-contract tx-sender)) amount) 
              ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-none (map-get? token-lockups 
                               { token-contract: token-contract, user: tx-sender }))
              ERR-ALREADY-LOCKED)
    
    ;; Validate lock period and multiplier
    ;; Example: 30 days = 1.2x, 90 days = 1.5x, 180 days = 2x
    (asserts! (and (>= lock-period u7) (<= lock-period u365)) ERR-INVALID-LOCK-PERIOD)
    (asserts! (and (>= multiplier u100) (<= multiplier u300)) (err u112)) ;; Invalid multiplier
    
    ;; Transfer tokens to this contract (will hold during lock period)
    (asserts! (is-ok (contract-call? token-contract transfer 
                                   amount tx-sender (as-contract tx-sender) none))
              (err u113)) ;; Transfer failed
    
    ;; Calculate lock height based on days
    (let ((lock-blocks (+ block-height (* lock-period (/ SECONDS-PER-DAY u10)))))
      (ok (map-set token-lockups
                  { token-contract: token-contract, user: tx-sender }
                  { 
                    amount: amount,
                    lock-until-height: lock-blocks,
                    lock-multiplier: multiplier,
                    locked-at-height: block-height
                  })))))

;; Unlock tokens after lock period expires
(define-public (unlock-tokens (token-contract principal))
  (begin
    (asserts! (is-token-supported token-contract) ERR-INVALID-TOKEN)
    
    (match (map-get? token-lockups { token-contract: token-contract, user: tx-sender })
      lockup-data
        (begin
          (asserts! (>= block-height (get lock-until-height lockup-data)) ERR-LOCK-NOT-EXPIRED)
          
          ;; Delete lockup record first before transfer to prevent reentrancy
          (map-delete token-lockups { token-contract: token-contract, user: tx-sender })
          
          ;; Return tokens to owner
          (as-contract 
            (contract-call? token-contract transfer 
                          (get amount lockup-data) 
                          tx-sender 
                          tx-sender 
                          none)))
      ERR-NO-SNAPSHOT))) ;; No lockup found