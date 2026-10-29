package com.consegvida.app.core;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.DirectoryStream;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;

/** Durable replace: a failed write never becomes successful in-memory progress. */
public final class StateStore {
    public static final int MAX_BYTES = 1_048_576;
    interface AtomicMove { void move(Path temporary, Path destination) throws IOException; }
    private final Path file;
    private final AtomicMove mover;
    public StateStore(Path file) {
        this(file, (from, to) -> Files.move(from, to, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING));
    }
    StateStore(Path file, AtomicMove mover) {
        this.file = file.toAbsolutePath();
        this.mover = mover;
    }
    public ProgressState load() throws IOException {
        try (FileChannel source = FileChannel.open(file, StandardOpenOption.READ)) {
            if (source.size() > MAX_BYTES) throw new IOException("Arquivo de progresso maior que o limite de leitura.");
            ByteBuffer buffer = ByteBuffer.allocate(MAX_BYTES + 1);
            while (source.read(buffer) > 0) {
                if (buffer.position() > MAX_BYTES) throw new IOException("Arquivo de progresso maior que o limite de leitura.");
            }
            buffer.flip();
            String json = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(buffer).toString();
            try { return StateCodec.decode(json); }
            catch (IllegalArgumentException invalid) { throw new IOException(invalid.getMessage(), invalid); }
        } catch (NoSuchFileException missing) {
            // Missing progress is the sole case that starts fresh. Permission/corruption never does.
            if (Files.exists(file)) throw missing;
            return ProgressState.empty();
        }
    }
    public void save(ProgressState state) throws IOException {
        byte[] bytes = StateCodec.encode(state).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_BYTES) throw new IOException("O progresso atingiu o limite de armazenamento desta versão.");
        Files.createDirectories(file.getParent());
        Path temporary = Files.createTempFile(file.getParent(), ".progress-", ".tmp");
        try {
            try (FileChannel target = FileChannel.open(temporary, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING)) {
                ByteBuffer source = ByteBuffer.wrap(bytes);
                while (source.hasRemaining()) target.write(source);
                target.force(true);
            }
            mover.move(temporary, file);
        } finally {
            Files.deleteIfExists(temporary);
        }
    }
    /** Call only after explicit reset confirmation; remove crash remnants, then replace state. */
    public void reset() throws IOException {
        Path parent = file.getParent();
        if (Files.exists(parent)) {
            try (DirectoryStream<Path> candidates = Files.newDirectoryStream(parent, ".progress-*.tmp")) {
                for (Path candidate : candidates) {
                    // Files.createTempFile uses a numeric generated suffix. Never delete arbitrary
                    // similarly named files, follow symlinks, or recurse through directories.
                    if (!candidate.getFileName().toString().matches("\\.progress-[0-9]+\\.tmp")) continue;
                    if (!Files.isRegularFile(candidate, LinkOption.NOFOLLOW_LINKS)) throw new IOException("Não foi possível remover um arquivo temporário do progresso.");
                    Files.delete(candidate);
                }
            }
        }
        // Cleanup failures above leave the primary state untouched. The replacement is atomic.
        save(ProgressState.empty());
    }
}
