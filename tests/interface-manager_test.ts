import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Ensure members can register with initial stake",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;

        const block = chain.mineBlock([
            Tx.contractCall('interface-manager', 'register-member', 
                [types.uint(1000)], 
                wallet1.address)
        ]);

        // First assert verifies the transaction succeeded
        block.receipts[0].result.expectOk();

        // Validate member registration by checking details
        const memberDetails = chain.callReadOnlyFn(
            'interface-manager', 
            'get-member-info', 
            [types.principal(wallet1.address)],
            wallet1.address
        );

        memberDetails.result.expectSome();
    }
});

Clarinet.test({
    name: "Prevent duplicate member registration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;

        const block = chain.mineBlock([
            Tx.contractCall('interface-manager', 'register-member', 
                [types.uint(1000)], 
                wallet1.address),
            Tx.contractCall('interface-manager', 'register-member', 
                [types.uint(1000)], 
                wallet1.address)
        ]);

        // First registration should work
        block.receipts[0].result.expectOk();
        
        // Second registration should fail
        block.receipts[1].result.expectErr().expectUint(101);
    }
});

Clarinet.test({
    name: "Create proposal with valid parameters",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;

        // First register member
        chain.mineBlock([
            Tx.contractCall('interface-manager', 'register-member', 
                [types.uint(5000)], 
                wallet1.address)
        ]);

        const block = chain.mineBlock([
            Tx.contractCall('interface-manager', 'create-proposal', 
                [
                    types.ascii('UI Enhancement'),
                    types.utf8('Improving navigation and user experience'),
                    types.uint(1000),
                    types.ascii('https://example.com/proposal')
                ], 
                wallet1.address)
        ]);

        // Assert proposal creation succeeded
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Stake-weighted voting on proposal",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;
        const wallet2 = accounts.get('wallet_2')!;

        // Register members with different stakes
        chain.mineBlock([
            Tx.contractCall('interface-manager', 'register-member', 
                [types.uint(5000)], 
                wallet1.address),
            Tx.contractCall('interface-manager', 'register-member', 
                [types.uint(2000)], 
                wallet2.address)
        ]);

        // Create a proposal
        chain.mineBlock([
            Tx.contractCall('interface-manager', 'create-proposal', 
                [
                    types.ascii('UI Enhancement'),
                    types.utf8('Improving navigation and user experience'),
                    types.uint(1000),
                    types.ascii('https://example.com/proposal')
                ], 
                wallet1.address)
        ]);

        // Activate proposal
        chain.mineBlock([
            Tx.contractCall('interface-manager', 'activate-proposal', 
                [types.uint(1)], 
                wallet1.address)
        ]);

        // Vote with different stakes
        const block = chain.mineBlock([
            Tx.contractCall('interface-manager', 'vote-on-proposal', 
                [types.uint(1), types.bool(true)], 
                wallet1.address),
            Tx.contractCall('interface-manager', 'vote-on-proposal', 
                [types.uint(1), types.bool(false)], 
                wallet2.address)
        ]);

        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
    }
});