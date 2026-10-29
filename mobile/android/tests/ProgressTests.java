package com.consegvida.app.core;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;

/** Dependency-free contract tests; exercise public domain and actual disk I/O. */
public final class ProgressTests {
    private static int checks;
    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }
    private interface Throwing { void run() throws Exception; }
    private static void rejected(Throwing work, String label) throws Exception {
        try { work.run(); } catch (IllegalArgumentException | IOException expected) { checks++; return; }
        throw new AssertionError("Expected rejection: " + label);
    }
    public static void main(String[] args) throws Exception {
        String today = "2026-10-29";
        ProgressState empty = ProgressState.empty();
        check(empty.activeMission() == null && empty.completions().isEmpty(), "fresh state");
        ProgressState started = empty.start("mental-foco");
        check("mental-foco".equals(started.activeMission()), "start mission");
        check(empty.activeMission() == null, "immutable transition");
        ProgressState done = started.complete("mental-foco", today, today);
        check(done.completions().size() == 1 && done.activeMission() == null, "complete active");
        check(done.complete("mental-foco", today, today).completions().size() == 1, "same day idempotent");
        check(done.start("mental-foco").complete("mental-foco", "2026-10-30", "2026-10-30").completions().size() == 2, "new local day");
        rejected(() -> empty.complete("mental-foco", today, today), "must start first");
        rejected(() -> started.complete("fisico-entorno", today, today), "wrong active mission");
        rejected(() -> started.complete("mental-foco", "2026-10-30", today), "future completion");
        rejected(() -> empty.start("unknown"), "unknown mission");
        for (String date : new String[]{"2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01", "0000-01-01", "2026-1-01", "2026-01-01Z", "2026-01-01T00:00:00Z", "+2026-01-01"}) {
            rejected(() -> ProgressState.parseDay(date), "invalid date " + date);
        }
        check(ProgressState.parseDay("2024-02-29").equals(LocalDate.of(2024, 2, 29)), "leap year");
        String json = StateCodec.encode(done);
        check(StateCodec.decode(json).completions().size() == 1, "round trip");
        check("mental-foco".equals(StateCodec.decode(StateCodec.encode(started)).activeMission()), "active persists");
        rejected(() -> StateCodec.decode(json.replace("\"version\":1", "\"version\":2")), "unknown version");
        rejected(() -> StateCodec.decode(json.replace("2026-10-29", "2026-02-30")), "invalid stored date");
        rejected(() -> StateCodec.decode(json.replace("mental-foco", "invented")), "invalid stored mission");
        rejected(() -> StateCodec.decode(json.replace("\"version\":1", "\"version\":1,\"version\":1")), "duplicate JSON field");
        rejected(() -> StateCodec.decode(json.replace("\"version\":1", "\"version\":1,\"extra\":null")), "unknown field");
        rejected(() -> StateCodec.decode(json + "garbage"), "trailing input");
        rejected(() -> StateCodec.decode(json.replace("\"version\":1", "\"version\":01")), "non-JSON leading zero");
        rejected(() -> StateCodec.decode(json.replace("\"version\":1", "\"version\":1.0")), "integer version required");
        rejected(() -> StateCodec.decode("{\"version\":1,\"activeMission\":null}"), "missing history");
        rejected(() -> StateCodec.decode("{\"\\u+076ersion\":1,\"activeMission\":null,\"completions\":[]}"), "signed unicode escape rejected");
        rejected(() -> StateCodec.decode("{\"version\":1,\"activeMission\":\"\\u-001\",\"completions\":[]}"), "negative unicode escape rejected");
        rejected(() -> StateCodec.decode("{\"\\u００７６ersion\":1,\"activeMission\":null,\"completions\":[]}"), "non ASCII hexadecimal escape rejected");
        rejected(() -> StateCodec.decode("{\"version\":1,\"activeMission\":null,\"completions\":[{\"missionId\":\"mental-foco\",\"completedOn\":\"2026-10-29\"},{\"missionId\":\"mental-foco\",\"completedOn\":\"2026-10-29\"}]}"), "duplicate completion");
        ArrayList<ProgressState.Completion> largeHistory = new ArrayList<>();
        for (int i = 0; i < ProgressState.MAX_RECORDS; i++) largeHistory.add(new ProgressState.Completion("mental-foco", LocalDate.of(1990, 1, 1).plusDays(i).toString()));
        check(StateCodec.decode(StateCodec.encode(new ProgressState(null, largeHistory))).completions().size() == ProgressState.MAX_RECORDS, "bounded history maximum round trip");
        largeHistory.add(new ProgressState.Completion("mental-foco", LocalDate.of(1990, 1, 1).plusDays(ProgressState.MAX_RECORDS).toString()));
        rejected(() -> new ProgressState(null, largeHistory), "record count limit");
        Path folder = Files.createTempDirectory("consegvida-contract-");
        Path file = folder.resolve("progress.json");
        try {
            StateStore store = new StateStore(file);
            check(store.load().completions().isEmpty(), "missing file starts fresh");
            store.save(started);
            check("mental-foco".equals(new StateStore(file).load().activeMission()), "actual process-independent reload");
            store.save(done);
            check(new StateStore(file).load().completions().size() == 1, "actual completed reload");
            StateStore failedMove = new StateStore(file, (from, to) -> { throw new IOException("injected atomic rename failure"); });
            rejected(() -> failedMove.save(empty), "write failure surfaced");
            check(store.load().completions().size() == 1, "failed write retains prior valid state");
            try (var files = Files.list(folder)) { check(files.count() == 1, "temporary file cleaned"); }
            Files.writeString(file, "{broken", StandardCharsets.UTF_8);
            rejected(() -> store.load(), "corruption visible");
            check(Files.readString(file).equals("{broken"), "corruption never erased on read");
            Files.writeString(file, "{\"version\":99,\"activeMission\":null,\"completions\":[]}");
            rejected(() -> store.load(), "unknown version visible");
            check(Files.readString(file).contains("99"), "unknown version never erased");
            Files.write(file, new byte[StateStore.MAX_BYTES + 1]);
            rejected(() -> store.load(), "oversized file bounded");
            Files.write(file, new byte[]{(byte)0xc0, (byte)0xaf});
            rejected(() -> store.load(), "malformed UTF-8 rejected");
            check(Files.size(file) == 2, "malformed encoding preserved");
            Path orphan = folder.resolve(".progress-123456789.tmp");
            Path unrelated = folder.resolve("keep-this.tmp");
            Path similar = folder.resolve(".progress-manual.tmp");
            Files.writeString(orphan, json);
            Files.writeString(unrelated, "preserve unrelated file");
            Files.writeString(similar, "not a generated temporary");
            store.reset(); // UI requires confirmation before this explicit operation.
            check(store.load().activeMission() == null && store.load().completions().isEmpty(), "explicit reset persisted");
            check(!Files.exists(orphan), "reset removes own orphaned temporary");
            check(Files.readString(unrelated).equals("preserve unrelated file"), "reset preserves unrelated files");
            check(Files.readString(similar).equals("not a generated temporary"), "reset restricts temporary name pattern");
            Files.delete(unrelated);
            Files.delete(similar);
            store.save(done);
            Files.createDirectory(orphan);
            Files.writeString(orphan.resolve("keep"), "do not recursively remove");
            rejected(() -> store.reset(), "orphan cleanup failure surfaced");
            check(store.load().completions().size() == 1, "cleanup failure retains primary progress");
            check(Files.readString(orphan.resolve("keep")).equals("do not recursively remove"), "reset never recursively removes paths");
            Files.delete(orphan.resolve("keep"));
            Files.delete(orphan);
            Path parentFile = folder.resolve("not-a-directory");
            Files.writeString(parentFile, "preserve me");
            rejected(() -> new StateStore(parentFile.resolve("progress.json")).save(done), "real invalid filesystem destination");
            check(Files.readString(parentFile).equals("preserve me"), "filesystem failure preserves unrelated data");
            Files.delete(parentFile);
        } finally {
            Files.deleteIfExists(file);
            Files.deleteIfExists(folder);
        }
        System.out.println("PASS: " + checks + " Android domain/persistence checks");
    }
}
