import { SuiClient } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { fromB64 } from '@mysten/sui.js/utils';

// Configuration
const PACKAGE_ID = "0xcaa136654bee12efac50cbb345b5f0327a27374398b60130842607152461bb0a";
const RPC_URL = "https://fullnode.devnet.sui.io:443";

// Initialize provider and keypairs
const provider = new SuiClient({ url: RPC_URL });

// Мнемонические фразы для двух кошельков
const MNEMONIC_1 = "erode enroll credit vicious custom they friend layer large enact leave story";
const MNEMONIC_2 = "spare crack birth steak trigger public random vague afford december ignore stand";

// Создаем keypairs из мнемоник
const keypair1 = Ed25519Keypair.deriveKeypair(MNEMONIC_1);
const keypair2 = Ed25519Keypair.deriveKeypair(MNEMONIC_2);

// Выводим адреса для проверки
console.log("Wallet 1 address:", keypair1.getPublicKey().toSuiAddress());
console.log("Wallet 2 address:", keypair2.getPublicKey().toSuiAddress());

// State
let treasuryId: string;
let managerCapId: string;
let proposalId: string;
let lpTokenId1: string;
let lpTokenId2: string;

// Helper function to execute transactions
async function executeTransaction(tx: TransactionBlock, signer: Ed25519Keypair) {
    try {
        // Добавляем газовый бюджет
        tx.setGasBudget(20000000);

        console.log("Executing transaction with address:", signer.getPublicKey().toSuiAddress());

        // Получим список монет перед транзакцией
        const coins = await provider.getCoins({
            owner: signer.getPublicKey().toSuiAddress()
        });
        console.log("Available coins:", coins);

        const result = await provider.signAndExecuteTransactionBlock({
            transactionBlock: tx,
            signer: signer,
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

    const result = await executeTransaction(tx, keypair1);

    if (result.effects?.status?.status === 'success') {
        // Находим Treasury по типу объекта
        const treasuryObj = result.objectChanges?.find(
            change => change.type === 'created' &&
                change.objectType.includes('::treasury_voting::Treasury')
        );

        // Находим ManagerCap по типу объекта
        const managerCapObj = result.objectChanges?.find(
            change => change.type === 'created' &&
                change.objectType.includes('::treasury_voting::ManagerCap')
        );

        if (treasuryObj && 'objectId' in treasuryObj &&
            managerCapObj && 'objectId' in managerCapObj) {
            treasuryId = treasuryObj.objectId;
            managerCapId = managerCapObj.objectId;
            console.log("Created Treasury:", treasuryId);
            console.log("Created ManagerCap:", managerCapId);
            return { treasuryId, managerCapId };
        }
        throw new Error("Failed to find created objects");
    }
    throw new Error(`Failed to create treasury: ${result.effects?.status?.error}`);
}

// Deposit SUI
async function deposit(amount: number, signer: Ed25519Keypair) {
    const tx = new TransactionBlock();
    const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(amount)]);

    console.log("Depositing with params:", {
        treasury: treasuryId,
        amount: amount,
        signer: signer.getPublicKey().toSuiAddress()
    });

    // Вызываем deposit
    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::deposit`,
        arguments: [
            tx.object(treasuryId),
            coin
        ]
    });

    const result = await executeTransaction(tx, signer);

    if (result.effects?.status?.status === 'success') {
        // Ищем созданный LPToken в objectChanges
        const lpToken = result.objectChanges?.find(
            change => change.type === 'created' &&
                'objectType' in change &&
                change.objectType === `${PACKAGE_ID}::treasury_voting::LPToken`
        );

        if (lpToken && 'objectId' in lpToken) {
            if (signer === keypair1) {
                lpTokenId1 = lpToken.objectId;
                console.log("Wallet 1 deposited amount:", amount, "MIST");
                console.log("Created LPToken 1:", lpTokenId1);
                return lpTokenId1;
            } else {
                lpTokenId2 = lpToken.objectId;
                console.log("Wallet 2 deposited amount:", amount, "MIST");
                console.log("Created LPToken 2:", lpTokenId2);
                return lpTokenId2;
            }
        } else {
            throw new Error("Failed to find created LPToken");
        }
    } else {
        throw new Error(`Failed to deposit: ${result.effects?.status?.error}`);
    }
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

    const result = await executeTransaction(tx, keypair1);

    if (result.effects?.status?.status === 'success') {
        // Ищем созданный Proposal в objectChanges
        const proposal = result.objectChanges?.find(
            change => change.type === 'created' &&
                'objectType' in change &&
                change.objectType === `${PACKAGE_ID}::treasury_voting::WithdrawalProposal`
        );

        if (proposal && 'objectId' in proposal) {
            proposalId = proposal.objectId;
            console.log("Created proposal for amount:", amount, "MIST");
            console.log("Proposal ID:", proposalId);
            return proposalId;
        } else {
            throw new Error("Failed to find created Proposal");
        }
    } else {
        throw new Error(`Failed to create proposal: ${result.effects?.status?.error}`);
    }
}

// Vote on proposal
async function vote(lpTokenId: string, signer: Ed25519Keypair) {
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::vote`,
        arguments: [
            tx.object(proposalId),
            tx.object(lpTokenId)
        ]
    });

    await executeTransaction(tx, signer);
}

