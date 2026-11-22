package localtools;

import arena.install.ArenaAccount;
import com.google.gson.*;
import emu.grasscutter.command.*;
import emu.grasscutter.game.avatar.Avatar;
import emu.grasscutter.game.inventory.GameItem;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.game.inventory.ItemType;
import emu.grasscutter.game.world.Position;
import emu.grasscutter.plugin.Plugin;
import emu.grasscutter.server.packet.send.*;
import java.nio.file.*;
import java.util.*;

/** In-place edits for the single local test account. No new ports, dependencies or DB shortcuts. */
public final class LocalTestPlugin extends Plugin {
    private static final Path ROOT = ArenaAccount.pluginRoot(LocalTestPlugin.class);
    private static final Gson JSON = new GsonBuilder().setPrettyPrinting().create();
    private static LocalTestPlugin instance;
    private final Map<Integer, Entry> catalog = new HashMap<>();
    private record Entry(String kind, int stars) {}
    private record Change(Avatar avatar, GameItem weapon, int before, int after) {}

    @Override public void onEnable() {
        try {
            if (!Path.of("").toAbsolutePath().normalize().equals(ROOT.resolve("server")))
                throw new IllegalStateException("Expected local server working directory");
            refreshCatalog();
            Files.createDirectories(ROOT.resolve("run/edit-results"));
            Files.createDirectories(ROOT.resolve("backups/edits"));
            instance = this;
            CommandMap.getInstance().registerCommand("localconst", new ConstCommand());
            CommandMap.getInstance().registerCommand("localrefine", new RefineCommand());
            CommandMap.getInstance().registerCommand("localundo", new UndoCommand());
            JsonObject ready = new JsonObject();
            ready.addProperty("pid", ProcessHandle.current().pid()); ready.addProperty("version", "1.0.0");
            ready.addProperty("started", ProcessHandle.current().info().startInstant().orElseThrow().toString());
            ready.addProperty("jarHash", sha256(ROOT.resolve("server/plugins/LocalTestTools.jar")));
            atomic(ROOT.resolve("run/local-test-tools-ready.json"), ready);
            getLogger().info("LocalTestTools ready: in-place constellations/refinement, bound local test account only");
        } catch (Exception ex) { throw new IllegalStateException("LocalTestTools initialization failed", ex); }
    }
    @Override public void onDisable() {
        for (String s : List.of("localconst", "localrefine", "localundo")) CommandMap.getInstance().unregisterCommand(s);
        try { Files.deleteIfExists(ROOT.resolve("run/local-test-tools-ready.json")); } catch (Exception ignored) {}
    }
    private void refreshCatalog() throws Exception {
        Map<Integer, Entry> updated = new HashMap<>();
        for (JsonElement e : JsonParser.parseString(Files.readString(ROOT.resolve("catalog/items.json"))).getAsJsonArray()) {
            JsonObject o = e.getAsJsonObject(); if (!o.get("named").getAsBoolean()) continue;
            updated.put(o.get("id").getAsInt(), new Entry(o.get("kind").getAsString().equals("角色") ? "avatar" : "weapon", o.get("stars").getAsInt()));
        }
        catalog.clear(); catalog.putAll(updated);
    }
    static String sha256(Path p) throws Exception {
        return HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(p)));
    }
    static void atomic(Path path, JsonObject value) throws Exception {
        Path temporary = path.resolveSibling(path.getFileName() + ".tmp");
        Files.writeString(temporary, JSON.toJson(value));
        Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
    }
    private boolean selected(String kind, String selector, int id) {
        Entry e = catalog.get(id);
        return e != null && e.kind.equals(kind) && EditRules.matches(selector, id, e.stars);
    }
    private List<Change> plan(Player player, String kind, String selector, int level, int[] counts) {
        List<Change> changes = new ArrayList<>();
        if (kind.equals("avatar")) {
            for (Avatar a : player.getAvatars()) if (selected(kind, selector, a.getAvatarId())) {
                if (a.getSkillDepot() == null || a.getSkillDepot().getTalents() == null || a.getSkillDepot().getTalents().size() < level) { counts[1]++; continue; }
                counts[0]++;
                int old = a.getCoreProudSkillLevel();
                if (old == level) { counts[2]++; continue; }
                changes.add(new Change(a, null, old, level));
            }
        } else {
            for (GameItem w : player.getInventory()) if (w.getItemType() == ItemType.ITEM_WEAPON && selected(kind, selector, w.getItemId())) {
                if (!EditRules.refinable(w.getItemData().getSkillAffix())) { counts[1]++; continue; }
                counts[0]++;
                int old = w.getRefinement() + 1;
                if (old == level) { counts[2]++; continue; }
                changes.add(new Change(null, w, old, level));
            }
        }
        return changes;
    }
    private JsonObject backup(String nonce, String kind, String selector, List<Change> changes) {
        JsonObject b = new JsonObject(); b.addProperty("uid", ArenaAccount.uid(ROOT)); b.addProperty("request", nonce);
        b.addProperty("created", java.time.Instant.now().toString()); b.addProperty("kind", kind); b.addProperty("selector", selector);
        JsonArray rows = new JsonArray();
        for (Change c : changes) {
            JsonObject row = new JsonObject(); row.addProperty("before", c.before); row.addProperty("after", c.after);
            if (c.avatar != null) {
                row.addProperty("kind", "avatar"); row.addProperty("id", c.avatar.getAvatarId());
                row.addProperty("skillDepotId", c.avatar.getSkillDepotId()); row.addProperty("level", c.avatar.getLevel());
                row.addProperty("promoteLevel", c.avatar.getPromoteLevel());
                row.add("activeTalentIds", JSON.toJsonTree(c.avatar.getSkillDepot().getTalents()));
                row.add("baseSkillLevels", JSON.toJsonTree(c.avatar.getSkillLevelMap()));
            } else {
                row.addProperty("kind", "weapon"); row.addProperty("id", c.weapon.getItemId());
                row.addProperty("objectId", c.weapon.getObjectId().toHexString()); row.addProperty("level", c.weapon.getLevel());
                row.addProperty("equippedBy", c.weapon.getEquipCharacter()); row.addProperty("locked", c.weapon.isLocked());
                row.addProperty("promoteLevel", c.weapon.getPromoteLevel());
            }
            rows.add(row);
        }
        b.add("changes", rows); return b;
    }
    private List<Change> restorePlan(Player p, String backupToken) throws Exception {
        JsonObject saved = JsonParser.parseString(Files.readString(ROOT.resolve("backups/edits/" + EditRules.token(backupToken) + ".json"))).getAsJsonObject();
        if (saved.get("uid").getAsInt() != ArenaAccount.uid(ROOT)) throw new IllegalArgumentException("Wrong backup account");
        List<Change> changes = new ArrayList<>();
        for (JsonElement element : saved.getAsJsonArray("changes")) {
            JsonObject row = element.getAsJsonObject(); int before = row.get("before").getAsInt(), after = row.get("after").getAsInt();
            if (row.get("kind").getAsString().equals("avatar")) {
                EditRules.validateLevel("avatar", before);
                Avatar a = p.getAvatars().getAvatarById(row.get("id").getAsInt());
                if (a == null || a.getSkillDepotId() != row.get("skillDepotId").getAsInt() || a.getCoreProudSkillLevel() != after)
                    throw new IllegalStateException("Character changed since this backup; restore aborted before editing");
                changes.add(new Change(a, null, after, before));
            } else {
                EditRules.validateLevel("weapon", before);
                String objectId = row.get("objectId").getAsString(); GameItem w = null;
                for (GameItem owned : p.getInventory()) if (owned.getObjectId() != null && owned.getObjectId().toHexString().equals(objectId)) w = owned;
                if (w == null || w.getRefinement() + 1 != after || w.getItemId() != row.get("id").getAsInt())
                    throw new IllegalStateException("Weapon changed since this backup; restore aborted before editing");
                changes.add(new Change(null, w, after, before));
            }
        }
        return changes;
    }
    private void apply(Player p, List<Change> changes, boolean reverse) {
        boolean lowered = false; Set<Avatar> equipped = new HashSet<>(); List<GameItem> weapons = new ArrayList<>();
        for (Change c : changes) {
            int value = reverse ? c.before : c.after;
            if (c.avatar != null) {
                lowered |= value < c.avatar.getCoreProudSkillLevel();
                c.avatar.forceConstellationLevel(value); c.avatar.recalcConstellations(); c.avatar.recalcStats(true); c.avatar.save();
                p.sendPacket(new PacketAvatarPropNotify(c.avatar));
            } else {
                c.weapon.setRefinement(value - 1); c.weapon.save(); weapons.add(c.weapon);
                Avatar wearer = p.getAvatars().getAvatarById(c.weapon.getEquipCharacter()); if (wearer != null) equipped.add(wearer);
            }
        }
        // Small notification batches to avoid oversized inventory packets.
        for (int i = 0; i < weapons.size(); i += 25) p.sendPacket(new PacketStoreItemChangeNotify(weapons.subList(i, Math.min(i + 25, weapons.size()))));
        for (Avatar a : equipped) a.recalcStats(true);
        if (lowered && p.getWorld() != null && p.getScene() != null) {
            int scene = p.getScene().getId(); Position pos = new Position(p.getPosition());
            p.getWorld().transferPlayerToScene(p, 1, pos); p.getWorld().transferPlayerToScene(p, scene, pos);
            p.getScene().broadcastPacket(new PacketSceneEntityAppearNotify(p));
        }
    }
    private synchronized void execute(String kind, Player sender, Player p, List<String> args) {
        String nonce = args.size() >= 3 ? args.get(2) : UUID.randomUUID().toString().replace("-", "");
        JsonObject result = new JsonObject();
        try {
            EditRules.token(nonce); result.addProperty("request", nonce); result.addProperty("uid", ArenaAccount.uid(ROOT));
            if (p == null || p.getUid() != ArenaAccount.uid(ROOT) || (sender != null && sender.getUid() != ArenaAccount.uid(ROOT))) throw new IllegalArgumentException("This plugin only targets the bound local test account");
            if (p.getScene() == null || !p.getAvatars().isLoaded() || !p.getInventory().isLoaded()) throw new IllegalStateException("Enter the game world first");
            refreshCatalog(); int[] counts = new int[3]; List<Change> changes; String selector;
            if (kind.equals("restore")) {
                if (args.isEmpty()) throw new IllegalArgumentException("Usage: localundo @<local-uid> <backup-token> [request-token]");
                selector = EditRules.token(args.get(0)); changes = restorePlan(p, selector); counts[0] = changes.size();
            } else {
                if (args.size() < 2) throw new IllegalArgumentException("Usage: localconst/localrefine @<local-uid> <all|stars4|stars5|ID[,ID]> <level>");
                selector = EditRules.validateSelector(args.get(0)); int level = Integer.parseInt(args.get(1)); EditRules.validateLevel(kind, level);
                changes = plan(p, kind, selector, level, counts);
            }
            result.addProperty("kind", kind); result.addProperty("selector", selector);
            result.addProperty("matched", counts[0]); result.addProperty("skipped", counts[1]); result.addProperty("unchanged", counts[2]);
            if (!changes.isEmpty()) {
                atomic(ROOT.resolve("backups/edits/" + nonce + ".json"), backup(nonce, kind, selector, changes));
                result.addProperty("backup", nonce);
                try { apply(p, changes, false); }
                catch (Exception error) {
                    try { apply(p, changes, true); result.addProperty("rolledBack", true); }
                    catch (Exception restoreError) { result.addProperty("rollbackError", restoreError.toString()); }
                    throw error;
                }
            }
            result.addProperty("changed", changes.size()); result.addProperty("ok", true);
            CommandHandler.sendMessage(sender, "LocalTestTools: changed=" + changes.size() + ", unchanged=" + counts[2] + ", skipped=" + counts[1] + ", backup=" + nonce);
        } catch (Exception ex) {
            result.addProperty("ok", false); result.addProperty("error", ex.toString());
            getLogger().warn("Local edit failed: {}", ex.toString()); CommandHandler.sendMessage(sender, "LocalTestTools: " + ex.getMessage());
        }
        try { EditRules.token(nonce); atomic(ROOT.resolve("run/edit-results/" + nonce + ".json"), result); }
        catch (Exception ex) { getLogger().error("Local edit response failed", ex); }
    }
    @Command(label="localconst", permission="player.setconstellation", permissionTargeted="player.setconstellation.others", usage={"<all|stars4|stars5|ID[,ID]> <0..6> [request-token]"})
    public static final class ConstCommand implements CommandHandler {
        public void execute(Player sender, Player target, List<String> args) { instance.execute("avatar", sender, target, args); }
    }
    @Command(label="localrefine", permission="player.give", permissionTargeted="player.give.others", usage={"<all|stars4|stars5|ID[,ID]> <1..5> [request-token]"})
    public static final class RefineCommand implements CommandHandler {
        public void execute(Player sender, Player target, List<String> args) { instance.execute("weapon", sender, target, args); }
    }
    @Command(label="localundo", permission="player.give", permissionTargeted="player.give.others", usage={"<backup-token> [request-token]"})
    public static final class UndoCommand implements CommandHandler {
        public void execute(Player sender, Player target, List<String> args) {
            // Normalize undo's optional request token to the normal third-argument position.
            List<String> normalized = new ArrayList<>(args); if (normalized.size() == 2) normalized.add(1, "0");
            instance.execute("restore", sender, target, normalized);
        }
    }
}
