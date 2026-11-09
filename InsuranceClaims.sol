// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InsuranceClaims
/// @notice Blockchain middle layer between a policyholder (sender) and an insurer (receiver).
///         Premiums, claims and payouts are recorded on-chain; evidence documents stay
///         off-chain and only their hash is stored (tamper-proof, privacy friendly).
contract InsuranceClaims {

    // ---------- Types ----------
    enum PolicyStatus { None, Active, Expired }
    enum ClaimStatus  { None, Submitted, Approved, Rejected, Paid }

    struct Policy {
        address holder;
        uint256 premium;      // wei paid
        uint256 coverage;     // max payout in wei
        uint256 startTime;
        uint256 endTime;
        PolicyStatus status;
    }

    struct Claim {
        uint256 policyId;
        address holder;
        uint256 amount;       // requested amount in wei
        bytes32 evidenceHash; // hash of photos/reports kept off-chain
        uint256 filedAt;
        ClaimStatus status;
    }

    // ---------- State ----------
    address public insurer;           // receiver of premiums, approves claims
    address public assessor;          // independent claims assessor
    uint256 public premiumRate = 5;   // premium = coverage * 5 / 100
    uint256 public policyCount;
    uint256 public claimCount;

    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim)  public claims;
    mapping(uint256 => bool)   private policyHasOpenClaim;

    // ---------- Events (audit trail) ----------
    event PolicyPurchased(uint256 indexed policyId, address indexed holder, uint256 coverage, uint256 premium);
    event ClaimSubmitted(uint256 indexed claimId, uint256 indexed policyId, uint256 amount, bytes32 evidenceHash);
    event ClaimApproved(uint256 indexed claimId, address indexed by);
    event ClaimRejected(uint256 indexed claimId, address indexed by);
    event ClaimPaid(uint256 indexed claimId, address indexed holder, uint256 amount);
    event PoolFunded(address indexed from, uint256 amount);

    // ---------- Modifiers ----------
    modifier onlyInsurer() {
        require(msg.sender == insurer, "Only insurer");
        _;
    }

    modifier onlyAssessorOrInsurer() {
        require(msg.sender == assessor || msg.sender == insurer, "Only assessor or insurer");
        _;
    }

    constructor(address _assessor) {
        insurer = msg.sender;
        assessor = _assessor;
    }

    // ---------- Insurer funds the payout pool ----------
    function fundPool() external payable onlyInsurer {
        require(msg.value > 0, "Send some ether");
        emit PoolFunded(msg.sender, msg.value);
    }

    // ---------- Policyholder buys a policy (sender -> receiver) ----------
    function buyPolicy(uint256 coverage, uint256 durationDays) external payable returns (uint256 policyId) {
        require(coverage > 0, "Coverage must be > 0");
        require(durationDays > 0, "Duration must be > 0");
        uint256 premium = (coverage * premiumRate) / 100;
        require(msg.value == premium, "Send exact premium");

        policyId = ++policyCount;
        policies[policyId] = Policy({
            holder: msg.sender,
            premium: premium,
            coverage: coverage,
            startTime: block.timestamp,
            endTime: block.timestamp + (durationDays * 1 days),
            status: PolicyStatus.Active
        });

        emit PolicyPurchased(policyId, msg.sender, coverage, premium);
    }

    function quotePremium(uint256 coverage) external view returns (uint256) {
        return (coverage * premiumRate) / 100;
    }

    // ---------- Policyholder files a claim ----------
    function submitClaim(uint256 policyId, uint256 amount, bytes32 evidenceHash)
        external
        returns (uint256 claimId)
    {
        Policy storage p = policies[policyId];
        require(p.status == PolicyStatus.Active, "Policy not active");
        require(p.holder == msg.sender, "Not policy holder");
        require(block.timestamp <= p.endTime, "Policy expired");
        require(amount > 0 && amount <= p.coverage, "Invalid amount");
        require(!policyHasOpenClaim[policyId], "Open claim exists");

        claimId = ++claimCount;
        claims[claimId] = Claim({
            policyId: policyId,
            holder: msg.sender,
            amount: amount,
            evidenceHash: evidenceHash,
            filedAt: block.timestamp,
            status: ClaimStatus.Submitted
        });
        policyHasOpenClaim[policyId] = true;

        emit ClaimSubmitted(claimId, policyId, amount, evidenceHash);
    }

    // ---------- Assessor / insurer decision ----------
    function approveClaim(uint256 claimId) external onlyAssessorOrInsurer {
        Claim storage c = claims[claimId];
        require(c.status == ClaimStatus.Submitted, "Not awaiting decision");
        c.status = ClaimStatus.Approved;
        emit ClaimApproved(claimId, msg.sender);
    }

    function rejectClaim(uint256 claimId) external onlyAssessorOrInsurer {
        Claim storage c = claims[claimId];
        require(c.status == ClaimStatus.Submitted, "Not awaiting decision");
        c.status = ClaimStatus.Rejected;
        policyHasOpenClaim[c.policyId] = false;
        emit ClaimRejected(claimId, msg.sender);
    }

    // ---------- Automatic payout (insurer -> policyholder) ----------
    function payClaim(uint256 claimId) external onlyInsurer {
        Claim storage c = claims[claimId];
        require(c.status == ClaimStatus.Approved, "Claim not approved");
        require(address(this).balance >= c.amount, "Pool too low");

        // Effects before interaction (reentrancy-safe pattern)
        c.status = ClaimStatus.Paid;
        policies[c.policyId].status = PolicyStatus.Expired; // one payout per policy
        policyHasOpenClaim[c.policyId] = false;

        (bool ok, ) = payable(c.holder).call{value: c.amount}("");
        require(ok, "Transfer failed");

        emit ClaimPaid(claimId, c.holder, c.amount);
    }

    // ---------- Helpers ----------
    function poolBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Anyone can verify an evidence file by hashing it and comparing.
    function verifyEvidence(uint256 claimId, bytes32 fileHash) external view returns (bool) {
        return claims[claimId].evidenceHash == fileHash;
    }

    // Premiums arrive via buyPolicy; reject stray transfers
    receive() external payable {
        revert("Use buyPolicy or fundPool");
    }
}
