# Combat server changes / 战斗服务端改动

Base: AstaPS 0fac870873a35e88b9f969aa1b242a832b602005. Selected from local patch workspaces whose corresponding top-level class file matches the installed server JAR byte for byte. This identifies build artifacts; it is not a source rebuild or damage-parity test. Incomplete where matching build artifacts are missing.

以下源码差异按已安装服务端的同名主 class 匹配筛选；不是完整重编译或全角色实战验证。

- src/main/java/emu/grasscutter/command/commands/DPSCommand.java
- src/main/java/emu/grasscutter/data/ResourceLoader.java
- src/main/java/emu/grasscutter/data/excels/ItemData.java
- src/main/java/emu/grasscutter/game/ability/Ability.java
- src/main/java/emu/grasscutter/game/ability/AbilityManager.java
- src/main/java/emu/grasscutter/game/ability/AbilityMaxHpRatioHelper.java
- src/main/java/emu/grasscutter/game/ability/MavuikaSpiritHelper.java
- src/main/java/emu/grasscutter/game/ability/PhlogistonStateHelper.java
- src/main/java/emu/grasscutter/game/ability/PredicateEvaluator.java
- src/main/java/emu/grasscutter/game/ability/SkillLevelResolver.java
- src/main/java/emu/grasscutter/game/ability/SkillParticlePacketCompat.java
- src/main/java/emu/grasscutter/game/ability/WaterResonanceHelper.java
- src/main/java/emu/grasscutter/game/ability/actions/AbilityActionHandler.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionAddGlobalValue.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionAddHPDebts.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionAttachModifier.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionClearGlobalValue.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionCopyGlobalValue.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionGenerateElemBall.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionGetFightProperty.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionNyxSet.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionSetGlobalValue.java
- src/main/java/emu/grasscutter/game/ability/actions/ActionSetRandomOverrideMapValue.java
- src/main/java/emu/grasscutter/game/avatar/Avatar.java
- src/main/java/emu/grasscutter/game/avatar/QuestProudSkillSyncHelper.java
- src/main/java/emu/grasscutter/game/dps/DPSMeter.java
- src/main/java/emu/grasscutter/game/entity/EntityAvatar.java
- src/main/java/emu/grasscutter/game/inventory/Inventory.java
- src/main/java/emu/grasscutter/game/managers/energy/EnergyManager.java
- src/main/java/emu/grasscutter/game/player/Player.java
- src/main/java/emu/grasscutter/game/player/TeamManager.java
- src/main/java/emu/grasscutter/server/packet/send/PacketAvatarSkillDepotChangeNotify.java
- src/main/java/emu/grasscutter/server/packet/send/PacketPlayerEnterSceneInfoNotify.java
