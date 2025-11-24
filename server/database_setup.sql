-- Script para criar a tabela de Cartas e Decks no PostgreSQL

-- Habilita a extensão para gerar UUIDs automaticamente
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Tabela de Usuários
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL, -- Nunca salvar senha em texto puro!
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Tabela de Cartas (Otimizada para busca e dados do MTGJSON)
CREATE TABLE IF NOT EXISTS cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scryfall_id UUID UNIQUE NOT NULL, -- ID oficial da carta (Oracle ID)
    name TEXT NOT NULL,
    mana_cost TEXT,
    type_line TEXT,
    oracle_text TEXT,
    colors TEXT[], -- Array de cores ex: {'W', 'U'}
    image_url TEXT, -- URL da imagem na Scryfall
    set_code TEXT,
    rarity TEXT,
    ai_description TEXT, -- Cache de explicações da IA
    price DECIMAL(10,2), -- Preço da carta (integração Scryfall)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índice para busca rápida por nome
CREATE INDEX IF NOT EXISTS idx_cards_name ON cards (name);

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

-- 5. Tabela de Decks
CREATE TABLE IF NOT EXISTS decks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    format TEXT NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    
    -- Campos de Análise da IA
    synergy_score INTEGER DEFAULT 0, -- 0 a 100: Quão consolidado/sinérgico é o deck
    strengths TEXT, -- Ex: "Ramp rápido, Proteção contra anulações"
    weaknesses TEXT, -- Ex: "Vulnerável a board wipes, Falta de card draw"
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE -- Soft delete
);

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
