# Relatório completo de cores, temas e gradientes

> Gerado automaticamente por varredura do código-fonte local.  
> Base: `app/lib/core/theme/app_theme.dart` + usos em `app/lib/**`

## 1) Onde o tema é aplicado

- Tema global configurado em `app/lib/main.dart` com `theme: AppTheme.darkTheme`.
- Fundo global com gradiente aplicado em `app/lib/core/widgets/main_scaffold.dart` via `AppTheme.scaffoldGradient`.
- Regra de projeto no próprio `app_theme.dart`: cores devem ser centralizadas nesse arquivo.

## 2) Paleta principal (cores base)

| Token | HEX | Definição | Referências no app |
|---|---:|---|---:|
| `backgroundAbyss` | `0xFF0A0E14` | `app_theme.dart:16` | 30 |
| `surfaceSlate` | `0xFF1E293B` | `app_theme.dart:17` | 68 |
| `surfaceSlate2` | `0xFF0F172A` | `app_theme.dart:18` | 45 |
| `manaViolet` | `0xFF8B5CF6` | `app_theme.dart:19` | 124 |
| `loomCyan` | `0xFF06B6D4` | `app_theme.dart:20` | 75 |
| `mythicGold` | `0xFFF59E0B` | `app_theme.dart:21` | 108 |
| `textPrimary` | `0xFFF1F5F9` | `app_theme.dart:23` | 84 |
| `textSecondary` | `0xFF94A3B8` | `app_theme.dart:24` | 263 |
| `textHint` | `0xFF64748B` | `app_theme.dart:25` | 14 |
| `outlineMuted` | `0xFF334155` | `app_theme.dart:26` | 91 |
| `success` | `0xFF22C55E` | `app_theme.dart:29` | 28 |
| `error` | `0xFFEF4444` | `app_theme.dart:30` | 50 |
| `warning` | `0xFFF97316` | `app_theme.dart:31` | 16 |
| `disabled` | `0xFF6B7280` | `app_theme.dart:32` | 7 |
| `manaW` | `0xFFF0F2C0` | `app_theme.dart:83` | 1 |
| `manaU` | `0xFFB3CEEA` | `app_theme.dart:84` | 1 |
| `manaB` | `0xFFA69F9D` | `app_theme.dart:85` | 1 |
| `manaR` | `0xFFEB9F82` | `app_theme.dart:86` | 1 |
| `manaG` | `0xFFC4D3CA` | `app_theme.dart:87` | 1 |
| `manaC` | `0xFFB8C0CC` | `app_theme.dart:88` | 1 |
| `formatPioneer` | `0xFF34D399` | `app_theme.dart:103` | 1 |
| `formatLegacy` | `0xFFEC4899` | `app_theme.dart:104` | 1 |

## 3) Gradientes

| Gradiente | Definição | Cores HEX explícitas | Referências no app |
|---|---|---|---:|
| `scaffoldGradient` | `app_theme.dart:35` | `0xFF0C1020`, `0xFF0A0D1A` | 1 |
| `heroGradient` | `app_theme.dart:42` | `0xFF1A0A2E`, `0xFF0F172A` | 0 |
| `primaryGradient` | `app_theme.dart:48` | `0xFF6D28D9` | 14 |
| `cardGradient` | `app_theme.dart:54` | - | 5 |
| `goldAccentGradient` | `app_theme.dart:60` | `0xFFD97706` | 0 |

### Uso dos gradientes no app

- `scaffoldGradient`:
  - `app/lib/core/widgets/main_scaffold.dart` (linhas: 96)
- `heroGradient`:
  - **Sem uso direto atualmente**.
- `primaryGradient`:
  - `app/lib/features/home/home_screen.dart` (linhas: 39, 44, 77, 268, 302, 542, 562)
  - `app/lib/features/auth/screens/register_screen.dart` (linhas: 94, 250, 268)
  - `app/lib/features/auth/screens/login_screen.dart` (linhas: 95, 115, 207, 225)
- `cardGradient`:
  - `app/lib/features/home/home_screen.dart` (linhas: 456, 535, 593, 689)
  - `app/lib/features/decks/widgets/deck_card.dart` (linhas: 46)
- `goldAccentGradient`:
  - **Sem uso direto atualmente**.

## 4) Cores de texto (como e onde são usadas)

### `textPrimary`
- Total de referências: **84**
- Principais telas/arquivos:
  - `app/lib/features/social/screens/user_profile_screen.dart` (10 refs)
  - `app/lib/features/trades/screens/trade_detail_screen.dart` (10 refs)
  - `app/lib/features/community/screens/community_screen.dart` (9 refs)
  - `app/lib/features/binder/widgets/binder_item_editor.dart` (7 refs)
  - `app/lib/features/cards/screens/card_detail_screen.dart` (6 refs)
  - `app/lib/features/trades/screens/create_trade_screen.dart` (6 refs)
  - `app/lib/features/messages/screens/message_inbox_screen.dart` (4 refs)
  - `app/lib/features/messages/screens/chat_screen.dart` (4 refs)
  - `app/lib/features/binder/screens/binder_screen.dart` (4 refs)
  - `app/lib/features/binder/screens/marketplace_screen.dart` (4 refs)
  - `app/lib/features/home/life_counter_screen.dart` (3 refs)
  - `app/lib/features/market/screens/market_screen.dart` (3 refs)
  - `app/lib/features/notifications/screens/notification_screen.dart` (3 refs)
  - `app/lib/features/social/screens/user_search_screen.dart` (2 refs)
  - `app/lib/features/community/screens/community_deck_detail_screen.dart` (2 refs)

