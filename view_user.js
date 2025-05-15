const { Connection, PublicKey, Keypair } = require('@solana/web3.js');
const { Program, AnchorProvider, Wallet, BN } = require('@coral-xyz/anchor');
const fs = require('fs');
const path = require('path');

// Constantes do sistema
const PROGRAM_ID = "jFUpBH7wTd9G1EfFADhJCZ89CSujPoh15bdWL5NutT9";
const TOKEN_MINT = "H4T9Y1wGsexYKYshYbqHG3fKhu16nkJhyYQArp1Q1Adj";
const MAX_UPLINE_DEPTH = 6;

// Função principal para carregar e analisar matriz
async function analyzeUserMatrix(userPda) {
    try {
        console.log("🔍 ANALISADOR DE MATRIZ - SISTEMA DE REFERÊNCIA 🔍");
        console.log("===================================================");
        console.log(`📄 PDA do Usuário: ${userPda}`);
        
        // Conectar à rede Solana (devnet)
        const connection = new Connection('https://weathered-quiet-theorem.solana-devnet.quiknode.pro/198997b67cb51804baeb34ed2257274aa2b2d8c0', 'confirmed');
        console.log("✅ Conectado à Devnet");
        
        // Criar keypair temporário para o provider (não será usado para transações)
        const dummyKp = Keypair.generate();
        const wallet = new Wallet(dummyKp);
        const provider = new AnchorProvider(connection, wallet, { commitment: 'confirmed' });
        
        // Carregar IDL do programa
        console.log("📋 Carregando IDL do programa...");
        const idlPath = path.join(__dirname, './target/idl/referral_system.json');
        const idl = JSON.parse(fs.readFileSync(idlPath, 'utf8'));
        
        // Inicializar o programa
        const program = new Program(idl, new PublicKey(PROGRAM_ID), provider);
        console.log(`✅ Programa inicializado: ${PROGRAM_ID}`);
        
        // Carregar conta do usuário
        console.log("\n📊 CARREGANDO DADOS DO USUÁRIO...");
        const userPdaPublicKey = new PublicKey(userPda);
        const userAccount = await program.account.userAccount.fetch(userPdaPublicKey);
        
        // Mostrar informações básicas
        console.log("\n📋 INFORMAÇÕES BÁSICAS:");
        console.log(`👤 PDA do Usuário: ${userPda}`);
        console.log(`🔑 Wallet do Proprietário: ${userAccount.ownerWallet.toString()}`);
        console.log(`✅ Registrado: ${userAccount.isRegistered ? "Sim" : "Não"}`);
        
        // Mostrar referenciador (se houver)
        if (userAccount.referrer) {
            console.log(`👥 Referenciador: ${userAccount.referrer.toString()}`);
            
            try {
                // Tentar carregar o referenciador para mostrar detalhes
                const referrerAccount = await program.account.userAccount.fetch(userAccount.referrer);
                console.log(`   └─ Wallet do Referenciador: ${referrerAccount.ownerWallet.toString()}`);
                console.log(`   └─ Registrado: ${referrerAccount.isRegistered ? "Sim" : "Não"}`);
            } catch (e) {
                console.log("   └─ Não foi possível carregar detalhes do referenciador");
            }
        } else {
            console.log("👥 Referenciador: Nenhum (Usuário Base)");
        }
        
        // Mostrar informações da matriz
        console.log("\n📊 INFORMAÇÕES DA MATRIZ:");
        console.log(`🆔 ID da Matriz: ${userAccount.chain.id}`);
        console.log(`📊 Slots Preenchidos: ${userAccount.chain.filledSlots}/3`);
        
        // Mostrar cada slot e seus usuários
        console.log("\n📋 DETALHES DOS SLOTS:");
        for (let i = 0; i < 3; i++) {
            const slot = userAccount.chain.slots[i];
            if (slot) {
                console.log(`   Slot ${i+1}: ${slot.toString()}`);
                
                try {
                    // Tentar carregar o usuário do slot para mostrar detalhes
                    const slotUserAccount = await program.account.userAccount.fetch(slot);
                    console.log(`      └─ Wallet: ${slotUserAccount.ownerWallet.toString()}`);
                    console.log(`      └─ Registrado: ${slotUserAccount.isRegistered ? "Sim" : "Não"}`);
                } catch (e) {
                    console.log("      ");
                }
            } else {
                console.log(`   Slot ${i+1}: Vazio`);
            }
        }
        
        // Mostrar informações financeiras
        console.log("\n💰 INFORMAÇÕES FINANCEIRAS:");
        console.log(`💵 SOL Reservado: ${userAccount.reservedSol / 1e9} SOL`);
        console.log(`🪙 Tokens Reservados: ${userAccount.reservedTokens / 1e9} DONUT`);
        
        // Mostrar informações de upline
        console.log("\n🔄 INFORMAÇÕES DE UPLINE:");
        console.log(`🆔 ID da Upline: ${userAccount.upline.id}`);
        console.log(`🔢 Profundidade: ${userAccount.upline.depth}`);
        
        // Mostrar entradas da upline
        if (userAccount.upline.upline && userAccount.upline.upline.length > 0) {
            console.log(`📋 Total de Uplines: ${userAccount.upline.upline.length}`);
            console.log("\n📋 DETALHES DAS UPLINES (Mais Recente → Mais Antiga):");
            
            for (let i = userAccount.upline.upline.length - 1; i >= 0; i--) {
                const entry = userAccount.upline.upline[i];
                console.log(`   Upline #${userAccount.upline.upline.length - i}:`);
                console.log(`      └─ PDA: ${entry.pda.toString()}`);
                console.log(`      └─ Wallet: ${entry.wallet.toString()}`);
                
                try {
                    // Tentar carregar a conta da upline para mostrar detalhes adicionais
                    const uplineAccount = await program.account.userAccount.fetch(entry.pda);
                    console.log(`      └─ Profundidade: ${uplineAccount.upline.depth}`);
                    console.log(`      └─ Matriz ID: ${uplineAccount.chain.id}`);
                    console.log(`      └─ Slots Preenchidos: ${uplineAccount.chain.filledSlots}/3`);
                } catch (e) {
                    console.log("      └─ Não foi possível carregar detalhes adicionais");
                }
            }
        } else {
            console.log("📋 Uplines: Nenhuma (Usuário Base)");
        }
        
        // Verificar ATA do token para o usuário
        const associatedToken = await getAssociatedTokenAddress(
            new PublicKey(TOKEN_MINT),
            userAccount.ownerWallet
        );
        
        console.log("\n🪙 INFORMAÇÕES DE TOKEN:");
        console.log(`   Token: DONUT (${TOKEN_MINT})`);
        console.log(`   ATA do Usuário: ${associatedToken.toString()}`);
        
        try {
            // Tentar obter saldo do token
            const tokenInfo = await connection.getTokenAccountBalance(associatedToken);
            console.log(`   Saldo: ${tokenInfo.value.uiAmount} DONUT`);
        } catch (e) {
            console.log("   Saldo: Não foi possível carregar (A conta pode não existir)");
        }
        
        console.log("\n✅ ANÁLISE CONCLUÍDA!");
        
    } catch (error) {
        console.error("❌ ERRO AO ANALISAR MATRIZ:", error);
        
        // Verificar se é um erro de conta não encontrada
        if (error.toString().includes("Account does not exist")) {
            console.error("\n⚠️ A conta especificada não existe ou não é uma conta de usuário válida!");
            console.error("Verifique se a PDA está correta e se a conta foi inicializada.");
        }
    }
}

// Função helper para derivar endereço de token associado
async function getAssociatedTokenAddress(mint, owner) {
    // Implementação simples do SPL Token getProgramDerivedAddress
    const SPL_ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID = new PublicKey('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL');
    const TOKEN_PROGRAM_ID = new PublicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA');
    
    const [address] = await PublicKey.findProgramAddress(
        [
            owner.toBuffer(),
            TOKEN_PROGRAM_ID.toBuffer(),
            mint.toBuffer(),
        ],
        SPL_ASSOCIATED_TOKEN_ACCOUNT_PROGRAM_ID
    );
    
    return address;
}

// Verificar argumentos da linha de comando
const userPda = process.argv[2] || "F5jpNk6WwcHdkxVkMHiR6EgB6aPCPBZ23dESwUtPL7LS";

// Executar análise
analyzeUserMatrix(userPda)
    .catch(err => {
        console.error("Erro fatal:", err);
        process.exit(1);
    });