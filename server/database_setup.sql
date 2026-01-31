-- Script para criar a tabela de Cartas e Decks no PostgreSQL

-- Habilita a extensão para gerar UUIDs automaticamente
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Tabela de Usuários
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL, -- Nunca salvar senha em texto puro!
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Para bancos existentes (idempotente)
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- 2. Tabela de Cartas (Otimizada para busca e dados do MTGJSON)
	CREATE TABLE IF NOT EXISTS cards (
	    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	    scryfall_id UUID UNIQUE NOT NULL, -- ID oficial da carta (Oracle ID)
	    name TEXT NOT NULL,
	    mana_cost TEXT,
	    type_line TEXT,
	    oracle_text TEXT,
	    colors TEXT[], -- Array de cores ex: {'W', 'U'}
	    color_identity TEXT[], -- Identidade de cor (Commander), ex: {'W','U'}
	    image_url TEXT, -- URL da imagem na Scryfall
	    set_code TEXT,
	    rarity TEXT,
	    ai_description TEXT, -- Cache de explicações da IA
	    price DECIMAL(10,2), -- Preço da carta (integração Scryfall)
	    price_updated_at TIMESTAMP WITH TIME ZONE,
	    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	);

-- Para bancos existentes (idempotente)
ALTER TABLE cards ADD COLUMN IF NOT EXISTS ai_description TEXT;
ALTER TABLE cards ADD COLUMN IF NOT EXISTS price DECIMAL(10,2);
ALTER TABLE cards ADD COLUMN IF NOT EXISTS price_updated_at TIMESTAMP WITH TIME ZONE;

-- Índice para busca rápida por nome
CREATE INDEX IF NOT EXISTS idx_cards_name ON cards (name);
-- Índice GIN para buscas por identidade (Commander/Brawl)
CREATE INDEX IF NOT EXISTS idx_cards_color_identity ON cards USING GIN (color_identity);

-- 2.1. Tabela de Sets/Edições (para exibir nome e data da edição)
-- Fonte: MTGJSON SetList.json
CREATE TABLE IF NOT EXISTS sets (
    code TEXT PRIMARY KEY, -- Ex: 'UNH'
    name TEXT NOT NULL, -- Ex: 'Unhinged'
    release_date DATE, -- Ex: 2004-11-20
    type TEXT, -- Ex: 'expansion', 'promo'
    block TEXT, -- Ex: 'Ravnica'
    is_online_only BOOLEAN,
    is_foreign_only BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sets_name ON sets (name);

-- 3. Tabela de Legalidade/Banidas (Relacionamento 1:N com Cartas)
-- Ex: Card X -> Commander: Banned
CREATE TABLE IF NOT EXISTS card_legalities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID REFERENCES cards(id) ON DELETE CASCADE,
    format TEXT NOT NULL, -- 'commander', 'modern', 'standard'
    status TEXT NOT NULL, -- 'legal', 'banned', 'restricted'
    UNIQUE(card_id, format)
);

-- 4. Tabela de Regras do Jogo (Para consulta e IA)
CREATE TABLE IF NOT EXISTS rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL, -- Ex: "Combat Phase"
    description TEXT NOT NULL, -- Texto completo da regra
    category TEXT, -- Ex: "Turn Structure", "Keywords"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índices para busca rápida de regras
CREATE INDEX IF NOT EXISTS idx_rules_title ON rules (title);
CREATE INDEX IF NOT EXISTS idx_rules_category ON rules (category);

-- 5. Tabela de Decks
	CREATE TABLE IF NOT EXISTS decks (
	    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
	    name TEXT NOT NULL,
	    format TEXT NOT NULL,
	    description TEXT,
	    is_public BOOLEAN DEFAULT FALSE,

    -- Preferências do usuário (UX)
    archetype TEXT, -- Ex: "Goblin Tribal", "Voltron", etc.
    bracket INTEGER, -- 1..4 (EDH bracket / power level)
    
	    -- Campos de Análise da IA
	    synergy_score INTEGER DEFAULT 0, -- 0 a 100: Quão consolidado/sinérgico é o deck
	    strengths TEXT, -- Ex: "Ramp rápido, Proteção contra anulações"
	    weaknesses TEXT, -- Ex: "Vulnerável a board wipes, Falta de card draw"

	    -- Snapshot de custo (UX)
	    pricing_currency TEXT DEFAULT 'USD',
	    pricing_total NUMERIC(10,2),
	    pricing_missing_cards INTEGER DEFAULT 0,
	    pricing_updated_at TIMESTAMP WITH TIME ZONE,
	    
	    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
	    deleted_at TIMESTAMP WITH TIME ZONE -- Soft delete
	);