### `textSecondary`
- Total de referências: **263**
- Principais telas/arquivos:
  - `app/lib/features/community/screens/community_screen.dart` (49 refs)
  - `app/lib/features/market/screens/market_screen.dart` (21 refs)
  - `app/lib/features/binder/widgets/binder_item_editor.dart` (19 refs)
  - `app/lib/features/social/screens/user_profile_screen.dart` (18 refs)
  - `app/lib/features/binder/screens/binder_screen.dart` (18 refs)
  - `app/lib/features/binder/screens/marketplace_screen.dart` (16 refs)
  - `app/lib/features/trades/screens/trade_detail_screen.dart` (13 refs)
  - `app/lib/features/social/screens/user_search_screen.dart` (11 refs)
  - `app/lib/features/trades/screens/create_trade_screen.dart` (10 refs)
  - `app/lib/features/scanner/widgets/scanned_card_preview.dart` (10 refs)
  - `app/lib/features/trades/screens/trade_inbox_screen.dart` (8 refs)
  - `app/lib/features/home/life_counter_screen.dart` (7 refs)
  - `app/lib/features/community/screens/community_deck_detail_screen.dart` (7 refs)
  - `app/lib/features/cards/screens/card_detail_screen.dart` (7 refs)
  - `app/lib/features/messages/screens/message_inbox_screen.dart` (5 refs)

### `textHint`
- Total de referências: **14**
- Principais telas/arquivos:
  - `app/lib/features/home/life_counter_screen.dart` (5 refs)
  - `app/lib/features/decks/screens/deck_details_screen.dart` (4 refs)
  - `app/lib/features/trades/screens/trade_detail_screen.dart` (3 refs)
  - `app/lib/features/cards/screens/card_detail_screen.dart` (1 refs)
  - `app/lib/features/decks/widgets/deck_card.dart` (1 refs)

## 5) Cores dos cards (cards de deck/cartas/coleção)

### 5.1 Moldura de card de deck por formato
- Mapeamento em `app/lib/features/decks/widgets/deck_card.dart`:
  - Commander → `AppTheme.formatCommander`
  - Standard → `AppTheme.formatStandard`
  - Modern → `AppTheme.formatModern`
  - Pioneer → `AppTheme.formatPioneer`
  - Legacy → `AppTheme.formatLegacy`
  - Vintage → `AppTheme.formatVintage`
  - Pauper → `AppTheme.formatPauper`
- O card usa `AppTheme.cardGradient` como fundo + borda lateral com cor do formato.

### 5.2 Cor por condição da carta (NM/LP/MP/HP/DMG)
- Mapeamento central: `AppTheme.conditionColor()` em `app/lib/core/theme/app_theme.dart`.
- Usada em:
  - `app/lib/features/binder/screens/binder_screen.dart`
  - `app/lib/features/binder/screens/marketplace_screen.dart`
  - `app/lib/features/trades/screens/create_trade_screen.dart`
  - `app/lib/features/social/screens/user_profile_screen.dart`
- Implementações locais equivalentes também existem em:
  - `app/lib/features/scanner/widgets/scanned_card_preview.dart`
  - `app/lib/features/decks/screens/deck_details_screen.dart`

### 5.3 Cores de mana e identidade de cor
- Tokens W/U/B/R/G/C definidos em `AppTheme.manaW/manaU/manaB/manaR/manaG/manaC`.
- Mapa `AppTheme.wubrg` usado em `app/lib/features/decks/widgets/deck_analysis_tab.dart`.
- Símbolos de mana em preview de scanner usam os tokens `mana*` em `app/lib/features/scanner/widgets/scanned_card_preview.dart`.
- `AppTheme.identityColor()` está definido para badge de identidade (mono-color retorna WUBRG, multicolor retorna `manaViolet`).

### 5.4 Cor de score/sinergia
- `AppTheme.scoreColor(score)`:
  - `>= 80` → `success`
  - `>= 60` → `mythicGold`
  - `< 60` → `error`
- Uso em `app/lib/features/decks/widgets/deck_card.dart`.

### 5.5 Cores de raridade exibidas no app
- Em `app/lib/features/cards/screens/card_detail_screen.dart`:
  - common = `Colors.grey`
  - uncommon = `Color(0xFFC0C0C0)`
  - rare = `Color(0xFFFFD700)`
  - mythic = `AppTheme.mythicGold`
- Em `app/lib/features/scanner/widgets/scanned_card_preview.dart` (dot):
  - mythic = `AppTheme.warning`
  - rare = `AppTheme.mythicGold`
  - uncommon = `AppTheme.textSecondary`
  - default = `AppTheme.outlineMuted`

## 6) Exceções (cores hardcoded fora do AppTheme)

Arquivos com `Color(0x...)` fora de `app_theme.dart`:

- `app/lib/features/home/home_screen.dart`
  - L133: `color: const Color(0xFFEF4444),`
  - L142: `color: const Color(0xFF22C55E),`
  - L230: `Color(0xFF1A0A2E),`
  - L231: `Color(0xFF0F172A),`
- `app/lib/features/home/life_counter_screen.dart`
  - L56: `Color(0xFFEF4444),`
  - L490: `color: const Color(0xFF10B981), // green for poison`
  - L727: `color: const Color(0xFF10B981),`
- `app/lib/features/auth/screens/register_screen.dart`
  - L77: `Color(0xFF1A0A2E),`
- `app/lib/features/auth/screens/login_screen.dart`
  - L73: `Color(0xFF1A0A2E),`
