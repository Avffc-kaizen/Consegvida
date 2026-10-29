package com.consegvida.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import android.window.OnBackInvokedDispatcher;

import com.consegvida.app.core.ProgressState;
import com.consegvida.app.core.StateStore;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/** Native Android UI; app progress never leaves the application sandbox. */
public final class MainActivity extends Activity {
    private static final int NAVY = Color.rgb(18, 32, 58), CREAM = Color.rgb(243, 239, 230),
            PAPER = Color.rgb(255, 253, 248), INK = Color.rgb(28, 29, 26), MUTED = Color.rgb(92, 100, 96),
            GOLD = Color.rgb(184, 154, 91);
    private JSONObject content;
    private StateStore store;
    private ProgressState state;
    private String screen = "home", missionId, recovery;
    private boolean contentFailed;
    private int historyPage;
    private LinearLayout root, body;

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (savedInstanceState != null) {
            screen = savedInstanceState.getString("screen", "home");
            missionId = savedInstanceState.getString("mission");
        }
        try {
            try (InputStream input = getAssets().open("content.json"); ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
                byte[] chunk = new byte[4096];
                int read;
                while ((read = input.read(chunk)) != -1) {
                    if (bytes.size() + read > 131_072) throw new IllegalStateException("Conteúdo excede o limite.");
                    bytes.write(chunk, 0, read);
                }
                content = new JSONObject(bytes.toString(StandardCharsets.UTF_8.name()));
            }
            Set<String> bundled = new HashSet<>();
            JSONArray missions = content.getJSONArray("missions");
            for (int i = 0; i < missions.length(); i++) bundled.add(missions.getJSONObject(i).getString("id"));
            if (content.getInt("schemaVersion") != 1 || !bundled.equals(ProgressState.MISSION_IDS) || missions.length() != 3) throw new IllegalStateException("Conteúdo incompatível.");
            // Android excludes this directory from Auto Backup and device transfer.
            store = new StateStore(getNoBackupFilesDir().toPath().resolve("progress-v1.json"));
        } catch (Exception error) {
            contentFailed = true;
            recovery = "Não foi possível abrir o conteúdo desta versão. Seu progresso foi preservado. Atualize o aplicativo e tente novamente.";
        }
        if (Build.VERSION.SDK_INT >= 33) getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::goBack);
    }

    @Override protected void onResume() {
        super.onResume();
        if (!contentFailed) loadProgress(); // Reload after background/clock/date changes.
        render();
    }
    @Override protected void onSaveInstanceState(Bundle out) {
        out.putString("screen", screen);
        out.putString("mission", missionId);
        super.onSaveInstanceState(out);
    }
    @Override public void onBackPressed() { goBack(); }
    private void goBack() {
        if (missionId != null) { missionId = null; screen = "missions"; render(); }
        else if (!"home".equals(screen)) { screen = "home"; render(); }
        else finish();
    }
    private void loadProgress() {
        try { state = store.load(); recovery = null; }
        catch (Exception error) { state = null; recovery = "Não foi possível ler seu progresso. O arquivo existente foi preservado. Você pode tentar novamente ou apagar o progresso depois de confirmar."; }
    }
    private String today() { return LocalDate.now().toString(); }
    private void navigate(String destination) { screen = destination; missionId = null; historyPage = 0; render(); }
    private void openMission(String id) { missionId = id; render(); }

    private void render() {
        root = column();
        root.setBackgroundColor(CREAM);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            } else view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        setContentView(root);
        root.requestApplyInsets();
        LinearLayout header = row();
        header.setPadding(dp(22), dp(14), dp(22), dp(10));
        TextView monogram = text("C", 28, NAVY, true);
        monogram.setTypeface(Typeface.create("serif", Typeface.ITALIC));
        monogram.setGravity(Gravity.CENTER);
        monogram.setBackground(surface(PAPER, GOLD, 30));
        monogram.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        header.addView(monogram, new LinearLayout.LayoutParams(dp(48), dp(48)));
        LinearLayout wordmark = column();
        wordmark.setPadding(dp(12), 0, 0, 0);
        wordmark.addView(text("ConsegVida", 23, NAVY, true));
        wordmark.addView(text("Fase 1 · Despertar", 12, MUTED, false));
        header.addView(wordmark, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        body = column();
        body.setPadding(dp(22), dp(12), dp(22), dp(26));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        try {
            if (recovery != null || state == null) showRecovery();
            else if (missionId != null) showMission(mission(missionId));
            else if ("missions".equals(screen)) showMissions();
            else if ("journey".equals(screen)) showJourney();
            else if ("about".equals(screen)) showAbout();
            else showHome();
        } catch (Exception invalidContent) {
            body.removeAllViews();
            heading("Conteúdo indisponível");
            paragraph("Não foi possível abrir esta tela. Seu progresso não foi alterado.");
            body.addView(button("Voltar ao início", false, () -> navigate("home")));
        }
        if (!contentFailed && recovery == null) {
            LinearLayout navigation = row();
            navigation.setGravity(Gravity.CENTER);
            navigation.setPadding(dp(6), dp(8), dp(6), dp(8));
            navigation.setBackgroundColor(PAPER);
            String[][] items = {{"home", "Hoje"}, {"missions", "Missões"}, {"journey", "Jornada"}, {"about", "Sobre"}};
            for (String[] item : items) {
                Button nav = button(item[1], item[0].equals(screen) && missionId == null, () -> navigate(item[0]));
                nav.setTextSize(13);
                nav.setPadding(dp(4), dp(8), dp(4), dp(8));
                nav.setSelected(item[0].equals(screen) && missionId == null);
                LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
                params.setMargins(dp(3), 0, dp(3), 0);
                navigation.addView(nav, params);
            }
            root.addView(navigation);
        }
    }

    private void showHome() throws JSONException {
        eyebrow("UM GESTO POSSÍVEL HOJE");
        heading("Cuidar começa\ncom presença.");
        paragraph(content.getString("introduction"));
        if (state.activeMission() != null) {
            JSONObject active = mission(state.activeMission());
            LinearLayout card = card();
            card.addView(text("SEU PRÓXIMO PASSO", 12, MUTED, true));
            card.addView(text(active.getString("title"), 22, NAVY, true));
            card.addView(button("Continuar missão", true, () -> openMission(state.activeMission())));
        } else body.addView(button("Escolher um cuidado", true, () -> navigate("missions")));
        section("Três formas de cuidar");
        JSONArray axes = content.getJSONArray("axes");
        JSONArray missions = content.getJSONArray("missions");
        for (int i = 0; i < axes.length(); i++) {
            JSONObject axis = axes.getJSONObject(i);
            JSONObject mission = missions.getJSONObject(i);
            String id = mission.getString("id");
            LinearLayout card = card();
            TextView axisName = text(axis.getString("label"), 23, Color.parseColor(axis.getString("color")), true);
            card.addView(axisName);
            card.addView(text(axis.getString("protects"), 16, MUTED, false));
            card.addView(button("Explorar cuidado · " + mission.getInt("minutes") + " min", false, () -> openMission(id)));
        }
        int count = 0;
        String day = today();
        for (ProgressState.Completion completion : state.completions()) if (day.equals(completion.completedOn)) count++;
        paragraph(count == 0 ? "Um começo pequeno já é um começo. Escolha um cuidado no seu ritmo." : count + (count == 1 ? " cuidado registrado hoje." : " cuidados registrados hoje."));
    }
    private void showMissions() throws JSONException {
        eyebrow("NO SEU RITMO");
        heading("Pequenos cuidados.\nAções possíveis.");
        paragraph("Escolha uma missão. Ao terminar, registre o que você fez neste aparelho.");
        JSONArray missions = content.getJSONArray("missions");
        for (int i = 0; i < missions.length(); i++) {
            JSONObject mission = missions.getJSONObject(i);
            String id = mission.getString("id");
            LinearLayout card = card();
            card.addView(text(axisLabel(mission.getString("axis")) + " · " + mission.getInt("minutes") + " min", 13, MUTED, true));
            card.addView(text(mission.getString("title"), 23, NAVY, true));
            card.addView(text(mission.getString("summary"), 16, INK, false));
            String label = state.completedOn(id, today()) ? "Ver missão · concluída hoje" : id.equals(state.activeMission()) ? "Continuar missão" : "Ver missão";
            Button open = button(label, false, () -> openMission(id));
            open.setContentDescription(label + ": " + mission.getString("title"));
            card.addView(open);
        }
    }
    private void showMission(JSONObject mission) throws JSONException {
        String id = mission.getString("id");
        body.addView(button("← Voltar às missões", false, () -> navigate("missions")));
        eyebrow(axisLabel(mission.getString("axis")) + " · " + mission.getInt("minutes") + " MIN");
        heading(mission.getString("title"));
        paragraph(mission.getString("summary"));
        JSONArray steps = mission.getJSONArray("steps");
        for (int i = 0; i < steps.length(); i++) {
            LinearLayout card = card();
            card.addView(text(String.format(Locale.forLanguageTag("pt-BR"), "%02d", i + 1), 14, MUTED, true));
            card.addView(text(steps.getString(i), 18, INK, false));
        }
        if (state.completedOn(id, today())) {
            section("Cuidado registrado hoje");
            paragraph("Seu registro está salvo neste aparelho. Amanhã você pode repetir esta missão.");
            body.addView(button("Ver minha jornada", true, () -> navigate("journey")));
        } else if (id.equals(state.activeMission())) {
            paragraph("Missão em andamento. Conclua quando terminar os passos, no seu ritmo.");
            body.addView(button("Concluir este cuidado", true, () -> {
                String localDay = today();
                try { if (persist(state.complete(id, localDay, localDay))) {
                    Toast.makeText(this, "Cuidado salvo neste aparelho", Toast.LENGTH_SHORT).show();
                    navigate("journey");
                }} catch (IllegalArgumentException error) { showSaveError(error.getMessage()); }
            }));
        } else {
            body.addView(button("Começar esta missão", true, () -> {
                if (state.activeMission() != null) {
                    new AlertDialog.Builder(this).setTitle("Trocar de missão?")
                            .setMessage("Você tem uma missão em andamento. Ao trocar, ela fica disponível para começar depois. Suas conclusões continuam salvas.")
                            .setNegativeButton("Continuar a atual", null).setPositiveButton("Trocar missão", (dialog, which) -> { if (persist(state.start(id))) render(); }).show();
                } else if (persist(state.start(id))) render();
            }));
        }
    }
    private void showJourney() throws JSONException {
        eyebrow("SEU HISTÓRICO LOCAL");
        heading("Minha jornada");
        int total = state.completions().size();
        paragraph(total == 0 ? "Ainda não há cuidados registrados. Sua jornada pode começar com cinco minutos." : total + (total == 1 ? " cuidado registrado por você." : " cuidados registrados por você."));
        if (state.activeMission() != null) {
            LinearLayout active = card();
            active.addView(text("Em andamento", 13, MUTED, true));
            active.addView(text(mission(state.activeMission()).getString("title"), 21, NAVY, true));
            active.addView(button("Continuar", true, () -> openMission(state.activeMission())));
        }
        List<ProgressState.Completion> history = new ArrayList<>(state.completions());
        history.sort(Comparator.comparing((ProgressState.Completion item) -> item.completedOn).reversed());
        int pageSize = 50;
        historyPage = Math.min(historyPage, Math.max(0, (history.size() - 1) / pageSize));
        int first = historyPage * pageSize;
        int end = Math.min(history.size(), first + pageSize);
        for (int i = first; i < end; i++) {
            ProgressState.Completion record = history.get(i);
            LinearLayout card = card();
            card.addView(text(ProgressState.parseDay(record.completedOn).format(DateTimeFormatter.ofPattern("dd 'de' MMMM 'de' uuuu", Locale.forLanguageTag("pt-BR"))), 13, MUTED, false));
            card.addView(text(mission(record.missionId).getString("title"), 18, NAVY, true));
        }
        if (history.size() > pageSize) {
            paragraph("Registros " + (first + 1) + " a " + end + " de " + total + ". Todos continuam salvos neste aparelho.");
            if (historyPage > 0) body.addView(button("Ver registros mais recentes", false, () -> { historyPage--; render(); }));
            if (end < history.size()) body.addView(button("Ver registros anteriores", false, () -> { historyPage++; render(); }));
        }
        if (total == 0) body.addView(button("Escolher uma missão", true, () -> navigate("missions")));
        section("Você controla seu progresso");
        paragraph("O histórico fica neste aparelho, sem sincronização. Desinstalar o aplicativo remove esse progresso. Você também pode apagá-lo agora.");
        body.addView(button("Apagar meu progresso", false, this::confirmReset));
    }
    private void showAbout() throws JSONException {
        eyebrow(content.getString("phase"));
        heading("Segurança\ndo ser humano.");
        paragraph("Evolução física, mental e espiritual. Presença, propósito e cuidado com o lugar onde você vive.");
        section("O manifesto");
        paragraph("Conheça o plano e suas ideias na fonte original. O vídeo será aberto fora do aplicativo.");
        body.addView(button("Abrir manifesto no YouTube", true, () -> new AlertDialog.Builder(this)
                .setTitle("Abrir o YouTube?")
                .setMessage("Você sairá da ConsegVida. O YouTube poderá usar sua conexão e aplicar suas próprias práticas de privacidade.")
                .setNegativeButton("Ficar aqui", null)
                .setPositiveButton("Abrir vídeo", (dialog, which) -> {
                    try {
                        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(content.optString("manifestoURL"))));
                    } catch (ActivityNotFoundException error) {
                        new AlertDialog.Builder(this).setTitle("Nenhum navegador disponível").setMessage("Abra o manifesto em um navegador quando estiver disponível.").setPositiveButton("Entendi", null).show();
                    }
                }).show()));
        paragraph(content.getString("horizon"));
        section("Privacidade");
        paragraph(content.getString("privacy"));
        paragraph("Guardamos somente a missão em andamento e o identificador e a data local dos cuidados concluídos. Não solicitamos nome, e-mail, localização, dados de saúde ou anotações pessoais.");
        section("Sobre esta versão");
        paragraph("ConsegVida 0.1.0 · Fase 1\nAs missões são adaptações práticas da filosofia do projeto. Os registros são seus relatos de conclusão; não medem resultados de saúde ou impacto social.");
    }
    private void showRecovery() {
        heading(contentFailed ? "Conteúdo indisponível" : "Vamos cuidar do seu progresso");
        paragraph(recovery == null ? "Não foi possível acessar o progresso." : recovery);
        if (!contentFailed) {
            body.addView(button("Tentar ler novamente", true, () -> { loadProgress(); render(); }));
            body.addView(button("Apagar progresso e recomeçar", false, this::confirmReset));
        }
    }
    private void confirmReset() {
        new AlertDialog.Builder(this).setTitle("Apagar o progresso deste aparelho?")
                .setMessage("A missão em andamento e todas as conclusões serão removidas. Esta ação não pode ser desfeita.")
                .setNegativeButton("Manter meu progresso", null)
                .setPositiveButton("Apagar progresso", (dialog, which) -> {
                    try {
                        store.reset();
                        state = ProgressState.empty();
                        recovery = null;
                        navigate("home");
                    } catch (Exception failure) {
                        new AlertDialog.Builder(this).setTitle("Não foi possível apagar o progresso")
                                .setMessage("A limpeza não foi concluída. O arquivo principal do progresso foi mantido. Tente novamente.")
                                .setPositiveButton("Entendi", null).show();
                    }
                }).show();
    }
    private boolean persist(ProgressState next) {
        try { store.save(next); state = next; return true; }
        catch (Exception failure) { showSaveError("Não foi possível salvar. Seu progresso anterior foi mantido. Verifique o espaço disponível e tente novamente."); return false; }
    }
    private void showSaveError(String message) {
        new AlertDialog.Builder(this).setTitle("O cuidado ainda não foi salvo").setMessage(message).setPositiveButton("Entendi", null).show();
    }
    private JSONObject mission(String id) throws JSONException {
        JSONArray list = content.getJSONArray("missions");
        for (int i = 0; i < list.length(); i++) if (id.equals(list.getJSONObject(i).getString("id"))) return list.getJSONObject(i);
        throw new JSONException("Missão ausente");
    }
    private String axisLabel(String id) throws JSONException {
        JSONArray list = content.getJSONArray("axes");
        for (int i = 0; i < list.length(); i++) if (id.equals(list.getJSONObject(i).getString("id"))) return list.getJSONObject(i).getString("label");
        throw new JSONException("Eixo ausente");
    }
    private LinearLayout column() { LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); return layout; }
    private LinearLayout row() { LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.HORIZONTAL); layout.setGravity(Gravity.CENTER_VERTICAL); return layout; }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView text = new TextView(this);
        text.setText(value); text.setTextSize(size); text.setTextColor(color);
        text.setTypeface(Typeface.create("sans-serif", bold ? Typeface.BOLD : Typeface.NORMAL));
        text.setLineSpacing(dp(3), 1f);
        text.setPadding(0, dp(5), 0, dp(5));
        return text;
    }
    private void eyebrow(String value) { TextView view = text(value, 12, MUTED, true); view.setLetterSpacing(.09f); body.addView(view); }
    private void heading(String value) { TextView view = text(value, 34, NAVY, false); view.setTypeface(Typeface.create("serif", Typeface.NORMAL)); if (Build.VERSION.SDK_INT >= 28) view.setAccessibilityHeading(true); body.addView(view); }
    private void section(String value) { TextView view = text(value, 22, NAVY, true); view.setPadding(0, dp(25), 0, dp(7)); if (Build.VERSION.SDK_INT >= 28) view.setAccessibilityHeading(true); body.addView(view); }
    private void paragraph(String value) { TextView view = text(value, 17, INK, false); view.setPadding(0, dp(9), 0, dp(16)); body.addView(view); }
    private LinearLayout card() {
        LinearLayout card = column();
        card.setPadding(dp(19), dp(15), dp(19), dp(15));
        card.setBackground(surface(PAPER, Color.rgb(231, 228, 220), 20));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, dp(7), 0, dp(7));
        body.addView(card, params);
        return card;
    }
    private Button button(String label, boolean primary, Runnable action) {
        Button button = new Button(this);
        button.setText(label); button.setAllCaps(false); button.setTextSize(16);
        button.setTextColor(primary ? PAPER : NAVY);
        button.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        button.setMinHeight(dp(52)); button.setMinimumHeight(dp(52));
        button.setPadding(dp(14), dp(12), dp(14), dp(12));
        button.setBackground(surface(primary ? NAVY : PAPER, primary ? NAVY : Color.rgb(214, 207, 192), 13));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, dp(7), 0, dp(7));
        button.setLayoutParams(params);
        button.setOnClickListener(view -> action.run());
        return button;
    }
    private GradientDrawable surface(int fill, int border, int radius) { GradientDrawable shape = new GradientDrawable(); shape.setColor(fill); shape.setCornerRadius(dp(radius)); shape.setStroke(dp(1), border); return shape; }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
