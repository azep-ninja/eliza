type ChainMappings = {
    [key: string]: string[]
};

const CHAIN_MAPPINGS: ChainMappings = {
    eth: ['eth', 'ethereum', 'ether', 'mainnet'],
    bsc: ['bsc', 'binance', 'bnb', 'binance smart chain', 'smartchain'],
    polygon: ['polygon', 'matic', 'poly'],
    arbitrum: ['arbitrum', 'arb', 'arbitrum one'],
    avalanche: ['avalanche', 'avax', 'avalanche c-chain'],
    base: ['base'],
    optimism: ['optimism', 'op', 'optimistic'],
    fantom: ['fantom', 'ftm', 'opera'],
    cronos: ['cronos', 'cro'],
    gnosis: ['gnosis', 'xdai', 'dai chain'],
    celo: ['celo'],
    moonbeam: ['moonbeam', 'glmr'],
    moonriver: ['moonriver', 'movr'],
    harmony: ['harmony', 'one'],
    aurora: ['aurora'],
    metis: ['metis', 'andromeda'],
    boba: ['boba'],
    kcc: ['kcc', 'kucoin'],
    heco: ['heco', 'huobi'],
    okex: ['okex', 'okexchain', 'okc'],
    zkera: ['zkera', 'zksync era', 'era'],
    zksync: ['zksync', 'zks'],
    polygonzkevm: ['polygon zkevm', 'zkevm'],
    linea: ['linea'],
    mantle: ['mantle'],
    scroll: ['scroll'],
    core: ['core', 'core dao'],
    telos: ['telos'],
    syscoin: ['syscoin', 'sys'],
    conflux: ['conflux', 'cfx'],
    klaytn: ['klaytn', 'klay'],
    fusion: ['fusion', 'fsn'],
    canto: ['canto'],
    nova: ['nova', 'arbitrum nova'],
    fuse: ['fuse'],
    evmos: ['evmos'],
    astar: ['astar'],
    dogechain: ['dogechain', 'doge'],
    thundercore: ['thundercore', 'tt'],
    oasis: ['oasis'],
    velas: ['velas'],
    meter: ['meter'],
    sx: ['sx', 'sx network'],
    kardiachain: ['kardiachain', 'kai'],
    wanchain: ['wanchain', 'wan'],
    gochain: ['gochain'],
    ethereumpow: ['ethereumpow', 'ethw'],
    pulse: ['pulsechain', 'pls'],
    kava: ['kava'],
    milkomeda: ['milkomeda'],
    nahmii: ['nahmii'],
    worldchain: ['worldchain'],
    ink: ['ink'],
    soneium: ['soneium'],
    sonic: ['sonic'],
    morph: ['morph'],
    real: ['real','re.al'],
    mode: ['mode'],
    zeta: ['zeta'],
    blast: ['blast'],
    unichain: ['unichain'],
    abstract: ['abstract'],
    step: ['step', 'stepnetwork'],
    ronin: ['ronin', 'ron'],
    iotex: ['iotex'],
    shiden: ['shiden'],
    elastos: ['elastos', 'ela'],
    solana: ['solana', 'sol'],
    tron: ['tron', 'trx'],
    sui: ['sui']
} as const;

// Regular expressions for different token address formats
const TOKEN_PATTERNS = {
    evm: /\b(0x[a-fA-F0-9]{40})\b/i,
    solana: /\b([1-9A-HJ-NP-Za-km-z]{32,44})\b/i,
    tron: /\b(T[1-9A-HJ-NP-Za-km-z]{33})\b/i,
    sui: /\b(0x[a-fA-F0-9]{64})\b/i
};

export interface TokenInfo {
    chain: string | null;
    tokenAddress: string | null;
}

function normalizeChainName(chain: string): string | null {
    const normalizedInput = chain.toLowerCase().trim();
    
    // First try exact matches
    for (const [standardName, variations] of Object.entries(CHAIN_MAPPINGS)) {
        if (variations.includes(normalizedInput)) {
            return standardName;
        }
    }
    
    // Return the normalized input to allow for new/unknown chains
    return normalizedInput;
}

export function extractTokenInfo(message: string): TokenInfo {
    const result: TokenInfo = {
        chain: null,
        tokenAddress: null
    };

    const cleanMessage = message.toLowerCase().trim();

    // Try to find chain name first
    const prepositionPattern = /(?:on|for|in|at|chain)\s+([a-zA-Z0-9]+)/i;
    const prepositionMatch = cleanMessage.match(prepositionPattern);

    if (prepositionMatch?.[1]) {
        result.chain = normalizeChainName(prepositionMatch[1]);
    } else {
        // Look for exact chain matches in the message
        for (const [chainName, variations] of Object.entries(CHAIN_MAPPINGS)) {
            if (variations.some(v => cleanMessage.split(/\s+/).includes(v))) {
                result.chain = chainName;
                break;
            }
        }
    }

    // Find token address and determine chain from address format
    let detectedChainType: string | null = null;
    
    for (const [chainType, pattern] of Object.entries(TOKEN_PATTERNS)) {
        const match = message.match(pattern);
        if (match?.[1]) {
            result.tokenAddress = match[1];
            
            // Determine chain type based on address format
            if (!result.chain) {
                if (chainType === 'solana' && match[1].length >= 32 && match[1].length <= 44) {
                    detectedChainType = 'solana';
                } else if (chainType === 'tron' && match[1].startsWith('T')) {
                    detectedChainType = 'tron';
                } else if (chainType === 'sui' && match[1].length === 66) {
                    detectedChainType = 'sui';
                } else if (chainType === 'evm') {
                    detectedChainType = 'eth'; // Default EVM chain
                }
            }
        }
    }

    // Set chain based on detected address type if no chain was explicitly specified
    if (!result.chain && detectedChainType) {
        result.chain = detectedChainType;
    }

    return result;
}