- `app/lib/features/cards/screens/card_detail_screen.dart`
  - L229: `const Color(0xFFF0F2C0),`
  - L230: `const Color(0xFF3D3000),`
  - L235: `const Color(0xFFB3CEEA),`
  - L236: `const Color(0xFF0A2340),`
  - L241: `const Color(0xFFA69F9D),`
  - L242: `const Color(0xFF1A1A1A),`
  - L247: `const Color(0xFFEB9F82),`
  - L248: `const Color(0xFF3D1005),`
  - ... +9 ocorrência(s)

## 7) Mapa completo por token (`AppTheme.*`)

### `backgroundAbyss` (30 refs)
- `app/lib/features/home/home_screen.dart`: 232
- `app/lib/features/home/life_counter_screen.dart`: 229
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 83
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 27, 29
- `app/lib/features/messages/screens/chat_screen.dart`: 81, 189
- `app/lib/features/social/screens/user_search_screen.dart`: 38
- `app/lib/features/social/screens/user_profile_screen.dart`: 98, 713
- `app/lib/features/auth/screens/register_screen.dart`: 79
- `app/lib/features/auth/screens/login_screen.dart`: 75
- `app/lib/features/auth/screens/splash_screen.dart`: 74
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 83
- `app/lib/features/community/screens/community_screen.dart`: 58, 307, 314
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 148
- `app/lib/features/collection/screens/collection_screen.dart`: 43
- `app/lib/features/binder/screens/binder_screen.dart`: 618
- `app/lib/features/cards/screens/card_detail_screen.dart`: 22
- `app/lib/features/market/screens/market_screen.dart`: 40, 55
- `app/lib/features/trades/screens/create_trade_screen.dart`: 313
- `app/lib/features/notifications/screens/notification_screen.dart`: 27, 29
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 77, 137
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 609
- `app/lib/core/widgets/main_scaffold.dart`: 30

### `cardGradient` (5 refs)
- `app/lib/features/home/home_screen.dart`: 456, 535, 593, 689
- `app/lib/features/decks/widgets/deck_card.dart`: 46

### `conditionColor` (5 refs)
- `app/lib/features/social/screens/user_profile_screen.dart`: 1158
- `app/lib/features/binder/screens/binder_screen.dart`: 911
- `app/lib/features/binder/screens/marketplace_screen.dart`: 597
- `app/lib/features/trades/screens/create_trade_screen.dart`: 276, 581

### `darkTheme` (1 refs)
- `app/lib/main.dart`: 373

### `disabled` (7 refs)
- `app/lib/features/cards/screens/card_search_screen.dart`: 268
- `app/lib/features/trades/providers/trade_provider.dart`: 305
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 511, 531
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 226
- `app/lib/features/decks/widgets/deck_analysis_tab.dart`: 317
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 486

### `error` (50 refs)
- `app/lib/features/home/home_screen.dart`: 720, 728
- `app/lib/features/home/life_counter_screen.dart`: 436, 541, 829, 834, 840, 858, 878
- `app/lib/features/profile/profile_screen.dart`: 126
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 74
- `app/lib/features/community/screens/community_screen.dart`: 1199
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 244, 727, 728
- `app/lib/features/market/screens/market_screen.dart`: 325
- `app/lib/features/trades/providers/trade_provider.dart`: 303, 307
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 502, 550, 567, 611
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 224
- `app/lib/features/decks/screens/deck_list_screen.dart`: 120, 160
- `app/lib/features/decks/screens/deck_import_screen.dart`: 212, 217, 222, 570, 575, 580
- `app/lib/features/decks/screens/deck_details_screen.dart`: 1297, 1312, 1332, 1374, 2296, 2299, 2306, 2314, 2582, 2968, 3177, 3327
- `app/lib/features/notifications/screens/notification_screen.dart`: 235
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 323, 337, 612, 615
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 388
- `app/lib/core/widgets/main_scaffold.dart`: 79

### `fontDisplay` (1 refs)
- `app/lib/features/social/screens/user_profile_screen.dart`: 158

### `fontLg` (42 refs)
- `app/lib/features/home/home_screen.dart`: 371
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 59, 143
- `app/lib/features/messages/screens/chat_screen.dart`: 114
- `app/lib/features/social/screens/user_search_screen.dart`: 113, 135, 223
- `app/lib/features/social/screens/user_profile_screen.dart`: 410, 598, 869, 1064
- `app/lib/features/auth/screens/register_screen.dart`: 288
- `app/lib/features/auth/screens/login_screen.dart`: 245
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 296, 319
- `app/lib/features/community/screens/community_screen.dart`: 248, 396, 559, 592, 670, 828, 944, 1283
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 201
- `app/lib/features/binder/screens/marketplace_screen.dart`: 225
- `app/lib/features/market/screens/market_screen.dart`: 460
- `app/lib/features/trades/screens/create_trade_screen.dart`: 245, 430, 446
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 245
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 308
- `app/lib/features/decks/screens/deck_import_screen.dart`: 405, 503, 610, 620
- `app/lib/features/decks/screens/deck_generate_screen.dart`: 293, 349
- `app/lib/features/notifications/screens/notification_screen.dart`: 76
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 153, 400, 626
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 722

