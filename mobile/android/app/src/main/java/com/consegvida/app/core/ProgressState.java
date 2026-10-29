package com.consegvida.app.core;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Immutable, platform-independent progress. No identity or journal data. */
public final class ProgressState {
    public static final int VERSION = 1;
    public static final int MAX_RECORDS = 10_000;
    public static final Set<String> MISSION_IDS = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "fisico-entorno", "mental-foco", "espiritual-presenca")));
    public static final class Completion {
        public final String missionId;
        public final String completedOn;
        public Completion(String missionId, String completedOn) {
            requireMission(missionId);
            parseDay(completedOn);
            this.missionId = missionId;
            this.completedOn = completedOn;
        }
    }
    private final String activeMission;
    private final List<Completion> completions;
    public ProgressState(String activeMission, List<Completion> completions) {
        if (activeMission != null) requireMission(activeMission);
        if (completions == null || completions.size() > MAX_RECORDS) throw new IllegalArgumentException("Histórico excede o limite local.");
        Set<String> keys = new HashSet<>();
        for (Completion item : completions) {
            if (item == null) throw new IllegalArgumentException("Registro inválido.");
            requireMission(item.missionId);
            parseDay(item.completedOn);
            if (!keys.add(item.missionId + ":" + item.completedOn)) throw new IllegalArgumentException("Registro duplicado.");
        }
        this.activeMission = activeMission;
        this.completions = Collections.unmodifiableList(new ArrayList<>(completions));
    }
    public static ProgressState empty() { return new ProgressState(null, Collections.emptyList()); }
    public String activeMission() { return activeMission; }
    public List<Completion> completions() { return completions; }
    public ProgressState start(String missionId) {
        requireMission(missionId);
        return new ProgressState(missionId, completions);
    }
    public boolean completedOn(String missionId, String day) {
        requireMission(missionId);
        parseDay(day);
        for (Completion item : completions) if (item.missionId.equals(missionId) && item.completedOn.equals(day)) return true;
        return false;
    }
    public ProgressState complete(String missionId, String day, String today) {
        requireMission(missionId);
        if (parseDay(day).isAfter(parseDay(today))) throw new IllegalArgumentException("Não é possível registrar uma data futura.");
        if (completedOn(missionId, day)) return this;
        if (!missionId.equals(activeMission)) throw new IllegalArgumentException("Inicie esta missão antes de concluí-la.");
        List<Completion> next = new ArrayList<>(completions);
        next.add(new Completion(missionId, day));
        return new ProgressState(null, next);
    }
    public static void requireMission(String id) {
        if (!MISSION_IDS.contains(id)) throw new IllegalArgumentException("Missão desconhecida.");
    }
    public static LocalDate parseDay(String value) {
        if (value == null || !value.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}") || value.startsWith("0000")) throw new IllegalArgumentException("Data local inválida.");
        try { return LocalDate.parse(value); }
        catch (DateTimeParseException failure) { throw new IllegalArgumentException("Data local inválida.", failure); }
    }
}
