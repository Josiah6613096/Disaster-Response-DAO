(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_VOTING_ENDED (err u104))
(define-constant ERR_INSUFFICIENT_FUNDS (err u105))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u106))
(define-constant ERR_ALREADY_EXECUTED (err u107))
(define-constant ERR_NOT_MEMBER (err u108))

(define-constant ERR_INVALID_SCORE (err u201))

(define-data-var next-proposal-id uint u1)
(define-data-var total-members uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var total-stake uint u0)

(define-map members principal bool)
(define-map member-stakes principal uint)

(define-map proposals
  uint
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    amount: uint,
    recipient: principal,
    votes-for: uint,
    votes-against: uint,
    end-block: uint,
    executed: bool,
    passed: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, stake: uint }
)

(define-map emergency-contacts
  principal
  {
    name: (string-ascii 50),
    contact-info: (string-ascii 100),
    verified: bool
  }
)

(define-public (join-dao (stake-amount uint))
  (begin
    (asserts! (> stake-amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set members tx-sender true)
    (map-set member-stakes tx-sender stake-amount)
    (var-set total-members (+ (var-get total-members) u1))
    (var-set treasury-balance (+ (var-get treasury-balance) stake-amount))
    (var-set total-stake (+ (var-get total-stake) stake-amount))
    (ok true)
  )
)

(define-public (donate (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok true)
  )
)

(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (amount uint)
  (recipient principal)
  (voting-period uint)
)
  (let
    (
      (proposal-id (var-get next-proposal-id))
      (end-block (+ stacks-block-height voting-period))
    )
    (asserts! (is-member tx-sender) ERR_NOT_MEMBER)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set proposals proposal-id
      {
        proposer: tx-sender,
        title: title,
        description: description,
        amount: amount,
        recipient: recipient,
        votes-for: u0,
        votes-against: u0,
        end-block: end-block,
        executed: false,
        passed: false
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote (proposal-id uint) (support bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (voter-stake (unwrap! (map-get? member-stakes tx-sender) ERR_NOT_MEMBER))
      (vote-key { proposal-id: proposal-id, voter: tx-sender })
    )
    (asserts! (is-member tx-sender) ERR_NOT_MEMBER)
    (asserts! (< stacks-block-height (get end-block proposal)) ERR_VOTING_ENDED)
    (asserts! (is-none (map-get? votes vote-key)) ERR_ALREADY_VOTED)
    
    (map-set votes vote-key { vote: support, stake: voter-stake })
    
    (if support
      (map-set proposals proposal-id
        (merge proposal { votes-for: (+ (get votes-for proposal) voter-stake) })
      )
      (map-set proposals proposal-id
        (merge proposal { votes-against: (+ (get votes-against proposal) voter-stake) })
      )
    )
    
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
      (quorum-threshold (/ (var-get total-stake) u2))
      (majority-threshold (/ total-votes u2))
    )
    (asserts! (>= stacks-block-height (get end-block proposal)) ERR_VOTING_ENDED)
    (asserts! (not (get executed proposal)) ERR_ALREADY_EXECUTED)
    (asserts! (>= total-votes quorum-threshold) ERR_PROPOSAL_NOT_PASSED)
    (asserts! (> (get votes-for proposal) majority-threshold) ERR_PROPOSAL_NOT_PASSED)
    
    (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get recipient proposal))))
    
    (map-set proposals proposal-id
      (merge proposal { executed: true, passed: true })
    )
    
    (var-set treasury-balance (- (var-get treasury-balance) (get amount proposal)))
    (ok true)
  )
)

(define-public (register-emergency-contact 
  (contact principal)
  (name (string-ascii 50))
  (contact-info (string-ascii 100))
)
  (begin
    (asserts! (is-member tx-sender) ERR_NOT_MEMBER)
    (map-set emergency-contacts contact
      {
        name: name,
        contact-info: contact-info,
        verified: false
      }
    )
    (ok true)
  )
)

