import {
    Clarinet,
    Tx,
    Chain,
    Account,
    types
} from 'https://deno.land/x/clarinet@v1.0.2/index.ts';
import { assertEquals, assertObjectEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Delegation: Prevent self-delegation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const voter = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'delegate-vote', 
                [types.principal(voter.address)], 
                voter.address
            )
        ]);
        
        block.receipts[0].result.expectErr().expectUint(105); // ERR_SELF_DELEGATION
    }
});

Clarinet.test({
    name: "Delegation: Multiple delegations and revocation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const voter1 = accounts.get('wallet_1')!;
        const voter2 = accounts.get('wallet_2')!;
        const voter3 = accounts.get('wallet_3')!;
        
        // First delegation
        let firstBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'delegate-vote', 
                [types.principal(voter2.address)], 
                voter1.address
            )
        ]);
        firstBlock.receipts[0].result.expectOk().expectBool(true);
        
        // Attempt duplicate delegation (should fail)
        let duplicateBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'delegate-vote', 
                [types.principal(voter2.address)], 
                voter1.address
            )
        ]);
        duplicateBlock.receipts[0].result.expectErr().expectUint(101); // ERR_ALREADY_DELEGATED
        
        // Delegate from another account
        let secondBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'delegate-vote', 
                [types.principal(voter3.address)], 
                voter2.address
            )
        ]);
        secondBlock.receipts[0].result.expectOk().expectBool(true);
        
        // Revoke delegation
        let revokeBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'revoke-delegation', 
                [], 
                voter1.address
            )
        ]);
        revokeBlock.receipts[0].result.expectOk().expectBool(true);
    }
});

Clarinet.test({
    name: "Proposal: Create and vote with input validation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const voter = accounts.get('wallet_1')!;
        
        // Attempt proposal creation with long title (should fail)
        let longTitleBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'create-proposal', 
                [
                    types.ascii("This is an extremely long proposal title that exceeds the maximum allowed length of 50 characters")
                ],
                deployer.address
            )
        ]);
        longTitleBlock.receipts[0].result.expectErr().expectUint(103); // ERR_INVALID_PROPOSAL
        
        // Create valid proposal
        let createBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'create-proposal', 
                [
                    types.ascii("Valid Proposal"),
                    types.uint(100)  // Expiration blocks
                ],
                deployer.address
            )
        ]);
        createBlock.receipts[0].result.expectOk().expectUint(0);
        
        // Vote on proposal
        let voteBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'vote', 
                [types.uint(0), types.bool(true)],
                voter.address
            )
        ]);
        voteBlock.receipts[0].result.expectOk().expectBool(true);
        
        // Check proposal details
        let checkBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'get-proposal-summary', 
                [types.uint(0)],
                deployer.address
            )
        ]);
        let proposalSummary = checkBlock.receipts[0].result.expectOk().expectSome();
        assertEquals(proposalSummary['votes-for'], types.uint(1));
    }
});

Clarinet.test({
    name: "Proposal: Expiration and Invalid Voting Scenarios",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const voter = accounts.get('wallet_1')!;
        
        // Create proposal with minimal expiration
        let createBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'create-proposal', 
                [
                    types.ascii("Expiring Soon"),
                    types.uint(1)  // Very short expiration
                ],
                deployer.address
            )
        ]);
        createBlock.receipts[0].result.expectOk().expectUint(0);
        
        // Mine enough blocks to expire the proposal
        chain.mineEmptyBlock(2);
        
        // Attempt to vote on expired proposal
        let expiredVoteBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'vote', 
                [types.uint(0), types.bool(true)],
                voter.address
            )
        ]);
        expiredVoteBlock.receipts[0].result.expectErr().expectUint(104); // ERR_PROPOSAL_EXPIRED
    }
});

Clarinet.test({
    name: "Delegation: Read-only Functions and Authorization",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const voter1 = accounts.get('wallet_1')!;
        const voter2 = accounts.get('wallet_2')!;
        const deployer = accounts.get('deployer')!;
        
        // Delegate vote
        let delegateBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'delegate-vote', 
                [types.principal(voter2.address)], 
                voter1.address
            )
        ]);
        delegateBlock.receipts[0].result.expectOk().expectBool(true);
        
        // Check delegation details
        let detailsBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'get-delegation-details', 
                [types.principal(voter1.address)],
                deployer.address
            )
        ]);
        let delegationDetails = detailsBlock.receipts[0].result.expectSome();
        assertEquals(delegationDetails['delegation-time'], types.uint(1));
        assertEquals(delegationDetails['vote-power'], types.uint(1));
    }
});

Clarinet.test({
    name: "Total Voting Power: Calculation Verification",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const voter1 = accounts.get('wallet_1')!;
        const voter2 = accounts.get('wallet_2')!;
        
        // Create proposal
        let createBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'create-proposal', 
                [
                    types.ascii("Voting Power Test"),
                    types.uint(100)
                ],
                deployer.address
            )
        ]);
        createBlock.receipts[0].result.expectOk().expectUint(0);
        
        // Multiple voters
        let voteBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'vote', 
                [types.uint(0), types.bool(true)],
                voter1.address
            ),
            Tx.contractCall('voting-proxy', 'vote', 
                [types.uint(0), types.bool(false)],
                voter2.address
            )
        ]);
        voteBlock.receipts[0].result.expectOk().expectBool(true);
        voteBlock.receipts[1].result.expectOk().expectBool(true);
        
        // Calculate total voting power
        let powerBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'calculate-total-voting-power', 
                [types.uint(0)],
                deployer.address
            )
        ]);
        powerBlock.receipts[0].result.expectOk().expectUint(2);
    }
});
