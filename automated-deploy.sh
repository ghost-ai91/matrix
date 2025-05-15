#!/bin/bash
# automated-deploy.sh - Script automatizado para deploy de contratos Solana com verificação por hash

# ----- CONFIGURAÇÕES (EDITE ESTAS VARIÁVEIS) -----
# Usuário do GitHub
GITHUB_USER="ghost-ai91"

# Token de acesso pessoal do GitHub (deixar em branco para solicitar durante a execução)
# Crie um em: https://github.com/settings/tokens
GITHUB_TOKEN=""

# Nome do repositório
REPO_NAME="matrix"

# URL do RPC (Devnet ou Mainnet)
RPC_URL="https://weathered-quiet-theorem.solana-devnet.quiknode.pro/198997b67cb51804baeb34ed2257274aa2b2d8c0" # Devnet
#RPC_URL="https://api.mainnet-beta.solana.com" # Mainnet

# Caminho para sua wallet
WALLET_KEYPAIR="/root/.config/solana/id.json"

# Caminho para keypair do programa
PROGRAM_KEYPAIR="/app/matrizV2-testes/target/deploy/matrix_system-keypair.json"

# Caminho para o arquivo .so do programa
PROGRAM_SO="/app/matrizV2-testes/target/deploy/matrix_system.so"

# Tamanho máximo do programa
MAX_PROGRAM_SIZE="500000"

# Compute unit price para transações
COMPUTE_UNIT_PRICE="1000"

# Tipo de deploy: "new" para novo programa, "upgrade" para atualizar existente
# IMPORTANTE: Use "new" para criar um novo Program ID, "upgrade" para usar um existente
DEPLOY_TYPE="upgrade"

# ----- NÃO EDITE ABAIXO DESTA LINHA -----

# Função para exibir mensagens coloridas
print_message() {
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    
    case $1 in
        "info") echo -e "${GREEN}[INFO]${NC} $2" ;;
        "warn") echo -e "${YELLOW}[WARN]${NC} $2" ;;
        "error") echo -e "${RED}[ERROR]${NC} $2" ;;
        *) echo "$2" ;;
    esac
}

# Verificar se o Git está instalado
if ! command -v git &> /dev/null; then
    print_message "error" "Git não está instalado. Por favor, instale-o primeiro."
    exit 1
fi

# Verificar se o Solana CLI está instalado
if ! command -v solana &> /dev/null; then
    print_message "error" "Solana CLI não está instalado. Por favor, instale-o primeiro."
    exit 1
fi

# Verificar se o Anchor está instalado
if ! command -v anchor &> /dev/null; then
    print_message "error" "Anchor CLI não está instalado. Por favor, instale-o primeiro."
    exit 1
fi

# Função para solicitar token GitHub quando necessário
request_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        print_message "info" "Token GitHub não encontrado na configuração."
        read -sp "Digite seu token GitHub (não aparecerá na tela): " GITHUB_TOKEN
        echo ""
        if [ -n "$GITHUB_TOKEN" ]; then
            print_message "info" "Token GitHub recebido. Atualizando configuração do Git..."
            if git remote | grep -q "^origin$"; then
                git remote set-url origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git
                print_message "info" "URL do remote atualizada com token"
            fi
        else
            print_message "warn" "Nenhum token fornecido. Operações no GitHub podem falhar."
        fi
    fi
}

# Função para obter a versão do programa a partir de tags do Git
get_program_version() {
    print_message "info" "Obtendo versão do programa a partir de tags Git..."
    
    # Tentar obter a última tag
    if git describe --tags --abbrev=0 2>/dev/null; then
        GIT_TAG=$(git describe --tags --abbrev=0)
        print_message "info" "Usando versão da tag Git: $GIT_TAG"
        export PROGRAM_VERSION="$GIT_TAG"
    else
        # Se não houver tags, usar uma versão padrão + hash curto
        SHORT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        DEFAULT_VERSION="0.1.0-dev+$SHORT_HASH"
        print_message "warn" "Nenhuma tag Git encontrada. Usando versão padrão: $DEFAULT_VERSION"
        export PROGRAM_VERSION="$DEFAULT_VERSION"
        
        # Perguntar se deseja criar uma tag
        read -p "Deseja criar uma tag Git para esta versão? (s/n): " create_tag
        if [ "$create_tag" = "s" ]; then
            read -p "Digite a versão desejada (ex: v1.0.0): " tag_version
            if [ -n "$tag_version" ]; then
                # Tentar criar a tag, ignorando erros se já existir
                git tag -a "$tag_version" -m "Versão $tag_version" 2>/dev/null || true
                print_message "info" "Tag $tag_version criada localmente"
                export PROGRAM_VERSION="$tag_version"
            else
                print_message "warn" "Tag não criada. Usando versão padrão: $DEFAULT_VERSION"
            fi
        fi
    fi
}

# Função para fazer backup de arquivos importantes
backup_files() {
    print_message "info" "Fazendo backup de arquivos importantes..."
    mkdir -p ./backups
    cp $PROGRAM_KEYPAIR ./backups/program-keypair-backup-$(date +%Y%m%d%H%M%S).json 2>/dev/null || :
    cp $WALLET_KEYPAIR ./backups/wallet-keypair-backup-$(date +%Y%m%d%H%M%S).json 2>/dev/null || :
    print_message "info" "Backup concluído"
}

