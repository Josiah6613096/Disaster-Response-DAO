(define-constant ERR_NOT_AUTHORIZED (err u500))
(define-constant ERR_INVALID_AMOUNT (err u501))
(define-constant ERR_PROJECT_NOT_FOUND (err u502))
(define-constant ERR_MILESTONE_NOT_FOUND (err u503))
(define-constant ERR_ALREADY_COMPLETED (err u504))
(define-constant ERR_INSUFFICIENT_FUNDS (err u505))
(define-constant ERR_INVALID_INDEX (err u506))
(define-constant ERR_NOT_VALIDATOR (err u507))

(define-data-var contract-owner principal tx-sender)
(define-data-var next-project-id uint u1)

(define-map projects
  uint
  {
    recipient: principal,
    title: (string-ascii 100),
    total-budget: uint,
    disbursed: uint,
    created-at: uint,
    active: bool
  }
)

(define-map milestones
  { project-id: uint, milestone-index: uint }
  {
    description: (string-ascii 200),
    amount: uint,
    completed: bool,
    verified-by: (optional principal),
    completed-at: (optional uint)
  }
)

(define-map project-milestone-count uint uint)
(define-map validators principal bool)

(define-public (add-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set validators validator true)
    (ok true)
  )
)

(define-public (create-project 
  (title (string-ascii 100))
  (recipient principal)
  (total-budget uint)
)
  (let ((project-id (var-get next-project-id)))
    (asserts! (> total-budget u0) ERR_INVALID_AMOUNT)
    (map-set projects project-id
      {
        recipient: recipient,
        title: title,
        total-budget: total-budget,
        disbursed: u0,
        created-at: stacks-block-height,
        active: true
      }
    )
    (map-set project-milestone-count project-id u0)
    (var-set next-project-id (+ project-id u1))
    (ok project-id)
  )
)

(define-public (add-milestone 
  (project-id uint)
  (description (string-ascii 200))
  (amount uint)
)
  (let
    (
      (project (unwrap! (map-get? projects project-id) ERR_PROJECT_NOT_FOUND))
      (milestone-count (default-to u0 (map-get? project-milestone-count project-id)))
    )
    (asserts! (is-eq tx-sender (get recipient project)) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (map-set milestones { project-id: project-id, milestone-index: milestone-count }
      {
        description: description,
        amount: amount,
        completed: false,
        verified-by: none,
        completed-at: none
      }
    )
    (map-set project-milestone-count project-id (+ milestone-count u1))
    (ok milestone-count)
  )
)

(define-public (verify-milestone (project-id uint) (milestone-index uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) ERR_PROJECT_NOT_FOUND))
      (milestone-key { project-id: project-id, milestone-index: milestone-index })
      (milestone (unwrap! (map-get? milestones milestone-key) ERR_MILESTONE_NOT_FOUND))
    )
    (asserts! (default-to false (map-get? validators tx-sender)) ERR_NOT_VALIDATOR)
    (asserts! (not (get completed milestone)) ERR_ALREADY_COMPLETED)
    (asserts! (<= (+ (get disbursed project) (get amount milestone)) (get total-budget project)) 
              ERR_INSUFFICIENT_FUNDS)
    (map-set milestones milestone-key
      (merge milestone 
        { 
          completed: true, 
          verified-by: (some tx-sender),
          completed-at: (some stacks-block-height)
        }
      )
    )
    (map-set projects project-id
      (merge project { disbursed: (+ (get disbursed project) (get amount milestone)) })
    )
    (ok true)
  )
)

(define-read-only (get-project (project-id uint))
  (map-get? projects project-id)
)

(define-read-only (get-milestone (project-id uint) (milestone-index uint))
  (map-get? milestones { project-id: project-id, milestone-index: milestone-index })
)

(define-read-only (get-milestone-count (project-id uint))
  (default-to u0 (map-get? project-milestone-count project-id))
)

(define-read-only (is-validator (user principal))
  (default-to false (map-get? validators user))
)

(define-read-only (get-project-progress (project-id uint))
  (match (map-get? projects project-id)
    project
    (some {
      disbursed: (get disbursed project),
      total-budget: (get total-budget project),
      progress-percent: (if (> (get total-budget project) u0)
                          (/ (* (get disbursed project) u100) (get total-budget project))
                          u0)
    })
    none
  )
)