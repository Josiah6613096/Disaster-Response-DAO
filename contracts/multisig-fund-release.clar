(define-constant ERR_NOT_AUTHORIZED (err u600))
(define-constant ERR_INVALID_AMOUNT (err u601))
(define-constant ERR_REQUEST_NOT_FOUND (err u602))
(define-constant ERR_ALREADY_APPROVED (err u603))
(define-constant ERR_ALREADY_EXECUTED (err u604))
(define-constant ERR_INSUFFICIENT_APPROVALS (err u605))
(define-constant ERR_NOT_SIGNER (err u606))

(define-data-var contract-owner principal tx-sender)
(define-data-var next-request-id uint u1)
(define-data-var required-approvals uint u2)

(define-map authorized-signers principal bool)

(define-map fund-requests
  uint
  {
    requester: principal,
    recipient: principal,
    amount: uint,
    purpose: (string-ascii 200),
    created-at: uint,
    approvals: uint,
    executed: bool
  }
)

(define-map request-approvals
  { request-id: uint, signer: principal }
  { approved: bool, timestamp: uint }
)

(define-public (add-signer (signer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set authorized-signers signer true)
    (ok true)
  )
)

(define-public (remove-signer (signer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-delete authorized-signers signer)
    (ok true)
  )
)

(define-public (update-required-approvals (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> new-threshold u0) ERR_INVALID_AMOUNT)
    (var-set required-approvals new-threshold)
    (ok true)
  )
)

(define-public (create-fund-request
  (recipient principal)
  (amount uint)
  (purpose (string-ascii 200))
)
  (let ((request-id (var-get next-request-id)))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (map-set fund-requests request-id
      {
        requester: tx-sender,
        recipient: recipient,
        amount: amount,
        purpose: purpose,
        created-at: stacks-block-height,
        approvals: u0,
        executed: false
      }
    )
    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

(define-public (approve-request (request-id uint))
  (let
    (
      (request (unwrap! (map-get? fund-requests request-id) ERR_REQUEST_NOT_FOUND))
      (approval-key { request-id: request-id, signer: tx-sender })
    )
    (asserts! (default-to false (map-get? authorized-signers tx-sender)) ERR_NOT_SIGNER)
    (asserts! (not (get executed request)) ERR_ALREADY_EXECUTED)
    (asserts! (is-none (map-get? request-approvals approval-key)) ERR_ALREADY_APPROVED)
    (map-set request-approvals approval-key
      { approved: true, timestamp: stacks-block-height }
    )
    (map-set fund-requests request-id
      (merge request { approvals: (+ (get approvals request) u1) })
    )
    (ok true)
  )
)

(define-public (execute-request (request-id uint))
  (let
    (
      (request (unwrap! (map-get? fund-requests request-id) ERR_REQUEST_NOT_FOUND))
    )
    (asserts! (not (get executed request)) ERR_ALREADY_EXECUTED)
    (asserts! (>= (get approvals request) (var-get required-approvals)) ERR_INSUFFICIENT_APPROVALS)
    (try! (as-contract (stx-transfer? (get amount request) tx-sender (get recipient request))))
    (map-set fund-requests request-id (merge request { executed: true }))
    (ok true)
  )
)

(define-read-only (get-fund-request (request-id uint))
  (map-get? fund-requests request-id)
)

(define-read-only (get-approval-status (request-id uint) (signer principal))
  (map-get? request-approvals { request-id: request-id, signer: signer })
)

(define-read-only (is-authorized-signer (signer principal))
  (default-to false (map-get? authorized-signers signer))
)

(define-read-only (get-required-approvals)
  (var-get required-approvals)
)
