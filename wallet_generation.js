// Script para gerar múltiplas carteiras Solana
const { Keypair } = require('@solana/web3.js');
const fs = require('fs');
const path = require('path');

// Configurações
const WALLETS_COUNT = 7;
const WALLETS_FOLDER = './carteiras';

function main() {
  console.log("🔑 GERANDO CARTEIRAS SOLANA 🔑");
  console.log("==============================");
  
  // Verificar se a pasta já existe, se não, criar
  if (!fs.existsSync(WALLETS_FOLDER)) {
    console.log(`Criando pasta ${WALLETS_FOLDER}...`);
    fs.mkdirSync(WALLETS_FOLDER, { recursive: true });
  } else {
    console.log(`A pasta ${WALLETS_FOLDER} já existe.`);
  }
  
  // Gerar carteiras
  const wallets = [];
  
  for (let i = 1; i <= WALLETS_COUNT; i++) {
    // Gerar novo keypair
    const keypair = Keypair.generate();
    
    // Converter para formato adequado para salvar
    const secretKey = Array.from(keypair.secretKey);
    
    // Definir caminho do arquivo
    const filePath = path.join(WALLETS_FOLDER, `carteira${i}.json`);
    
    // Salvar a chave privada no arquivo
    fs.writeFileSync(filePath, JSON.stringify(secretKey));
    
    // Obter o endereço público para exibir
    const publicKey = keypair.publicKey.toString();
    
    console.log(`Carteira ${i} gerada:`);
    console.log(`- Endereço: ${publicKey}`);
    console.log(`- Arquivo: ${filePath}`);
    console.log("------------------------------");
    
    wallets.push({
      index: i,
      publicKey,
      filePath
    });
  }
  
  // Salvar resumo de todas as carteiras em um arquivo separado
  const summaryPath = path.join(WALLETS_FOLDER, 'resumo.json');
  fs.writeFileSync(summaryPath, JSON.stringify(wallets, null, 2));
  console.log(`Resumo de todas as carteiras salvo em: ${summaryPath}`);
  
  console.log("\n✅ TODAS AS CARTEIRAS FORAM GERADAS COM SUCESSO!");
  console.log("⚠️ IMPORTANTE: Estas carteiras não possuem fundos.");
  console.log("⚠️ Você precisará enviar SOL para cada uma delas antes de usá-las.");
  
  console.log("\n📋 Resumo dos endereços:");
  wallets.forEach(wallet => {
    console.log(`Carteira ${wallet.index}: ${wallet.publicKey}`);
  });
}

main();