(define-public (verify-emergency-contact (contact principal))
  (let
    (
      (contact-data (unwrap! (map-get? emergency-contacts contact) ERR_NOT_AUTHORIZED))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set emergency-contacts contact
      (merge contact-data { verified: true })
    )
    (ok true)
  )
)

(define-public (emergency-funding 
  (recipient principal)
  (amount uint)
  (justification (string-ascii 200))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    (ok true)
  )
)

(define-public (leave-dao)
  (let
    (
      (member-stake (unwrap! (map-get? member-stakes tx-sender) ERR_NOT_MEMBER))
    )
    (asserts! (is-member tx-sender) ERR_NOT_MEMBER)
    
    (try! (as-contract (stx-transfer? member-stake tx-sender tx-sender)))
    (map-delete members tx-sender)
    (map-delete member-stakes tx-sender)
    (var-set total-members (- (var-get total-members) u1))
    (var-set treasury-balance (- (var-get treasury-balance) member-stake))
    (var-set total-stake (- (var-get total-stake) member-stake))
    (ok true)
  )
)

(define-public (update-stake (new-stake uint))
  (let
    (
      (current-stake (unwrap! (map-get? member-stakes tx-sender) ERR_NOT_MEMBER))
      (stake-diff (if (> new-stake current-stake) 
                     (- new-stake current-stake) 
                     (- current-stake new-stake)))
    )
    (asserts! (is-member tx-sender) ERR_NOT_MEMBER)
    (asserts! (> new-stake u0) ERR_INVALID_AMOUNT)
    
    (if (> new-stake current-stake)
      (begin
        (try! (stx-transfer? stake-diff tx-sender (as-contract tx-sender)))
        (var-set treasury-balance (+ (var-get treasury-balance) stake-diff))
        (var-set total-stake (+ (var-get total-stake) stake-diff))
      )
      (begin
        (try! (as-contract (stx-transfer? stake-diff tx-sender tx-sender)))
        (var-set treasury-balance (- (var-get treasury-balance) stake-diff))
        (var-set total-stake (- (var-get total-stake) stake-diff))
      )
    )
    
    (map-set member-stakes tx-sender new-stake)
    (ok true)
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (is-member (user principal))
  (default-to false (map-get? members user))
)

(define-read-only (get-member-stake (member principal))
  (map-get? member-stakes member)
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-total-members)
  (var-get total-members)
)

(define-read-only (get-total-stake)
  (var-get total-stake)
)

(define-read-only (get-emergency-contact (contact principal))
  (map-get? emergency-contacts contact)
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
    (let
      (
        (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
        (quorum-met (>= total-votes (/ (var-get total-stake) u2)))
        (majority-met (> (get votes-for proposal) (/ total-votes u2)))
        (voting-ended (>= stacks-block-height (get end-block proposal)))
      )
      (some {
        quorum-met: quorum-met,
        majority-met: majority-met,
        voting-ended: voting-ended,
        can-execute: (and quorum-met majority-met voting-ended (not (get executed proposal))),
        total-votes: total-votes
      })
    )
    none
  )
)

(define-read-only (get-dao-stats)
  {
    total-members: (var-get total-members),
    total-stake: (var-get total-stake),
    treasury-balance: (var-get treasury-balance),
    next-proposal-id: (var-get next-proposal-id)
  }
)


(define-map member-reputation
  principal
  {
    total-score: uint,
    proposals-created: uint,
    proposals-passed: uint,
    votes-cast: uint,
    participation-rate: uint,
    trust-level: (string-ascii 20)
  }
)

(define-map reputation-history
  { member: principal, action-id: uint }
  {
    action-type: (string-ascii 30),
    score-change: int,
    timestamp: uint
  }
)

(define-data-var next-action-id uint u1)

