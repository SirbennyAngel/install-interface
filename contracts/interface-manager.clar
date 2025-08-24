;; ===========================================
;; Install Interface - DAO Governance Contract
;; ===========================================
;; This contract manages a decentralized governance system 
;; for software installation, interface development, and 
;; collaborative technology management.

;; ===========================================
;; Error Constants
;; ===========================================
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-INSUFFICIENT-STAKE (err u103))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u104))
(define-constant ERR-INVALID-PROPOSAL-STATE (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-VOTING-CLOSED (err u107))
(define-constant ERR-INVALID-PARAMETERS (err u108))

;; ===========================================
;; Proposal States and Phases
;; ===========================================
(define-constant PROPOSAL-STATE-DRAFT u0)
(define-constant PROPOSAL-STATE-ACTIVE u1)
(define-constant PROPOSAL-STATE-PASSED u2)
(define-constant PROPOSAL-STATE-REJECTED u3)
(define-constant PROPOSAL-STATE-EXECUTED u4)

(define-constant PHASE-SUBMISSION u0)
(define-constant PHASE-REVIEW u1)
(define-constant PHASE-VOTING u2)
(define-constant PHASE-IMPLEMENTATION u3)

;; ===========================================
;; Data Maps and Variables
;; ===========================================
;; Member registration tracking
(define-map members principal {
  stake-balance: uint,
  is-active: bool,
  joined-at: uint,
  delegated-to: (optional principal)
})

;; Interface development proposals
(define-map proposals uint {
  title: (string-ascii 100),
  description: (string-utf8 500),
  proposed-by: principal,
  created-at: uint,
  target-stake: uint,
  state: uint,
  current-phase: uint,
  phase-end-time: uint,
  yes-votes: uint,
  no-votes: uint,
  implementation-link: (string-ascii 255)
})

;; Voting records for tracking individual participation
(define-map proposal-votes 
  { proposal-id: uint, voter: principal } 
  { 
    vote: bool, 
    stake-weight: uint,
    voted-at: uint 
  }
)

;; Tracked global variables
(define-data-var total-registered-stake uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var governance-stake-threshold uint u1000)
(define-data-var voting-period-length uint u14400) ;; Blocks, roughly 2 days

;; ===========================================
;; Private Helper Functions
;; ===========================================
(define-private (is-registered (user principal))
  (default-to false (get is-active (map-get? members user))))

(define-private (calculate-stake-weight (stake uint))
  ;; Simple stake-based weighting function
  (+ u1 (/ stake u100)))

;; ===========================================
;; Read-Only Functions
;; ===========================================
(define-read-only (get-member-info (member principal))
  (map-get? members member))

(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals proposal-id))

(define-read-only (get-total-registered-stake)
  (var-get total-registered-stake))

;; ===========================================
;; Public Registration Functions
;; ===========================================
(define-public (register-member (initial-stake uint))
  (let (
    (caller tx-sender)
  )
    ;; Validate initial stake
    (asserts! (> initial-stake u0) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-registered caller)) ERR-ALREADY-REGISTERED)

    ;; Register member with stake
    (map-set members caller {
      stake-balance: initial-stake,
      is-active: true,
      joined-at: block-height,
      delegated-to: none
    })

    ;; Update total registered stake
    (var-set total-registered-stake 
      (+ (var-get total-registered-stake) initial-stake))

    (ok true)
  ))

(define-public (increase-stake (additional-stake uint))
  (let (
    (caller tx-sender)
    (member-info (unwrap! (map-get? members caller) ERR-NOT-REGISTERED))
  )
    ;; Validate additional stake
    (asserts! (> additional-stake u0) ERR-INVALID-PARAMETERS)

    ;; Update member's stake
    (map-set members caller (merge member-info {
      stake-balance: (+ (get stake-balance member-info) additional-stake)
    }))

    ;; Update total registered stake
    (var-set total-registered-stake 
      (+ (var-get total-registered-stake) additional-stake))

    (ok true)
  ))

;; ===========================================
;; Proposal Management Functions
;; ===========================================
(define-public (create-proposal 
                (title (string-ascii 100))
                (description (string-utf8 500))
                (target-stake uint)
                (implementation-link (string-ascii 255)))
  (let (
    (caller tx-sender)
    (proposal-id (+ (var-get proposal-counter) u1))
    (phase-end-time (+ block-height (var-get voting-period-length)))
  )
    ;; Validate proposal parameters
    (asserts! (is-registered caller) ERR-NOT-REGISTERED)
    (asserts! (> target-stake u0) ERR-INVALID-PARAMETERS)

    ;; Create new proposal
    (map-set proposals proposal-id {
      title: title,
      description: description,
      proposed-by: caller,
      created-at: block-height,
      target-stake: target-stake,
      state: PROPOSAL-STATE-DRAFT,
      current-phase: PHASE-SUBMISSION,
      phase-end-time: phase-end-time,
      yes-votes: u0,
      no-votes: u0,
      implementation-link: implementation-link
    })

    ;; Increment proposal counter
    (var-set proposal-counter proposal-id)

    (ok proposal-id)
  ))

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (caller tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (member-info (unwrap! (map-get? members caller) ERR-NOT-REGISTERED))
    (stake-weight (calculate-stake-weight (get stake-balance member-info)))
  )
    ;; Validate voting conditions
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-ACTIVE) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: caller })) ERR-ALREADY-VOTED)

    ;; Record vote and update proposal
    (map-set proposal-votes 
      { proposal-id: proposal-id, voter: caller }
      { 
        vote: vote-for, 
        stake-weight: stake-weight,
        voted-at: block-height 
      }
    )

    ;; Update vote tallies
    (map-set proposals proposal-id (merge proposal {
      yes-votes: (if vote-for 
                    (+ (get yes-votes proposal) stake-weight)
                    (get yes-votes proposal)),
      no-votes: (if vote-for
                   (get no-votes proposal)
                   (+ (get no-votes proposal) stake-weight))
    }))

    (ok true)
  ))

;; ===========================================
;; Governance Control Functions
;; ===========================================
(define-public (activate-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Validate proposal can be activated
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-DRAFT) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (>= (get-total-registered-stake) (get target-stake proposal)) ERR-INSUFFICIENT-STAKE)

    ;; Activate proposal
    (map-set proposals proposal-id (merge proposal {
      state: PROPOSAL-STATE-ACTIVE,
      current-phase: PHASE-VOTING
    }))

    (ok true)
  ))

(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
    (yes-percentage (if (is-eq total-votes u0) 
                        u0 
                        (/ (* (get yes-votes proposal) u100) total-votes)))
  )
    ;; Validate finalization conditions
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-ACTIVE) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (>= block-height (get phase-end-time proposal)) ERR-INVALID-PROPOSAL-STATE)

    ;; Determine proposal outcome
    (let (
      (new-state (if (>= yes-percentage u60) 
                     PROPOSAL-STATE-PASSED 
                     PROPOSAL-STATE-REJECTED))
    )
      (map-set proposals proposal-id (merge proposal {
        state: new-state,
        current-phase: (if (is-eq new-state PROPOSAL-STATE-PASSED) 
                           PHASE-IMPLEMENTATION 
                           PHASE-VOTING)
      }))

      (ok (is-eq new-state PROPOSAL-STATE-PASSED))
    )
  ))