# MitoV3 Architecture Refactor (branch: refactor/architecture)

Agreed with Codex adversarial review (2 rounds). Conservative, behavior-preserving, FLAT file
decomposition. No MVVM/engine extraction, no folder reorg, no backend method-extensions tonight.
Move self-contained leaf types into new flat files; origin files shrink; names/state/logic unchanged.
Build (iPhone 17 Pro sim, /tmp/mito-dd) + smoke + commit after EVERY split. `private` top-level types
that move become `internal`; move dependent private helpers with their struct.

## Steps (check off as committed)
- [x] 1. BackendModels.swift — DTO structs from MitoBackend.swift (keep class + methods + MitoBackendError)
- [x] BattleAbilityEffects.swift — *Effect structs, PixelSpark, LightningBolt, BattleAbilityEffectView, SpriteSheetAbilityEffect
- [x] BattleFlashcardPanels.swift — BattleFlashcardPanel, BattlePanelTag, BattleGradeButton, MultipleChoicePanel, TypeInPanel, AnswerModePicker, BattleStatusChip
- [x] BattleCapturePopup.swift — CapturePopup
- [x] BattleSetupViews.swift — CampaignStageSetup, EndlessReviewSetup, TagFilterSection, EndlessDeckRow
- [x] BattleCombatView.swift — BattleCombatView (+ DamageNumberView, FloatingDamage, AbilityActionButton)
- [x]  ContentView splits — Tutorial.swift, Onboarding.swift, AppChrome.swift, Social.swift
- [x]  FlashcardsView splits — FlashcardEditor.swift, CardImport.swift
- [x]  CollectionView — CharacterInfoModal.swift
- [x]  StudyView — FocusSession.swift

## RESULT (all steps done, clean build green, all screens smoke-tested)
Every step behavior-preserving, committed individually, built green, verified in the iPhone 17 Pro sim
(home/onboarding, battle combat + flashcard, team, cards/decks, shop, tutorial all render correctly).

Biggest-file reductions:
- BattleView.swift   3236 -> 976   (+ BattleCombatView 1147, BattleSetupViews 472, BattleAbilityEffects 311, BattleFlashcardPanels 283, BattleCapturePopup 70)
- ContentView.swift  2219 -> 460   (+ Social 839, Onboarding 283, Tutorial 252, AppChrome 168, SettingsSheet 166; dead TutorialOverlay/TutorialStep removed)
- FlashcardsView.swift 1494 -> 722 (+ CardImport 468, FlashcardEditor 319)
- MitoBackend.swift  1345 -> 880   (+ BackendModels 470)
- StudyView.swift     756 -> 449   (+ FocusSession 313)
- CollectionView.swift 731 -> 491  (+ CharacterInfoModal 246)

No single file now exceeds ~1150 lines (was 3236). New files added to the target via the xcodeproj gem.
Pre-existing warning only: Social.swift LobbyService `subscribe()` Supabase deprecation (not introduced here).
