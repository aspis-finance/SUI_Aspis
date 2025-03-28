import { SuiClient } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { fromB64 } from '@mysten/sui.js/utils';

// Configuration
const PACKAGE_ID = "0xd3cec38ed63345f1e8b17fca3b3955c02285710ff7b415043d1d77d3d6655b00";
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
async function createTreasury(initialBalance: number, requiredVotes: number, initialPoolValue: number) {
    console.log("Creating treasury with balance:", initialBalance);
    const tx = new TransactionBlock();

    // Create initial balance
    console.log("Splitting coins...");
    const [initialBalanceCoin] = tx.splitCoins(tx.gas, [tx.pure(initialBalance)]);

    console.log("Calling new treasury...");
    const [treasury, managerCap] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::new`,
        arguments: [
            initialBalanceCoin,
            tx.pure(requiredVotes),
            tx.pure(initialPoolValue)
        ]
    });

    const result = await executeTransaction(tx);
    treasuryId = result.effects?.created?.[0]?.reference.objectId || "";
    managerCapId = result.effects?.created?.[1]?.reference.objectId || "";

    console.log("Created Treasury:", treasuryId);
    console.log("Created ManagerCap:", managerCapId);
    return { treasuryId, managerCapId };
}

// Deposit SUI
async function deposit(amount: number) {
    const tx = new TransactionBlock();
    const [coin] = tx.splitCoins(tx.gas, [tx.pure(amount)]);

    const [lpToken] = tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::deposit`,
        arguments: [
            tx.object(treasuryId),
            coin
        ]
    });

    const result = await executeTransaction(tx);
    lpTokenId = result.effects?.created?.[0]?.reference.objectId || "";

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
            tx.pure(recipient),
            tx.pure(amount)
        ]
    });

    const result = await executeTransaction(tx);
    proposalId = result.effects?.created?.[0]?.reference.objectId || "";

    console.log("Created Proposal:", proposalId);
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
    const { treasuryId, managerCapId } = await createTreasury(1, 2, 1000);
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
        // Create treasury with 0.1 SUI initial balance
        await createTreasury(100000000, 2, 100000000); // 0.1 SUI = 100000000 MIST

        // Deposit 0.1 SUI
        await deposit(100000000); // 0.1 SUI

        // Create proposal to withdraw 0.05 SUI
        const myAddress = keypair.getPublicKey().toSuiAddress();
        await createProposal(myAddress, 50000000); // 0.05 SUI

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

// Запускаем
main(); 