-- Backfill/compat: adiciona colunas se o banco já existir (idempotente)
	ALTER TABLE decks ADD COLUMN IF NOT EXISTS archetype TEXT;
	ALTER TABLE decks ADD COLUMN IF NOT EXISTS bracket INTEGER;
	ALTER TABLE decks ADD COLUMN IF NOT EXISTS pricing_currency TEXT DEFAULT 'USD';
	ALTER TABLE decks ADD COLUMN IF NOT EXISTS pricing_total NUMERIC(10,2);
	ALTER TABLE decks ADD COLUMN IF NOT EXISTS pricing_missing_cards INTEGER DEFAULT 0;
	ALTER TABLE decks ADD COLUMN IF NOT EXISTS pricing_updated_at TIMESTAMP WITH TIME ZONE;

-- 6. Tabela de Itens do Deck (Relacionamento N:N entre Deck e Cartas)
CREATE TABLE IF NOT EXISTS deck_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_id UUID REFERENCES decks(id) ON DELETE CASCADE,
    card_id UUID REFERENCES cards(id) ON DELETE CASCADE,
    quantity INTEGER DEFAULT 1,
    is_commander BOOLEAN DEFAULT FALSE,
    UNIQUE(deck_id, card_id)
);

-- 7. Tabela de Matchups (Counters e Estatísticas)
-- Armazena a vantagem estatística de um deck sobre outro
CREATE TABLE IF NOT EXISTS deck_matchups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_id UUID REFERENCES decks(id) ON DELETE CASCADE,
    opponent_deck_id UUID REFERENCES decks(id) ON DELETE CASCADE,
    win_rate FLOAT, -- 0.0 a 1.0 (Ex: 0.75 = 75% de vitória)
    notes TEXT, -- Observações da IA sobre o matchup
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(deck_id, opponent_deck_id)
);

-- 8. Tabela de Simulações de Batalha (Dataset para Machine Learning)
-- Cada linha é uma partida simulada que serve de treino para a IA
CREATE TABLE IF NOT EXISTS battle_simulations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_a_id UUID REFERENCES decks(id) ON DELETE SET NULL,
    deck_b_id UUID REFERENCES decks(id) ON DELETE SET NULL,
    winner_deck_id UUID REFERENCES decks(id) ON DELETE SET NULL,
    turns_played INTEGER,
    game_log JSONB, -- Log completo passo-a-passo da partida (crucial para RL)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. Tabela de Decks do Meta (Crawler)
-- Armazena decks competitivos importados de sites externos (MTGTop8, MTGO)
CREATE TABLE IF NOT EXISTS meta_decks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    format TEXT NOT NULL, -- 'standard', 'commander', etc.
    archetype TEXT, -- Ex: 'Rakdos Midrange', 'Mono Red Aggro'
    source_url TEXT UNIQUE NOT NULL, -- URL de origem para evitar duplicatas
    card_list TEXT NOT NULL, -- Lista de cartas em texto puro (formato de importação)
    placement TEXT, -- Posição no torneio (ex: '1', 'Top 8')
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. Tabela de Staples por Formato (Sincronizada via Scryfall API)
-- Armazena as cartas mais populares de cada formato, atualizada semanalmente
-- Para evitar hardcoded staples e manter dados sempre atualizados
CREATE TABLE IF NOT EXISTS format_staples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_name TEXT NOT NULL,              -- Nome exato da carta (ex: 'Sol Ring')
    format TEXT NOT NULL,                  -- 'commander', 'standard', 'modern', etc.
    archetype TEXT,                        -- 'aggro', 'control', 'combo', 'midrange', NULL = universal
    color_identity TEXT[],                 -- Cores da carta: {'W'}, {'U', 'B'}, etc. NULL = incolor/universal
    edhrec_rank INTEGER,                   -- Rank EDHREC (1 = mais popular)
    category TEXT,                         -- 'ramp', 'draw', 'removal', 'staple', 'finisher', etc.
    scryfall_id UUID,                      -- ID da carta no Scryfall para referência
    is_banned BOOLEAN DEFAULT FALSE,       -- Se foi banida recentemente (atualizado via sync)
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(card_name, format, archetype)   -- Evita duplicatas por formato/arquétipo
);

