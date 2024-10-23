;; Advanced Bitcoin Yield Optimizer Protocol
;; A sophisticated DeFi protocol for yield optimization on Bitcoin through Stacks

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-POOL-NOT-FOUND (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-POOL-FULL (err u104))
(define-constant ERR-LOCK-PERIOD-INVALID (err u105))
(define-constant ERR-NO-REWARDS (err u106))
(define-constant ERR-STILL-LOCKED (err u107))
(define-constant ERR-EMERGENCY-SHUTDOWN (err u108))
(define-constant ERR-SLIPPAGE-TOO-HIGH (err u109))
(define-constant ERR-NO-POSITION (err u110))
(define-constant ERR-INVALID-PARAMETER (err u111))
(define-constant ERR-POOL-INACTIVE (err u112))

;; Contract owner and governance
(define-data-var contract-owner principal tx-sender)
(define-data-var protocol-fee-rate uint u50) ;; 0.5% in basis points
(define-data-var emergency-shutdown bool false)
(define-data-var min-stake-amount uint u1000000) ;; Minimum stake in µSTX
(define-data-var max-pool-size uint u1000000000000) ;; Maximum pool size in µSTX

;; Protocol statistics
(define-data-var total-protocol-fees uint u0)
(define-data-var total-unique-stakers uint u0)
(define-data-var total-tvl uint u0)
(define-data-var last-rebalance-height uint u0)

;; Pool types and strategies
(define-map pool-types 
    { type-id: uint }
    {
        name: (string-ascii 64),
        risk-level: uint,
        min-lock-period: uint,
        max-lock-period: uint,
        base-apy: uint,
        is-active: bool
    }
)

;; Pool data structure
(define-map pools 
    { pool-id: uint } 
    { 
        type-id: uint,
        current-apy: uint,
        total-staked: uint,
        staker-count: uint,
        is-active: bool,
        last-update-height: uint,
        total-rewards-distributed: uint,
        strategy-params: (list 10 uint)
    }
)

;; User positions across pools
(define-map user-positions
    { user: principal, pool-id: uint }
    {
        staked-amount: uint,
        pending-rewards: uint,
        stake-height: uint,
        lock-until: uint,
        last-claim-height: uint,
        boost-multiplier: uint,
        compound-rewards: bool
    }
)

;; User statistics
(define-map user-stats
    { user: principal }
    {
        total-staked: uint,
        total-claimed-rewards: uint,
        pools-participated: uint,
        first-stake-height: uint,
        last-action-height: uint
    }
)

;; Governance and admin functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)

(define-public (set-protocol-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-fee u1000) ERR-INVALID-PARAMETER) ;; Max 10% fee
        (var-set protocol-fee-rate new-fee)
        (ok true)
    )
)

(define-public (toggle-emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set emergency-shutdown (not (var-get emergency-shutdown)))
        (ok true)
    )
)


;; Pool management functions
(define-public (create-pool-type 
    (type-id uint) 
    (name (string-ascii 64))
    (risk-level uint)
    (min-lock uint)
    (max-lock uint)
    (base-apy uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= risk-level u10) ERR-INVALID-PARAMETER)
        (asserts! (< min-lock max-lock) ERR-INVALID-PARAMETER)
        (asserts! (<= base-apy u10000) ERR-INVALID-PARAMETER) ;; Max 100% APY
        
        (map-set pool-types
            { type-id: type-id }
            {
                name: name,
                risk-level: risk-level,
                min-lock-period: min-lock,
                max-lock-period: max-lock,
                base-apy: base-apy,
                is-active: true
            }
        )
        (ok true)
    )
)

(define-public (create-pool 
    (pool-id uint) 
    (type-id uint)
    (strategy-params (list 10 uint)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? pool-types { type-id: type-id })) ERR-INVALID-PARAMETER)
        
        (let ((pool-type (unwrap! (map-get? pool-types { type-id: type-id }) ERR-INVALID-PARAMETER)))
            (map-set pools
                { pool-id: pool-id }
                {
                    type-id: type-id,
                    current-apy: (get base-apy pool-type),
                    total-staked: u0,
                    staker-count: u0,
                    is-active: true,
                    last-update-height: block-height,
                    total-rewards-distributed: u0,
                    strategy-params: strategy-params
                }
            )
            (ok true)
        )
    )
)