### `fontMd` (64 refs)
- `app/lib/features/home/home_screen.dart`: 495, 701
- `app/lib/features/home/life_counter_screen.dart`: 850
- `app/lib/features/profile/profile_screen.dart`: 100
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 69, 153
- `app/lib/features/messages/screens/chat_screen.dart`: 141, 270
- `app/lib/features/social/screens/user_profile_screen.dart`: 181, 461, 725, 906, 997, 1147
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 209, 222, 234, 367
- `app/lib/features/community/screens/community_screen.dart`: 67, 256, 406, 570, 1093, 1154, 1160, 1261
- `app/lib/features/collection/screens/collection_screen.dart`: 60
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 363, 481, 570, 600
- `app/lib/features/binder/screens/binder_screen.dart`: 65, 626, 811
- `app/lib/features/binder/screens/marketplace_screen.dart`: 86, 389, 427
- `app/lib/features/cards/screens/card_detail_screen.dart`: 112
- `app/lib/features/market/screens/market_screen.dart`: 152, 161, 271, 415
- `app/lib/features/trades/screens/create_trade_screen.dart`: 266, 515, 573, 628
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 383
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 152, 200, 206, 265, 283, 448, 589, 829, 860
- `app/lib/features/decks/screens/deck_import_screen.dart`: 248, 418, 527
- `app/lib/features/decks/screens/deck_details_screen.dart`: 2242
- `app/lib/features/notifications/screens/notification_screen.dart`: 174
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 540
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 518, 544

### `fontSm` (109 refs)
- `app/lib/features/home/home_screen.dart`: 431, 712
- `app/lib/features/home/life_counter_screen.dart`: 429
- `app/lib/features/profile/profile_screen.dart`: 246, 266
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 163
- `app/lib/features/messages/screens/chat_screen.dart`: 103
- `app/lib/features/social/screens/user_search_screen.dart`: 231, 244, 256
- `app/lib/features/social/screens/user_profile_screen.dart`: 260, 278, 379, 491, 506, 655, 879, 977, 1182
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 181, 375, 383
- `app/lib/features/community/screens/community_screen.dart`: 309, 702, 737, 754, 768, 858, 873, 952, 966, 979, 1099, 1157, 1172, 1231, 1268, 1270, 1271, 1295
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 338, 369, 616
- `app/lib/features/binder/screens/binder_screen.dart`: 579, 670, 694, 744, 749, 856
- `app/lib/features/binder/screens/marketplace_screen.dart`: 142, 165, 320, 325, 467, 552
- `app/lib/features/market/screens/market_screen.dart`: 66, 157, 175, 277, 359, 428, 434, 440, 480
- `app/lib/features/trades/screens/create_trade_screen.dart`: 272, 277, 288, 485, 729
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 326, 347, 421
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 211, 272, 323, 351, 367, 456, 463, 820, 839
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 148, 246
- `app/lib/features/decks/widgets/deck_analysis_tab.dart`: 322
- `app/lib/features/decks/screens/deck_import_screen.dart`: 195, 290, 310, 558, 634
- `app/lib/features/decks/screens/deck_details_screen.dart`: 399, 1497, 2185, 2253, 2276, 2285, 2315, 2344, 2354, 2363
- `app/lib/features/decks/screens/deck_generate_screen.dart`: 265
- `app/lib/features/notifications/screens/notification_screen.dart`: 45, 186
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 169, 193, 277, 358, 550, 635
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 571

### `fontXl` (10 refs)
- `app/lib/features/home/life_counter_screen.dart`: 879
- `app/lib/features/social/screens/user_search_screen.dart`: 207
- `app/lib/features/social/screens/user_profile_screen.dart`: 372
- `app/lib/features/community/screens/community_screen.dart`: 929
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 301, 584
- `app/lib/features/binder/screens/binder_screen.dart`: 402
- `app/lib/features/cards/screens/card_search_screen.dart`: 483
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 316
- `app/lib/features/decks/screens/deck_details_screen.dart`: 2180

### `fontXs` (32 refs)
- `app/lib/features/home/home_screen.dart`: 729
- `app/lib/features/home/life_counter_screen.dart`: 429, 859
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 176, 191
- `app/lib/features/messages/screens/chat_screen.dart`: 278
- `app/lib/features/social/screens/user_profile_screen.dart`: 481, 1222, 1239
- `app/lib/features/community/screens/community_screen.dart`: 723, 848, 1301
- `app/lib/features/binder/screens/binder_screen.dart`: 834, 887, 904
- `app/lib/features/binder/screens/marketplace_screen.dart`: 454, 482, 507, 576, 591
- `app/lib/features/market/screens/market_screen.dart`: 493
- `app/lib/features/trades/screens/create_trade_screen.dart`: 582, 593
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 847
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 233, 316
- `app/lib/features/decks/screens/deck_details_screen.dart`: 607, 1051, 1095
- `app/lib/features/notifications/screens/notification_screen.dart`: 195
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 467
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 696

### `fontXxl` (3 refs)
- `app/lib/features/social/screens/user_profile_screen.dart`: 170
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 163
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 146

### `formatCommander` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 23

### `formatLegacy` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 27

### `formatModern` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 25

### `formatPauper` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 29

### `formatPioneer` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 26

### `formatStandard` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 24

### `formatVintage` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 28