-- Índices para busca eficiente de staples
CREATE INDEX IF NOT EXISTS idx_format_staples_format ON format_staples (format);
CREATE INDEX IF NOT EXISTS idx_format_staples_archetype ON format_staples (archetype);
CREATE INDEX IF NOT EXISTS idx_format_staples_color ON format_staples USING GIN (color_identity);
CREATE INDEX IF NOT EXISTS idx_format_staples_category ON format_staples (category);
CREATE INDEX IF NOT EXISTS idx_format_staples_rank ON format_staples (edhrec_rank);

-- 11. Tabela de Histórico de Sincronização (Log de Atualizações)
-- Registra quando os dados foram sincronizados para auditoria e debugging
CREATE TABLE IF NOT EXISTS sync_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sync_type TEXT NOT NULL,               -- 'staples', 'banlist', 'meta', 'prices'
    format TEXT,                           -- Formato sincronizado (NULL = todos)
    records_updated INTEGER DEFAULT 0,     -- Quantidade de registros atualizados
    records_inserted INTEGER DEFAULT 0,    -- Quantidade de registros inseridos
    records_deleted INTEGER DEFAULT 0,     -- Quantidade de registros removidos (bans)
    status TEXT NOT NULL,                  -- 'success', 'partial', 'failed'
    error_message TEXT,                    -- Mensagem de erro se houver
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP WITH TIME ZONE
);

