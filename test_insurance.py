"""
Deploys InsuranceClaims to local Ganache and runs the full claim lifecycle.
Run: python test_insurance.py   (Ganache must be running on http://127.0.0.1:8545)
"""
import hashlib
from solcx import compile_standard, install_solc
from web3 import Web3

SOLC_VERSION = "0.8.20"
install_solc(SOLC_VERSION)

source = open("InsuranceClaims.sol").read()
compiled = compile_standard(
    {
        "language": "Solidity",
        "sources": {"InsuranceClaims.sol": {"content": source}},
        "settings": {"outputSelection": {"*": {"*": ["abi", "evm.bytecode"]}}},
    },
    solc_version=SOLC_VERSION,
)
contract_data = compiled["contracts"]["InsuranceClaims.sol"]["InsuranceClaims"]
abi = contract_data["abi"]
bytecode = contract_data["evm"]["bytecode"]["object"]

w3 = Web3(Web3.HTTPProvider("http://127.0.0.1:8545"))
assert w3.is_connected(), "Start Ganache first (ganache --port 8545)"

insurer, assessor, holder = w3.eth.accounts[0], w3.eth.accounts[1], w3.eth.accounts[2]


def send(fn, sender, value=0):
    tx = fn.transact({"from": sender, "value": value})
    return w3.eth.wait_for_transaction_receipt(tx)


# 1. Deploy
Contract = w3.eth.contract(abi=abi, bytecode=bytecode)
receipt = w3.eth.wait_for_transaction_receipt(
    Contract.constructor(assessor).transact({"from": insurer})
)
c = w3.eth.contract(address=receipt.contractAddress, abi=abi)
print("Deployed at:", c.address)

# 2. Insurer funds the payout pool (5 ETH)
send(c.functions.fundPool(), insurer, w3.to_wei(5, "ether"))
print("Pool balance (ETH):", w3.from_wei(c.functions.poolBalance().call(), "ether"))

# 3. Policyholder buys a policy: coverage 2 ETH, 30 days
coverage = w3.to_wei(2, "ether")
premium = c.functions.quotePremium(coverage).call()
send(c.functions.buyPolicy(coverage, 30), holder, premium)
print("Policy 1 bought, premium (ETH):", w3.from_wei(premium, "ether"))

# 4. Policyholder submits claim with hashed evidence
evidence = b"photo_of_damage + police_report"
evidence_hash = hashlib.sha256(evidence).digest()
send(c.functions.submitClaim(1, w3.to_wei(1, "ether"), evidence_hash), holder)
print("Claim 1 submitted, status:", c.functions.claims(1).call()[5], "(1 = Submitted)")

# 5. Evidence verification
print("Evidence verifies:", c.functions.verifyEvidence(1, evidence_hash).call())

# 6. Assessor approves
send(c.functions.approveClaim(1), assessor)
print("Claim 1 status:", c.functions.claims(1).call()[5], "(2 = Approved)")

# 7. Insurer pays out
before = w3.eth.get_balance(holder)
send(c.functions.payClaim(1), insurer)
after = w3.eth.get_balance(holder)
print("Holder received (ETH):", w3.from_wei(after - before, "ether"))
print("Claim 1 status:", c.functions.claims(1).call()[5], "(4 = Paid)")

# 8. Negative test: stranger cannot approve
try:
    send(c.functions.approveClaim(1), holder)
except Exception as e:
    print("Unauthorized approve blocked:", str(e)[:70])

print("\nAll steps completed.")