### `loomCyan` (75 refs)
- `app/lib/features/home/home_screen.dart`: 120
- `app/lib/features/home/life_counter_screen.dart`: 54, 787
- `app/lib/features/social/screens/user_search_screen.dart`: 57, 238
- `app/lib/features/social/screens/user_profile_screen.dart`: 365, 717, 720, 877, 895, 920, 1167, 1194, 1200
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 95, 97, 208, 213, 278, 317
- `app/lib/features/community/screens/community_screen.dart`: 168, 312, 316, 502, 699, 706, 960, 1337
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 492, 498, 508, 514, 647, 650
- `app/lib/features/binder/screens/binder_screen.dart`: 57, 60, 423, 510, 530, 664, 668, 674, 680, 845
- `app/lib/features/binder/screens/marketplace_screen.dart`: 136, 140, 146, 416, 466, 529, 533
- `app/lib/features/cards/screens/card_detail_screen.dart`: 291, 338
- `app/lib/features/market/screens/market_screen.dart`: 526
- `app/lib/features/trades/providers/trade_provider.dart`: 295
- `app/lib/features/trades/screens/create_trade_screen.dart`: 293, 362, 452
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 234, 819
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 179
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 222
- `app/lib/features/decks/screens/deck_details_screen.dart`: 371, 376, 388, 396, 2576
- `app/lib/features/notifications/screens/notification_screen.dart`: 229, 239
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 126, 331
- `app/lib/features/scanner/widgets/scanner_overlay.dart`: 58
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 371, 499
- `app/lib/core/widgets/main_scaffold.dart`: 57

### `manaB` (1 refs)
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 482

### `manaC` (1 refs)
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 485

### `manaG` (1 refs)
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 484

### `manaR` (1 refs)
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 483

### `manaU` (1 refs)
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 481

### `manaViolet` (124 refs)
- `app/lib/features/home/home_screen.dart`: 78, 271, 307, 563, 676
- `app/lib/features/home/life_counter_screen.dart`: 53, 994, 1024
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 125, 202
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 40, 79, 133, 141, 175, 184
- `app/lib/features/messages/screens/chat_screen.dart`: 89, 101, 130, 213, 218, 253
- `app/lib/features/social/screens/user_search_screen.dart`: 85, 197, 205, 250
- `app/lib/features/social/screens/user_profile_screen.dart`: 108, 148, 157, 231, 291, 473, 480, 582, 614, 630, 638, 942, 1044, 1074, 1084, 1155
- `app/lib/features/auth/screens/register_screen.dart`: 272
- `app/lib/features/auth/screens/login_screen.dart`: 98, 229
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 110, 173, 179
- `app/lib/features/community/screens/community_screen.dart`: 64, 209, 274, 377, 418, 430, 530, 716, 722, 841, 847, 919, 927, 973, 1066
- `app/lib/features/collection/screens/collection_screen.dart`: 56, 57
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 354, 397, 402, 418, 610, 620, 689, 713, 743, 791, 798
- `app/lib/features/binder/screens/binder_screen.dart`: 360, 433, 451, 461, 540, 819
- `app/lib/features/binder/screens/marketplace_screen.dart`: 188, 249, 399, 444, 455
- `app/lib/features/cards/screens/card_search_screen.dart`: 331, 333, 340
- `app/lib/features/market/screens/market_screen.dart`: 241
- `app/lib/features/trades/providers/trade_provider.dart`: 297
- `app/lib/features/trades/screens/create_trade_screen.dart`: 271, 352, 401, 414, 456
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 70, 71, 151, 152
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 343, 524, 722, 806
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 144, 184, 274
- `app/lib/features/decks/widgets/deck_analysis_tab.dart`: 145
- `app/lib/features/decks/widgets/deck_card.dart`: 30
- `app/lib/features/decks/screens/deck_details_screen.dart`: 1578
- `app/lib/features/notifications/screens/notification_screen.dart`: 44, 57, 87, 158, 243, 245
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 217, 217, 385, 506, 539, 562
- `app/lib/core/widgets/cached_card_image.dart`: 143

### `manaW` (1 refs)
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 480

### `mythicGold` (108 refs)
- `app/lib/features/home/home_screen.dart`: 111
- `app/lib/features/home/life_counter_screen.dart`: 55, 500, 738, 776
- `app/lib/features/social/screens/user_profile_screen.dart`: 498, 504, 718, 721, 878, 898, 904, 930, 1163, 1171, 1181, 1194, 1200
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 243, 248, 294
- `app/lib/features/community/screens/community_screen.dart`: 746, 753, 866, 872, 1039, 1088, 1116, 1117, 1167, 1172, 1191, 1335, 1336
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 330, 332, 337, 447, 530, 536, 546, 552, 634, 637, 660, 663
- `app/lib/features/binder/screens/binder_screen.dart`: 58, 61, 423, 516, 522, 688, 692, 698, 704, 826, 848, 855
- `app/lib/features/binder/screens/marketplace_screen.dart`: 159, 163, 169, 407, 419, 426, 528, 532
- `app/lib/features/cards/screens/card_detail_screen.dart`: 550
- `app/lib/features/market/screens/market_screen.dart`: 44, 79, 80, 168, 174, 188, 210, 266, 522, 524
- `app/lib/features/trades/providers/trade_provider.dart`: 293
- `app/lib/features/trades/screens/create_trade_screen.dart`: 281, 287, 339, 454, 586, 592, 670, 686, 713, 717, 725
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 282, 300, 302, 306, 315
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 114, 174, 231, 258, 261
- `app/lib/features/decks/screens/deck_list_screen.dart`: 345
- `app/lib/features/decks/screens/deck_details_screen.dart`: 2578
- `app/lib/features/notifications/screens/notification_screen.dart`: 231
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 322, 333, 432
- `app/lib/features/scanner/widgets/scanner_overlay.dart`: 58
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 428, 558

