# Blockchain Insurance Claims DApp

Smart contract that lets a policyholder (sender) buy a policy, file a claim, and receive an automatic payout from an insurer (receiver), with the blockchain as the trusted middle layer.

## Files
- `InsuranceClaims.sol` – Solidity smart contract
- `test_insurance.py` – deploys to Ganache and runs the full claim lifecycle
- `run.sh` – starts Ganache and runs the test

## Run with Ganache + Python
```bash
chmod +x run.sh
./run.sh
```

## Test in Remix IDE 
1. Open https://remix.ethereum.org and paste `InsuranceClaims.sol`.
2. Compile with Solidity 0.8.20.
3. Deploy & Run: Environment = Remix VM. Account 1 = insurer, Account 2 = assessor, Account 3 = holder.
4. Deploy with Account 1, constructor argument = Account 2 address.
5. `fundPool` from Account 1 with value 5 ether. 
6. Switch to Account 3: `quotePremium(2000000000000000000)`, then `buyPolicy(2000000000000000000, 30)` sending the premium (0.1 ether). 
7. `submitClaim(1, 1000000000000000000, 0x<32-byte hash>)`. 
8. Switch to Account 2: `approveClaim(1)`. Screenshot.
9. Switch to Account 1: `payClaim(1)`. Check `claims(1)` shows status 4 (Paid). 
10. Failure test: Account 3 calls `approveClaim` and the transaction reverts "Only assessor or insurer". 

## Roles
| Role | Account | Can do |
|---|---|---|
| Insurer | deployer | fund pool, approve/reject, pay |
| Assessor | set at deploy | approve/reject |
| Policyholder | anyone | buy policy, submit claim |