-- 11.1. Sync State (Checkpoint do último sync)
-- Armazena estado simples (key/value) para sincronizações incrementais.
CREATE TABLE IF NOT EXISTS sync_state (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 12. Tabela de Counters por Arquétipo (Hate Cards e Counter-Strategies)
-- Armazena cartas e estratégias para countar arquétipos específicos
-- Evita hardcoded hate cards e permite atualização dinâmica
CREATE TABLE IF NOT EXISTS archetype_counters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archetype TEXT NOT NULL,               -- 'graveyard', 'artifacts', 'tokens', 'ramp', 'combo'
    counter_archetype TEXT,                -- Arquétipo que countera (opcional, para matchups)
    hate_cards TEXT[] NOT NULL,            -- Array de nomes de cartas hate
    priority INTEGER DEFAULT 1,            -- 1=essencial, 2=bom ter, 3=situacional
    format TEXT DEFAULT 'commander',       -- Formato aplicável
    color_identity TEXT[],                 -- Cores que podem usar (NULL = qualquer)
    notes TEXT,                            -- Notas explicativas (ex: "Usar contra Muldrotha")
    effectiveness_score INTEGER DEFAULT 5, -- 1-10, quão efetivo é o counter
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índices para busca eficiente de counters
CREATE INDEX IF NOT EXISTS idx_archetype_counters_archetype ON archetype_counters (archetype);
CREATE INDEX IF NOT EXISTS idx_archetype_counters_format ON archetype_counters (format);
CREATE INDEX IF NOT EXISTS idx_archetype_counters_priority ON archetype_counters (priority);

-- Dados iniciais de hate cards por arquétipo (pode ser expandido via sync)
INSERT INTO archetype_counters (archetype, hate_cards, priority, notes, effectiveness_score) VALUES
    ('graveyard', ARRAY['Rest in Peace', 'Grafdigger''s Cage', 'Soul-Guide Lantern', 'Leyline of the Void', 'Bojuka Bog', 'Tormod''s Crypt', 'Relic of Progenitus'], 1, 'Essencial contra Muldrotha, Meren, Karador', 9),
    ('artifacts', ARRAY['Collector Ouphe', 'Stony Silence', 'Null Rod', 'Vandalblast', 'Kataki, War''s Wage', 'Energy Flux'], 1, 'Essencial contra Urza, Breya, artifact storm', 8),
    ('tokens', ARRAY['Massacre Wurm', 'Rakdos Charm', 'Illness in the Ranks', 'Virulent Plague', 'Echoing Truth', 'Aetherspouts'], 2, 'Bom contra go-wide strategies', 7),
    ('ramp', ARRAY['Confiscate', 'Collector Ouphe', 'Blood Moon', 'Back to Basics', 'Stranglehold', 'Aven Mindcensor'], 2, 'Contra decks que dependem de ramp excessivo', 6),
    ('combo', ARRAY['Rule of Law', 'Deafening Silence', 'Drannith Magistrate', 'Cursed Totem', 'Linvala, Keeper of Silence', 'Torpor Orb'], 1, 'Essencial contra storm e infinite combos', 9),
    ('enchantments', ARRAY['Tranquil Grove', 'Back to Nature', 'Bane of Progress', 'Aura Shards', 'Primeval Light'], 2, 'Contra enchantress e aura-based strategies', 7),
    ('planeswalkers', ARRAY['The Immortal Sun', 'Vampire Hexmage', 'Hex Parasite', 'Pithing Needle', 'Sorcerous Spyglass'], 2, 'Contra superfriends', 7),
    ('voltron', ARRAY['Maze of Ith', 'Fog Bank', 'Ghostly Prison', 'Propaganda', 'Constant Mists', 'Spore Frog'], 2, 'Contra voltron e commander damage', 6),
    ('control', ARRAY['Cavern of Souls', 'Boseiju, Who Shelters All', 'Destiny Spinner', 'Vexing Shusher', 'Defense Grid'], 2, 'Contra counterspell-heavy decks', 7),
    ('aggro', ARRAY['Ensnaring Bridge', 'Crawlspace', 'Silent Arbiter', 'Meekstone', 'Sphere of Safety'], 2, 'Contra creature aggro', 6)
ON CONFLICT DO NOTHING;

-- 13. Tabela de Análise de Fraquezas (Weakness Reports)
-- Armazena análises de fraquezas identificadas em decks
CREATE TABLE IF NOT EXISTS deck_weakness_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_id UUID REFERENCES decks(id) ON DELETE CASCADE,
    weakness_type TEXT NOT NULL,           -- 'graveyard_vulnerability', 'low_removal', 'high_curve'
    severity TEXT NOT NULL,                -- 'critical', 'high', 'medium', 'low'
    description TEXT NOT NULL,             -- Descrição legível da fraqueza
    recommendations TEXT[],                -- Array de cartas/ações recomendadas
    auto_detected BOOLEAN DEFAULT TRUE,    -- Se foi detectado automaticamente
    addressed BOOLEAN DEFAULT FALSE,       -- Se já foi tratado pelo usuário
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_weakness_reports_deck ON deck_weakness_reports (deck_id);
CREATE INDEX IF NOT EXISTS idx_weakness_reports_severity ON deck_weakness_reports (severity);

-- 14. Tabela de Logs de IA (Observabilidade)
-- Armazena métricas e resumos das chamadas de IA para debugging e auditoria
CREATE TABLE IF NOT EXISTS ai_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    deck_id UUID REFERENCES decks(id) ON DELETE SET NULL,
    endpoint TEXT NOT NULL,              -- 'optimize', 'complete', 'explain', 'archetypes'
    model TEXT NOT NULL,                 -- 'gpt-4o', 'gpt-4o-mini', etc.
    prompt_summary TEXT,                 -- Resumo do prompt (sem dados sensíveis)
    input_tokens INTEGER,                -- Tokens de entrada (se disponível)
    output_tokens INTEGER,               -- Tokens de saída (se disponível)
    response_summary TEXT,               -- Resumo da resposta
    success BOOLEAN NOT NULL DEFAULT TRUE,
    error_message TEXT,                  -- Mensagem de erro (se falhou)
    latency_ms INTEGER NOT NULL,         -- Tempo total da chamada em ms
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ai_logs_user ON ai_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_deck ON ai_logs (deck_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_endpoint ON ai_logs (endpoint);
CREATE INDEX IF NOT EXISTS idx_ai_logs_created ON ai_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_logs_success ON ai_logs (success);
