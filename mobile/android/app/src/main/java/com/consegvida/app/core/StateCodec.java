package com.consegvida.app.core;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Strict JSON reader for the small, versioned progress contract. */
public final class StateCodec {
    private StateCodec() { }
    public static String encode(ProgressState state) {
        StringBuilder out = new StringBuilder("{\"version\":1,\"activeMission\":");
        out.append(state.activeMission() == null ? "null" : "\"" + state.activeMission() + "\"");
        out.append(",\"completions\":[");
        boolean first = true;
        for (ProgressState.Completion item : state.completions()) {
            if (!first) out.append(',');
            first = false;
            out.append("{\"missionId\":\"").append(item.missionId).append("\",\"completedOn\":\"").append(item.completedOn).append("\"}");
        }
        return out.append("]}").toString();
    }
    public static ProgressState decode(String json) {
        if (json == null || json.getBytes(StandardCharsets.UTF_8).length > StateStore.MAX_BYTES) throw invalid();
        Parser parser = new Parser(json);
        Object value = parser.value(0);
        parser.space();
        if (parser.at != json.length()) throw invalid();
        Map<?, ?> root = object(value, "version", "activeMission", "completions");
        if (!(root.get("version") instanceof Long) || ((Long) root.get("version")) != ProgressState.VERSION) throw new IllegalArgumentException("Versão do progresso não suportada.");
        Object activeValue = root.get("activeMission");
        if (activeValue != null && !(activeValue instanceof String)) throw invalid();
        Object history = root.get("completions");
        if (!(history instanceof List)) throw invalid();
        List<?> records = (List<?>) history;
        if (records.size() > ProgressState.MAX_RECORDS) throw invalid();
        List<ProgressState.Completion> completions = new ArrayList<>();
        for (Object record : records) {
            Map<?, ?> item = object(record, "missionId", "completedOn");
            if (!(item.get("missionId") instanceof String) || !(item.get("completedOn") instanceof String)) throw invalid();
            completions.add(new ProgressState.Completion((String) item.get("missionId"), (String) item.get("completedOn")));
        }
        return new ProgressState((String) activeValue, completions);
    }
    private static Map<?, ?> object(Object value, String... expected) {
        if (!(value instanceof Map)) throw invalid();
        Map<?, ?> map = (Map<?, ?>) value;
        if (!map.keySet().equals(new HashSet<>(Arrays.asList(expected)))) throw invalid();
        return map;
    }
    private static IllegalArgumentException invalid() { return new IllegalArgumentException("Arquivo de progresso inválido. Seus dados não foram apagados."); }
    private static final class Parser {
        final String text;
        int at;
        Parser(String text) { this.text = text; }
        void space() { while (at < text.length() && " \n\r\t".indexOf(text.charAt(at)) >= 0) at++; }
        boolean take(char c) { space(); if (at < text.length() && text.charAt(at) == c) { at++; return true; } return false; }
        void expect(char c) { if (!take(c)) throw invalid(); }
        Object value(int depth) {
            if (depth > 8) throw invalid();
            space();
            if (at >= text.length()) throw invalid();
            char c = text.charAt(at);
            if (c == '"') return string();
            if (c == '{') {
                at++;
                Map<String, Object> map = new LinkedHashMap<>();
                if (take('}')) return map;
                do {
                    space();
                    String key = string();
                    expect(':');
                    if (map.containsKey(key)) throw invalid();
                    map.put(key, value(depth + 1));
                    if (map.size() > 4) throw invalid();
                } while (take(','));
                expect('}');
                return map;
            }
            if (c == '[') {
                at++;
                List<Object> list = new ArrayList<>();
                if (take(']')) return list;
                do {
                    if (list.size() >= ProgressState.MAX_RECORDS) throw invalid();
                    list.add(value(depth + 1));
                } while (take(','));
                expect(']');
                return list;
            }
            if (text.startsWith("null", at)) { at += 4; return null; }
            int start = at;
            while (at < text.length() && text.charAt(at) >= '0' && text.charAt(at) <= '9') at++;
            if (start == at || at - start > 9 || at - start > 1 && text.charAt(start) == '0') throw invalid();
            try { return Long.parseLong(text.substring(start, at)); }
            catch (NumberFormatException failure) { throw invalid(); }
        }
        String string() {
            if (at >= text.length() || text.charAt(at++) != '"') throw invalid();
            StringBuilder result = new StringBuilder();
            while (at < text.length()) {
                char c = text.charAt(at++);
                if (c == '"') return result.toString();
                if (c < 0x20) throw invalid();
                if (c == '\\') {
                    if (at >= text.length()) throw invalid();
                    char escaped = text.charAt(at++);
                    switch (escaped) {
                        case '"': case '\\': case '/': c = escaped; break;
                        case 'b': c = '\b'; break;
                        case 'f': c = '\f'; break;
                        case 'n': c = '\n'; break;
                        case 'r': c = '\r'; break;
                        case 't': c = '\t'; break;
                        case 'u':
                            if (at + 4 > text.length()) throw invalid();
                            for (int i = at; i < at + 4; i++) {
                                char hex = text.charAt(i);
                                if (!((hex >= '0' && hex <= '9') || (hex >= 'a' && hex <= 'f') || (hex >= 'A' && hex <= 'F'))) throw invalid();
                            }
                            try { c = (char) Integer.parseInt(text.substring(at, at + 4), 16); }
                            catch (NumberFormatException failure) { throw invalid(); }
                            at += 4;
                            break;
                        default: throw invalid();
                    }
                }
                result.append(c);
                if (result.length() > 128) throw invalid();
            }
            throw invalid();
        }
    }
}