# Verificar se estamos em um repositório Git
check_git_repo() {
    if [ ! -d .git ]; then
        print_message "warn" "Não estamos em um repositório Git. Iniciando um novo..."
        
        # Inicializar Git se não estiver presente
        git init
        
        # Configurar remote URL baseado nas variáveis
        if [ -n "$GITHUB_TOKEN" ]; then
            # Usar token para autenticação
            git remote add origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git
        else
            git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git
        fi
        
        # Verificar se temos arquivos README.md e SECURITY.md
        if [ ! -f README.md ]; then
            print_message "warn" "README.md não encontrado. Criando um modelo básico..."
            cat > README.md << EOF
# DONUT Referral Matrix System

A decentralized referral matrix system on the Solana blockchain that rewards participants for bringing new users to the network.

## Overview

The DONUT Referral Matrix System is a protocol designed to incentivize user acquisition through a multi-level referral structure. The system creates a 3-slot matrix for each user, where each slot represents a different action when filled:

- **Slot 1**: Deposit SOL to liquidity pools
- **Slot 2**: Reserve SOL and mint DONUT tokens
- **Slot 3**: Pay reserved SOL and tokens to referrers

## Key Features

- **Verifiable Smart Contract**: The code is publicly available and verified on-chain
- **Chainlink Integration**: Uses Chainlink oracles for reliable SOL/USD price feeds
- **Meteora Pool Integration**: Interacts with liquidity pools for token exchanges
- **Secure Address Verification**: Implements strict address validation for security
- **Automated Referral Processing**: Handles the full referral chain automatically

## Technical Details

- **Chain Structure**: Each user has a matrix with 3 slots
- **Upline Management**: Users can have multiple upline referrers with defined depth
- **Token Economics**: SOL deposits are converted to DONUT tokens based on pool rates
- **Secure Operations**: All functions implement strict validation and error handling

## Security

See [SECURITY.md](./SECURITY.md) for our security policy and reporting vulnerabilities.

## Contact

For questions or support:
- Email: ghostninjax01@gmail.com
- Discord: ghostninjax01
- WhatsApp: [Contact via email for WhatsApp]

## License

This project is licensed under the MIT License - see the LICENSE file for details.
EOF
        fi
        
        # Obter o Program ID para o SECURITY.md
        PROGRAM_ID="Unknown"
        if [ -f "$PROGRAM_KEYPAIR" ]; then
            PROGRAM_ID=$(solana-keygen pubkey $PROGRAM_KEYPAIR 2>/dev/null || echo "Unknown")
        fi
        
        if [ ! -f SECURITY.md ]; then
            print_message "warn" "SECURITY.md não encontrado. Criando um modelo básico..."
            cat > SECURITY.md << EOF
# Security Policy for DONUT Referral Matrix System

## Reporting a Vulnerability

If you discover a security vulnerability in our smart contract, please report it through one of the following channels:

- **Email**: [ghostninjax01@gmail.com](mailto:ghostninjax01@gmail.com)
- **Discord**: \`ghostninjax01\`
- **WhatsApp**: Contact via email for WhatsApp details

When reporting, please include:
- A detailed description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggestions for remediation if available

## Bug Bounty Program

We offer rewards for critical security vulnerabilities found in our smart contract, based on severity:

| Severity | Description | Potential Reward (SOL) |
|----------|-------------|-------------------|
| Critical | Issues that allow direct theft of funds, permanent freezing of funds, or unauthorized control of the protocol | 5-20 SOL |
| High | Issues that could potentially lead to loss of funds under specific conditions | 1-5 SOL |
| Medium | Issues that don't directly threaten assets but could compromise system integrity | 0.5-1 SOL |
| Low | Issues that don't pose a significant risk but should be addressed | 0.1-0.5 SOL |

The final reward amount is determined at our discretion based on:
- The potential impact of the vulnerability
- The quality of the vulnerability report
- The uniqueness of the finding
- The clarity of proof-of-concept provided

## Eligibility Requirements

A vulnerability is eligible for reward if:
- It is previously unreported
- It affects the latest version of our contract
- The reporter provides sufficient information to reproduce and fix the issue
- The reporter allows a reasonable time for remediation before public disclosure

## Scope

This security policy covers the DONUT Referral Matrix System smart contract deployed at \`$PROGRAM_ID\`.

## Out of Scope

The following are considered out of scope:
- Vulnerabilities in third-party applications or websites
- Vulnerabilities requiring physical access to a user's device
- Social engineering attacks
- DoS attacks requiring excessive resources
- Issues related to frontend applications rather than the smart contract itself

## Responsible Disclosure

We are committed to working with security researchers to verify and address any potential vulnerabilities reported. We request that:

1. You give us reasonable time to investigate and address the vulnerability before any public disclosure
2. You make a good faith effort to avoid privacy violations, data destruction, and interruption or degradation of our services
3. You do not exploit the vulnerability beyond what is necessary to prove it exists

## Acknowledgments

We thank all security researchers who contribute to the security of our protocol. Contributors who discover valid vulnerabilities will be acknowledged (if desired) once the issue has been resolved.
EOF
        fi
        
        # Adicionar todos os arquivos e fazer commit
        git add .
        git commit -m "Initial version of DONUT Referral Matrix System"
    else
        print_message "info" "Repositório Git já inicializado"
        
        # Atualizar o remote se o token foi fornecido
        if [ -n "$GITHUB_TOKEN" ]; then
            git remote set-url origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git
            print_message "info" "URL do remote atualizada com token"
        fi
    fi
}

# Função para garantir que o SECURITY.md exista e esteja atualizado
ensure_security_md() {
    print_message "info" "Verificando e atualizando SECURITY.md..."
    
    # Obter o Program ID
    PROGRAM_ID=$(solana-keygen pubkey $PROGRAM_KEYPAIR 2>/dev/null || echo "Unknown")
    
    # Criar ou atualizar o SECURITY.md
    cat > SECURITY.md << EOF
# Security Policy for DONUT Referral Matrix System

## Reporting a Vulnerability

If you discover a security vulnerability in our smart contract, please report it through one of the following channels:

- **Email**: [ghostninjax01@gmail.com](mailto:ghostninjax01@gmail.com)
- **Discord**: \`ghostninjax01\`
- **WhatsApp**: Contact via email for WhatsApp details

When reporting, please include:
- A detailed description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggestions for remediation if available

## Bug Bounty Program

We offer rewards for critical security vulnerabilities found in our smart contract, based on severity:

| Severity | Description | Potential Reward (SOL) |
|----------|-------------|-------------------|
| Critical | Issues that allow direct theft of funds, permanent freezing of funds, or unauthorized control of the protocol | 5-20 SOL |
| High | Issues that could potentially lead to loss of funds under specific conditions | 1-5 SOL |
| Medium | Issues that don't directly threaten assets but could compromise system integrity | 0.5-1 SOL |
| Low | Issues that don't pose a significant risk but should be addressed | 0.1-0.5 SOL |

The final reward amount is determined at our discretion based on:
- The potential impact of the vulnerability
- The quality of the vulnerability report
- The uniqueness of the finding
- The clarity of proof-of-concept provided

## Eligibility Requirements

A vulnerability is eligible for reward if:
- It is previously unreported
- It affects the latest version of our contract
- The reporter provides sufficient information to reproduce and fix the issue
- The reporter allows a reasonable time for remediation before public disclosure

## Scope

This security policy covers the DONUT Referral Matrix System smart contract deployed at \`$PROGRAM_ID\`.

## Out of Scope

The following are considered out of scope:
- Vulnerabilities in third-party applications or websites
- Vulnerabilities requiring physical access to a user's device
- Social engineering attacks
- DoS attacks requiring excessive resources
- Issues related to frontend applications rather than the smart contract itself

## Responsible Disclosure

We are committed to working with security researchers to verify and address any potential vulnerabilities reported. We request that:

1. You give us reasonable time to investigate and address the vulnerability before any public disclosure
2. You make a good faith effort to avoid privacy violations, data destruction, and interruption or degradation of our services
3. You do not exploit the vulnerability beyond what is necessary to prove it exists

## Acknowledgments

We thank all security researchers who contribute to the security of our protocol. Contributors who discover valid vulnerabilities will be acknowledged (if desired) once the issue has been resolved.
EOF

    # Adicionar ao Git se houver alterações
    git add SECURITY.md
    if git diff --staged --quiet SECURITY.md; then
        print_message "info" "SECURITY.md está atualizado."
    else
        git commit -m "Atualizar SECURITY.md com o Program ID: $PROGRAM_ID"
        print_message "info" "SECURITY.md atualizado e commitado."
    fi
}

# Função para corrigir os caminhos no lib.rs
fix_lib_rs_urls() {
    print_message "info" "Verificando e corrigindo URLs no lib.rs..."
    
    # Caminho para o lib.rs (ajuste conforme necessário)
    LIB_RS_PATH="programs/matrix-system/src/lib.rs"
    
    if [ -f "$LIB_RS_PATH" ]; then
        # Corrigir o caminho para SECURITY.md
        sed -i 's|"https://github.com/ghost-ai91/matrix/SECURITY.md"|"https://github.com/ghost-ai91/matrix/blob/main/SECURITY.md"|g' "$LIB_RS_PATH"
        
        # Corrigir o caminho para src/lib.rs
        sed -i 's|"https://github.com/ghost-ai91/matrix/programs/src/lib.rs"|"https://github.com/ghost-ai91/matrix/blob/main/programs/matrix-system/src/lib.rs"|g' "$LIB_RS_PATH"
        
        # Adicionar ao Git se houver alterações
        git add "$LIB_RS_PATH"
        if git diff --staged --quiet "$LIB_RS_PATH"; then
            print_message "info" "URLs no lib.rs estão corretas."
        else
            git commit -m "Corrigir URLs no lib.rs para apontar para o branch main"
            print_message "info" "URLs no lib.rs corrigidas e commitadas."
        fi
    else
        print_message "warn" "Arquivo lib.rs não encontrado em $LIB_RS_PATH"
    fi
}

# Nova função para mesclar para o branch principal após o deploy
merge_to_main() {
    print_message "info" "Mesclando alterações para o branch principal..."
    
    # Obter o branch atual
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Não fazer nada se já estivermos no branch main
    if [ "$current_branch" = "main" ]; then
        print_message "info" "Já estamos no branch principal, nenhuma mesclagem necessária."
        return
    fi
    
    # Verificar se o branch main existe localmente
    if git show-ref --verify --quiet refs/heads/main; then
        # Main existe localmente
        print_message "info" "Branch main encontrado localmente."
    else
        # Main não existe localmente, verificar se existe remotamente
        if git ls-remote --exit-code --heads origin main &>/dev/null; then
            # Main existe remotamente, criar localmente
            print_message "info" "Criando branch main localmente baseado no remoto..."
            git branch main origin/main
        else
            # Main não existe nem local nem remotamente, criar um novo
            print_message "info" "Branch main não encontrado. Criando um novo branch main..."
            git checkout -b main
            git checkout "$current_branch"
        fi
    fi
    
    # Fazer checkout para main
    git checkout main
    
    # Tentar mesclar o branch atual
    print_message "info" "Mesclando $current_branch para main..."
    if git merge --no-ff "$current_branch" -m "Merge branch '$current_branch' para main"; then
        print_message "info" "Mesclagem concluída com sucesso."
        
        # Enviar para o GitHub
        print_message "info" "Enviando branch main para GitHub..."
        if git push origin main; then
            print_message "info" "Branch main enviado com sucesso para GitHub."
        else
            print_message "warn" "Falha ao enviar branch main para GitHub."
        fi
    else
        print_message "error" "Conflitos detectados durante a mesclagem."
        print_message "error" "Por favor, resolva os conflitos manualmente e faça push para o branch main."
        git merge --abort
        git checkout "$current_branch"
    fi
    
    # Voltar para o branch original se diferente de main
    if [ "$current_branch" != "main" ]; then
        git checkout "$current_branch"
    fi
}

# Função para configurar .gitignore adequado
setup_gitignore() {
    print_message "info" "Configurando .gitignore para proteção de arquivos sensíveis..."
    
    # Verificar se já existe um .gitignore
    if [ ! -f .gitignore ]; then
        # Criar .gitignore com as configurações recomendadas
        cat > .gitignore << EOF
# Anchor/Solana specific
.anchor/
.DS_Store
target/
**/*.rs.bk
test-ledger/
.yarn/

# Arquivos de dependências
node_modules/

# Arquivos de build
dist/
build/

# Chaves privadas e carteiras
**/*.keypair
**/*keypair*.json
**/*wallet*.json
**/id.json
**/*wallet*.json

# Permitir arquivos JSON específicos
!**/package.json
!**/package-lock.json
!**/tsconfig.json
!**/token-metadata.json

# Arquivos de ambiente
.env
.env.*
**/.env*

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Arquivos de IDE
.idea/
.vscode/
*.swp
*.swo

# Arquivos de secrets
*.pem
*.key
*.secret

# Programas Solana compilados
**/*.so
program_dump.so
EOF
        print_message "info" ".gitignore criado com proteções para arquivos sensíveis"
    else
        # Verificar se o .gitignore existente tem as proteções necessárias
        NEEDS_UPDATE=false
        
        # Verificar proteções essenciais
        if ! grep -q "**/*.keypair" .gitignore; then
            NEEDS_UPDATE=true
        fi
        
        if ! grep -q "**/id.json" .gitignore; then
            NEEDS_UPDATE=true
        fi
        
        if ! grep -q "**/*wallet*.json" .gitignore; then
            NEEDS_UPDATE=true
        fi
        
        # Atualizar se necessário
        if [ "$NEEDS_UPDATE" = true ]; then
            print_message "warn" ".gitignore existente não tem todas as proteções necessárias"
            print_message "info" "Fazendo backup do .gitignore existente e criando um novo"
            
            # Backup do .gitignore existente
            cp .gitignore .gitignore.bak-$(date +%Y%m%d%H%M%S)
            
            # Adicionar proteções ao .gitignore
            cat >> .gitignore << EOF

# Proteções adicionais para arquivos sensíveis
**/*.keypair
**/*keypair*.json
**/*wallet*.json
**/id.json
**/*.secret
*.pem
*.key
EOF
            print_message "info" ".gitignore atualizado com proteções adicionais"
        else
            print_message "info" ".gitignore existente já tem proteções adequadas"
        fi
    fi
}

# Função para verificar arquivos sensíveis antes do commit
check_sensitive_files() {
    print_message "info" "Verificando se há arquivos sensíveis que poderiam ser expostos..."
    
    # Lista de padrões sensíveis para verificar
    SENSITIVE_PATTERNS=(
        "*.keypair"
        "*keypair*.json"
        "*wallet*.json"
        "id.json"
        "*.pem"
        "*.key"
        "*.secret"
        ".env"
    )
    
    # Verificar cada padrão
    FOUND_SENSITIVE=false
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        # Encontrar arquivos que correspondam ao padrão e não estejam em .gitignore
        SENSITIVE_FILES=$(git ls-files --exclude-standard --others --cached | grep -E "$pattern" || true)
        
        if [ -n "$SENSITIVE_FILES" ]; then
            FOUND_SENSITIVE=true
            print_message "error" "ALERTA DE SEGURANÇA: Encontrados arquivos sensíveis que podem ser expostos no GitHub:"
            echo "$SENSITIVE_FILES"
        fi
    done
    
    # Se encontrou arquivos sensíveis, perguntar se deseja continuar
    if [ "$FOUND_SENSITIVE" = true ]; then
        print_message "warn" "Os arquivos listados acima podem conter informações sensíveis como chaves privadas."
        read -p "Deseja continuar mesmo assim? Isso pode expor dados sensíveis! (s/n): " continue_anyway
        
        if [ "$continue_anyway" != "s" ]; then
            print_message "info" "Operação cancelada pelo usuário devido a preocupações de segurança."
            print_message "info" "Por favor, adicione esses arquivos ao .gitignore ou remova-os antes de continuar."
            exit 1
        fi
        
        print_message "warn" "Continuando apesar do risco. Cuidado: seus dados podem ser expostos!"
    else
        print_message "info" "Nenhum arquivo sensível detectado fora do .gitignore."
    fi
}

# Função para obter ou criar keypair do programa
prepare_program_keypair() {
    # Verificar se estamos criando um novo programa ou atualizando existente
    if [ "$DEPLOY_TYPE" = "new" ]; then
        # Verificar se o keypair já existe
        if [ -f "$PROGRAM_KEYPAIR" ]; then
            print_message "warn" "Keypair do programa já existe em $PROGRAM_KEYPAIR"
            read -p "Deseja criar um novo keypair? Isso gerará um novo Program ID (s/n): " create_new_keypair
            
            if [ "$create_new_keypair" = "s" ]; then
                # Fazer backup do keypair existente
                cp $PROGRAM_KEYPAIR ./backups/program-keypair-backup-$(date +%Y%m%d%H%M%S).json
                
                # Criar novo keypair
                solana-keygen new --no-bip39-passphrase -o $PROGRAM_KEYPAIR
                print_message "info" "Novo keypair do programa criado"
            fi
        else
            # Criar diretório se não existir
            mkdir -p $(dirname "$PROGRAM_KEYPAIR")
            
            # Criar novo keypair
            solana-keygen new --no-bip39-passphrase -o $PROGRAM_KEYPAIR
            print_message "info" "Novo keypair do programa criado"
        fi
    else
        # Modo upgrade - verificar se o keypair existe
        if [ ! -f "$PROGRAM_KEYPAIR" ]; then
            print_message "error" "Keypair do programa não encontrado em $PROGRAM_KEYPAIR!"
            print_message "error" "É necessário um keypair existente para atualizações."
            exit 1
        fi
    fi
    
    # Exibir o Program ID
    PROGRAM_ID=$(solana-keygen pubkey $PROGRAM_KEYPAIR)
    print_message "info" "Program ID: $PROGRAM_ID"
}

# Função para obter o hash do commit e fazer build
build_with_hash() {
    # Obter o hash do último commit ou criar um novo commit se necessário
    if git rev-parse HEAD &>/dev/null; then
        COMMIT_HASH=$(git rev-parse HEAD)
    else
        print_message "warn" "Nenhum commit encontrado. Criando commit inicial..."
        git add .
        git commit -m "Versão inicial do Sistema de Matriz de Referência"
        COMMIT_HASH=$(git rev-parse HEAD)
    fi
    
    print_message "info" "Hash do commit: $COMMIT_HASH"
    
    # Obter a versão do programa
    get_program_version
    
    # Configurar as variáveis de ambiente com o hash do commit e versão
    export GITHUB_SHA=$COMMIT_HASH
    export PROGRAM_VERSION=${PROGRAM_VERSION:-"0.1.0"}
    
    # Fazer o build do programa com as variáveis de ambiente
    print_message "info" "Construindo o programa com o hash do commit incorporado..."
    GITHUB_SHA=$COMMIT_HASH PROGRAM_VERSION=$PROGRAM_VERSION anchor build
    build_result=$?

    if [ $build_result -ne 0 ]; then
        print_message "error" "Build falhou! Verifique os erros acima."
        exit 1
    fi
    
    # Verificar se o build foi bem-sucedido
    if [ ! -f "$PROGRAM_SO" ]; then
        print_message "error" "Build falhou! O arquivo $PROGRAM_SO não foi encontrado."
        exit 1
    fi
    
    print_message "info" "Build concluído com sucesso"
    
    # Verificar se o hash foi incorporado
    if strings "$PROGRAM_SO" | grep -q "$COMMIT_HASH"; then
        print_message "info" "Hash do commit incorporado com sucesso no programa!"
    else
        print_message "warn" "Hash do commit não encontrado no programa. Isto pode ser normal se o hash é processado de forma específica."
    fi
    
    # Verificar se a versão foi incorporada
    if [ -n "$PROGRAM_VERSION" ] && strings "$PROGRAM_SO" | grep -q "$PROGRAM_VERSION"; then
        print_message "info" "Versão do programa ($PROGRAM_VERSION) incorporada com sucesso!"
    else
        print_message "warn" "Versão do programa não encontrada no binário. Verifique se a linha source_release está configurada corretamente."
    fi
}

# Função para enviar código para o GitHub
push_to_github() {
    print_message "info" "Verificando status do repositório remoto..."
    
    # Verificar se o remote origin já existe
    if ! git remote | grep -q "^origin$"; then
        print_message "warn" "Remote 'origin' não encontrado. Adicionando..."
        
        if [ -n "$GITHUB_TOKEN" ]; then
            # Usar token para autenticação
            git remote add origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git
        else
            git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git
        fi
    fi
    
    # Verificar se há alterações para commit
    if ! git diff-index --quiet HEAD --; then
        print_message "info" "Alterações não commitadas encontradas. Fazendo commit..."
        git add .
        git commit -m "Atualização automática antes do deploy"
    fi
    
    # Obter a situação atual
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Abordagem alternativa para sincronização que evita problemas de rebase
    print_message "info" "Tentando sincronizar com o repositório remoto..."
    
    # Fetch remoto primeiro
    if ! git fetch origin; then
        print_message "warn" "Não foi possível buscar as alterações remotas."
    else
        print_message "info" "Busca remota concluída com sucesso."
        
        # Verificar se há diferenças entre local e remoto
        if git diff --quiet $current_branch origin/$current_branch 2>/dev/null; then
            print_message "info" "Repositório local já está sincronizado com o remoto."
        else
            print_message "warn" "Há diferenças entre o repositório local e remoto."
            print_message "info" "Tentando criar um branch temporário para preservar mudanças locais..."
            
            # Criar branch temporário com as mudanças atuais
            temp_branch="temp_deploy_branch_$(date +%s)"
            git branch $temp_branch
            
            # Tentar fazer reset do branch atual para o remoto
            print_message "info" "Atualizando branch atual para corresponder ao remoto..."
            if git reset --hard origin/$current_branch; then
                print_message "info" "Branch atual atualizado para corresponder ao remoto."
                
                # Mesclar alterações do branch temporário (apenas se não estivermos em um branch vazio)
                if git rev-parse HEAD &>/dev/null; then
                    print_message "info" "Mesclando alterações locais..."
                    if git merge $temp_branch --no-commit; then
                        print_message "info" "Alterações locais mescladas com sucesso."
                    else
                        # Abortar mesclagem se houver conflitos
                        git merge --abort
                        print_message "warn" "Conflitos detectados. Usando apenas as alterações mais recentes."
                        
                        # Adicionar apenas os arquivos sem conflitos
                        git add .
                        git commit -m "Mesclagem manual de alterações após sincronização"
                    fi
                fi
                
                # Limpar branch temporário
                git branch -D $temp_branch
            else
                print_message "warn" "Não foi possível atualizar o branch. Tentando outra abordagem..."
                # Reverter para o branch original
                git checkout $temp_branch
                git branch -D $current_branch
                git checkout -b $current_branch
                git branch -D $temp_branch
            fi
        fi
    fi
    
    # Fazer push para o GitHub
    print_message "info" "Enviando código para o GitHub..."
    # Usar --force-with-lease que é mais seguro que --force, mas ainda sobrescreve conflitos
    if ! git push --force-with-lease origin $current_branch; then
        # Tentar push normal se o force-with-lease falhar
        if ! git push origin $current_branch; then
            if [ -z "$GITHUB_TOKEN" ]; then
                print_message "warn" "Falha ao enviar para o GitHub. Nenhum token foi fornecido."
                print_message "warn" "Adicione seu token do GitHub na variável GITHUB_TOKEN no início do script."
                
                # Perguntar se deseja continuar sem push
                read -p "Continuar com o deploy sem enviar para o GitHub? (s/n): " continue_deploy
                if [ "$continue_deploy" != "s" ]; then
                    print_message "info" "Operação cancelada pelo usuário."
                    exit 0
                fi
            else
                print_message "error" "Falha ao enviar para o GitHub mesmo com token. Verificando novamente o token..."
                # Solicitar token novamente
                print_message "info" "Fornecendo nova oportunidade para inserir o token GitHub."
                read -sp "Digite novamente seu token GitHub (não aparecerá na tela): " GITHUB_TOKEN
                echo ""
                
                if [ -n "$GITHUB_TOKEN" ]; then
                    print_message "info" "Atualizando configuração do Git com novo token..."
                    git remote set-url origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git
                    
                    # Tentar push mais uma vez com o novo token
                    if ! git push --force-with-lease origin $current_branch; then
                        print_message "error" "Falha ao enviar mesmo com novo token."
                        read -p "Continuar com o deploy sem enviar para o GitHub? (s/n): " continue_deploy
                        if [ "$continue_deploy" != "s" ]; then
                            print_message "info" "Operação cancelada pelo usuário."
                            exit 0
                        fi
                    else
                        print_message "info" "Código enviado para o GitHub com sucesso usando o novo token"
                    fi
                else
                    read -p "Continuar com o deploy sem enviar para o GitHub? (s/n): " continue_deploy
                    if [ "$continue_deploy" != "s" ]; then
                        print_message "info" "Operação cancelada pelo usuário."
                        exit 0
                    fi
                fi
            fi
        else
            print_message "info" "Código enviado para o GitHub com sucesso"
        fi
    else
        print_message "info" "Código enviado para o GitHub com sucesso usando --force-with-lease"
    fi
    
    # Enviar tags se existirem
    if [ -n "$PROGRAM_VERSION" ] && [[ "$PROGRAM_VERSION" == v* ]]; then
        print_message "info" "Enviando tag de versão para o GitHub..."
        if git push origin "$PROGRAM_VERSION"; then
            print_message "info" "Tag $PROGRAM_VERSION enviada com sucesso"
        else
            print_message "warn" "Falha ao enviar a tag $PROGRAM_VERSION"
        fi
    fi
}

# Função para fazer deploy do programa
deploy_program() {
    # Configurar Solana CLI
    print_message "info" "Configurando Solana CLI..."
    solana config set --url $RPC_URL
    solana config set --keypair $WALLET_KEYPAIR
    
    # Verificar saldo
    BALANCE=$(solana balance)
    print_message "info" "Saldo atual: $BALANCE"
    
    # Criar buffer
    print_message "info" "Criando buffer para o programa..."
    BUFFER_RESULT=$(solana program write-buffer $PROGRAM_SO \
        --with-compute-unit-price $COMPUTE_UNIT_PRICE \
        --max-sign-attempts 10)
    
    echo "$BUFFER_RESULT"
    
    # Extrair o ID do buffer - versão melhorada
    BUFFER_ID=$(echo "$BUFFER_RESULT" | grep -o "Buffer: [A-Za-z0-9]*" | cut -d " " -f 2)
    
    # Se não conseguir extrair automaticamente, perguntar ao usuário
    if [ -z "$BUFFER_ID" ]; then
        print_message "warn" "Não foi possível extrair o ID do buffer automaticamente."
        echo "Verifique a saída acima e encontre uma linha como 'Buffer: ABC123...'"
        read -p "Por favor, digite o ID do buffer manualmente: " BUFFER_ID
        
        if [ -z "$BUFFER_ID" ]; then
            print_message "error" "Nenhum ID de buffer fornecido. Não é possível prosseguir."
            exit 1
        fi
    fi
    
    print_message "info" "Buffer criado com sucesso. ID: $BUFFER_ID"
    
    # Realizar o deploy
    print_message "info" "Fazendo deploy do programa..."
    PROGRAM_ID=$(solana-keygen pubkey $PROGRAM_KEYPAIR)
    
    if [ "$DEPLOY_TYPE" = "new" ]; then
        # Deploy como novo programa
        DEPLOY_RESULT=$(solana program deploy $PROGRAM_SO \
            --program-id $PROGRAM_KEYPAIR \
            --buffer $BUFFER_ID \
            --max-len $MAX_PROGRAM_SIZE \
            --with-compute-unit-price $COMPUTE_UNIT_PRICE \
            --max-sign-attempts 10 \
            --use-rpc)
    else
        # Deploy como upgrade - corrigido para usar a sintaxe correta para versão 1.18.15
        # Nota: Removido o argumento --upgrade que causava erro
        DEPLOY_RESULT=$(solana program deploy $PROGRAM_SO \
            --program-id $PROGRAM_KEYPAIR \
            --buffer $BUFFER_ID \
            --max-len $MAX_PROGRAM_SIZE \
            --with-compute-unit-price $COMPUTE_UNIT_PRICE \
            --max-sign-attempts 10 \
            --use-rpc)
    fi
    
    echo "$DEPLOY_RESULT"
    
    print_message "info" "Deploy concluído com sucesso!"
    print_message "info" "Program ID: $PROGRAM_ID"
    
    # Verificar o programa
    print_message "info" "Verificando o programa na blockchain..."
    solana program show $PROGRAM_ID
    
    # Verificar hash incorporado - corrigindo o comando de dump
    print_message "info" "Verificando se o hash foi incorporado corretamente..."
    # Corrigido para usar a sintaxe correta para versão 1.18.15
    solana program dump $PROGRAM_ID program_dump.so
    
    if [ -f program_dump.so ] && strings program_dump.so | grep -q "$COMMIT_HASH"; then
        print_message "info" "Hash do commit ($COMMIT_HASH) incorporado e verificado!"
    else
        print_message "warn" "Hash do commit não encontrado no programa implantado ou não foi possível baixar o programa."
        if [ -f program_dump.so ]; then
            print_message "info" "Verificando conteúdo do programa baixado:"
            strings program_dump.so | grep -A 10 -B 10 security_txt || true
        else
            print_message "warn" "Não foi possível baixar o programa para verificação."
        fi
    fi
    
    # Verificar a versão incorporada
    if [ -n "$PROGRAM_VERSION" ]; then
        print_message "info" "Verificando se a versão foi incorporada corretamente..."
        if [ -f program_dump.so ] && strings program_dump.so | grep -q "$PROGRAM_VERSION"; then
            print_message "info" "Versão ($PROGRAM_VERSION) incorporada e verificada!"
        else
            print_message "warn" "Versão não encontrada no programa implantado."
        fi
    fi
    
    # Criar uma tag do Git se ainda não existir
    if [ -n "$PROGRAM_VERSION" ] && [[ "$PROGRAM_VERSION" != v* ]]; then
        print_message "info" "Criando tag Git para esta implantação..."
        DEPLOY_TAG="v1.0.0-deploy-$(date +%Y%m%d)"
        git tag -a "$DEPLOY_TAG" -m "Deploy em $(date): Program ID $PROGRAM_ID"
        print_message "info" "Tag $DEPLOY_TAG criada localmente"
        
        # Perguntar se deseja enviar a tag
        read -p "Enviar a tag $DEPLOY_TAG para o GitHub? (s/n): " push_tag
        if [ "$push_tag" = "s" ]; then
            if [ -z "$GITHUB_TOKEN" ]; then
                print_message "info" "Token GitHub necessário para enviar a tag."
                read -sp "Digite seu token GitHub (não aparecerá na tela): " GITHUB_TOKEN
                echo ""
                if [ -n "$GITHUB_TOKEN" ]; then
                    git remote set-url origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git
                fi
            fi
            
            if [ -n "$GITHUB_TOKEN" ]; then
                if git push origin "$DEPLOY_TAG"; then
                    print_message "info" "Tag $DEPLOY_TAG enviada para o GitHub"
                else
                    print_message "warn" "Falha ao enviar a tag $DEPLOY_TAG"
                fi
            else
                print_message "warn" "Sem token GitHub, a tag não foi enviada."
            fi
        fi
    fi
}

# Nova função para criar release no GitHub
create_github_release() {
    print_message "info" "Criando release no GitHub..."
    
    # Verificar se temos o comando curl
    if ! command -v curl &> /dev/null; then
        print_message "error" "O comando 'curl' não está instalado. Ele é necessário para criar releases."
        print_message "info" "Você pode instalá-lo com: sudo apt-get install curl"
        return 1
    fi
    
    # Verificar se há token do GitHub
    if [ -z "$GITHUB_TOKEN" ]; then
        print_message "warn" "Token GitHub necessário para criar release."
        read -sp "Digite seu token GitHub (não aparecerá na tela): " GITHUB_TOKEN
        echo ""
        if [ -z "$GITHUB_TOKEN" ]; then
            print_message "error" "Nenhum token fornecido. Não é possível criar o release."
            return 1
        fi
    fi
    
    # Determinar qual tag usar para o release
    if [ -n "$PROGRAM_VERSION" ] && [[ "$PROGRAM_VERSION" == v* ]]; then
        # Usar a versão do programa se estiver no formato correto (v*)
        RELEASE_TAG="$PROGRAM_VERSION"
    else
        # Usar a tag de deploy criada durante o deploy
        if [ -n "$DEPLOY_TAG" ]; then
            RELEASE_TAG="$DEPLOY_TAG"
        else
            # Criar uma nova tag se nenhuma existir
            RELEASE_TAG="v1.0.0-release-$(date +%Y%m%d%H%M%S)"
            git tag -a "$RELEASE_TAG" -m "Release criado em $(date): Program ID $PROGRAM_ID"
            print_message "info" "Nova tag $RELEASE_TAG criada para o release"
            
            # Enviar a nova tag para o GitHub
            if git push origin "$RELEASE_TAG"; then
                print_message "info" "Tag $RELEASE_TAG enviada para o GitHub"
            else
                print_message "warn" "Falha ao enviar a tag $RELEASE_TAG"
            fi
        fi
    fi
    
    # Obter o Program ID
    PROGRAM_ID=$(solana-keygen pubkey $PROGRAM_KEYPAIR)
    
    # Verificar se o hash do commit está disponível
    if [ -z "$COMMIT_HASH" ]; then
        COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    fi
    
    # Determinar qual branch estamos
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    
    # Detectar se estamos em devnet ou mainnet
    NETWORK=$(echo "$RPC_URL" | grep -q "mainnet" && echo "Mainnet" || echo "Devnet")
    
    # Usar método mais simples usando arquivo temporário
    print_message "info" "Enviando release para o GitHub..."
    
    # Criar JSON simples e limpo
    TEMP_FILE=$(mktemp)
    cat > "$TEMP_FILE" << EOF
{
  "tag_name": "$RELEASE_TAG",
  "name": "DONUT Matrix System $RELEASE_TAG",
  "body": "Deploy em $(date)\\n\\nProgram ID: $PROGRAM_ID\\nCommit: $COMMIT_HASH\\nRede: $NETWORK",
  "draft": false,
  "prerelease": $(echo "$RPC_URL" | grep -q "mainnet" && echo "false" || echo "true")
}
EOF
    
    # Exibir o conteúdo do JSON para depuração
    print_message "info" "Conteúdo do JSON que será enviado:"
    cat "$TEMP_FILE"
    
    # Enviar solicitação para criar o release
    RESPONSE=$(curl -s -X POST \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/releases \
      --data @"$TEMP_FILE")
    
    # Remover arquivo temporário
    rm -f "$TEMP_FILE"
    
    # Verificar se o release foi criado com sucesso
    if echo "$RESPONSE" | grep -q "html_url"; then
        RELEASE_URL=$(echo "$RESPONSE" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
        print_message "info" "Release criado com sucesso: $RELEASE_URL"
        return 0
    else
        print_message "error" "Falha ao criar release. Resposta da API:"
        echo "$RESPONSE"
        
        # Se falhar, tentar um JSON ainda mais simples
        print_message "info" "Tentando com formato JSON mínimo..."
        
        RESPONSE=$(curl -s -X POST \
          -H "Authorization: token $GITHUB_TOKEN" \
          -H "Accept: application/vnd.github+json" \
          -H "Content-Type: application/json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/releases \
          -d "{\"tag_name\":\"$RELEASE_TAG\",\"name\":\"Release $RELEASE_TAG\",\"body\":\"Program ID: $PROGRAM_ID\"}")
        
        if echo "$RESPONSE" | grep -q "html_url"; then
            RELEASE_URL=$(echo "$RESPONSE" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
            print_message "info" "Release criado com sucesso usando formato mínimo: $RELEASE_URL"
            return 0
        else
            print_message "error" "Todas as tentativas de criação de release falharam. Resposta final:"
            echo "$RESPONSE"
            return 1
        fi
    fi
}

# Função principal
main() {
    print_message "info" "=== Iniciando processo automatizado de deploy ==="
    print_message "info" "RPC URL: $RPC_URL"
    print_message "info" "Tipo de deploy: $DEPLOY_TYPE"
    
    # Fazer backup de arquivos importantes
    backup_files
    
    # Verificar e configurar Git
    check_git_repo
    
    # Configurar .gitignore adequado
    setup_gitignore
    
    # Garantir que SECURITY.md exista e esteja atualizado
    ensure_security_md
    
    # Corrigir URLs no lib.rs
    fix_lib_rs_urls
    
    # Verificar arquivos sensíveis
    check_sensitive_files
    
    # Preparar keypair do programa
    prepare_program_keypair
    
    # Enviar código para o GitHub (opcional)
    read -p "Enviar código para o GitHub? (s/n): " push_github
    if [ "$push_github" = "s" ]; then
        # Solicitar token se necessário
        request_github_token
        push_to_github
    fi
    
    # Fazer build com hash
    build_with_hash
    
    # Perguntar se deseja fazer deploy
    read -p "Prosseguir com o deploy? (s/n): " do_deploy
    if [ "$do_deploy" = "s" ]; then
        deploy_program
        
        # Mesclar para o branch main após o deploy
        read -p "Mesclar alterações para o branch main? (s/n): " do_merge
        if [ "$do_merge" = "s" ]; then
            merge_to_main
        fi
        
        # NOVA PARTE: Criar release no GitHub
        read -p "Criar release no GitHub? (s/n): " do_release
        if [ "$do_release" = "s" ]; then
            create_github_release
        fi
    else
        print_message "info" "Deploy cancelado pelo usuário."
    fi
    
    print_message "info" "=== Processo concluído ==="
}

# Executar o script
main