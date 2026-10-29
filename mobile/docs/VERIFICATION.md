# Evidências de implementação mobile

Data: 29/10/2026. Referência anterior: `94aef07fb12c852b7f555d5f5f5f51827b78de8e`.

## Baseline verificada

O repositório público continha 11 arquivos, sem telas web implementadas, código Android/iOS, testes, workflows ou releases. `main` e `feat/app-router` apontavam para a mesma revisão. O README descrevia rotas que não existiam na árvore. Identidade, filosofia e tokens foram reutilizados sem alterar os arquivos canônicos.

## Execuções locais

| Critério | Evidência | Resultado |
|---|---|---|
| Ferramenta solicitada | xtool oficial 1.24.0, SHA-256 conferido, `--version`, `--help`, `new ConsegVidaScaffold --skip-setup` | Confirmado: ferramenta executada e scaffold gerado |
| Android domínio/persistência | `sh mobile/android/test-core.sh` | 59 verificações passaram após revisão e correções |
| Swift domínio/persistência | Swift 6.4.1, `swift test --build-system native`, caches isolados | 31 XCTest passaram; 22 domínio e 9 persistência; zero falhas |
| Conteúdo compartilhado | `python3 mobile/scripts/sync_content.py --check` | Confirmado: identidade/tokens/IDs conferidos e cópias idênticas |
| Estrutura de configuração | parse XML Android, Apple plist/privacy, YAML do workflow, `bash -n` | Confirmado |
| Interface SwiftUI | análise sintática pelo compilador Swift | Passou sintaxe; não equivale a build com Apple SDK |
| Native Android local | tentativa Gradle | Bloqueado: JRE sem launcher javac e SDK Android ausente |
| Native iOS local | pré-requisitos | Apple SDK e hardware ausentes; nenhuma autenticação/assinatura realizada |

Conteúdo compartilhado SHA-256: `2275cce9d5872f7171815a731ec931b2b7de678df01255b622c6df2e645ac042`.

A toolchain Swift foi baixada do Swift.org e a assinatura PGP foi validada com fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`. Bibliotecas de execução faltantes foram obtidas dos pacotes assinados do Ubuntu e extraídas em diretório isolado. O ambiente exigiu execução do compilador fora do sandbox; isso não acessou conta Apple ou credenciais.

## Correções encontradas pela revisão

- Android: escape JSON Unicode inválido era aceito pelo parser numérico; teste reproduziu a falha e a validação foi corrigida.
- iOS: histórico com data superior ao relógio após mudança de fuso/data deve ser preservado; somente novas operações futuras são rejeitadas.
- iOS: atributos de backup/proteção são aplicados antes da substituição atômica, evitando um erro posterior a uma gravação já confirmada.
- Ambas: reset confirmado considera temporários órfãos pertencentes ao aplicativo e preserva arquivos alheios.
- iOS: atualização de dia/fuso/relógio, histórico paginado e validação exata do formato de estado.

## Verificação nativa no CI

O workflow `ConsegVida mobile preview` foi preparado para:

1. Android: build APK debug, lint e jornada em emulador API 36 com persistência após reinício, cancelamento e confirmação de reset.
2. iOS: testes do núcleo, build com xtool em macOS/Apple SDK e smoke de instalação/abertura em simulador.

O resultado de execução deve ser registrado abaixo após retorno efetivo do GitHub. A existência do workflow ou de um artefato não basta para considerar o teste aprovado.

**Estado nesta revisão preparatória: execução remota pendente.**

## Publicação e contas

- Google Play Console: a navegação chegou a uma solicitação de nova verificação da conta ConsegVida; console autenticado não confirmado.
- App Store Connect: a navegação chegou a `/login`; acesso à conta não confirmado.
- Nenhum certificado, profile, chave de upload, compra, build de distribuição ou submissão foi realizado.
- Aparelhos físicos, TestFlight, teste interno Google Play e disponibilidade pública nas lojas permanecem não homologados.

Esta evidência sustenta uma implementação em preparação. Não sustenta conclusão 100%, nota de homologação ou lançamento público.
