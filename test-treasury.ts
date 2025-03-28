import { JsonRpcProvider, TransactionBlock, Ed25519Keypair } from '@mysten/sui.js';
import { fromB64 } from '@mysten/sui.js/utils';

// Configuration
const PACKAGE_ID = "0x9f70cea5256cff8947144c40481b7368570cdd252607c4dd41c24546e490c1f9";
const RPC_URL = "https://fullnode.testnet.sui.io:443";

// Initialize provider and keypair
const provider = new JsonRpcProvider({ url: RPC_URL });
const keypair = Ed25519Keypair.fromSecretKey(fromB64("YOUR_PRIVATE_KEY")); // Replace with your private key from: sui client export-private-key <ADDRESS>

// State
let treasuryId: string;
let managerCapId: string;
let proposalId: string;
let lpTokenId: string;

// Helper function to execute transactions
async function executeTransaction(tx: TransactionBlock) {
    const result = await provider.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showEvents: true
        }
    });
    console.log("Transaction result:", result);
    return result;
}

// Create new treasury
export async function createTreasury(initialBalance: number, requiredVotes: number, initialPoolValue: number) {
    const tx = new TransactionBlock();

    // Create initial balance
    const [initialBalanceCoin] = tx.splitCoins(tx.gas, [tx.pure(initialBalance)]);

    const [treasury, managerCap] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::new`,
        arguments: [
            initialBalanceCoin,
            tx.pure(requiredVotes),
            tx.pure(initialPoolValue)
        ]
    });

    const result = await executeTransaction(tx);
    treasuryId = result.effects?.created?.[0]?.objectId || "";
    managerCapId = result.effects?.created?.[1]?.objectId || "";

    console.log("Created Treasury:", treasuryId);
    console.log("Created ManagerCap:", managerCapId);

    return { treasuryId, managerCapId };
}

// Deposit SUI
export async function deposit(amount: number) {
    const tx = new TransactionBlock();

    // Create a coin for deposit
    const [coin] = tx.splitCoins(tx.gas, [tx.pure(amount)]);

    const [lpToken] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::deposit`,
        arguments: [
            tx.object(treasuryId),
            coin
        ]
    });

    const result = await executeTransaction(tx);
    lpTokenId = result.effects?.created?.[0]?.objectId || "";

    console.log("Created LPToken:", lpTokenId);
    return lpTokenId;
}

// Create withdrawal proposal
export async function createProposal(recipient: string, amount: number) {
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::create_proposal`,
        arguments: [
            tx.object(treasuryId),
            tx.object(managerCapId),
            tx.pure(recipient),
            tx.pure(amount)
        ]
    });

    const result = await executeTransaction(tx);
    proposalId = result.effects?.created?.[0]?.objectId || "";

    console.log("Created Proposal:", proposalId);
    return proposalId;
}

// Vote on proposal
export async function vote() {
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::vote`,
        arguments: [
            tx.object(proposalId),
            tx.object(lpTokenId)
        ]
    });

    await executeTransaction(tx);
}

// Execute proposal
export async function executeProposal() {
    const tx = new TransactionBlock();

    const [withdrawnCoin] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::execute_proposal`,
        arguments: [
            tx.object(treasuryId),
            tx.object(proposalId),
            tx.object(managerCapId)
        ]
    });

    const result = await executeTransaction(tx);
    console.log("Withdrawn coin:", result.effects?.created?.[0]?.objectId);
}

// Withdraw SUI
export async function withdraw() {
    const tx = new TransactionBlock();

    const [withdrawnCoin] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::withdraw`,
        arguments: [
            tx.object(treasuryId),
            tx.object(lpTokenId)
        ]
    });

    const result = await executeTransaction(tx);
    console.log("Withdrawn coin:", result.effects?.created?.[0]?.objectId);
}

// Example usage
async function main() {
    try {
        // Create treasury with 1000 SUI initial balance
        await createTreasury(1000, 2, 1000);

        // Deposit 100 SUI
        await deposit(100);

        // Create proposal to withdraw 50 SUI
        await createProposal("0xcdb0d91425fb5ca2541d30685cd1347483363ddf172ef8561a7d2869819420af", 50);

        // Vote
        await vote();

        // Execute proposal
        await executeProposal();

        // Withdraw remaining LP tokens
        await withdraw();
    } catch (error) {
        console.error("Error:", error);
    }
}

// Run if called directly
if (require.main === module) {
    main();
} 