### `outlineMuted` (91 refs)
- `app/lib/features/home/home_screen.dart`: 236, 458, 512, 537, 595, 691
- `app/lib/features/home/life_counter_screen.dart`: 589, 707, 926
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 192
- `app/lib/features/profile/profile_screen.dart`: 338
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 86
- `app/lib/features/messages/screens/chat_screen.dart`: 174
- `app/lib/features/social/screens/user_search_screen.dart`: 184
- `app/lib/features/social/screens/user_profile_screen.dart`: 237, 271, 427, 624, 911, 1122
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 151
- `app/lib/features/community/screens/community_screen.dart`: 316, 643, 803, 908, 1157, 1181, 1211, 1270
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 217
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 289, 403, 419, 499, 537, 620, 634, 647, 660, 684, 708, 791, 798
- `app/lib/features/binder/screens/binder_screen.dart`: 675, 699, 737, 784
- `app/lib/features/binder/screens/marketplace_screen.dart`: 147, 170, 313, 363
- `app/lib/features/cards/screens/card_detail_screen.dart`: 99, 303, 349, 480, 533
- `app/lib/features/market/screens/market_screen.dart`: 157, 337, 434
- `app/lib/features/trades/screens/create_trade_screen.dart`: 247, 391, 396, 473, 511, 676, 681, 717
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 241, 304
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 197, 245, 369, 402, 430, 788, 807
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 106, 262
- `app/lib/features/decks/widgets/deck_card.dart`: 50, 51, 52
- `app/lib/features/notifications/screens/notification_screen.dart`: 94
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 210, 238, 262, 370, 436
- `app/lib/core/widgets/cached_card_image.dart`: 121, 160
- `app/lib/core/widgets/main_scaffold.dart`: 37, 102

### `primaryGradient` (14 refs)
- `app/lib/features/home/home_screen.dart`: 39, 44, 77, 268, 302, 542, 562
- `app/lib/features/auth/screens/register_screen.dart`: 94, 250, 268
- `app/lib/features/auth/screens/login_screen.dart`: 95, 115, 207, 225

### `radiusLg` (10 refs)
- `app/lib/features/home/home_screen.dart`: 536
- `app/lib/features/home/life_counter_screen.dart`: 179, 203
- `app/lib/features/cards/screens/card_detail_screen.dart`: 82, 83, 95, 96
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 613
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 559, 586

### `radiusMd` (116 refs)
- `app/lib/features/home/home_screen.dart`: 405, 410, 457, 463, 594
- `app/lib/features/home/life_counter_screen.dart`: 831
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 191
- `app/lib/features/social/screens/user_search_screen.dart`: 69, 183, 187
- `app/lib/features/social/screens/user_profile_screen.dart`: 426, 430, 623, 1002, 1121, 1125
- `app/lib/features/auth/screens/register_screen.dart`: 124, 150, 188, 226, 251, 269, 281
- `app/lib/features/auth/screens/login_screen.dart`: 145, 183, 208, 226, 238
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 150, 282
- `app/lib/features/community/screens/community_screen.dart`: 180, 514, 642, 646, 802, 806, 907, 911, 1207
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 314, 399, 495, 533, 682, 687, 706, 711, 731, 747
- `app/lib/features/binder/screens/binder_screen.dart`: 643, 783, 787
- `app/lib/features/binder/screens/marketplace_screen.dart`: 106, 362
- `app/lib/features/cards/screens/card_detail_screen.dart`: 301, 347
- `app/lib/features/market/screens/market_screen.dart`: 333
- `app/lib/features/trades/screens/create_trade_screen.dart`: 389, 394, 399, 417, 471, 509, 530, 551, 674, 679, 684, 715
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 286, 290
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 131, 191, 227, 301, 339, 384, 595, 769, 808
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 105
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 112, 117, 142
- `app/lib/features/decks/widgets/deck_card.dart`: 47, 68, 186
- `app/lib/features/decks/screens/deck_list_screen.dart`: 320
- `app/lib/features/decks/screens/deck_import_screen.dart`: 389
- `app/lib/features/decks/screens/deck_details_screen.dart`: 107, 432, 555, 655, 666, 767, 829, 853, 938, 973, 1150, 1218, 1403, 1413, 2530, 3266, 3361, 3369, 3405
- `app/lib/features/decks/screens/deck_generate_screen.dart`: 212, 241, 330, 408
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 101, 121, 386, 388

### `radiusSm` (60 refs)
- `app/lib/features/home/home_screen.dart`: 344, 356, 474, 603, 690
- `app/lib/features/home/life_counter_screen.dart`: 549, 584, 590
- `app/lib/features/social/screens/user_profile_screen.dart`: 449, 858, 972, 1135, 1196
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 174, 345
- `app/lib/features/community/screens/community_screen.dart`: 657, 816, 1168, 1224, 1239, 1290
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 331, 785, 793
- `app/lib/features/binder/screens/binder_screen.dart`: 736, 798
- `app/lib/features/binder/screens/marketplace_screen.dart`: 312, 374, 540
- `app/lib/features/cards/screens/card_search_screen.dart`: 315
- `app/lib/features/market/screens/market_screen.dart`: 169, 352, 368, 469
- `app/lib/features/trades/screens/create_trade_screen.dart`: 261, 562, 604
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 166, 211, 218
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 238
- `app/lib/features/decks/widgets/deck_card.dart`: 88
- `app/lib/features/decks/screens/deck_import_screen.dart`: 174, 213, 272
- `app/lib/features/decks/screens/deck_details_screen.dart`: 499, 505, 524, 530, 569, 591, 1079, 2215, 2297, 2331
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 183, 348, 371, 373, 648

### `radiusXl` (15 refs)
- `app/lib/features/messages/screens/chat_screen.dart`: 195
- `app/lib/features/social/screens/user_profile_screen.dart`: 234, 273
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 54
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 336
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 708
- `app/lib/features/decks/screens/deck_details_screen.dart`: 313, 323, 365, 373, 1612, 1637, 2073
- `app/lib/features/scanner/screens/card_scanner_screen.dart`: 500, 540