;; Staking functions
(define-public (stake (pool-id uint) (amount uint) (lock-blocks uint))
    (let (
        (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
        (pool-type (unwrap! (map-get? pool-types { type-id: (get type-id pool) }) ERR-POOL-NOT-FOUND))
        (current-position (default-to 
            {
                staked-amount: u0,
                pending-rewards: u0,
                stake-height: block-height,
                lock-until: u0,
                last-claim-height: block-height,
                boost-multiplier: u100,
                compound-rewards: false
            }
            (map-get? user-positions { user: tx-sender, pool-id: pool-id })))
    )
        (asserts! (not (var-get emergency-shutdown)) ERR-EMERGENCY-SHUTDOWN)
        (asserts! (get is-active pool) ERR-POOL-INACTIVE)
        (asserts! (>= amount (var-get min-stake-amount)) ERR-INVALID-AMOUNT)
        (asserts! (<= (+ (get total-staked pool) amount) (var-get max-pool-size)) ERR-POOL-FULL)
        (asserts! 
            (and 
                (>= lock-blocks (get min-lock-period pool-type))
                (<= lock-blocks (get max-lock-period pool-type))
            )
            ERR-LOCK-PERIOD-INVALID
        )
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Calculate boost multiplier based on lock period
        (let (
            (boost-multiplier (+ u100 (/ (* lock-blocks u100) (get max-lock-period pool-type))))
        )
            ;; Update user position
            (map-set user-positions
                { user: tx-sender, pool-id: pool-id }
                {
                    staked-amount: (+ (get staked-amount current-position) amount),
                    pending-rewards: (get pending-rewards current-position),
                    stake-height: block-height,
                    lock-until: (+ block-height lock-blocks),
                    last-claim-height: block-height,
                    boost-multiplier: boost-multiplier,
                    compound-rewards: (get compound-rewards current-position)
                }
            )
            
            ;; Update pool data
            (map-set pools
                { pool-id: pool-id }
                (merge pool {
                    total-staked: (+ (get total-staked pool) amount),
                    staker-count: (if (is-eq (get staked-amount current-position) u0)
                        (+ (get staker-count pool) u1)
                        (get staker-count pool))
                })
            )
            
            ;; Update protocol statistics
            (var-set total-tvl (+ (var-get total-tvl) amount))
            
            (ok true)
        )
    )
)

;; Advanced reward calculation with compounding effects
(define-read-only (calculate-rewards (user principal) (pool-id uint))
    (let (
        (position (unwrap! (map-get? user-positions { user: user, pool-id: pool-id }) ERR-NO-POSITION))
        (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
        (blocks-staked (- block-height (get last-claim-height position)))
        (base-amount (get staked-amount position))
    )
        (let (
            (base-rewards (* (* base-amount (get current-apy pool)) blocks-staked))
            (boosted-rewards (* base-rewards (get boost-multiplier position)))
            (compounded-rewards (if (get compound-rewards position)
                (+ boosted-rewards (* boosted-rewards (/ blocks-staked u52560)))
                boosted-rewards))
        )
            (ok (/ compounded-rewards u10000))
        )
    )
)

;; Claim rewards function with safety checks
(define-public (claim-rewards (pool-id uint))
    (let (
        (position (unwrap! (map-get? user-positions { user: tx-sender, pool-id: pool-id }) ERR-NO-POSITION))
        (rewards (unwrap! (calculate-rewards tx-sender pool-id) ERR-NO-REWARDS))
    )
        (asserts! (not (var-get emergency-shutdown)) ERR-EMERGENCY-SHUTDOWN)
        (asserts! (> rewards u0) ERR-NO-REWARDS)
        
        ;; Calculate protocol fee
        (let (
            (fee (/ (* rewards (var-get protocol-fee-rate)) u10000))
            (net-rewards (- rewards fee))
        )
            ;; Transfer rewards
            (try! (as-contract (stx-transfer? net-rewards tx-sender tx-sender)))
            (var-set total-protocol-fees (+ (var-get total-protocol-fees) fee))
            
            ;; Update user position
            (map-set user-positions
                { user: tx-sender, pool-id: pool-id }
                (merge position {
                    pending-rewards: u0,
                    last-claim-height: block-height
                })
            )
            
            ;; Update pool statistics
            (map-set pools
                { pool-id: pool-id }
                (merge (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND)
                    { total-rewards-distributed: (+ (get total-rewards-distributed (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND)) rewards) }
                )
            )
            
            (ok rewards)
        )
    )
)

;; Pool rebalancing mechanism
(define-private (rebalance-pool (pool-id uint))
    (let (
        (pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
        (pool-type (unwrap! (map-get? pool-types { type-id: (get type-id pool) }) ERR-POOL-NOT-FOUND))
        (utilization-rate (/ (* (get total-staked pool) u10000) (var-get max-pool-size)))
    )
        (let (
            (new-apy (if (> utilization-rate u8000)
                ;; High utilization: reduce APY
                (- (get base-apy pool-type) (/ (get base-apy pool-type) u4))
                ;; Low utilization: increase APY
                (+ (get base-apy pool-type) (/ (get base-apy pool-type) u4))))
        )
            (map-set pools
                { pool-id: pool-id }
                (merge pool {
                    current-apy: new-apy,
                    last-update-height: block-height
                })
            )
            (var-set last-rebalance-height block-height)
            (ok true)
        )
    )
)