(define-private (calculate-trust-level (score uint))
  (if (>= score u1000)
    "legendary"
    (if (>= score u500)
      "veteran"
      (if (>= score u200)
        "trusted"
        (if (>= score u50)
          "active"
          "newcomer"
        )
      )
    )
  )
)

(define-private (update-participation-rate (member principal))
  (let
    (
      (rep-data (default-to
        { total-score: u0, proposals-created: u0, proposals-passed: u0, 
          votes-cast: u0, participation-rate: u0, trust-level: "newcomer" }
        (map-get? member-reputation member)
      ))
      (proposals-created (get proposals-created rep-data))
      (proposals-passed (get proposals-passed rep-data))
    )
    (if (> proposals-created u0)
      (/ (* proposals-passed u100) proposals-created)
      u0
    )
  )
)

(define-public (award-reputation (member principal) (points uint) (action (string-ascii 30)))
  (let
    (
      (action-id (var-get next-action-id))
      (current-rep (default-to
        { total-score: u0, proposals-created: u0, proposals-passed: u0,
          votes-cast: u0, participation-rate: u0, trust-level: "newcomer" }
        (map-get? member-reputation member)
      ))
      (new-score (+ (get total-score current-rep) points))
    )
    (map-set member-reputation member
      (merge current-rep
        {
          total-score: new-score,
          trust-level: (calculate-trust-level new-score)
        }
      )
    )
    
    (map-set reputation-history { member: member, action-id: action-id }
      {
        action-type: action,
        score-change: (to-int points),
        timestamp: stacks-block-height
      }
    )
    
    (var-set next-action-id (+ action-id u1))
    (ok true)
  )
)

(define-public (record-vote-cast (voter principal))
  (let
    (
      (current-rep (default-to
        { total-score: u0, proposals-created: u0, proposals-passed: u0,
          votes-cast: u0, participation-rate: u0, trust-level: "newcomer" }
        (map-get? member-reputation voter)
      ))
    )
    (map-set member-reputation voter
      (merge current-rep
        {
          votes-cast: (+ (get votes-cast current-rep) u1),
          total-score: (+ (get total-score current-rep) u5)
        }
      )
    )

    (ok true)
  )
)

(define-public (record-proposal-created (proposer principal))
  (let
    (
      (current-rep (default-to
        { total-score: u0, proposals-created: u0, proposals-passed: u0,
          votes-cast: u0, participation-rate: u0, trust-level: "newcomer" }
        (map-get? member-reputation proposer)
      ))
    )
    (map-set member-reputation proposer
      (merge current-rep
        {
          proposals-created: (+ (get proposals-created current-rep) u1),
          total-score: (+ (get total-score current-rep) u10)
        }
      )
    )

    (ok true)
  )
)

(define-public (record-proposal-passed (proposer principal))
  (let
    (
      (current-rep (default-to
        { total-score: u0, proposals-created: u0, proposals-passed: u0,
          votes-cast: u0, participation-rate: u0, trust-level: "newcomer" }
        (map-get? member-reputation proposer)
      ))
      (new-passed (+ (get proposals-passed current-rep) u1))
      (new-rate (update-participation-rate proposer))
    )
    (map-set member-reputation proposer
      (merge current-rep
        {
          proposals-passed: new-passed,
          participation-rate: new-rate,
          total-score: (+ (get total-score current-rep) u25)
        }
      )
    )

    (ok true)
  )
)

(define-read-only (get-member-reputation (member principal))
  (map-get? member-reputation member)
)

(define-read-only (get-reputation-history (member principal) (action-id uint))
  (map-get? reputation-history { member: member, action-id: action-id })
)

(define-read-only (get-trust-level (member principal))
  (match (map-get? member-reputation member)
    rep-data (get trust-level rep-data)
    "newcomer"
  )
)

(define-read-only (get-reputation-score (member principal))
  (match (map-get? member-reputation member)
    rep-data (get total-score rep-data)
    u0
  )
)