### `radiusXs` (24 refs)
- `app/lib/features/home/home_screen.dart`: 723
- `app/lib/features/social/screens/user_profile_screen.dart`: 475, 1216, 1233
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 361
- `app/lib/features/community/screens/community_screen.dart`: 717, 842
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 290
- `app/lib/features/binder/screens/binder_screen.dart`: 881, 898
- `app/lib/features/binder/screens/marketplace_screen.dart`: 571, 586
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 254
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 158
- `app/lib/features/decks/widgets/deck_analysis_tab.dart`: 246
- `app/lib/features/decks/widgets/deck_card.dart`: 229
- `app/lib/features/decks/screens/deck_details_screen.dart`: 953, 1038, 1714, 3212
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 515
- `app/lib/core/widgets/cached_card_image.dart`: 116, 135, 156

### `scaffoldGradient` (1 refs)
- `app/lib/core/widgets/main_scaffold.dart`: 96

### `scoreColor` (1 refs)
- `app/lib/features/decks/widgets/deck_card.dart`: 205

### `success` (28 refs)
- `app/lib/features/home/home_screen.dart`: 720, 728
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 67
- `app/lib/features/community/screens/community_screen.dart`: 1199
- `app/lib/features/market/screens/market_screen.dart`: 325
- `app/lib/features/trades/providers/trade_provider.dart`: 299, 301
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 495, 543, 560, 610
- `app/lib/features/decks/widgets/deck_progress_indicator.dart`: 57, 141, 220
- `app/lib/features/decks/screens/deck_details_screen.dart`: 294, 321, 326, 340, 350, 1297, 1345, 1374, 2574, 3012
- `app/lib/features/decks/screens/deck_generate_screen.dart`: 141, 353
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 321, 329

### `surfaceSlate` (68 refs)
- `app/lib/features/home/life_counter_screen.dart`: 176, 199
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 190
- `app/lib/features/profile/profile_screen.dart`: 283
- `app/lib/features/messages/screens/chat_screen.dart`: 254
- `app/lib/features/social/screens/user_search_screen.dart`: 67, 181
- `app/lib/features/social/screens/user_profile_screen.dart`: 230, 424, 621, 839, 1119
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 149
- `app/lib/features/community/screens/community_screen.dart`: 178, 313, 512, 640, 800, 905, 1192, 1206
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 192, 239, 247
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 52, 230
- `app/lib/features/binder/screens/binder_screen.dart`: 640, 665, 689, 735, 745, 781
- `app/lib/features/binder/screens/marketplace_screen.dart`: 102, 137, 160, 311, 321, 360
- `app/lib/features/cards/screens/card_detail_screen.dart`: 93
- `app/lib/features/market/screens/market_screen.dart`: 189, 332
- `app/lib/features/trades/screens/create_trade_screen.dart`: 215, 387, 470, 508, 549, 672, 714
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 283
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 190, 226, 338, 383, 635, 651, 690, 768
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 104
- `app/lib/features/decks/widgets/deck_analysis_tab.dart`: 210
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 120, 209, 261, 524, 526, 528
- `app/lib/core/widgets/cached_card_image.dart`: 115, 134, 155

### `surfaceSlate2` (45 refs)
- `app/lib/features/home/life_counter_screen.dart`: 231, 396, 830
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 86
- `app/lib/features/messages/screens/chat_screen.dart`: 83, 172
- `app/lib/features/social/screens/user_search_screen.dart`: 41, 48
- `app/lib/features/social/screens/user_profile_screen.dart`: 101, 142, 288
- `app/lib/features/auth/screens/register_screen.dart`: 78
- `app/lib/features/auth/screens/login_screen.dart`: 74
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 86, 342
- `app/lib/features/community/screens/community_screen.dart`: 61, 158, 494, 1113, 1147, 1223, 1247, 1248, 1250
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 151
- `app/lib/features/collection/screens/collection_screen.dart`: 46
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 398, 493, 531, 611
- `app/lib/features/binder/screens/binder_screen.dart`: 53, 489
- `app/lib/features/cards/screens/card_detail_screen.dart`: 28, 300, 346
- `app/lib/features/market/screens/market_screen.dart`: 145, 351, 377, 385, 394
- `app/lib/features/trades/screens/create_trade_screen.dart`: 316
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 67
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 702
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 165
- `app/lib/core/widgets/main_scaffold.dart`: 35

### `textHint` (14 refs)
- `app/lib/features/home/life_counter_screen.dart`: 239, 746, 858, 931, 1037
- `app/lib/features/cards/screens/card_detail_screen.dart`: 317
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 462, 700, 846
- `app/lib/features/decks/widgets/deck_card.dart`: 123
- `app/lib/features/decks/screens/deck_details_screen.dart`: 372, 377, 1466, 3211

### `textPrimary` (84 refs)
- `app/lib/features/home/home_screen.dart`: 699
- `app/lib/features/home/life_counter_screen.dart`: 238, 849, 970
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 218
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 32, 34, 151, 162
- `app/lib/features/messages/screens/chat_screen.dart`: 84, 113, 182, 269
- `app/lib/features/social/screens/user_search_screen.dart`: 52, 221
- `app/lib/features/social/screens/user_profile_screen.dart`: 169, 232, 247, 270, 292, 370, 459, 647, 867, 1145
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 162, 366
- `app/lib/features/community/screens/community_screen.dart`: 65, 163, 308, 497, 668, 826, 942, 1261, 1283
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 199, 257
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 232, 300, 425, 460, 583, 673, 700
- `app/lib/features/binder/screens/binder_screen.dart`: 401, 626, 749, 809
- `app/lib/features/binder/screens/marketplace_screen.dart`: 86, 224, 325, 387
- `app/lib/features/cards/screens/card_detail_screen.dart`: 32, 37, 160, 310, 380, 440
- `app/lib/features/market/screens/market_screen.dart`: 49, 413, 458
- `app/lib/features/trades/screens/create_trade_screen.dart`: 243, 265, 381, 444, 571, 665
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 318
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 206, 239, 264, 356, 396, 636, 642, 697, 781, 828
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 119, 232
- `app/lib/features/notifications/screens/notification_screen.dart`: 32, 34, 172

