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
- [ ] 7. ContentView splits — Tutorial.swift, Onboarding.swift, AppChrome.swift, Social.swift
- [ ] 8. FlashcardsView splits — FlashcardEditor.swift, CardImport.swift
- [ ] 9. CollectionView — CharacterInfoModal.swift
- [ ] 10. StudyView — FocusSession.swift