// Execute proposal
async function executeProposal() {
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::execute_proposal`,
        arguments: [
            tx.object(treasuryId),
            tx.object(proposalId),
            tx.object(managerCapId)
        ]
    });

    const result = await executeTransaction(tx, keypair1);
    console.log("Proposal executed successfully");
}

// Withdraw SUI
async function withdraw() {
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${PACKAGE_ID}::treasury_voting::withdraw`,
        arguments: [
            tx.object(treasuryId),
            tx.object(lpTokenId1)
        ]
    });

    const result = await executeTransaction(tx, keypair1);
    console.log("Withdrawal completed successfully");
}

// Функция для взаимодействия с контрактом
async function interactWithContract(packageId: string) {
    // Создаем treasury с 1 SUI initial balance
    const { treasuryId, managerCapId } = await createTreasury(2);
    console.log("Created treasury:", treasuryId);

    // Депозит 1 SUI
    const lpTokenId = await deposit(1, keypair1);
    console.log("Deposited, LP token:", lpTokenId);

    // Создаем proposal
    const myAddress = keypair1.getPublicKey().toSuiAddress();
    const proposalId = await createProposal(myAddress, 50);
    console.log("Created proposal:", proposalId);
}

async function main() {
    try {
        console.log("Starting treasury test script...");

        // Create treasury with 40% required votes threshold
        console.log("Creating treasury...");
        await createTreasury(40); // 40% threshold

        // Deposit from both wallets
        console.log("Depositing from Wallet 1...");
        await deposit(100_000_000, keypair1); // 0.1 SUI = 100,000,000 MIST
        // После этого депозита будет создано 100,000,000 LP токенов

        console.log("Depositing from Wallet 2...");
        await deposit(200_000_000, keypair2); // 0.2 SUI = 200,000,000 MIST
        // После этого депозита будет создано примерно 200,000,000 LP токенов
        // Всего LP токенов: ~300,000,000

        // Create proposal to withdraw 0.15 SUI
        console.log("Creating withdrawal proposal...");
        const myAddress = keypair1.getPublicKey().toSuiAddress();
        await createProposal(myAddress, 150_000_000); // 0.15 SUI

        // Vote on proposal from both wallets
        // Wallet1 голосует 100M LP токенов (~33% от общего количества)
        console.log("Voting from Wallet 1...");
        await vote(lpTokenId1, keypair1);

        // Wallet2 голосует 200M LP токенов (~66% от общего количества)
        // Вместе будет 100% голосов, что больше требуемых 40%
        console.log("Voting from Wallet 2...");
        await vote(lpTokenId2, keypair2);

        // Execute proposal
        console.log("Executing proposal...");
        await executeProposal();

        // Withdraw remaining LP tokens
        console.log("Withdrawing remaining LP tokens...");
        await withdraw();

        console.log("Test script completed successfully!");
    } catch (error) {
        console.error("Error in test script:", error);
        if (error instanceof Error) {
            console.error("Error message:", error.message);
            console.error("Error stack:", error.stack);
        }
    }
}

// Запускаем
main().catch(console.error); 