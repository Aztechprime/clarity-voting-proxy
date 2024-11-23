import {
    Clarinet,
    Tx,
    Chain,
    Account,
    types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Test delegation flow",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const voter1 = accounts.get('wallet_1')!;
        const voter2 = accounts.get('wallet_2')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'delegate-vote', 
                [types.principal(voter2.address)], 
                voter1.address
            )
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
        
        // Verify delegation
        let checkBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'get-delegate',
                [types.principal(voter1.address)],
                deployer.address
            )
        ]);
        
        checkBlock.receipts[0].result.expectOk().expectSome().assertEquals(voter2.address);
    }
});

Clarinet.test({
    name: "Test proposal creation and voting",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const voter = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'create-proposal',
                [types.ascii("Test Proposal")],
                deployer.address
            )
        ]);
        
        block.receipts[0].result.expectOk().expectUint(0);
        
        // Test voting
        let voteBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'vote',
                [types.uint(0), types.bool(true)],
                voter.address
            )
        ]);
        
        voteBlock.receipts[0].result.expectOk().expectBool(true);
        
        // Verify proposal state
        let checkBlock = chain.mineBlock([
            Tx.contractCall('voting-proxy', 'get-proposal',
                [types.uint(0)],
                deployer.address
            )
        ]);
        
        let proposal = checkBlock.receipts[0].result.expectOk().expectSome();
        assertEquals(proposal['votes-for'], types.uint(1));
    }
});
