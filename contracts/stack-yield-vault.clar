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