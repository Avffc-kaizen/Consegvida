# ConsegVida para Android e iOS

Primeira versão nativa da **Fase 1 — Despertar**, baseada na filosofia e identidade deste repositório. Os três eixos são Físico, Mental e Espiritual.

## Experiência

Escolher uma missão pequena, iniciar, concluir e consultar os registros salvos no aparelho. Uma conclusão por missão e dia evita duplicações. O histórico não representa resultado clínico, resultado social, ranking ou pontuação. O conteúdo trata objetivos de longo prazo como horizonte, nunca como resultados já atingidos.

O aplicativo não solicita conta, não usa IA paga, não incorpora anúncios ou analytics e não depende de API para o fluxo principal. O usuário pode apagar seu progresso com confirmação. A abertura do manifesto em vídeo é uma ação explícita que usa o navegador/YouTube externo.

## Estrutura

| Pasta | Função |
|---|---|
| `shared/content.json` | Conteúdo idêntico para os dois aplicativos |
| `android/` | Cliente Android nativo Java, build Gradle e testes de persistência |
| `core-swift/` | Domínio e persistência Foundation, testáveis sem Apple SDK |
| `ios/` | Cliente SwiftUI e projeto SwiftPM/xtool |
| `scripts/` | Sincronização do conteúdo e diagnóstico local de pré-requisitos |
| `docs/` | Contrato, preparação das lojas e evidências |

Não há integração com corretagem, CRM, Sofia ou Hero-mindset nesta superfície. Não há sincronização entre aparelhos nesta versão. O identificador `com.consegvida.app` é provisório até conferência nas contas das lojas.

## Validação local

Na raiz do repositório:

```sh
python3 mobile/scripts/sync_content.py --check
sh mobile/android/test-core.sh
swift test --package-path mobile/core-swift
python3 mobile/scripts/preflight.py
```

Quando alterar o conteúdo canônico mobile, execute `python3 mobile/scripts/sync_content.py` e confira o diff. Os tokens e a filosofia originais permanecem nas pastas `src/`.

O workflow `.github/workflows/mobile-preview.yml` valida somente alterações relacionadas a mobile ou aos seus insumos canônicos. Usa runners standard, permissões de leitura, nenhuma credencial de loja e retenção de artefatos de um dia. Código em PR, testes, APK de desenvolvimento, simulador e publicação nas lojas são estados diferentes.

Consulte `docs/RELEASE.md` para publicação e `docs/VERIFICATION.md` para o que foi realmente verificado.
