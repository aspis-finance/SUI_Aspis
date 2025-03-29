import { SuiClient } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { fromB64 } from '@mysten/sui.js/utils';

// Configuration
const PACKAGE_ID = "0x00cf538658ebb2933d139a41ba3be0f6d0e48a178986987c142e1729dbc6598b";
const RPC_URL = "https://fullnode.devnet.sui.io:443";

// Initialize provider and keypair
const provider = new SuiClient({ url: RPC_URL });

// Мнемоническая фраза
const MNEMONIC = "erode enroll credit vicious custom they friend layer large enact leave story";

// Создаем keypair из мнемоники
const keypair = Ed25519Keypair.deriveKeypair(MNEMONIC);

// Выводим адрес для проверки
const address = keypair.getPublicKey().toSuiAddress();
console.log("Derived address:", address);

// Можно также попробовать с другим путем деривации
const keypairWithPath = Ed25519Keypair.deriveKeypair(MNEMONIC, "m/44'/784'/0'/0'/0'");
console.log("Derived address with path:", keypairWithPath.getPublicKey().toSuiAddress());

// State
let treasuryId: string;
let managerCapId: string;
let proposalId: string;
let lpTokenId: string;

// Helper function to execute transactions
async function executeTransaction(tx: TransactionBlock) {
    try {
        // Добавляем газовый бюджет
        tx.setGasBudget(20000000);

        console.log("Executing transaction with address:", keypair.getPublicKey().toSuiAddress());

        // Получим список монет перед транзакцией
        const coins = await provider.getCoins({
            owner: keypair.getPublicKey().toSuiAddress()
        });
        console.log("Available coins:", coins);

        const result = await provider.signAndExecuteTransactionBlock({
            transactionBlock: tx,
            signer: keypair,
            options: {
                showEffects: true,
                showEvents: true,
                showObjectChanges: true
            }
        });
        console.log("Transaction result:", result);
        return result;
    } catch (error) {
        console.error("Transaction error details:", error);
        throw error;
    }
}

// Create new treasury
async function createTreasury(requiredVotes: number) {
    const tx = new TransactionBlock();

    const [treasury, managerCap] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::new`,
        arguments: [
            tx.pure.u64(requiredVotes)
        ]
    });

    const result = await executeTransaction(tx);

    if (result.effects?.status?.status === 'success') {
        treasuryId = result.effects?.created?.[0]?.reference.objectId || "";
        managerCapId = result.effects?.created?.[1]?.reference.objectId || "";
        console.log("Created Treasury:", treasuryId);
        console.log("Created ManagerCap:", managerCapId);
        return { treasuryId, managerCapId };
    } else {
        throw new Error(`Failed to create treasury: ${result.effects?.status?.error}`);
    }
}

// Deposit SUI
async function deposit(amount: number) {
    const tx = new TransactionBlock();
    const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(amount)]);

    const [lpToken] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::deposit`,
        arguments: [
            tx.object(treasuryId),
            coin
        ]
    });

    const result = await executeTransaction(tx);
    lpTokenId = result.effects?.created?.[0]?.reference.objectId || "";
    console.log("Deposited amount:", amount, "MIST");
    console.log("Created LPToken:", lpTokenId);
    return lpTokenId;
}

// Create withdrawal proposal
async function createProposal(recipient: string, amount: number) {
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::create_proposal`,
        arguments: [
            tx.object(treasuryId),
            tx.object(managerCapId),
            tx.pure.address(recipient),
            tx.pure.u64(amount)
        ]
    });

    const result = await executeTransaction(tx);
    proposalId = result.effects?.created?.[0]?.reference.objectId || "";
    console.log("Created proposal for amount:", amount, "MIST");
    console.log("Proposal ID:", proposalId);
    return proposalId;
}

// Vote on proposal
async function vote() {
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
async function executeProposal() {
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
    console.log("Withdrawn coin:", result.effects?.created?.[0]?.reference.objectId);
}

// Withdraw SUI
async function withdraw() {
    const tx = new TransactionBlock();

    const [withdrawnCoin] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::withdraw`,
        arguments: [
            tx.object(treasuryId),
            tx.object(lpTokenId)
        ]
    });

    const result = await executeTransaction(tx);
    console.log("Withdrawn coin:", result.effects?.created?.[0]?.reference.objectId);
}

// Функция для взаимодействия с контрактом
async function interactWithContract(packageId: string) {
    // Создаем treasury с 1 SUI initial balance
    const { treasuryId, managerCapId } = await createTreasury(2);
    console.log("Created treasury:", treasuryId);

    // Депозит 1 SUI
    const lpTokenId = await deposit(1);
    console.log("Deposited, LP token:", lpTokenId);

    // Создаем proposal
    const myAddress = keypair.getPublicKey().toSuiAddress();
    const proposalId = await createProposal(myAddress, 50);
    console.log("Created proposal:", proposalId);
}

async function main() {
    try {
        console.log("Starting treasury test script...");

        // Create treasury with 2 required votes
        console.log("Creating treasury...");
        await createTreasury(2);

        // Deposit 1 SUI
        console.log("Depositing 1 SUI...");
        await deposit(1_000_000_000); // 1 SUI = 1_000_000_000 MIST

        // Create proposal to withdraw 0.5 SUI
        console.log("Creating withdrawal proposal...");
        const myAddress = keypair.getPublicKey().toSuiAddress();
        await createProposal(myAddress, 500_000_000); // 0.5 SUI

        // Vote on proposal
        console.log("Voting on proposal...");
        await vote();

        // Execute proposal
        console.log("Executing proposal...");
        await executeProposal();

        // Withdraw remaining LP tokens
        console.log("Withdrawing remaining LP tokens...");
        await withdraw();

        console.log("Test script completed successfully!");
    } catch (error) {
        console.error("Error in test script:", error);
    }
}

// Запускаем
main().catch(console.error); 