### `textSecondary` (263 refs)
- `app/lib/features/home/home_screen.dart`: 256, 555, 620, 711
- `app/lib/features/home/life_counter_screen.dart`: 245, 250, 594, 980, 997, 1011, 1027
- `app/lib/features/home/onboarding_core_flow_screen.dart`: 152, 228
- `app/lib/features/profile/profile_screen.dart`: 100, 220, 245, 265
- `app/lib/features/messages/screens/message_inbox_screen.dart`: 53, 58, 68, 162, 175
- `app/lib/features/messages/screens/chat_screen.dart`: 140, 187, 277
- `app/lib/features/social/screens/user_search_screen.dart`: 55, 60, 94, 106, 112, 128, 134, 230, 243, 255, 265
- `app/lib/features/social/screens/user_profile_screen.dart`: 118, 122, 180, 293, 378, 406, 410, 490, 516, 593, 598, 654, 659, 722, 953, 999, 1056, 1064
- `app/lib/features/auth/screens/register_screen.dart`: 109
- `app/lib/features/auth/screens/login_screen.dart`: 131
- `app/lib/features/community/screens/community_deck_detail_screen.dart`: 120, 123, 191, 221, 233, 374, 382
- `app/lib/features/community/screens/community_screen.dart`: 66, 166, 171, 219, 223, 243, 248, 255, 390, 395, 405, 500, 505, 538, 553, 558, 569, 587, 592, 681 ... (+29)
- `app/lib/features/collection/screens/latest_set_collection_screen.dart`: 174, 207, 241, 249, 265
- `app/lib/features/collection/screens/collection_screen.dart`: 58
- `app/lib/features/binder/widgets/binder_item_editor.dart`: 235, 363, 368, 437, 461, 481, 509, 515, 547, 553, 570, 600, 615, 632, 644, 657, 677, 680, 704
- `app/lib/features/binder/screens/binder_screen.dart`: 62, 370, 373, 393, 411, 563, 629, 631, 633, 669, 681, 693, 705, 744, 747, 754, 833, 868
- `app/lib/features/binder/screens/marketplace_screen.dart`: 90, 92, 95, 141, 164, 198, 201, 219, 231, 320, 323, 330, 475, 481, 500, 506
- `app/lib/features/cards/screens/card_search_screen.dart`: 272, 357
- `app/lib/features/cards/screens/card_detail_screen.dart`: 106, 111, 176, 427, 432, 462, 467
- `app/lib/features/market/screens/market_screen.dart`: 65, 72, 81, 148, 152, 161, 214, 228, 233, 254, 271, 277, 290, 294, 358, 381, 389, 398, 427, 528 ... (+1)
- `app/lib/features/trades/providers/trade_provider.dart`: 309
- `app/lib/features/trades/screens/create_trade_screen.dart`: 234, 385, 479, 483, 515, 619, 640, 651, 668, 726
- `app/lib/features/trades/screens/trade_inbox_screen.dart`: 72, 153, 227, 245, 325, 383, 417, 421
- `app/lib/features/trades/screens/trade_detail_screen.dart`: 68, 152, 162, 178, 211, 271, 323, 351, 391, 455, 776, 838, 860
- `app/lib/features/decks/widgets/sample_hand_widget.dart`: 128, 154, 315
- `app/lib/features/decks/widgets/deck_card.dart`: 135, 254
- `app/lib/features/decks/screens/deck_list_screen.dart`: 267
- `app/lib/features/decks/screens/deck_details_screen.dart`: 389, 397, 515, 1452, 2664
- `app/lib/features/decks/screens/deck_generate_screen.dart`: 200, 253
- `app/lib/features/notifications/screens/notification_screen.dart`: 70, 75, 185, 194, 247
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 127, 168, 237, 271, 276, 285, 377, 434, 549, 644
- `app/lib/core/widgets/main_scaffold.dart`: 59, 81

### `warning` (16 refs)
- `app/lib/features/decks/screens/deck_import_screen.dart`: 156, 234, 240
- `app/lib/features/decks/screens/deck_details_screen.dart`: 2206, 2211, 2233, 2254, 2330, 2333, 2343, 2355, 2365, 2437, 2580
- `app/lib/features/scanner/widgets/scanned_card_preview.dart`: 335, 430

### `wubrg` (2 refs)
- `app/lib/features/decks/widgets/deck_analysis_tab.dart`: 312, 340

## 8) Resumo objetivo

- **Fonte única de tema:** `app/lib/core/theme/app_theme.dart`.
- **Tema ativo:** `AppTheme.darkTheme` em `app/lib/main.dart`.
- **Gradientes sem uso direto:** `heroGradient` e `goldAccentGradient`.
- **Tokens mais usados:** `textSecondary`, `manaViolet`, `mythicGold`, `radiusMd`, `fontSm`.
- **Cards:** cores por formato, condição, mana/identidade e raridade estão mapeadas e referenciadas nas telas de deck, scanner, card detail, binder e trades.
