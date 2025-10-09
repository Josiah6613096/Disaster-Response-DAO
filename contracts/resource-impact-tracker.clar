(define-constant ERR_NOT_AUTHORIZED (err u400))
(define-constant ERR_INVALID_AMOUNT (err u401))
(define-constant ERR_RESOURCE_NOT_FOUND (err u402))
(define-constant ERR_ALREADY_REPORTED (err u403))
(define-constant ERR_INVALID_STATUS (err u404))

(define-data-var next-resource-id uint u1)
(define-data-var contract-admin principal tx-sender)

(define-map resource-allocations
  uint
  {
    recipient: principal,
    amount: uint,
    purpose: (string-ascii 100),
    allocated-at: uint,
    expected-beneficiaries: uint,
    status: (string-ascii 20)
  }
)

(define-map impact-reports
  uint
  {
    reporter: principal,
    actual-beneficiaries: uint,
    impact-score: uint,
    evidence: (string-ascii 200),
    verified: bool,
    reported-at: uint
  }
)

(define-map verified-reporters principal bool)

(define-public (add-verified-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_NOT_AUTHORIZED)
    (map-set verified-reporters reporter true)
    (ok true)
  )
)

(define-public (register-resource-allocation 
  (recipient principal)
  (amount uint)
  (purpose (string-ascii 100))
  (expected-beneficiaries uint)
)
  (let
    (
      (resource-id (var-get next-resource-id))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> expected-beneficiaries u0) ERR_INVALID_AMOUNT)
    
    (map-set resource-allocations resource-id
      {
        recipient: recipient,
        amount: amount,
        purpose: purpose,
        allocated-at: stacks-block-height,
        expected-beneficiaries: expected-beneficiaries,
        status: "allocated"
      }
    )
    
    (var-set next-resource-id (+ resource-id u1))
    (ok resource-id)
  )
)

(define-public (submit-impact-report 
  (resource-id uint)
  (actual-beneficiaries uint)
  (impact-score uint)
  (evidence (string-ascii 200))
)
  (let
    (
      (allocation (unwrap! (map-get? resource-allocations resource-id) ERR_RESOURCE_NOT_FOUND))
      (is-recipient (is-eq tx-sender (get recipient allocation)))
      (is-verified (default-to false (map-get? verified-reporters tx-sender)))
    )
    (asserts! (or is-recipient is-verified) ERR_NOT_AUTHORIZED)
    (asserts! (> impact-score u0) ERR_INVALID_AMOUNT)
    (asserts! (<= impact-score u100) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? impact-reports resource-id)) ERR_ALREADY_REPORTED)
    
    (map-set impact-reports resource-id
      {
        reporter: tx-sender,
        actual-beneficiaries: actual-beneficiaries,
        impact-score: impact-score,
        evidence: evidence,
        verified: is-verified,
        reported-at: stacks-block-height
      }
    )
    
    (map-set resource-allocations resource-id
      (merge allocation { status: "reported" })
    )
    
    (ok true)
  )
)

(define-public (verify-impact-report (resource-id uint))
  (let
    (
      (report (unwrap! (map-get? impact-reports resource-id) ERR_RESOURCE_NOT_FOUND))
      (allocation (unwrap! (map-get? resource-allocations resource-id) ERR_RESOURCE_NOT_FOUND))
    )
    (asserts! (default-to false (map-get? verified-reporters tx-sender)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get verified report)) ERR_ALREADY_REPORTED)
    
    (map-set impact-reports resource-id
      (merge report { verified: true })
    )
    
    (map-set resource-allocations resource-id
      (merge allocation { status: "verified" })
    )
    
    (ok true)
  )
)

(define-read-only (get-resource-allocation (resource-id uint))
  (map-get? resource-allocations resource-id)
)

(define-read-only (get-impact-report (resource-id uint))
  (map-get? impact-reports resource-id)
)

(define-read-only (is-verified-reporter (reporter principal))
  (default-to false (map-get? verified-reporters reporter))
)

(define-read-only (calculate-efficiency-ratio (resource-id uint))
  (match (map-get? resource-allocations resource-id)
    allocation
    (match (map-get? impact-reports resource-id)
      report
      (let
        (
          (expected (get expected-beneficiaries allocation))
          (actual (get actual-beneficiaries report))
          (ratio (if (> expected u0) (/ (* actual u100) expected) u0))
        )
        (some ratio)
      )
      none
    )
    none
  )
)

(define-read-only (get-total-resources)
  (- (var-get next-resource-id) u1)
)
